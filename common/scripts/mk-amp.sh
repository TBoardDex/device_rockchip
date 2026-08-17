#!/bin/bash -e

RK_RTOS_BSP_DIR=$RK_SDK_DIR/rtos/bsp/rockchip
ITS_CONFIG="$RK_CHIP_DIR/$RK_AMP_FIT_ITS"

RK_SCRIPTS_DIR="${RK_SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"

usage_hook()
{
	usage_oneline "amp[:its:<its_file>][:os:<os_type>]" "build and pack amp system"
	usage_oneline "amp:menuconfig" "modify menuconfig of default project for amp"
}

amp_get_value()
{
	echo "$1" | grep -owP "$2\s*=\s*<([^>]+)>" | awk -F'<|>' '{print $2}'
}

amp_get_string()
{
	echo "$1" | grep -owP "$2\s*=.*\"([^>]+)\"" | awk -F'"' '{print $2}'
}

amp_get_node()
{
	echo "$1" | \
	awk -v node="$2" \
		'$0 ~ node " {" {
		in_block = 1;
		block = $0;
		next;
		}
		in_block {
			block = block "\n" $0;
			if (/}/) {
				count_open = gsub(/{/, "&", block);
				count_close = gsub(/}/, "&", block);
				if (count_open == count_close) {
					in_block = 0;
					print block;
					block = "";
				}
			}
		}'
}

amp_filter_comments()
{
	# Remove single-line comments (// ...)
	# Remove multi-line comments (/* ... */)
	# Remove comments at end of lines but keep the line
	cat "$1" | sed -e 's|//.*||' -e 's|/\*.*\*/||g' | \
	awk '
		BEGIN { in_comment = 0; }
		{
			line = $0;
			# Handle multi-line comments
			while (1) {
				if (!in_comment) {
					# Check for /* comment start
					pos = index(line, "/*");
					if (pos > 0) {
						# Output part before comment
						printf "%s", substr(line, 1, pos-1);
						line = substr(line, pos+2);
						in_comment = 1;
						continue;
					}
				} else {
					# Check for */ comment end
					pos = index(line, "*/");
					if (pos > 0) {
						line = substr(line, pos+2);
						in_comment = 0;
						continue;
					} else {
						# Entire line is inside comment
						line = "";
					}
				}
				break;
			}
			if (!in_comment && line != "") {
				print line;
			}
		}
	'
}

amp_touch_export()
{
	if [ -n "$2" ]; then
		DST=$2
	else
		DST=$1
	fi

	[ -n "${!1}" ] && export "$DST"="${!1}" || true
}

amp_find_kernel_dtb()
{
	local dtb_file=""
	local dts_name="${RK_KERNEL_DTS_NAME}"

	if [ -z "$dts_name" ] && [ -f "$RK_SDK_DIR/output/.config" ]; then
		dts_name="$(grep "^RK_KERNEL_DTS_NAME=" "$RK_SDK_DIR/output/.config" 2>/dev/null | cut -d'"' -f2 || true)"
	fi

	if [ -z "$dts_name" ]; then
		error "RK_KERNEL_DTS_NAME is not set! Please configure project target first."
		exit 1
	fi

	dtb_file="$(find "$RK_SDK_DIR/kernel"* "$RK_SDK_DIR/output" -name "${dts_name}.dtb" -not -path "*/.*" 2>/dev/null | head -n 1 || true)"

	if [ -z "$dtb_file" ] || [ ! -f "$dtb_file" ]; then
		error "Kernel DTB file '${dts_name}.dtb' not found!"
		error "Please build the kernel first: ./build.sh kernel"
		exit 1
	fi

	echo "$dtb_file"
}

