# Rockchip Linux SDK

Rockchip Linux SDK for Rockchip SoC boards
  - wiki <http://opensource.rock-chips.com/wiki_Main_Page>.

## Quick Start

1. Check supported targets:
```shell
   ~$ make help
```
2. Choose SDK defconfig:
```shell
   ~$ make rockchip_defconfig
```
3. Modify SDK configurations:
```shell
   ~$ make menuconfig
   ~$ make savedefconfig
```
4. Modify kernel configurations:
```shell
   ~$ make kconfig
```
5. Place custom rootfs files in `device/rockchip/common/overlays/rootfs/default`.
6. Run `make` to build the images. Logs are saved in `output/log/latest`.
7. Flash the generated `output/firmware/update.img` to your device.
8. Boot your device and enjoy.
