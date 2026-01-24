#!/bin/bash -e

cd "$TARGET_DIR"

rm -rfv sha256sum*

if [ "$RK_DEBIAN_USER" != rockchip ]; then
	message "Changing default user to $RK_DEBIAN_USER..."

	if [ ! -d home/$RK_DEBIAN_USER ]; then
		mv -v home/rockchip home/$RK_DEBIAN_USER || true
	fi
	grep -rwl "rockchip" rockchip-test/ etc/ boot/ 2>/dev/null | \
		xargs sed -i "s/\<rockchip\>/$RK_DEBIAN_USER/g" 2>/dev/null || true
fi

if [ "$RK_DEBIAN_PASSWORD" != rockchip ]; then
	message "Changing default user's password..."
	echo "$RK_DEBIAN_USER:$RK_DEBIAN_PASSWORD" | chroot . chpasswd -m || true
fi

if ! [ "$RK_DEBIAN_UNIFIED_IMAGE" ]; then
	unset LIBMALI CAMERA_ENGINE RKNPU
	case "$RK_CHIP_FAMILY-$RK_CHIP" in
		rk312*|rk3036-*)
			LIBMALI=utgard-400
			CAMERA_ENGINE=rkisp
			;;
		*-rk3288)
			LIBMALI=midgard-t76x-*-r0p0
			CAMERA_ENGINE=rkisp
			;;
		*-rk3288w)
			LIBMALI=midgard-t76x-*-r1p0
			CAMERA_ENGINE=rkisp
			;;
		rk3399*)
			LIBMALI=midgard-t86x
			CAMERA_ENGINE=rkisp
			;;
		px30-*|rk3326-*|rk3328-*|rk3528-*)
			LIBMALI=bifrost-g31
			CAMERA_ENGINE=rkisp
			;;
		rk3566_rk3568-*)
			LIBMALI=bifrost-g52
			CAMERA_ENGINE=rkaiq_rk3568
			RKNPU=1
			;;
		rk3562-*)
			LIBMALI=bifrost-g52
			CAMERA_ENGINE=rkaiq_rk3562
			RKNPU=1
			;;
		rk3576-*)
			LIBMALI=bifrost-g52
			CAMERA_ENGINE=rkaiq_rk3576
			RKNPU=1
			;;
		rk3588-*)
			LIBMALI=valhall-g610
			CAMERA_ENGINE=rkaiq_rk3588
			RKNPU=1
			;;
		rv1126b-*)
			RKNPU=1
			;;
	esac

	if [ "$RKNPU" ]; then
		message "Extracting NPU2 tarball..."
		tar xvf rknpu2.tar || true
	fi

	PKGS=()
	if [ "$CAMERA_ENGINE" ]; then
		PKGS+=(./*camera_engine_${CAMERA_ENGINE}_*.deb)
	fi
	if [ "$LIBMALI" ]; then
		PKGS+=(./*libmali-${LIBMALI}-*.deb)
	fi

	if [ ${#PKGS[@]} -gt 0 ]; then
		message "Installing chip related packages..."

		mkdir -pv var/cache/apt/archives/partial

		if ! chroot . bash -c "apt install -fy ${PKGS[*]}"; then
			warning "Package installation failed..."
		fi

		"$RK_TOOLS_DIR/x86_64/ldconfig" -r "$TARGET_DIR/" || true
	fi

	rm -rfv *.deb *.tar
	touch usr/local/first_boot_flag
fi
