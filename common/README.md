# Rockchip Linux SDK

SDK for Rockchip SoC boards.
  - Wiki: <http://opensource.rock-chips.com/wiki_Main_Page>

## Prerequisites

- The SDK must be located on an ext4/xfs/btrfs/f2fs/zfs filesystem.
- The SDK directory must be owned by the current user.
- Required host packages: `python3`, `rsync`, `gcc`, `g++`.

## Quick Start

1. Check supported targets:
```shell
   ~$ make help
```
2. Clean up
```shell
   ~$ make cleanall
```
3. Choose SDK defconfig:
```shell
   ~$ make defconfig
```
4. Modify SDK configurations:
```shell
   ~$ make config
```
5. Modify kernel configurations:
```shell
   ~$ make kconfig
```
6. Modify partition table:
```shell
   ~$ make edit-parts
```
7. Modify the firmware packaging manifest file:
```shell
   ~$ make edit-package-file
```
8. Place custom rootfs files in `device/rockchip/common/overlays/rootfs/default`.
9. Run `make` to build the images. Logs are saved in `output/log/latest`.
10. Flash the generated `output/firmware/update.img` to your device.
11. Boot your device and enjoy.

## Common Targets

| Target | Description |
|--------|-------------|
| `make defconfig` | Select a board defconfig |
| `make config` | SDK menuconfig |
| `make kconfig` | Kernel menuconfig |
| `make kernel` | Build the kernel |
| `make loader` | Build U-Boot |
| `make rootfs` | Build the root filesystem |
| `make recovery` | Build the recovery image |
| `make amp` | Build the AMP subsystem |
| `make firmware` | Repack firmware from already-built components |
| `make cleanall` | Clean up all build outputs |

Run `make help` or `./build.sh help` for the full list of supported targets.

## Build Pipeline

The full build runs in the following order:
misc -> loader -> kernel -> rootfs -> security -> recovery -> amp -> firmware.

## Output

- Firmware image: `output/firmware/update.img`
- Build logs: `output/log/latest`