amp_get_dtb_node_reg()
{
	local dtb_file="$1"
	local node_key="$2"
	local field="$3"
	local res_path="/reserved-memory"

	# Find actual subnode under /reserved-memory matching node_key (e.g. mcu, amp-shmem, rpmsg, amp)
	local node_name="$(fdtget -l "$dtb_file" "$res_path" 2>/dev/null | grep -E "^${node_key}(@|_|$)" | head -n 1 || true)"
	if [ -z "$node_name" ]; then
		# Try strip _reserved suffix (e.g. amp_shmem_reserved -> amp-shmem)
		local alt_key="$(echo "$node_key" | sed -e 's/_reserved//' -e 's/_/-/g')"
		node_name="$(fdtget -l "$dtb_file" "$res_path" 2>/dev/null | grep -E "^${alt_key}(@|_|$)" | head -n 1 || true)"
	fi

	if [ -z "$node_name" ]; then
		error "Reserved memory node for '$node_key' not found in DTB ($dtb_file)!"
		exit 1
	fi

	local reg_vals=($(fdtget "$dtb_file" "$res_path/$node_name" reg 2>/dev/null || true))
	if [ "${#reg_vals[@]}" -lt 4 ]; then
		error "Failed to read reg attribute for node '$node_name' in DTB!"
		exit 1
	fi

	local addr="${reg_vals[1]}"
	local size="${reg_vals[3]}"

	if [ "$field" = "START" ]; then
		printf "0x%08x" "$addr"
	elif [ "$field" = "SIZE" ]; then
		printf "0x%08x" "$size"
	else
		echo "$size"
	fi
}

amp_process_dtb_tags()
{
	local temp_its="$1"

	if ! grep -q "DTB:" "$temp_its"; then
		return 0
	fi

	PARSED_DTB_FILE="$(amp_find_kernel_dtb)"
	if [ -z "$PARSED_DTB_FILE" ] || [ ! -f "$PARSED_DTB_FILE" ]; then
		error "Kernel DTB file not found for ${RK_CHIP:-rk3572}!"
		error "Please build the kernel first: ./build.sh kernel"
		exit 1
	fi

	# Process combined expression DTB:node1:SIZE+node2:SIZE or DTB:node1+node2:SIZE
	local comb_matches="$(grep -oE "DTB:[a-zA-Z0-9_-]+(:SIZE)?\+[a-zA-Z0-9_-]+:SIZE" "$temp_its" | sort -u || true)"
	for match in $comb_matches; do
		local part1="$(echo "$match" | cut -d':' -f2 | cut -d'+' -f1)"
		local part2="$(echo "$match" | cut -d'+' -f2 | cut -d':' -f1)"
		local size1="$(amp_get_dtb_node_reg "$PARSED_DTB_FILE" "$part1" "RAW_SIZE")"
		local size2="$(amp_get_dtb_node_reg "$PARSED_DTB_FILE" "$part2" "RAW_SIZE")"
		local total_size=$((size1 + size2))
		local hex_size="$(printf "0x%08x" "$total_size")"
		sed -i "s|${match}|${hex_size}|g" "$temp_its"
	done

	# Process single expression DTB:node:START or DTB:node:SIZE
	local matches="$(grep -oE "DTB:[a-zA-Z0-9_-]+:(START|SIZE)" "$temp_its" | sort -u || true)"
	for match in $matches; do
		local node_key="$(echo "$match" | cut -d':' -f2)"
		local field="$(echo "$match" | cut -d':' -f3)"
		local hex_val="$(amp_get_dtb_node_reg "$PARSED_DTB_FILE" "$node_key" "$field")"
		sed -i "s|${match}|${hex_val}|g" "$temp_its"
	done
}

amp_parse_subargs()
{
	shift 1 || true
	while [ $# -gt 0 ]; do
		case "$1" in
			menuconfig)
				DO_MENUCONFIG=1
				shift 1
				;;
			its)
				if [ -n "$2" ]; then
					OVERRIDE_ITS="$2"
					shift 2
				else
					error "Option 'its' requires an ITS filename argument!"
					exit 1
				fi
				;;
			os)
				if [ -n "$2" ]; then
					OVERRIDE_OS="$2"
					shift 2
				else
					error "Option 'os' requires an OS type argument (e.g. rtt, hal)!"
					exit 1
				fi
				;;
			cfg|defconfig)
				if [ -n "$2" ]; then
					OVERRIDE_CFG="$2"
					shift 2
				else
					error "Option 'cfg' requires a defconfig path argument!"
					exit 1
				fi
				;;
			node)
				if [ -n "$2" ]; then
					OVERRIDE_NODE="$2"
					shift 2
				else
					error "Option 'node' requires a node name argument!"
					exit 1
				fi
				;;
			*)
				warning "Unknown amp sub-argument: $1"
				shift 1
				;;
		esac
	done
}

