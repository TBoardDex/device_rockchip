#!/bin/bash -e

cd "$TARGET_DIR"

rm -rf sha256sum*

if [ "$RK_DEBIAN_USER" != linaro ]; then
	message "Changing default user to $RK_DEBIAN_USER..."

	if [ -d home/linaro ]; then
		sudo mv home/linaro home/$RK_DEBIAN_USER || true
	fi
	grep -rwl "linaro" rockchip-test/ etc/ boot/ 2>/dev/null | \
		xargs sed -i "s/\<linaro\>/$RK_DEBIAN_USER/g" 2>/dev/null || true
fi

if [ "$RK_DEBIAN_PASSWORD" != linaro ]; then
	message "Changing default user's password..."
	echo "$RK_DEBIAN_USER:$RK_DEBIAN_PASSWORD" | sudo chroot . chpasswd -m
fi
