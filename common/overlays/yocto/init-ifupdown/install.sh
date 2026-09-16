#!/bin/bash -e

TARGET_DIR="$1"
[ "$TARGET_DIR" ] || exit 1

INTERFACES_FILE="$TARGET_DIR/etc/network/interfaces"

message "Installing init-ifupdown overlay (nl80211 driver)..."

# Minimal change: only replace wpa-driver wext with nl80211 if the file exists
if [ -f "$INTERFACES_FILE" ]; then
    sed -i 's/wpa-driver wext/wpa-driver nl80211/' "$INTERFACES_FILE"
    message "Updated wpa-driver in $INTERFACES_FILE"
else
    message "Warning: $INTERFACES_FILE not found, skipping"
fi
