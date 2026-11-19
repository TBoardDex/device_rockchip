#!/bin/bash -e

source "${RK_POST_HELPER:-$(dirname "$(realpath "$0")")/post-helper}"

if [ "$RK_ROOTFS_INSTALL_MODULES" ]; then
	message "Installing kernel modules..."

	if [ "$POST_OS" = ubuntu ] && [ -n "$UBUNTU_KERNEL_BUILD_DIR" ]; then
		# Explicitly reuse a completed build; never silently publish missing modules.
		[ -s "$UBUNTU_KERNEL_BUILD_DIR/modules.order" ]
		while IFS= read -r module; do
			[ -f "$UBUNTU_KERNEL_BUILD_DIR/${module%.o}.ko" ] || {
				error "Missing prebuilt module: ${module%.o}.ko"
				exit 1
			}
		done < "$UBUNTU_KERNEL_BUILD_DIR/modules.order"
		source "$RK_SCRIPTS_DIR/kernel-helper"
		make -C "$UBUNTU_KERNEL_BUILD_DIR" ARCH="$RK_KERNEL_ARCH" \
			CROSS_COMPILE="$RK_KERNEL_TOOLCHAIN" modules_install \
			INSTALL_MOD_PATH="$TARGET_DIR" DEPMOD=true
		find "$TARGET_DIR/lib/modules" -type l -delete
	else
		"$RK_SCRIPTS_DIR/mk-kernel.sh" modules "$TARGET_DIR/"
	fi
fi

if [ "$RK_ROOTFS_STRIP_MODULES" ]; then
	message "Strip kernel modules..."

	source "$RK_SCRIPTS_DIR/kernel-helper"

	# The rootfs can have live /proc, /sys and /dev mounts during chroot
	# processing. Never descend into them or follow module build/source links.
	find "$TARGET_DIR" -xdev \
		\( -path "$TARGET_DIR/proc" -o -path "$TARGET_DIR/sys" \
		-o -path "$TARGET_DIR/dev" -o -path "$TARGET_DIR/run" \) -prune \
		-o -type f -name "*.ko" \
		-exec "${RK_KERNEL_TOOLCHAIN}strip" --strip-unneeded -v {} +
fi

# The vendor Wi-Fi loader uses insmod from /lib/modules, while standard
# modprobe uses the versioned modules tree. Expose the same installed modules.
if [[ "$RK_WIFIBT_MODULES" = AIC8800 && ( "$POST_OS" = ubuntu || "$POST_OS" = debian ) ]]; then
	for name in aic8800_bsp aic8800_fdrv; do
		module=$(find "$TARGET_DIR/lib/modules" -mindepth 3 -name "$name.ko" -print -quit)
		[ -n "$module" ] || { error "Missing installed $name.ko"; exit 1; }
		ln -rsf "$module" "$TARGET_DIR/lib/modules/$name.ko"
	done
fi