amp_resolve_its_path()
{
	local name="${1:-amp.its}"
	if [ -f "$RK_CHIP_DIR/$name" ]; then
		echo "$RK_CHIP_DIR/$name"
	elif [ -f "$name" ]; then
		echo "$name"
	else
		error "ITS config file '$name' not found!"
		exit 1
	fi
}

amp_print_build_info()
{
	message "=========================================="
	message "          Start building AMP"
	message "=========================================="
	message "AMP Fit ITS       : ${RK_AMP_FIT_ITS:-<none>}${OVERRIDE_ITS:+ (overridden by $OVERRIDE_ITS)}"
	message "ITS Config Path   : $ITS_CONFIG"
	[ -z "$PARSED_DTB_FILE" ] || message "DTB Source Path   : $PARSED_DTB_FILE"
	[ -z "$OVERRIDE_OS" ]     || message "OS Override       : $OVERRIDE_OS"
	message "------------------------------------------"
	[ -z "$SHMEM_BASE" ]       || message "AMP SHMEM Reserved: $SHMEM_BASE / ${SHMEM_SIZE:-<unk>}"
	[ -z "$LINUX_RPMSG_BASE" ] || message "RPMSG Reserved    : $LINUX_RPMSG_BASE / ${LINUX_RPMSG_SIZE:-<unk>}"
	message "------------------------------------------"
	[ -z "$RK_AMP_RTT_TARGET" ]     || message "RTT Target (AP)   : $RK_AMP_RTT_TARGET"
	[ -z "$RK_AMP_MCU_RTT_TARGET" ] || message "RTT Target (MCU)  : $RK_AMP_MCU_RTT_TARGET"
	[ -z "$RK_AMP_HAL_TARGET" ]     || message "HAL Target (AP)   : $RK_AMP_HAL_TARGET"
	[ -z "$RK_AMP_MCU_HAL_TARGET" ] || message "HAL Target (MCU)  : $RK_AMP_MCU_HAL_TARGET"
	message "Cross Compiler    : $CROSS_COMPILE"
	message "=========================================="
}

