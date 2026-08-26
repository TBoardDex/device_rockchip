#!/bin/bash

EXTCON_USB_PREFIX=${EXTCON_USB_PREFIX:-/sys/devices/platform/extcon-usb}
UDC_CLASS_DIR=${UDC_CLASS_DIR:-/sys/class/udc}
EXTCON_USB_PORT0="extcon-usb-port0"
EXTCON_USB_PORT1="extcon-usb-port1"

UDC_SELECT_SWITCH=n
PORT0_UDC=
PORT1_UDC=
UDC_SELECT_DEBUG=n

udc_log()
{
	if declare -F usb_msg >/dev/null 2>&1; then
		usb_msg "$@"
	elif [ "$UDC_SELECT_DEBUG" = y ]; then
		echo "$@"
	fi
}

udc_dt_prop()
{
	echo "$EXTCON_USB_PREFIX/$1/of_node/$2"
}

udc_read_phandle()
{
	hexdump -v -e '4/1 "%02x"' "$1" 2>/dev/null || true
}

udc_first_udc()
{
	ls "$UDC_CLASS_DIR"/ 2>/dev/null | head -n 1
}

udc_connected_port()
{
	local port state

	for port in $EXTCON_USB_PORT0 $EXTCON_USB_PORT1; do
		for state in "$EXTCON_USB_PREFIX/$port"/extcon/extcon*/state; do
			if [ -r "$state" ] && grep -q "USB=1" "$state"; then
				echo "$port"
				return
			fi
		done
	done
}

udc_current_udc()
{
	[ -n "$USB_GADGET_DIR" ] || return 0
	cat "$USB_GADGET_DIR/UDC" 2>/dev/null || true
}

udc_build_map()
{
	local port0_ph port1_ph udc udc_ph

	PORT0_UDC=
	PORT1_UDC=
	UDC_SELECT_SWITCH=n

	port0_ph=$(udc_read_phandle "$(udc_dt_prop $EXTCON_USB_PORT0 phandle)")
	port1_ph=$(udc_read_phandle "$(udc_dt_prop $EXTCON_USB_PORT1 phandle)")

	# SWITCH requires both port phandles to resolve AND both port nodes
	# to expose rockchip,usbc-orientation. Either gate failing keeps
	# SWITCH=n and the resolver falls back to the first UDC.
	if [ -z "$port0_ph" ] || [ -z "$port1_ph" ]; then
		return
	fi

	if [ ! -e "$(udc_dt_prop $EXTCON_USB_PORT0 rockchip,usbc-orientation)" ] ||
		[ ! -e "$(udc_dt_prop $EXTCON_USB_PORT1 rockchip,usbc-orientation)" ]; then
		return
	fi

	for udc in "$UDC_CLASS_DIR"/*; do
		[ -e "$udc" ] || continue

		udc_ph=$(udc_read_phandle "$udc/device/of_node/extcon")
		case "$udc_ph" in
			"$port0_ph") PORT0_UDC=$(basename "$udc") ;;
			"$port1_ph") PORT1_UDC=$(basename "$udc") ;;
		esac
	done

	if [ -n "$PORT0_UDC" ] && [ -n "$PORT1_UDC" ]; then
		UDC_SELECT_SWITCH=y
	fi
}

udc_resolve()
{
	local orientation

	UDC_SELECT=

	if [ "$UDC_SELECT_SWITCH" = y ]; then
		orientation=$(udc_connected_port)

		case "$orientation" in
			"$EXTCON_USB_PORT0"|"$EXTCON_USB_PORT1")
				if [ "$orientation" = "$EXTCON_USB_PORT0" ]; then
					UDC_SELECT=$PORT0_UDC
				else
					UDC_SELECT=$PORT1_UDC
				fi
				udc_log "Orientation $orientation, mapped UDC: $UDC_SELECT"
				;;
			*)
				UDC_SELECT=$(udc_current_udc)
				udc_log "No orientation detected, fallback UDC: ${UDC_SELECT:-none}"
				;;
		esac
	fi

	if [ -z "$UDC_SELECT" ]; then
		UDC_SELECT=$(udc_first_udc)
	fi

	if [ -z "$UDC_SELECT" ] || [ ! -d "$UDC_CLASS_DIR/$UDC_SELECT" ]; then
		udc_log "Failed to find a valid UDC device..."
		UDC_SELECT=none
	else
		udc_log "Selected UDC device: $UDC_SELECT"
	fi
}

udc_main()
{
	if [ "$1" = "Debug" ]; then
		UDC_SELECT_DEBUG=y
	fi

	udc_build_map
	udc_resolve

	if [ "${BASH_SOURCE[0]}" != "$0" ]; then
		USB_UDC=$UDC_SELECT
	else
		echo "UDC is $UDC_SELECT"
	fi
}

udc_main "$@"
