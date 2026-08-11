#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

kernel_source=''
kernel_build=''
kernel_release=''
output=''

usage() {
  cat <<'EOF'
Build the in-tree brcm80211 drivers against an EXACT ChromeOS Flex kernel tree.

Usage: build-driver.sh --kernel-source DIR --kernel-build DIR \
  --kernel-release RELEASE --output DIR

The prepared build tree must contain .config, include/generated, and Module.symvers
from the exact Flex kernel. A same-version upstream kernel is not ABI-compatible.
EOF
}

while (($#)); do
  case $1 in
    --kernel-source) kernel_source=$2; shift 2 ;;
    --kernel-build) kernel_build=$2; shift 2 ;;
    --kernel-release) kernel_release=$2; shift 2 ;;
    --output) output=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n $kernel_source && -n $kernel_build && -n $kernel_release && -n $output ]] || { usage >&2; exit 2; }
for cmd in make modinfo find; do need_cmd "$cmd"; done
[[ -f $kernel_build/.config ]] || die "kernel build tree has no .config"
[[ -f $kernel_build/Module.symvers ]] || die "kernel build tree has no Module.symvers; exact symbol CRCs are mandatory"
driver_source="$kernel_source/drivers/net/wireless/broadcom/brcm80211"
[[ -f $driver_source/Makefile ]] || die "brcm80211 source not found under $kernel_source"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -a "$driver_source" "$work/brcm80211"
log "Building brcmutil, brcmfmac, and brcmsmac for $kernel_release"
make -C "$kernel_build" M="$work/brcm80211" modules

bundle="$output/lib/modules/$kernel_release/kernel/drivers/net/wireless/broadcom/brcm80211"
mkdir -p "$bundle"
while IFS= read -r -d '' module; do
  relative=${module#"$work/brcm80211/"}
  mkdir -p "$bundle/$(dirname "$relative")"
  cp "$module" "$bundle/$relative"
done < <(find "$work/brcm80211" -type f -name '*.ko' -print0)

count=0
while IFS= read -r -d '' module; do
  vermagic=$(modinfo -F vermagic "$module")
  [[ $vermagic == "$kernel_release"* ]] || die "built module has wrong vermagic: $module ($vermagic)"
  count=$((count + 1))
done < <(find "$bundle" -type f -name '*.ko' -print0)
((count > 0)) || die "build produced no modules"
printf 'kernel_release=%s\nmodules=%s\n' "$kernel_release" "$count" >"$output/manifest.txt"
log "Module bundle ready: $output ($count modules)"
