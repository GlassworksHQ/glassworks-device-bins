#!/usr/bin/env bash
# Build U-Boot (SPL + proper) for the Aqara Panel Hub S1 Plus and package its Corresponding Source.
#
# Usage:
#   frames/aqara-s1-plus/uboot/build.sh [--docker|--native] [--source-only] [--out <dir>] [--work <dir>]
#
# Optional overrides:
#   UBOOT_SRC=<path>   Existing U-Boot git checkout (must match UPSTREAM.json commit unless ALLOW_CUSTOM_SRC=1)
#   TFA_SRC=<path>     Existing Trusted Firmware-A git checkout
#   BL31=<path>        Prebuilt sun50i_a133 bl31.bin (skips building TF-A; TFA_SRC still fetched for source tarball)
#   TFA_DEBUG=1        Apply tfa/0001-s1-debug-bl31-uart-markers-icache-off.patch and build DEBUG=1
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
MODE="docker"
SOURCE_ONLY=0
OUT_DIR="$PWD/out"
WORK_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --docker) MODE="docker"; shift ;;
    --native) MODE="native"; shift ;;
    --source-only) SOURCE_ONLY=1; shift ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --work) WORK_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

if [ -z "$WORK_DIR" ]; then
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
else
  mkdir -p "$WORK_DIR"
  WORK_DIR="$(cd "$WORK_DIR" && pwd)"
fi

read_json() {
  python3 -c 'import json, sys; d = json.load(open(sys.argv[1]));
for k in sys.argv[2].split("."): d = d[k]
print(d)' "$HERE/UPSTREAM.json" "$1"
}

UBOOT_REPO="$(read_json upstreams.uboot.repo)"
UBOOT_COMMIT="$(read_json upstreams.uboot.commit)"
TFA_REPO="$(read_json upstreams.tfa.repo)"
TFA_COMMIT="$(read_json upstreams.tfa.commit)"
DOCKER_IMAGE="$(read_json docker_image)"

fetch_commit() {
  local repo="$1" commit="$2" dest="$3"
  if [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)" = "$commit" ]; then
    return 0
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  git -C "$dest" init -q
  git -C "$dest" remote add origin "$repo"
  git -C "$dest" fetch --depth=1 origin "$commit"
  git -C "$dest" checkout -q FETCH_HEAD
  [ "$(git -C "$dest" rev-parse HEAD)" = "$commit" ] || {
    echo "Commit mismatch in $dest: expected $commit" >&2
    exit 1
  }
}

UBOOT_SRC="${UBOOT_SRC:-$WORK_DIR/u-boot}"
TFA_SRC="${TFA_SRC:-$WORK_DIR/arm-trusted-firmware}"

echo "==> Fetching pinned upstream sources"
fetch_commit "$UBOOT_REPO" "$UBOOT_COMMIT" "$UBOOT_SRC"
fetch_commit "$TFA_REPO" "$TFA_COMMIT" "$TFA_SRC"

echo "==> Packaging Corresponding Source archive"
STAGE="$WORK_DIR/source-stage/aqara-s1-plus-uboot-source"
rm -rf "$WORK_DIR/source-stage"
mkdir -p "$STAGE/board" "$STAGE/LICENSES"
git -C "$UBOOT_SRC" archive --format=tar --prefix=u-boot/ "$UBOOT_COMMIT" | tar -xf - -C "$STAGE"
git -C "$TFA_SRC" archive --format=tar --prefix=arm-trusted-firmware/ "$TFA_COMMIT" | tar -xf - -C "$STAGE"
cp -R "$HERE"/. "$STAGE/board/"
cp "$REPO_ROOT/LICENSES/GPL-2.0-only.txt" "$REPO_ROOT/LICENSES/BSD-3-Clause.txt" "$REPO_ROOT/LICENSES/MIT.txt" "$STAGE/LICENSES/"

TAR_BIN="tar"
if command -v gtar >/dev/null 2>&1; then
  TAR_BIN="gtar"
fi
SOURCE_TAR="$OUT_DIR/aqara-s1-plus-uboot-source.tar.xz"
if "$TAR_BIN" --version 2>/dev/null | grep -qi gnu; then
  "$TAR_BIN" --sort=name --mtime='UTC 2026-11-10' --owner=0 --group=0 --numeric-owner \
    -C "$WORK_DIR/source-stage" -cJf "$SOURCE_TAR" aqara-s1-plus-uboot-source
else
  COPYFILE_DISABLE=1 tar -C "$WORK_DIR/source-stage" -cJf "$SOURCE_TAR" aqara-s1-plus-uboot-source
fi
echo "Wrote $SOURCE_TAR"

if [ "$SOURCE_ONLY" -eq 1 ]; then
  exit 0
fi

# Prepare clean copies for building so source trees stay untouched.
BUILD_TFA="$WORK_DIR/build-tfa"
BUILD_UBOOT="$WORK_DIR/build-uboot"
rm -rf "$BUILD_TFA" "$BUILD_UBOOT"
git -C "$TFA_SRC" archive --format=tar "$TFA_COMMIT" | (mkdir -p "$BUILD_TFA" && tar -xf - -C "$BUILD_TFA")
git -C "$UBOOT_SRC" archive --format=tar "$UBOOT_COMMIT" | (mkdir -p "$BUILD_UBOOT" && tar -xf - -C "$BUILD_UBOOT")

