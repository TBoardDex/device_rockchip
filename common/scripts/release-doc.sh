#!/bin/bash -e

RK_SCRIPTS_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
RK_DEVICE_DIR="$(realpath "$RK_SCRIPTS_DIR/../../")"
RK_SDK_DIR="$(realpath "$RK_DEVICE_DIR/../../")"
RK_CHIPS_DIR="$RK_DEVICE_DIR/.chips"

source "$RK_SCRIPTS_DIR/release-helper"

CHIP="$1"
if [ -z "$CHIP" ] || [ ! -e "$RK_CHIPS_DIR/$CHIP" ]; then
	choose_chip
	[ -n "$CHIP" ] || exit 1
fi

DOC_DIR="$2"
if [ -z "$DOC_DIR" ]; then
	[ -d "$RK_SDK_DIR/docs" ] || exit 0
	find "$RK_SDK_DIR/docs" -name Socs | while read -r d; do
		"$0" "$CHIP" "$d"
	done
	exit 0
fi

SOC_DIR="$(echo "$CHIP" | tr '[:lower:]' '[:upper:]')"
if [ ! -d "$DOC_DIR/$SOC_DIR" ]; then
	echo "There's no doc for $CHIP in $DOC_DIR"
	exit 0
fi

echo "Releasing docs for $CHIP in $DOC_DIR"

cd "$DOC_DIR"

ORIG_COMMIT=$(git log --oneline -1 | cut -d' ' -f1)

COMMIT_MSG=$(mktemp)
cat << EOF > "$COMMIT_MSG"
Release $CHIP - $(date +%Y-%m-%d)

Based on:
$(git log -1 --format="%h %s")
EOF

git add -f .
git stash &>/dev/null

# Drop other docs
for f in *; do
	[ "$f" = "$SOC_DIR" ] && continue
	rm -rf "$f"
done
mv "$SOC_DIR"/* . 2>/dev/null || true
rmdir "$SOC_DIR" 2>/dev/null || true

# Checkout branch
if ! git branch | grep -wq "$CHIP"; then
	# Create new branch
	git branch -D "$CHIP" &>/dev/null || true
	git checkout --orphan "$CHIP" &>/dev/null
	git reset &>/dev/null
else
	git checkout "$CHIP" &>/dev/null
	git checkout "$ORIG_COMMIT" . &>/dev/null
fi

# Commit files
git add .
git commit --allow-empty -s -F "$COMMIT_MSG" &>/dev/null
rm -f "$COMMIT_MSG"
git checkout -B "$CHIP" &>/dev/null

# Recover
git checkout "$ORIG_COMMIT" &>/dev/null
cd "$RK_SDK_DIR"
