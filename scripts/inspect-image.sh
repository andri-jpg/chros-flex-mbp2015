#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

[[ $# -eq 1 ]] || { echo "usage: inspect-image.sh IMAGE" >&2; exit 2; }
image=$1
[[ -f $image ]] || die "image not found: $image"
for cmd in cgpt losetup mount umount; do need_cmd "$cmd"; done
sudo_prefix
mount_dir=$(mktemp -d)
loop=''
cleanup() {
  set +e
  mountpoint -q "$mount_dir" && "${SUDO[@]}" umount "$mount_dir"
  [[ -z ${loop:-} ]] || "${SUDO[@]}" losetup -d "$loop"
  rmdir "$mount_dir" 2>/dev/null || true
}
trap cleanup EXIT

echo '=== GPT ==='
cgpt show "$image"
loop=$("${SUDO[@]}" losetup --find --show --partscan --read-only "$image")
for part_number in 3 5; do
  part=$(partition_path "$loop" "$part_number")
  [[ -b $part ]] || continue
  fs_type=$("${SUDO[@]}" blkid -o value -s TYPE "$part" 2>/dev/null || true)
  [[ $fs_type == ext2 || $fs_type == ext3 || $fs_type == ext4 ]] || continue
  "${SUDO[@]}" mount -o ro "$part" "$mount_dir"
  echo "=== ROOT-$part_number ==="
  grep -E '^(CHROMEOS_RELEASE_(VERSION|CHROME_MILESTONE|BOARD)|GOOGLE_RELEASE)=' "$mount_dir/etc/lsb-release" 2>/dev/null || true
  find "$mount_dir/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf 'kernel=%f\n' 2>/dev/null || true
  find "$mount_dir/lib/firmware/brcm" -maxdepth 1 -iname 'brcmfmac43602*' -printf '%f %s bytes\n' 2>/dev/null | sort || true
  "${SUDO[@]}" umount "$mount_dir"
done