amp_menuconfig_env_setup()
{
	local core="$1"
	local exec_path="$2"
	local cc_prefix="$3"

	if [ -n "$exec_path" ]; then
		if [[ "$exec_path" != /* ]]; then
			export RTT_EXEC_PATH="${RK_SDK_DIR}/${exec_path}"
		else
			export RTT_EXEC_PATH="${exec_path}"
		fi
		notice "RTT_EXEC_PATH set to: $RTT_EXEC_PATH"
	fi

	if [ -n "$cc_prefix" ]; then
		export RTT_CC_PREFIX="$cc_prefix"
	else
		unset RTT_CC_PREFIX
	fi
}

amp_menuconfig_run()
{
	local bsp_dir="$1"
	local defconfig="$2"

	message "=================================================="
	message "      Entering RTOS Menuconfig for $(basename "$bsp_dir")  "
	message "      Defconfig: ${defconfig}                     "
	message "=================================================="

	cd "${bsp_dir}" || exit 1
	if [ -f "${defconfig}" ]; then
		notice "Loading existing ${defconfig}..."
		cp "${defconfig}" .config
	fi

	if [ -c /dev/tty ]; then
		scons --menuconfig < /dev/tty > /dev/tty
	else
		scons --menuconfig
	fi

	if [ -f .config ]; then
		cp .config "${defconfig}"
		message "Successfully saved new config to ${bsp_dir}/${defconfig}"
	else
		warning "Menuconfig aborted or failed. No changes saved to defconfig."
	fi

	cd "${RK_SDK_DIR}" || exit 1
}

amp_menuconfig()
{
	local its_file="$1"
	local override_os="$2"
	local override_cfg="$3"
	local override_node="$4"
	local bsp_target=""
	local defconfig=""
	local exec_path=""
	local core=""
	local sys=""

	[ -f "$its_file" ] || { error "ITS file '$its_file' not found!"; exit 1; }

	local clean_its="$(amp_filter_comments "$its_file")"
	local main_node="$override_node"
	if [ -z "$main_node" ]; then
		main_node="$(echo "$clean_its" | grep -wE "amp[0-9]* {|mcu {|hpmcu {" | head -n 1 | grep -oE "amp[0-9]*|mcu|hpmcu")"
	fi
	[ -n "$main_node" ] || { error "No valid image node found in '$its_file'!"; exit 1; }

	local node_content="$(amp_get_node "$clean_its" "$main_node")"
	sys="$(amp_get_string "$node_content" sys)"
	[ -z "$override_os" ] || sys="$override_os"
	core="$(amp_get_string "$node_content" core)"

	if [ -n "$override_cfg" ]; then
		defconfig="$override_cfg"
	else
		defconfig="$(amp_get_string "$node_content" rtt_config)"
	fi

	exec_path="$(amp_get_string "$node_content" rtt_exec)"
	local cc_prefix="$(amp_get_string "$node_content" cc_prefix)"

	if [[ "$sys" =~ ^hal ]]; then
		error "HAL project (SYS=$sys) does not support menuconfig!"
		exit 1
	fi

	if [ "$core" = "mcu" ]; then
		bsp_target="${RK_AMP_MCU_RTT_TARGET:-$(grep "^RK_AMP_MCU_RTT_TARGET=" "$RK_SDK_DIR/output/.config" 2>/dev/null | cut -d'"' -f2)}"
	else
		bsp_target="${RK_AMP_RTT_TARGET:-$(grep "^RK_AMP_RTT_TARGET=" "$RK_SDK_DIR/output/.config" 2>/dev/null | cut -d'"' -f2)}"
	fi

	[ -n "$bsp_target" ] || { error "Failed to determine BSP_TARGET for RT-Thread!"; exit 1; }
	local bsp_dir="$RK_RTOS_BSP_DIR/$bsp_target"
	[ -d "$bsp_dir" ] || { error "Project directory '$bsp_dir' does not exist!"; exit 1; }
	[ -n "$defconfig" ] || { error "Could not determine defconfig path from ITS file!"; exit 1; }

	amp_menuconfig_env_setup "$core" "$exec_path" "$cc_prefix"
	amp_menuconfig_run "$bsp_dir" "$defconfig"
}

build_hal()
{
	local append=

	check_config "$1" || return 0

	message "=========================================="
	message "  Building CPU $2: HAL-->${!1}"
	message "=========================================="

	cd "$RK_RTOS_BSP_DIR/common/hal/project/"${!1}"/GCC"

	[ ! -n "$CC" ] || append="CROSS_COMPILE=$CC"
	(
		amp_touch_export FIRMWARE_CPU_BASE
		amp_touch_export DRAM_SIZE
		amp_touch_export SRAM_BASE
		amp_touch_export SRAM_SIZE
		amp_touch_export CUR_CPU

		make clean > /dev/null
		rm -rf $3.elf $3.bin
		make $append -j$(nproc) > ${RK_SDK_DIR}/hal.log 2>&1
	)

	cp TestDemo.elf $3.elf
	mv TestDemo.bin $3.bin
	ln -rsf $3.bin $RK_OUTDIR/$3.bin

	finish_build build_hal $@
}

amp_setup_rtt_env()
{
	local cpu="$1"

	if [ -z "$RTT_EXEC_PATH" ]; then
		if [ -n "$CC" ]; then
			export RTT_EXEC_PATH="$(dirname "$CC")"
		elif [ -n "$CROSS_COMPILE" ]; then
			export RTT_EXEC_PATH="$(dirname "$CROSS_COMPILE")"
		fi
	fi

	if [ -n "$CC_PREFIX" ]; then
		export RTT_CC_PREFIX="$CC_PREFIX"
	else
		unset RTT_CC_PREFIX
	fi
}

build_rtthread()
{
	local append=

	check_config "$1" || return 0

	message "=========================================="
	message "  Building CPU $2: RT-Thread-->${!1}"
	message "                  Config-->$4"
	message "=========================================="

	cd "$RK_RTOS_BSP_DIR/${!1}"

	export RTT_ROOT=$RK_RTOS_BSP_DIR/../../

	amp_touch_export FIRMWARE_CPU_BASE RTT_PRMEM_BASE
	amp_touch_export DRAM_SIZE RTT_PRMEM_SIZE
	amp_touch_export SRAM_BASE RTT_SRAM_BASE
	amp_touch_export SRAM_SIZE RTT_SRAM_SIZE
	amp_touch_export SHMEM_BASE RTT_SHMEM_BASE
	amp_touch_export SHMEM_SIZE RTT_SHMEM_SIZE
	amp_touch_export RTT_EXEC RTT_EXEC_PATH
	amp_setup_rtt_env "$2"

	ROOT_PART_OFFSET=$(rk_partition_start root)
	ROOT_PART_SIZE=$(rk_partition_size root)

	if [ -f "$4" ] ;then
		scons --useconfig="$4"
	else
		warning "Warning: Config $4 not exit!\n"
		warning "Default config(.config) will be used!\n"
	fi

	scons -c > /dev/null
	rm -rf gcc_arm.ld Image/rtt$2.elf Image/rtt$2.bin
	scons -j$(nproc) > ${RK_SDK_DIR}/rtt.log 2>&1

	cp rtthread.elf Image/rtt$2.elf
	mv rtthread.bin Image/rtt$2.bin
	ln -rsf Image/rtt$2.bin $RK_OUTDIR/$3.bin

	if [ -n "$RK_AMP_RTT_ROOT_DATA" ] && [ -n "$ROOT_PART_SIZE" ] ;then

		RTT_ROOT_USERDAT=$RK_RTOS_BSP_DIR/$RK_AMP_RTT_TARGET/$RK_AMP_RTT_ROOT_DATA

		ROOT_SECTOR_SIZE=$(grep -r "CONFIG_RT_DFS_ELM_MAX_SECTOR_SIZE" "$4" | cut -d '=' -f 2)
		if [ -z $ROOT_SECTOR_SIZE ];then
			ROOT_SECTOR_SIZE=4096
		fi

		./mkroot.sh root $RTT_ROOT_USERDAT $RK_CHIP_DIR/$RK_PARAMETER $ROOT_SECTOR_SIZE $RK_FIRMWARE_DIR/root.img
	fi

	finish_build build_rtthread $@
}

clean_hook()
{
	[ "$RK_AMP" ] || return 0

	if [ "$RK_AMP_RTT_TARGET" ]; then
		cd "$RK_RTOS_BSP_DIR/$RK_AMP_RTT_TARGET"
		scons -c >/dev/null || true
	fi

	if [ "$RK_AMP_HAL_TARGET" ]; then
		cd "$RK_RTOS_BSP_DIR/common/hal/project/$RK_AMP_HAL_TARGET/GCC"
		make clean >/dev/null || true
	fi

	rm -rf "$RK_FIRMWARE_DIR/amp.img"
}

build_images()
{
	for item in $1
	do
		ITS_IMAGE=$(amp_get_node "$(cat $ITS_FILE)" $item)

		# update all parameters
		FIRMWARE_CPU_BASE=$(amp_get_value "$ITS_IMAGE" load)
		DRAM_SIZE=$(amp_get_value "$ITS_IMAGE" size)
		SRAM_BASE=$(amp_get_value "$ITS_IMAGE" sram_start)
		SRAM_SIZE=$(amp_get_value "$ITS_IMAGE" sram_size)
		CUR_CPU=$(amp_get_value "$ITS_IMAGE" cpu)
		CPU_BIN=$(amp_get_string "$ITS_IMAGE" data)
		if (( $CUR_CPU > 0xff )); then
			CUR_CPU=$((CUR_CPU >> 8))
		fi
		CUR_CPU=$(($CUR_CPU))

		notice "Image Target     : $item (CPU: $CUR_CPU | Load: ${FIRMWARE_CPU_BASE:-<none>} | Size: ${DRAM_SIZE:-<none>})"

		SYS=$(amp_get_string "$ITS_IMAGE" sys)
		if [ -n "$OVERRIDE_OS" ]; then
			notice "Temporarily replacing sys for $item ($SYS -> $OVERRIDE_OS)"
			SYS="$OVERRIDE_OS"
		fi

		CORE=$(amp_get_string "$ITS_IMAGE" core)

		CC=$(amp_get_string "$ITS_IMAGE" cc)
		[ ! -n "$CC" ] || CC="${RK_SDK_DIR}/${CC}"

		CC_PREFIX=$(amp_get_string "$ITS_IMAGE" cc_prefix)

		RTT_EXEC=$(amp_get_string "$ITS_IMAGE" rtt_exec)
		[ ! -n "$RTT_EXEC" ] || RTT_EXEC="${RK_SDK_DIR}/${RTT_EXEC}"

		SYS="${SYS}${CORE:+_$CORE}"

		case $SYS in
			hal_mcu)
				build_hal RK_AMP_MCU_HAL_TARGET mcu \
					  "$(basename -s .bin $CPU_BIN)"
				;;
			hal|hal_ap)
				build_hal RK_AMP_HAL_TARGET $CUR_CPU \
					  "$(basename -s .bin $CPU_BIN)"
				;;
			rtt_mcu)
				build_rtthread RK_AMP_MCU_RTT_TARGET mcu \
					       "$(basename -s .bin $CPU_BIN)" \
					       "$(amp_get_string "$ITS_IMAGE" rtt_config)"
				;;
			rtt|rtt_ap)
				build_rtthread RK_AMP_RTT_TARGET $CUR_CPU \
					       "$(basename -s .bin $CPU_BIN)" \
					       "$(amp_get_string "$ITS_IMAGE" rtt_config)" \
				;;
			*)
				break;;
		esac
	done
}

BUILD_CMDS="amp amp_all"

build_single_amp()
{
	local OVERRIDE_ITS="$1"
	local OVERRIDE_OS="$2"
	local TARGET_IMG_NAME="$3"

	[ -z "$OVERRIDE_ITS" ] || RK_AMP_FIT_ITS="$OVERRIDE_ITS"
	ITS_CONFIG="$(amp_resolve_its_path "${RK_AMP_FIT_ITS:-amp.its}")"

	if [ "$RK_AMP_RISCV" ]; then
		export CROSS_COMPILE=$(get_toolchain AMP "$RK_AMP_ARCH" none embed)
	else
		export CROSS_COMPILE=$(get_toolchain AMP "$RK_AMP_ARCH")
	fi
	[ "$CROSS_COMPILE" ] || exit 1

	"$RK_SCRIPTS_DIR/check-amp.sh"

	if [ -f "$RK_CHIP_DIR/$RK_AMP_CFG" ]; then
		set -a
		source $RK_CHIP_DIR/$RK_AMP_CFG
		set +a
	fi

	ITS_FILE="$(mktemp /tmp/temp_mk_amp_XXXXXXX.its)"
	trap "rm -f '$ITS_FILE'" EXIT INT TERM
	echo "$(amp_filter_comments "$ITS_CONFIG")" > "$ITS_FILE"

	PARSED_DTB_FILE=""
	amp_process_dtb_tags "$ITS_FILE"

	CORE_NUMBERS=$(grep -wcE "amp[0-9]* {|mcu {|hpmcu {" $ITS_FILE)

	EXT_SHARE=$(amp_get_node "$(cat $ITS_FILE)" share)
	if [ "$EXT_SHARE" ]; then
		SHMEM_BASE=$(amp_get_value "$EXT_SHARE" "shm_base")
		if [ "$SHMEM_BASE" ]; then
			export SHMEM_BASE
			export SHMEM_SIZE=$(amp_get_value "$EXT_SHARE" "shm_size")
			AMP_PRIMARY_CORE=$(amp_get_value "$EXT_SHARE" primary)
			[ ! $AMP_PRIMARY_CORE ] || export AMP_PRIMARY_CORE=$(($AMP_PRIMARY_CORE))
		fi

		LINUX_RPMSG_BASE=$(amp_get_value "$EXT_SHARE" "rpmsg_base")
		if [ "$LINUX_RPMSG_BASE" ]; then
			export LINUX_RPMSG_BASE=$LINUX_RPMSG_BASE
			export LINUX_RPMSG_SIZE=$(amp_get_value "$EXT_SHARE" "rpmsg_size")
		fi
	fi

	amp_print_build_info

	ITS_IMAGES=$(grep -wE "amp[0-9]* {|mcu {|hpmcu {" $ITS_FILE | grep -oE "amp[0-9]*|mcu")
	build_images "$ITS_IMAGES"

	cd "$RK_OUTDIR"
	ln -rsf $ITS_FILE amp.its
	sed -i '/share {/,/}/d' amp.its
	sed -i '/compile {/,/}/d' amp.its

	local AMP_OUT_DIR="$RK_FIRMWARE_DIR/amp_images"
	mkdir -p "$AMP_OUT_DIR"

	if [ -z "$TARGET_IMG_NAME" ]; then
		local cur_its="$(basename "$ITS_CONFIG")"
		local cur_os="$OVERRIDE_OS"
		if [ "$cur_its" = "amp_linux.its" ]; then
			cur_os="${cur_os:-rtt}"
			TARGET_IMG_NAME="amp_ap_${cur_os}.img"
		elif [ "$cur_its" = "amp_mcu.its" ]; then
			cur_os="${cur_os:-rtt}"
			TARGET_IMG_NAME="amp_mcu_${cur_os}.img"
		else
			TARGET_IMG_NAME="amp_mcu_rtt.img"
		fi
	fi

	$RK_RTOS_BSP_DIR/tools/mkimage -f amp.its -E -p 0xe00 "$AMP_OUT_DIR/$TARGET_IMG_NAME"
	notice "Generated AMP firmware: $AMP_OUT_DIR/$TARGET_IMG_NAME"
	ln -rsf "$AMP_OUT_DIR/$TARGET_IMG_NAME" "$AMP_OUT_DIR/amp.img"
	ln -rsf "$AMP_OUT_DIR/$TARGET_IMG_NAME" "$RK_FIRMWARE_DIR/amp.img"
	notice "Updated default symlink: $RK_FIRMWARE_DIR/amp.img -> amp_images/$TARGET_IMG_NAME"

	rm $ITS_FILE -f
}

build_amp_all()
{
	message "=================================================="
	message "      Building All 4 AMP Firmware Images         "
	message "=================================================="

	local AMP_OUT_DIR="$RK_FIRMWARE_DIR/amp_images"
	mkdir -p "$AMP_OUT_DIR"

	message ">>> [1/4] Building amp_ap_hal.img (Linux + AP HAL)"
	build_single_amp "amp_linux.its" "hal" "amp_ap_hal.img"

	message ">>> [2/4] Building amp_ap_rtt.img (Linux + AP RTT)"
	build_single_amp "amp_linux.its" "rtt" "amp_ap_rtt.img"

	message ">>> [3/4] Building amp_mcu_hal.img (Linux + MCU HAL)"
	build_single_amp "amp_mcu.its" "hal" "amp_mcu_hal.img"

	message ">>> [4/4] Building amp_mcu_rtt.img (Linux + MCU RTT - Default)"
	build_single_amp "amp_mcu.its" "rtt" "amp_mcu_rtt.img"

	ln -rsf "$AMP_OUT_DIR/amp_mcu_rtt.img" "$AMP_OUT_DIR/amp.img"
	ln -rsf "$AMP_OUT_DIR/amp_mcu_rtt.img" "$RK_FIRMWARE_DIR/amp.img"
	message "=================================================="
	message "All 4 AMP firmware images built successfully into '$AMP_OUT_DIR':"
	message "  - $AMP_OUT_DIR/amp_ap_hal.img"
	message "  - $AMP_OUT_DIR/amp_ap_rtt.img"
	message "  - $AMP_OUT_DIR/amp_mcu_hal.img"
	message "  - $AMP_OUT_DIR/amp_mcu_rtt.img"
	message "Default symlink: $RK_FIRMWARE_DIR/amp.img -> amp_images/amp_mcu_rtt.img"
	message "=================================================="
}

build_hook()
{
	local DO_MENUCONFIG=0
	local OVERRIDE_ITS=""
	local OVERRIDE_OS=""
	local OVERRIDE_CFG=""
	local OVERRIDE_NODE=""

	amp_parse_subargs "$@"
	check_config RK_AMP || false

	if [ "$1" = "amp_all" ]; then
		build_amp_all
		finish_build amp_all $@
		return 0
	fi

	if [ "$DO_MENUCONFIG" -eq 1 ]; then
		[ -z "$OVERRIDE_ITS" ] || RK_AMP_FIT_ITS="$OVERRIDE_ITS"
		ITS_CONFIG="$(amp_resolve_its_path "${RK_AMP_FIT_ITS:-amp.its}")"
		amp_menuconfig "$ITS_CONFIG" "$OVERRIDE_OS" "$OVERRIDE_CFG" "$OVERRIDE_NODE"
		finish_build amp $@
		return 0
	fi

	build_single_amp "$OVERRIDE_ITS" "$OVERRIDE_OS" ""
	finish_build amp $@
}

source "${RK_BUILD_HELPER:-$(dirname "$(realpath "$0")")/build-helper}"

build_hook $@
