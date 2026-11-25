#!/usr/bin/env bash
# Build the selinux_permissive kernel module for the lululemon Studio Mirror and package its
# Corresponding Source.
#
# Usage:
#   frames/lululemon-mirror/selinux-permissive/build.sh [--docker|--native] [--source-only] [--out <dir>] [--work <dir>]
#
# The module is a single freestanding C file with no includes and hardcoded ABI CRCs, so it builds
# with just clang targeting aarch64 — no Android NDK and no stock kernel tree. The toolchain (clang
# major version, target, and flags) is pinned in UPSTREAM.json; a mismatched compiler changes the
# bytes and so the published SHA-256, which is exactly why GlassworksHQ/glassworks pins a hash and
# verifies on real hardware before trusting a new build.
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
      sed -n '2,13p' "$0"
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
  python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d[k]
if isinstance(d, list):
    print(" ".join(str(x) for x in d))
else:
    print(d)' "$HERE/UPSTREAM.json" "$1"
}

COMPONENT="$(read_json component)"
MODULE_NAME="$(read_json source.name)"
SOURCE_FILE="$(read_json source.file)"
CLANG_MAJOR="$(read_json toolchain.major_version)"
CLANG_TARGET="$(read_json toolchain.target)"
CFLAGS="$(read_json toolchain.cflags)"
DOCKER_IMAGE="$(read_json docker_image)"
EXPECT_MODULE_LAYOUT="$(read_json abi.module_layout_crc)"
EXPECT_KALLSYMS="$(read_json abi.kallsyms_lookup_name_crc)"
EXPECT_VERMAGIC="$(read_json abi.vermagic)"
KO_NAME="${MODULE_NAME}.ko"
SOURCE_TAR="$OUT_DIR/${COMPONENT}-source.tar.xz"

echo "==> Packaging Corresponding Source archive"
STAGE_NAME="${COMPONENT}-source"
STAGE="$WORK_DIR/source-stage/$STAGE_NAME"
rm -rf "$WORK_DIR/source-stage"
mkdir -p "$STAGE/LICENSES"
cp "$HERE/$SOURCE_FILE" "$HERE/UPSTREAM.json" "$HERE/README.md" "$HERE/build.sh" "$STAGE/"
# In a repo checkout the license lives at the repo root; in an extracted Corresponding
# Source archive it sits next to this script. Prefer the archive-local copy so the
# shipped source rebuilds as-is.
if [ -f "$HERE/LICENSES/GPL-2.0-only.txt" ]; then
  cp "$HERE/LICENSES/GPL-2.0-only.txt" "$STAGE/LICENSES/"
else
  cp "$REPO_ROOT/LICENSES/GPL-2.0-only.txt" "$STAGE/LICENSES/"
fi

TAR_BIN="tar"
if command -v gtar >/dev/null 2>&1; then
  TAR_BIN="gtar"
fi
if "$TAR_BIN" --version 2>/dev/null | grep -qi gnu; then
  "$TAR_BIN" --sort=name --mtime='UTC 2026-11-10' --owner=0 --group=0 --numeric-owner \
    -C "$WORK_DIR/source-stage" -cJf "$SOURCE_TAR" "$STAGE_NAME"
else
  COPYFILE_DISABLE=1 tar -C "$WORK_DIR/source-stage" -cJf "$SOURCE_TAR" "$STAGE_NAME"
fi
echo "Wrote $SOURCE_TAR"

if [ "$SOURCE_ONLY" -eq 1 ]; then
  exit 0
fi

compile_module() {
  # $1 = clang binary, $2 = objcopy/readelf prefix dir (optional), $3 = output .ko
  local cc="$1" out_ko="$3"
  # shellcheck disable=SC2086
  "$cc" --target="$CLANG_TARGET" $CFLAGS -o "$out_ko" "$HERE/$SOURCE_FILE"
}

if [ "$MODE" = "native" ]; then
  echo "==> Building natively with clang-$CLANG_MAJOR"
  CC="${CC:-clang-$CLANG_MAJOR}"
  if ! command -v "$CC" >/dev/null 2>&1; then CC="clang"; fi
  ACTUAL_MAJOR="$("$CC" --version | sed -n 's/.*clang version \([0-9][0-9]*\).*/\1/p' | head -1)"
  if [ "$ACTUAL_MAJOR" != "$CLANG_MAJOR" ]; then
    echo "::warning::clang major $ACTUAL_MAJOR != pinned $CLANG_MAJOR; the .ko bytes (and its SHA-256) may differ" >&2
  fi
  compile_module "$CC" "" "$OUT_DIR/$KO_NAME"