if [ "${TFA_DEBUG:-0}" = "1" ]; then
  git apply --directory="$BUILD_TFA" "$HERE/tfa/0001-s1-debug-bl31-uart-markers-icache-off.patch"
fi

cp "$HERE/aqara-s1-plus_defconfig" "$BUILD_UBOOT/configs/"
cp "$HERE/sun50i-a133-aqara-s1-plus.dts" "$BUILD_UBOOT/dts/upstream/src/arm64/allwinner/"
for p in "$HERE"/patches/*.patch; do
  [ -e "$p" ] || continue
  patch -d "$BUILD_UBOOT" -p1 < "$p"
done

build_inside_linux() {
  local tfa_dir="$1" uboot_dir="$2" bl31_in="$3" tfa_debug="$4"
  local bl31_path="$bl31_in"
  if [ -z "$bl31_path" ]; then
    local dbg="0"
    local variant="release"
    if [ "$tfa_debug" = "1" ]; then
      dbg="1"
      variant="debug"
    fi
    make -C "$tfa_dir" PLAT=sun50i_a133 DEBUG="$dbg" -j"$(nproc)" bl31
    bl31_path="$tfa_dir/build/sun50i_a133/$variant/bl31.bin"
  fi
  cp "$bl31_path" "$uboot_dir/bl31-s1.bin"
  make -C "$uboot_dir" O=build-s1 aqara-s1-plus_defconfig
  make -C "$uboot_dir" O=build-s1 -j"$(nproc)" BL31="$uboot_dir/bl31-s1.bin" SCP=/dev/null
}

if [ "$MODE" = "native" ]; then
  echo "==> Building natively on Linux arm64"
  build_inside_linux "$BUILD_TFA" "$BUILD_UBOOT" "${BL31:-}" "${TFA_DEBUG:-0}"
else
  echo "==> Building in Docker ($DOCKER_IMAGE)"
  EXTRA_MOUNTS=()
  BL31_CONTAINER=""
  if [ -n "${BL31:-}" ]; then
    BL31_ABS="$(cd "$(dirname "$BL31")" && pwd)/$(basename "$BL31")"
    EXTRA_MOUNTS+=(-v "$BL31_ABS":/work/bl31-prebuilt.bin:ro)
    BL31_CONTAINER="/work/bl31-prebuilt.bin"
  fi
  docker run --rm --platform linux/arm64 \
    -v "$BUILD_TFA":/work/tfa \
    -v "$BUILD_UBOOT":/work/uboot \
    "${EXTRA_MOUNTS[@]}" \
    -e "TFA_DEBUG=${TFA_DEBUG:-0}" \
    -e "BL31_CONTAINER=$BL31_CONTAINER" \
    "$DOCKER_IMAGE" bash -euc '
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq >/dev/null
      apt-get install -y -qq build-essential bc bison flex libssl-dev python3 python3-dev \
          python3-setuptools python3-pyelftools swig device-tree-compiler libgnutls28-dev uuid-dev >/dev/null
      if [ -n "$BL31_CONTAINER" ]; then
        cp "$BL31_CONTAINER" /work/uboot/bl31-s1.bin
      else
        dbg=0; variant=release
        if [ "$TFA_DEBUG" = "1" ]; then dbg=1; variant=debug; fi
        make -C /work/tfa PLAT=sun50i_a133 DEBUG="$dbg" -j"$(nproc)" bl31
        cp "/work/tfa/build/sun50i_a133/$variant/bl31.bin" /work/uboot/bl31-s1.bin
      fi
      make -C /work/uboot O=build-s1 aqara-s1-plus_defconfig
      make -C /work/uboot O=build-s1 -j"$(nproc)" BL31=/work/uboot/bl31-s1.bin SCP=/dev/null
    '
fi

cp "$BUILD_UBOOT/build-s1/u-boot-sunxi-with-spl.bin" "$OUT_DIR/"
cp "$BUILD_UBOOT/build-s1/u-boot.bin" "$OUT_DIR/"

(
  cd "$OUT_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum u-boot-sunxi-with-spl.bin u-boot.bin aqara-s1-plus-uboot-source.tar.xz > SHA256SUMS
  else
    shasum -a 256 u-boot-sunxi-with-spl.bin u-boot.bin aqara-s1-plus-uboot-source.tar.xz > SHA256SUMS
  fi
)

python3 - "$HERE/UPSTREAM.json" "$OUT_DIR" "${GITHUB_SHA:-$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)}" <<'PY'
import hashlib, json, os, sys
from pathlib import Path

upstream = json.load(open(sys.argv[1]))
out = Path(sys.argv[2])
repo_sha = sys.argv[3]

def info(name):
    p = out / name
    data = p.read_bytes()
    return {"size": len(data), "sha256": hashlib.sha256(data).hexdigest()}

meta = {
    "component": upstream["component"],
    "frame": upstream["frame"],
    "device_bins_commit": repo_sha,
    "license": upstream["license"],
    "upstreams": upstream["upstreams"],
    "artifacts": {
        "u-boot-sunxi-with-spl.bin": info("u-boot-sunxi-with-spl.bin"),
        "u-boot.bin": info("u-boot.bin"),
    },
    "corresponding_source": {
        "file": "aqara-s1-plus-uboot-source.tar.xz",
        **info("aqara-s1-plus-uboot-source.tar.xz"),
    },
}
(out / "release-meta.json").write_text(json.dumps(meta, indent=2) + "\n")
PY

echo "==> Done:"
cat "$OUT_DIR/SHA256SUMS"
