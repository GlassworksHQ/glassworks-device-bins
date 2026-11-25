# lululemon Studio Mirror — selinux_permissive

A minimal, single-boot kernel module for the lululemon Studio Mirror (MSM8916, arm64) on stock
firmware **1.24.0**. It exists for exactly one job: a read-only backup of the Mirror's own
partitions by its owner.

## What it does, and nothing else

When loaded, the module's init function looks up the kernel's `selinux_enforcing` flag through
`kallsyms_lookup_name` and writes `0` to it. That puts SELinux into **Permissive mode in RAM for
one boot**, so authorized USB ADB can read the raw `system` (`/dev/block/mmcblk0p22`) and `boot`
(`/dev/block/mmcblk0p19`) block devices while `/system` stays mounted **read-only**. A reboot
restores Enforcing, because nothing is written to disk.

It does **not**:

- remount `/system` (or anything) read-write,
- spawn a daemon, background thread, or persistent service,
- modify any partition, policy file, or property,
- survive a reboot.

That is the whole module. It is loaded once, during a Glassworks backup, by the surgical ADB tool
in `GlassworksHQ/glassworks` (`tools/mirror/`), and the backup path immediately restores the stock
library it was loaded through.

## Why it lives here

`selinux_permissive.c` calls `kallsyms_lookup_name`, which the kernel exports as
`EXPORT_SYMBOL_GPL`. The module's license string is therefore mandatory `license=GPL`, which makes
the module GPL-2.0-only. The main Glassworks repository is MIT/MPL-2.0 and ships no GPL source or
GPL binaries (its Hard Rule 4), so the source — and the hash-pinned binary built from it — belong
here, published with their Corresponding Source, the same way the S1's U-Boot is.

## Contents

- `selinux_permissive.c` — the module source. No includes: `struct module`, `__versions`, and
  `.modinfo` are laid out by hand, with the ABI CRCs hardcoded (see below), so the Corresponding
  Source is self-contained and needs no stock kernel tree.
- `UPSTREAM.json` — the pinned toolchain (clang major version, target, flags), the ABI facts, and
  the SPDX license.
- `build.sh` — compiles `selinux_permissive.ko`, writes `SHA256SUMS` and `release-meta.json`, and
  packages the Corresponding Source archive (`lululemon-mirror-selinux-permissive-source.tar.xz`).

## Building

The module has no external headers, so any `clang` that targets AArch64 builds it — no Android NDK,
no kernel tree.

On x86_64 or arm64 Linux/macOS with Docker (uses `ubuntu:24.04` with `clang-18`):

```sh
frames/lululemon-mirror/selinux-permissive/build.sh --out dist
```

Natively, with `clang-18` on `PATH`:

```sh
frames/lululemon-mirror/selinux-permissive/build.sh --native --out dist
```

To package only the Corresponding Source tarball without compiling:

```sh
frames/lululemon-mirror/selinux-permissive/build.sh --source-only --out dist
```

`build.sh` verifies the built `.ko` before writing its hashes: it must be an AArch64 `ET_REL`
object whose `__versions` carries `module_layout=0xa5b7f7dd` and
`kallsyms_lookup_name=0xe007de41`, whose `.modinfo` says `license=GPL`, and whose vermagic is stock
1.24.0's. A different clang version compiles the same source to different bytes and so a different
SHA-256; always verify a fresh build on a real Mirror before `GlassworksHQ/glassworks` pins the new
hash.

## ABI constraint (single revision)

The module carries no kernel symbol versions of its own beyond the two it needs, and Linux 3.10's
`same_magic()` under `CONFIG_MODVERSIONS=y` compares the vermagic tail and the `__versions` CRCs.
The published binary therefore loads **only where `module_layout` matches**, which is stock
**1.24.0** (`0xa5b7f7dd`, kernel `3.10.49-perf-g4869d64961b`). This is a single-revision artifact.
If another Mirror firmware revision appears with a different `module_layout`, it needs its own build
and its own release tag; plan for a matrix at that point.

## License

- `selinux_permissive.ko`: `GPL-2.0-only` (`license=GPL` with no "or later").

The standard GPL-2.0 text is in [`../../../LICENSES/GPL-2.0-only.txt`](../../../LICENSES/GPL-2.0-only.txt).
