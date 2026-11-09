#!/bin/bash -e

source "${RK_POST_HELPER:-$(dirname "$(realpath "$0")")/post-helper}"

[ -n "$RK_ROOTFS_UDEV_RULES" ] || exit 0

cd "$RK_SDK_DIR"

case "$POST_OS" in
	debian|ubuntu)
		install -D -m 0644 "$RK_RKSCRIPT_DIR/LICENSE" \
			"$TARGET_DIR/usr/share/doc/tboard-rkscript/copyright"
		;;
esac

mkdir -p "$TARGET_DIR/lib/udev/rules.d"
for rule in "$RK_RKSCRIPT_DIR"/*.rules; do
	echo $rule | grep -vq usbdevice || continue

	message "Installing udev rule: $rule"
	install -m 0644 $rule "$TARGET_DIR/lib/udev/rules.d/"
done
