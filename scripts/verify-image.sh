#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

[[ $# -eq 1 ]] || { echo "usage: verify-image.sh IMAGE" >&2; exit 2; }
image=$1
[[ -f $image ]] || die "image not found: $image"
for cmd in cgpt dump_kernel_config losetup mount umount; do need_cmd "$cmd"; done
sudo_prefix

mount_dir=$(mktemp -d)
loop=''
roots_checked=0
kernels_checked=0
cleanup() {
  set +e
  mountpoint -q "$mount_dir" && "${SUDO[@]}" umount "$mount_dir"
  [[ -z ${loop:-} ]] || "${SUDO[@]}" losetup -d "$loop"
  rmdir "$mount_dir" 2>/dev/null || true
}
trap cleanup EXIT

cgpt show "$image" >/dev/null || die "invalid ChromeOS GPT"
loop=$("${SUDO[@]}" losetup --find --show --partscan --read-only "$image")

for kernel_number in 2 4; do
  kernel_part=$(partition_path "$loop" "$kernel_number")
  [[ -b $kernel_part ]] || continue
  config=$("${SUDO[@]}" dump_kernel_config "$kernel_part" 2>/dev/null || true)
  [[ -n $config ]] || continue
  grep -q 'root=/dev/dm-' <<<"$config" && die "kernel partition $kernel_number still enables dm-verity"
  grep -Eq '(^| )rw( |$)' <<<"$config" || die "kernel partition $kernel_number is not configured rw"
  kernels_checked=$((kernels_checked + 1))
done
((kernels_checked > 0)) || die "no usable kernel partition found"

for root_number in 3 5; do
  root_part=$(partition_path "$loop" "$root_number")
  [[ -b $root_part ]] || continue
  fs_type=$("${SUDO[@]}" blkid -o value -s TYPE "$root_part" 2>/dev/null || true)
  [[ $fs_type == ext2 || $fs_type == ext3 || $fs_type == ext4 ]] || continue
  "${SUDO[@]}" mount -o ro "$root_part" "$mount_dir"
  firmware="$mount_dir/lib/firmware/brcm/brcmfmac43602-pcie.bin"
  [[ -s $firmware ]] || die "ROOT partition $root_number has no BCM43602 firmware"
  [[ $(stat -c '%s' "$firmware") -gt 500000 ]] || die "BCM43602 firmware on ROOT partition $root_number is too small"
  if [[ -f $mount_dir/lib/firmware/brcm/brcmfmac43602-pcie.txt ]]; then
    ! grep -q 'xx:xx:xx:xx:xx:xx' "$mount_dir/lib/firmware/brcm/brcmfmac43602-pcie.txt" || die "NVRAM still has a placeholder MAC"
  fi
  roots_checked=$((roots_checked + 1))
  "${SUDO[@]}" umount "$mount_dir"
done

((roots_checked > 0)) || die "no usable ROOT partition found"
log "Image verification passed ($kernels_checked kernel, $roots_checked root partition(s))"
