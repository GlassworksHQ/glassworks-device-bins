# Aqara Panel Hub S1 Plus — U-Boot

RAM-only U-Boot SPL (`u-boot-sunxi-with-spl.bin`) and U-Boot (`u-boot.bin`) for the Aqara Panel Hub S1 Plus (Allwinner A133), booted over USB FEL during installation, backup, and restore. Nothing in this build writes U-Boot or its environment to eMMC (`CONFIG_ENV_IS_NOWHERE=y`).

## Contents

- `UPSTREAM.json` — pinned upstream U-Boot and Trusted Firmware-A commits, container image, and SPDX licenses.
- `aqara-s1-plus_defconfig` — A133 DDR4 timings, eMMC on `mmc2`, USB fastboot gadget, and `ENV_IS_NOWHERE`.
- `sun50i-a133-aqara-s1-plus.dts` — minimal device tree for FEL boot (UART0, 8-bit eMMC, AXP806 PMIC, USB OTG peripheral).
- `patches/0001-sunxi-a133-ddr4-match-boot0-controller-setup.patch` — DDR4 controller setup matching the stock `boot0` header.
- `patches/0002-fastboot-add-upload-command.patch` — adds fastboot `upload` (`fastboot get_staged`) so Kiln and the CLI installer can read partitions back over USB before writing.
- `tfa/` — Trusted Firmware-A BL31 provenance notes and the historical debug patch used in `aqara-s1-plus-uboot-v1` (see [`tfa/README.md`](tfa/README.md)).
- `build.sh` — builds `u-boot-sunxi-with-spl.bin`, `u-boot.bin`, `SHA256SUMS`, `release-meta.json`, and the full Corresponding Source archive (`aqara-s1-plus-uboot-source.tar.xz`).

## Building locally

On macOS or x86_64 Linux (uses Docker with `arm64v8/ubuntu:22.04`):

```sh
frames/aqara-s1-plus/uboot/build.sh --out dist
```

On native Linux arm64 (used in GitHub Actions):

```sh
frames/aqara-s1-plus/uboot/build.sh --native --out dist
```

To package only the Corresponding Source tarball without compiling:

```sh
frames/aqara-s1-plus/uboot/build.sh --source-only --out dist
```

U-Boot embeds its build timestamp, so fresh builds are not byte-identical to earlier releases. Always verify a new build on a real S1 over FEL before updating `kiln/assets.lock.json` in `GlassworksHQ/glassworks`.

## License

- `u-boot.bin`: `GPL-2.0-or-later`
- `u-boot-sunxi-with-spl.bin`: `GPL-2.0-or-later AND BSD-3-Clause` (includes TF-A BL31 packed by U-Boot's sunxi build; the installer starts U-Boot from RAM without running BL31)
- `sun50i-a133-aqara-s1-plus.dts`: `GPL-2.0-or-later OR MIT`
