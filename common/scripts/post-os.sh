#!/bin/bash -e

source "${RK_POST_HELPER:-$(dirname "$(realpath "$0")")/post-helper}"

OS_SCRIPT="$RK_SCRIPTS_DIR/post-$POST_OS.sh"
if [ -x "$OS_SCRIPT" ]; then
	notice "Running $(basename "$OS_SCRIPT") for $TARGET_DIR..."
	"$OS_SCRIPT"
fi
