#!/bin/bash -e

source "${RK_POST_HELPER:-$(dirname "$(realpath "$0")")/post-helper}"

if [ "$RK_ROOTFS_INSTALL_MODULES" ]; then
	message "Installing kernel modules..."

	if [ "$(id -u)" -eq 0 ] && [ "$RK_SUDO_ROOT" ]; then
		# Kernel builds run as the SDK owner. Ubuntu's debootstrap tree is
		# root-owned, so install into an owner-writable staging directory,
		# then copy the modules into the rootfs as root.
		MODULE_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/rk-rootfs-modules.XXXXXXXX")
		trap 'rm -rf -- "$MODULE_STAGE"' EXIT
		chown "$RK_OWNER_UID" "$MODULE_STAGE"
		"$RK_SCRIPTS_DIR/mk-kernel.sh" modules "$MODULE_STAGE/"
		mkdir -p "$TARGET_DIR/lib/modules"
		cp -a --no-preserve=ownership "$MODULE_STAGE/lib/modules/." \
			"$TARGET_DIR/lib/modules/"
		rm -rf -- "$MODULE_STAGE"
		trap - EXIT
	else
		"$RK_SCRIPTS_DIR/mk-kernel.sh" modules "$TARGET_DIR/"
	fi
fi

if [ "$RK_ROOTFS_STRIP_MODULES" ]; then
	message "Strip kernel modules..."

	source "$RK_SCRIPTS_DIR/kernel-helper"

	# Ubuntu keeps /proc, /sys and /dev mounted during post-processing.
	# Only scan installed modules, including the flat Wi-Fi modules. The
	# trailing slash also supports /lib or /lib/modules being a symlink on
	# merged-/usr rootfs trees. Propagate strip failures instead of hiding them.
	if [ -d "$TARGET_DIR/lib/modules" ]; then
		find "$TARGET_DIR/lib/modules/" -xdev -type f -name "*.ko" \
			-exec "${RK_KERNEL_TOOLCHAIN}strip" --strip-unneeded -v {} +
	fi
fi
