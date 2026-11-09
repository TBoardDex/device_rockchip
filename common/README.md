# Rockchip Linux SDK

Rockchip Linux SDK for the Rockchip SOC boards
  - wiki <http://opensource.rock-chips.com/wiki_Main_Page>.

## TBoard Ubuntu / Debian SDK

This published SDK supports the TBoard R5A (RK3588S) board with Debian 11
ARM64 (Xfce desktop, the default via `rockchip_defconfig`) and Ubuntu 22.04
Server / GNOME Desktop via the `tboard-r5a_rk3588s_*` configurations.
`./build.sh debian` builds Debian Xfce.

`./build.sh -h` and `make help` list the supported build, configuration, partition,
packaging and cleanup commands. `./build.sh chip` / `defconfig` list the default
and three TBoard configurations first, followed by the original Rockchip board
configurations. Ubuntu entries are limited to 22.04 Server and Desktop.

All native SDK commands exposed by the build hooks are shown in `./build.sh -h`
and `make help` and validated by the normal command parser, including Buildroot,
Yocto, Recovery, AMP, UEFI, secure-image and OTA. The `sdk-defconfigs` file defines the
board configuration menu and its order. Building each target requires its
corresponding configuration and source components.

Debian integration requires matching changes in both `device/rockchip/` and
`debian11/`. Include `debian11/check-resources.sh`, `bsp/`, the AIC8800 firmware
under `overlay-firmware/lib/firmware/aic8800/`, and the updated Debian build
scripts and overlays when publishing the SDK. Rootfs work directories and
generated images are build outputs and should not be included as source files.

```bash
./build.sh rockchip_defconfig
./build.sh all
# Or build the selected rootfs / repack existing images:
./build.sh rootfs
./build.sh firmware
./build.sh updateimg
```

After `./build.sh all` succeeds, all files under `rockdev/` are copied into
`IMAGE/<system>-<style>-<YYYYMMDDHHMM>/`, using Asia/Shanghai time. For example:
`IMAGE/debian11-Xfce-202611091952/`, `IMAGE/ubuntu22.04-Server-202611091952/`,
or `IMAGE/ubuntu22.04-GNOME-202611091952/`. Symbolic links are copied as their
actual contents. Existing files in `IMAGE/` are kept; archives created within
the same minute receive a numeric suffix such as `-2`. Copies are staged in a
temporary directory and published only after every file is copied successfully.

Full image packing via `updateimg` remains supported. See `debian11/readme.md`
and `ubuntu22.04/README.md` for distro requirements. Online package downloads
are still required.

## Quick Start

1. Check supported targets:
```shell
   ~ $ make help
```
2. Choose SDK's defconfig:
```shell
   ~ $ make rockchip_defconfig
```
3. Change SDK's configs:
```shell
   ~ $ make menuconfig
   ~ $ make savedefconfig
```
4. Run "make" to build the images, logs saved at "output/log/"
5. Flash the generated "output/firmware/update.img" to your device
6. Boot your device and enjoy it
