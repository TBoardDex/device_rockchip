#!/bin/bash -e

source "${RK_POST_HELPER:-$(dirname "$(realpath "$0")")/post-helper}"

case "$POST_OS" in
    debian|ubuntu)
        message "Setting default root and tboard accounts for $POST_OS..."
        /bin/bash "$(dirname "$(realpath "$0")")/setup-default-accounts.sh" "$TARGET_DIR"
        ;;
    # Buildroot uses BR2_TARGET_GENERIC_ROOT_PASSWD and its users table so
    # mkusers emits the correct home ownership into the fakeroot script.
esac
