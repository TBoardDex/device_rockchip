#!/bin/bash -e

echo "Executing $(basename "$BASH_SOURCE")..."

RK_SCRIPTS_DIR="$(dirname "$(realpath "$BASH_SOURCE")")"

# HACK: Allow host tools, e.g. python2 in yocto building
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \

# Keep the calling build's session. "latest" is a moving symlink: preparing
# Kconfig can start another SDK command and repoint it to a config-only session
# without final.env. Resolve it before entering build.sh, which reloads that
# file after its init hooks. Standalone callers may reuse the latest complete
# session; if none is available, let build.sh initialize a fresh one.
POST_SDK_DIR=$(realpath "$RK_SCRIPTS_DIR/../../../..")
POST_SESSION_DIR="$POST_SDK_DIR/output/sessions/${RK_SESSION:-latest}"
if [ -r "$POST_SESSION_DIR/final.env" ]; then
	export RK_SESSION="$(basename "$(realpath "$POST_SESSION_DIR")")"
else
	echo "No complete SDK session for post-rootfs; initializing a new session."
	unset RK_SESSION
fi

# Trigger build.sh's post-rootfs hooks.
"$RK_SCRIPTS_DIR/build.sh" post-rootfs "$@"
