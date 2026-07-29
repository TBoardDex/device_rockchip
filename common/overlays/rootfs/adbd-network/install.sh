#!/bin/bash -e

TARGET_DIR="$1"
[ "$TARGET_DIR" ] || exit 1

if [ -z "$RK_ADBD_NETWORK" ]; then
	notice "ADBD network service disabled..."
	exit 0
fi

OVERLAY_DIR="$(dirname "$(realpath "$0")")"

message "Installing ADBD network service..."

ensure_tools "$TARGET_DIR/usr/bin/adbd"

mkdir -p "$TARGET_DIR/etc"

{
	echo "# ADBD network configuration"
	echo "ADB_TCP_PORT=$RK_ADBD_NETWORK_TCP_PORT"
} > "$TARGET_DIR/etc/adbd-network.conf"

install -m 0755 "$OVERLAY_DIR/usr/bin/adbd-network-start" \
	"$TARGET_DIR/usr/bin/adbd-network-start"

install_sysv_service "$OVERLAY_DIR/S51adbd-network" S
install_busybox_service "$OVERLAY_DIR/S51adbd-network"
install_systemd_service "$OVERLAY_DIR/adbd-network.service"
