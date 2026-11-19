#!/bin/bash -e

echo "Executing $(basename "$BASH_SOURCE")..."

RK_SCRIPTS_DIR="$(dirname "$(realpath "$BASH_SOURCE")")"

# HACK: Allow host tools in yocto building
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ -f "$1/etc/os-release" ] && grep -qx 'VERSION_ID="24.04"' "$1/etc/os-release" && grep -qx 'ID=ubuntu' "$1/etc/os-release"; then
	exec "$RK_SCRIPTS_DIR/../../../../ubuntu24.04/post-sdk.sh" "$1"
fi

# Trigger build.sh's post-rootfs hooks
# Standalone and concurrent builds may have no saved final.env. In that
# case start a fresh session rather than inheriting the unrelated latest log.
POST_SDK_DIR=$(realpath "$RK_SCRIPTS_DIR/../../../..")
if [ -n "$RK_SESSION" ] && [ -r "$POST_SDK_DIR/output/sessions/$RK_SESSION/final.env" ]; then
	"$RK_SCRIPTS_DIR/build.sh" post-rootfs "$@"
else
	env -u RK_SESSION "$RK_SCRIPTS_DIR/build.sh" post-rootfs "$@"
fi
