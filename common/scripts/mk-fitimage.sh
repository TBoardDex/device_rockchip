#!/bin/bash -e

RK_SCRIPTS_DIR="${RK_SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"
RK_SDK_DIR="${RK_SDK_DIR:-$RK_SCRIPTS_DIR/../../../..}"

TARGET_IMG="$1"
ITS="$2"
KERNEL_IMG="$3"
KERNEL_DTB="$4"
RESOURCE_IMG="$5"
RAMDISK_IMG="$6"

get_reserved_memory_range()
{
	local dtb="$1"
	local label="$2"
	local node
	local range
	local addr
	local size

	node=$(fdtget -ts "$dtb" /__symbols__ "$label" 2>/dev/null) ||
		return 1
	read -r -a range <<< "$(fdtget -tx "$dtb" "$node" reg 2>/dev/null)" ||
		return 1

	case "${#range[@]}" in
	2)
		addr=$((0x${range[0]}))
		size=$((0x${range[1]}))
		;;
	4)
		addr=$(((0x${range[0]} << 32) | 0x${range[1]}))
		size=$(((0x${range[2]} << 32) | 0x${range[3]}))
		;;
	*) return 1 ;;
	esac

	printf "0x%x 0x%x\n" "$addr" "$size"
}

if [ ! -f "$ITS" ]; then
	echo "$ITS not exists!"
	exit 1
fi

TMP_ITS=$(mktemp)
cp "$ITS" "$TMP_ITS"

if [ "$RK_FASTBOOT" ] && \
	{ [ -z "$RAMDISK_IMG" ] || \
	  [ "$(realpath -q "$ITS")" = "$(realpath -q "$RK_FASTBOOT_ROOTFS_ITS")" ]; }; then
	notice "Fastboot rework its"

	if [ -z "$RAMDISK_IMG" ]; then
		kernel_r=`cat $TMP_ITS | grep entry | sed -E 's/.*entry = <(0x[0-9a-fA-F]+)>;.*/\1/'`
		KERNEL_GZ=$(mktemp)
		cat $KERNEL_IMG | gzip -n -f -9 > $KERNEL_GZ
		kernel_align_1mb_size=`stat -c %s $KERNEL_IMG | \
			     xargs -I{} bash -c 'echo $(( ( ({} + 1048575) / 1048576 ) * 1048576 ))' | \
			     xargs printf "0x%x"`
		kernel_c=$((kernel_r+kernel_align_1mb_size))
		printf -v kernel_c "0x%x" "$kernel_c"

		sed -i -e "s~@KERNEL_C@~$kernel_c~" \
			-e "s~@KERNEL_IMG@~$(realpath -q "$KERNEL_GZ")~" "$TMP_ITS"
		notice "kernel_r is " $kernel_r
		notice "kernel_c is " $kernel_c
	else
		notice "kernel dts" $(realpath -q "$KERNEL_DTB")

		if ! read -r ramdisk_r ramdisk_r_size <<< \
			"$(get_reserved_memory_range "$KERNEL_DTB" ramdisk_r)"; then
			error "ramdisk_r node not found in dtb!"
			error "Please check the ramdisk_r node of ${KERNEL_DTB%.*}.dts"
			exit 1
		fi

		ramdisk_img_size=$(stat -Lc "%s" "$RAMDISK_IMG")
		if ! gzip -t "$RAMDISK_IMG"; then
			error "$(basename "$RAMDISK_IMG") is not a valid gzip image"
			exit 1
		fi

		ramdisk_payload_size=$(gzip -dc "$RAMDISK_IMG" | wc -c)
		if [ "$ramdisk_payload_size" -gt "$((ramdisk_r_size))" ]; then
			error "$(basename "$RAMDISK_IMG") payload is larger than ramdisk_r"
			error "Please increase ramdisk_r in ${KERNEL_DTB%.*}.dts"
			exit 1
		fi

		sed -i -e "s~@RAMDISK_R@~$ramdisk_r~" "$TMP_ITS"
		notice "ramdisk_r is " $ramdisk_r
		notice "ramdisk_r_size is " $ramdisk_r_size

		if ! read -r ramdisk_c ramdisk_c_size <<< \
			"$(get_reserved_memory_range "$KERNEL_DTB" ramdisk_c)"; then
			error "$RK_CHIP_FAMILY ramdisk_c node not found in dtb!"
			error "Please check the ramdisk_c node of ${KERNEL_DTB%.*}.dts"
			exit 1
		fi

		if [ "$ramdisk_img_size" -gt "$((ramdisk_c_size))" ]; then
			error "$(basename "$RAMDISK_IMG") is larger than ramdisk_c"
			error "Please increase ramdisk_c in ${KERNEL_DTB%.*}.dts"
			exit 1
		fi

		sed -i -e "s~@RAMDISK_C@~$ramdisk_c~" "$TMP_ITS"
		notice "ramdisk_c is " "$ramdisk_c"
		notice "ramdisk_c_size is " "$ramdisk_c_size"

	fi
fi

if [ "$RK_SECURITY" ]; then
	echo "Security boot enabled, removing uboot-ignore ..."
	sed -i "/uboot-ignore/d" "$TMP_ITS"
fi

sed -i -e "s~@KERNEL_DTB@~$(realpath -q "$KERNEL_DTB")~" \
	-e "s~@KERNEL_IMG@~$(realpath -q "$KERNEL_IMG")~" \
	-e "s~@RESOURCE_IMG@~$(realpath -q "$RESOURCE_IMG")~" "$TMP_ITS"

if [ -n "$RAMDISK_IMG" ]; then
	sed -i -e "s~@RAMDISK_IMG@~$(realpath -q "$RAMDISK_IMG")~" "$TMP_ITS"
fi

"$RK_SDK_DIR/rkbin/tools/mkimage" -f "$TMP_ITS"  -E -p 0x800 "$TARGET_IMG"
rm -f "$TMP_ITS"
rm -f "$KERNEL_GZ"
