# Glassworks Device Binaries

Standalone GPL and copyleft bootloaders, kernels, system images, and independent device tools for [Glassworks](https://github.com/GlassworksHQ/glassworks) frames, published alongside their exact Corresponding Source.

## Why this repository exists

The main [Glassworks](https://github.com/GlassworksHQ/glassworks) repository is MIT-licensed (with the Glassworks core under MPL-2.0) and stays free of GPL source code and GPL release binaries.

Some hardware frames still require standalone GPL programs—such as custom U-Boot builds for USB bring-up, Linux kernels, recovery images, or independent root-side tools—that Kiln or a panel fetches and runs as separate programs. This repository gives those artifacts a dedicated home with automated, self-contained Corresponding Source archives so license obligations stay clear and verifiable.

## Boundaries and rules

1. **Standalone artifacts only.** Everything built here must be an independent bootloader, kernel, partition image, or standalone executable. Nothing in this repository may be compiled, linked, dynamically loaded, or imported into the Glassworks Android app, the Glassworks core, or the Kiln web/WASM runtime.
2. **No vendor binaries or stock firmware.** Only open-source code, patches, device trees, and build scripts belong here. Never commit proprietary vendor blobs, stock dumps, or device-unique keys.
3. **Immutable releases with Corresponding Source.** Every GitHub Release attaches the exact Corresponding Source archive (`*-source.tar.xz`), `SHA256SUMS`, and `release-meta.json` alongside its binaries. Never delete or overwrite a published release tag.
4. **Pinned consumption.** The main `GlassworksHQ/glassworks` repository consumes binaries from this repository strictly by pinned release URL and SHA-256 hash (in `kiln/assets.lock.json` for small blobs and `kiln/workers/refract/allowlist.json` for large images).
5. **Hardware verification required.** Any newly built bootloader, kernel, or system image must be tested on real target hardware before `GlassworksHQ/glassworks` updates its pinned SHA-256.

## Components

| Path | Frame | License | Purpose |
|---|---|---|---|
| [`frames/aqara-s1-plus/uboot`](frames/aqara-s1-plus/uboot/README.md) | Aqara Panel Hub S1 Plus | `GPL-2.0-or-later` (packed TF-A BL31: `BSD-3-Clause`) | RAM-only U-Boot SPL and U-Boot with USB fastboot + `upload` for FEL bring-up and backup |
| [`frames/lululemon-mirror/selinux-permissive`](frames/lululemon-mirror/selinux-permissive/README.md) | lululemon Studio Mirror | `GPL-2.0-only` | Single-boot, RAM-only kernel module that sets SELinux Permissive so an owner's authorized USB ADB can read `system`/`boot` read-only during a backup |

## Licenses

This repository contains components under different open-source licenses—there is no single repository-wide license. Standard license texts live in [`LICENSES/`](LICENSES/), and every component declares its exact SPDX license in its `UPSTREAM.json` and release metadata.
