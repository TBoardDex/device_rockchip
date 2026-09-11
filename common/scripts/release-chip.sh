#!/bin/bash -e

RK_SCRIPTS_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
RK_DEVICE_DIR="$(realpath "$RK_SCRIPTS_DIR/../../")"
RK_CHIPS_DIR="$RK_DEVICE_DIR/.chips"
RK_CHIP_DIR="$RK_DEVICE_DIR/.chip"

source "$RK_SCRIPTS_DIR/release-helper"

CHIP="$1"
if [ -z "$CHIP" ] || [ ! -e "$RK_CHIPS_DIR/$CHIP" ]; then
	choose_chip
	[ -n "$CHIP" ] || exit 1
fi

echo "Releasing chip: $CHIP"

cd "$RK_DEVICE_DIR"

ORIG_COMMIT=$(git log --oneline -1 | cut -d' ' -f1)

COMMIT_MSG=$(mktemp)
cat << EOF > "$COMMIT_MSG"
Release $CHIP - $(date +%Y-%m-%d)

Based on:
$(git log -1 --format="%h %s")
EOF

git add -f .
git stash &>/dev/null || true

# Drop other chips
rm -f "$RK_CHIP_DIR"
ln -rsf "$RK_CHIPS_DIR/$CHIP" "$RK_CHIP_DIR"
ln -rsf "$RK_CHIPS_DIR/$CHIP" .

# Checkout branch
if ! git branch | grep -wq "$CHIP"; then
	# Create new branch
	git branch -D "$CHIP" &>/dev/null || true
	git checkout --orphan "$CHIP" &>/dev/null || true
	git reset &>/dev/null || true
else
	git checkout "$CHIP" &>/dev/null || true
	git checkout "$ORIG_COMMIT" . &>/dev/null || true
fi

# Commit files
git add -f .gitignore common "$RK_CHIPS_DIR/$CHIP" "$RK_CHIP_DIR" "$CHIP"
git commit --allow-empty -s -F "$COMMIT_MSG" &>/dev/null || true
rm -f "$COMMIT_MSG"
git checkout -B "$CHIP" &>/dev/null || true

# Recover
git add -f .
git checkout "$ORIG_COMMIT" &>/dev/null || true