else
  echo "==> Building in Docker ($DOCKER_IMAGE)"
  docker run --rm \
    -v "$HERE":/src:ro \
    -v "$OUT_DIR":/out \
    -e "CLANG_MAJOR=$CLANG_MAJOR" -e "CLANG_TARGET=$CLANG_TARGET" \
    -e "CFLAGS=$CFLAGS" -e "SOURCE_FILE=$SOURCE_FILE" -e "KO_NAME=$KO_NAME" \
    "$DOCKER_IMAGE" bash -euc '
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq >/dev/null
      apt-get install -y -qq "clang-$CLANG_MAJOR" >/dev/null
      # shellcheck disable=SC2086
      "clang-$CLANG_MAJOR" --target="$CLANG_TARGET" $CFLAGS -o "/out/$KO_NAME" "/src/$SOURCE_FILE"
    '
fi

echo "==> Verifying the built module's ABI"
python3 - "$OUT_DIR/$KO_NAME" "$EXPECT_MODULE_LAYOUT" "$EXPECT_KALLSYMS" "$EXPECT_VERMAGIC" <<'PY'
import struct, sys
ko = open(sys.argv[1], "rb").read()
expect_ml = int(sys.argv[2], 16)
expect_ks = int(sys.argv[3], 16)
expect_vm = sys.argv[4]

# ELF64 header sanity
assert ko[:4] == b"\x7fELF" and ko[4] == 2 and ko[5] == 1, "not a 64-bit LE ELF"
(e_type, e_machine) = struct.unpack_from("<HH", ko, 16)
assert e_type == 1, f"not ET_REL (got {e_type})"
assert e_machine == 183, f"not AArch64 (got {e_machine})"

# Section headers: find __versions and .modinfo by name
e_shoff, = struct.unpack_from("<Q", ko, 0x28)
e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", ko, 0x3a)
def shdr(i):
    o = e_shoff + i * e_shentsize
    name, _type, _flags, _addr, offset, size = struct.unpack_from("<IIQQQQ", ko, o)
    return name, offset, size
shstr_off = shdr(e_shstrndx)[1]
def secname(nameoff):
    end = ko.index(b"\0", shstr_off + nameoff)
    return ko[shstr_off + nameoff:end].decode()
sections = {}
for i in range(e_shnum):
    name, offset, size = shdr(i)
    sections[secname(name)] = (offset, size)

off, size = sections["__versions"]
seen = {}
for p in range(off, off + size, 64):
    crc, = struct.unpack_from("<Q", ko, p)
    nm = ko[p + 8:p + 64].split(b"\0", 1)[0].decode()
    seen[nm] = crc
assert seen.get("module_layout") == expect_ml, f"module_layout CRC {seen.get('module_layout'):#x} != {expect_ml:#x}"
assert seen.get("kallsyms_lookup_name") == expect_ks, f"kallsyms_lookup_name CRC != {expect_ks:#x}"

off, size = sections[".modinfo"]
modinfo = ko[off:off + size].split(b"\0")
entries = {e.split(b"=", 1)[0].decode(): e.split(b"=", 1)[1].decode() for e in modinfo if b"=" in e}
assert entries.get("license") == "GPL", f"license is {entries.get('license')!r}, must be GPL"
assert entries.get("vermagic") == expect_vm, f"vermagic {entries.get('vermagic')!r} != expected {expect_vm!r}"
print(f"OK: ET_REL aarch64, module_layout={expect_ml:#x}, license=GPL, vermagic={entries['vermagic']!r}")
PY

(
  cd "$OUT_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$KO_NAME" "$(basename "$SOURCE_TAR")" > SHA256SUMS
  else
    shasum -a 256 "$KO_NAME" "$(basename "$SOURCE_TAR")" > SHA256SUMS
  fi
)

python3 - "$HERE/UPSTREAM.json" "$OUT_DIR" "$KO_NAME" "$(basename "$SOURCE_TAR")" \
  "${GITHUB_SHA:-$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)}" <<'PY'
import hashlib, json, sys
from pathlib import Path

upstream = json.load(open(sys.argv[1]))
out = Path(sys.argv[2])
ko_name = sys.argv[3]
source_name = sys.argv[4]
repo_sha = sys.argv[5]

def info(name):
    data = (out / name).read_bytes()
    return {"size": len(data), "sha256": hashlib.sha256(data).hexdigest()}

meta = {
    "component": upstream["component"],
    "frame": upstream["frame"],
    "device_bins_commit": repo_sha,
    "license": upstream["license"],
    "toolchain": upstream["toolchain"],
    "abi": upstream["abi"],
    "artifacts": {ko_name: info(ko_name)},
    "corresponding_source": {"file": source_name, **info(source_name)},
}
(out / "release-meta.json").write_text(json.dumps(meta, indent=2) + "\n")
PY

echo "==> Done:"
cat "$OUT_DIR/SHA256SUMS"
