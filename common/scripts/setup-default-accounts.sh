#!/bin/bash
# Host-side helper for Debian/Ubuntu targets; never modifies host accounts.
set -euo pipefail

[[ $# == 1 && -d "$1/etc" ]] || {
    echo "Usage: $0 <target rootfs>" >&2
    exit 1
}
TARGET=$(realpath "$1")
[[ "$TARGET" != / && -f "$TARGET/etc/passwd" && -f "$TARGET/etc/shadow" ]] || {
    echo "Refusing an invalid target rootfs: $TARGET" >&2
    exit 1
}

chroot "$TARGET" /bin/bash -s <<'ACCOUNTS'
set -euo pipefail

# Reuse the Linaro image's normal UID and existing desktop files, instead of
# leaving a third default login or recursively changing ownership of system files.
linaro_home=$(getent passwd linaro | cut -d: -f6) || linaro_home=/home/linaro
if ! getent passwd tboard >/dev/null; then
    if getent passwd linaro >/dev/null; then
        usermod -l tboard -d /home/tboard linaro
    else
        useradd -m -U -s /bin/bash tboard
    fi
fi
if getent group linaro >/dev/null && ! getent group tboard >/dev/null; then
    groupmod -n tboard linaro
fi
getent group tboard >/dev/null || groupadd tboard
[[ $(id -u root) == 0 && $(id -u tboard) -ge 1000 ]] || {
    echo "Expected root UID 0 and an unprivileged tboard UID >= 1000." >&2
    exit 1
}
# XFCE displays the GECOS full name, which otherwise remains "linaro".
usermod -d /home/tboard -g tboard -s /bin/bash -c tboard tboard
usermod -s /bin/bash root

# Give Debian and Ubuntu users sudo access with their own password.
getent group sudo >/dev/null || groupadd --system sudo
groups=(sudo)
for group in audio video render input dialout plugdev netdev bluetooth; do
    getent group "$group" >/dev/null && groups+=("$group")
done
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" == ubuntu ]]; then
        for group in adm; do
            getent group "$group" >/dev/null || groupadd --system "$group"
            groups+=("$group")
        done
    fi
fi
group_list=$(IFS=,; echo "${groups[*]}")
usermod -G "$group_list" tboard

mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/90-tboard <<'SUDOERS'
tboard ALL=(ALL:ALL) PASSWD: ALL
SUDOERS
chmod 0440 /etc/sudoers.d/90-tboard
if ! grep -Eq '^[[:space:]]*[#@]includedir[[:space:]]+/etc/sudoers.d/?([[:space:]]|$)' /etc/sudoers; then
    printf '\n#includedir /etc/sudoers.d\n' >> /etc/sudoers
fi
visudo -c

# OpenSSH uses the first global value: put managed defaults before Includes.
# Replace the previous block when reusing an already prepared rootfs.
if [[ -f /etc/ssh/sshd_config ]]; then
    sed -i '/^# BEGIN TBOARD LOGIN$/,/^# END TBOARD LOGIN$/d' /etc/ssh/sshd_config
    sed -i '1i\# BEGIN TBOARD LOGIN\nPermitRootLogin yes\nPasswordAuthentication yes\n# END TBOARD LOGIN' /etc/ssh/sshd_config
fi
printf 'root:root\ntboard:tboard\n' | chpasswd
for user in root tboard; do
    # A fixed nonzero last-change day also works on boards without a set RTC.
    chage -d 1 -m 0 -M -1 -I -1 -E -1 "$user"
done
mkdir -p /home/tboard
if [[ "$linaro_home" != /home/tboard && -d "$linaro_home" ]]; then
    cp -an "$linaro_home/." /home/tboard/
fi
if [[ -d /etc/skel ]]; then
    cp -an /etc/skel/. /home/tboard/
fi
chown -hR "$(id -u tboard):$(id -g tboard)" /home/tboard

# Older Debian rootfs trees replaced serial-getty with an unauthenticated root
# shell. Override that even when mk-image.sh reuses an already prepared tree.
# --keep-baud preserves the board's kernel console baud rate.
if [[ -d /etc/systemd/system ]]; then
    mkdir -p /etc/systemd/system/serial-getty@.service.d
    cat > /etc/systemd/system/serial-getty@.service.d/20-default-accounts.conf <<'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --keep-baud 115200,38400,9600 %I $TERM
GETTY
fi

# The Debian base may enable autologin for linaro. Require the new credentials
# for LightDM instead of leaving an inherited linaro autologin setting.
if [[ -d /etc/lightdm ]]; then
    # mk-image.sh may chroot without mounting /proc or /dev/fd.
    find /etc/lightdm -type f -name '*.conf' -print0 |
    while IFS= read -r -d '' file; do
        sed -i -E '/^[[:space:]]*autologin-user[[:space:]]*=/d' "$file"
    done
fi
ACCOUNTS
