#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

FIRMWARE_URL=${FIRMWARE_URL:-https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main/brcm/brcmfmac43602-pcie.bin}
input=''
output=''
nvram=''
wifi_mac=''
fetch_community_nvram=0
module_bundle=''
tuning=conservative

usage() {
  cat <<'EOF'
Customize an official ChromeOS Flex image for MacBookPro12,1 / BCM43602.

Usage:
  build-image.sh --input flex.bin --output flex-mbp2015.bin [options]

NVRAM options (choose one):
  --nvram FILE                    Use a locally supplied BCM43602 NVRAM file
  --fetch-community-nvram         Download the community Apple NVRAM at build time
  --wifi-mac AA:BB:CC:DD:EE:FF   Required with --fetch-community-nvram

Other options:
  --module-bundle DIR             Inject exact-kernel modules built by build-driver.sh
  --tuning conservative|none      Set brcmfmac roamoff=1 (default: conservative)

Requires Linux, root privileges, loop devices, cgpt, and vboot utilities.
EOF
}

while (($#)); do
  case $1 in
    --input) input=$2; shift 2 ;;
    --output) output=$2; shift 2 ;;
    --nvram) nvram=$2; shift 2 ;;
    --fetch-community-nvram) fetch_community_nvram=1; shift ;;
    --wifi-mac) wifi_mac=${2,,}; shift 2 ;;
    --module-bundle) module_bundle=$2; shift 2 ;;
    --tuning) tuning=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n $input && -n $output ]] || { usage >&2; exit 2; }
[[ -f $input ]] || die "input image not found: $input"
[[ $tuning == conservative || $tuning == none ]] || die "invalid tuning mode: $tuning"
[[ -z $nvram || $fetch_community_nvram -eq 0 ]] || die "choose --nvram or --fetch-community-nvram, not both"
if ((fetch_community_nvram)); then
  valid_mac "$wifi_mac" || die "--fetch-community-nvram requires a valid unicast --wifi-mac"
fi
if [[ -n $nvram ]]; then
  [[ -f $nvram ]] || die "NVRAM file not found: $nvram"
  grep -q '^devid=0x43ba' "$nvram" || die "NVRAM does not declare BCM43602 devid=0x43ba"
  grep -Eq '^macaddr=([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$' "$nvram" || die "NVRAM needs a real macaddr"
  nvram_mac=$(sed -n 's/^macaddr=//p' "$nvram" | head -n1)
  valid_mac "$nvram_mac" || die "NVRAM macaddr is not a valid unicast address"
fi

for cmd in cgpt curl dump_kernel_config futility losetup mount umount blkid cp install sed sha256sum; do
  need_cmd "$cmd"
done
sudo_prefix

input=$(absolute_path "$input")
output_dir=$(dirname "$output")
output_dir_created=0
[[ -d $output_dir ]] || output_dir_created=1
mkdir -p "$output_dir"
output=$(absolute_path "$output")
[[ $input != "$output" ]] || die "output must differ from input"
work=$(mktemp -d)
loop=''
mount_dir="$work/root"
mkdir -p "$mount_dir"

cleanup() {
  set +e
  mountpoint -q "$mount_dir" && "${SUDO[@]}" umount "$mount_dir"
  [[ -z ${loop:-} ]] || "${SUDO[@]}" losetup -d "$loop"
  [[ ! -d $work ]] || "${SUDO[@]}" rm -rf -- "$work"
}
trap cleanup EXIT

log "Copying base image (input is never modified)"
cp --reflink=auto --sparse=always "$input" "$output"

log "Extracting the image-matched ChromiumOS vboot tools and USB recovery keys"
loop=$("${SUDO[@]}" losetup --find --show --partscan --read-only "$output")
root_a=$(partition_path "$loop" 3)
"${SUDO[@]}" mount -o ro "$root_a" "$mount_dir"
mkdir -p "$work/vboot/lib/shflags"
cp "$mount_dir/usr/share/vboot/bin/make_dev_ssd.sh" "$work/vboot/"
cp "$mount_dir/usr/share/vboot/bin/common_minimal.sh" "$work/vboot/"
cp -a "$mount_dir/usr/share/vboot/devkeys" "$work/vboot/"
if [[ -f $mount_dir/usr/share/misc/shflags ]]; then
  cp "$mount_dir/usr/share/misc/shflags" "$work/vboot/lib/shflags/shflags"
else
  cp "$mount_dir/usr/share/vboot/bin/lib/shflags/shflags" "$work/vboot/lib/shflags/shflags"
fi
"${SUDO[@]}" umount "$mount_dir"
"${SUDO[@]}" losetup -d "$loop"
loop=''
chmod +x "$work/vboot/make_dev_ssd.sh"

log "Disabling dm-verity and making ROOT-A/ROOT-B writable"
GPT=$(command -v cgpt) FUTILITY=$(command -v futility) \
  "${SUDO[@]}" "$work/vboot/make_dev_ssd.sh" \
  --remove_rootfs_verification --image "$output" --partitions '2 4' \
  --keys "$work/vboot/devkeys" --backup_dir "$work/backups" \
  --recovery_key --force

# On generic EFI systems, GRUB loads the unpacked kernel from the ESP instead of
# the re-signed ChromeOS kernel partition. Mark that local/unverified boot path as
# an intentional developer boot; otherwise ChromeOS may shut down during early
# userspace initialization.
log "Enabling cros_debug on the local EFI boot path"
loop=$("${SUDO[@]}" losetup --find --show --partscan "$output")
efi_part=$(partition_path "$loop" 12)
"${SUDO[@]}" mount -o rw "$efi_part" "$mount_dir"
grub_cfg="$mount_dir/efi/boot/grub.cfg"
[[ -f $grub_cfg ]] || die "EFI GRUB configuration not found"
"${SUDO[@]}" sed -i \
  '/^[[:space:]]*linux /{/cros_debug/! s/ cros_efi/ cros_efi cros_debug/;}' \
  "$grub_cfg"
grep -A1 'menuentry "local image A"' "$grub_cfg" | grep -q 'cros_debug' || \
  die "failed to enable cros_debug for local image A"
"${SUDO[@]}" umount "$mount_dir"
"${SUDO[@]}" losetup -d "$loop"
loop=''

firmware="$work/brcmfmac43602-pcie.bin"
log "Downloading current BCM43602 STA firmware from linux-firmware"
curl --fail --location --retry 4 --silent --show-error "$FIRMWARE_URL" -o "$firmware"
[[ $(stat -c '%s' "$firmware") -gt 500000 ]] || die "firmware download is unexpectedly small"
log "Firmware SHA-256: $(sha256sum "$firmware" | awk '{print $1}')"

if ((fetch_community_nvram)); then
  nvram="$work/brcmfmac43602-pcie.txt"
  "$SCRIPT_DIR/fetch-nvram.sh" --wifi-mac "$wifi_mac" --output "$nvram"
elif [[ -n $nvram ]]; then
  nvram=$(absolute_path "$nvram")
fi

loop=$("${SUDO[@]}" losetup --find --show --partscan "$output")
for part_number in 3 5; do
  root_part=$(partition_path "$loop" "$part_number")
  [[ -b $root_part ]] || continue
  fs_type=$("${SUDO[@]}" blkid -o value -s TYPE "$root_part" 2>/dev/null || true)
  [[ $fs_type == ext2 || $fs_type == ext3 || $fs_type == ext4 ]] || continue
  log "Customizing root partition $part_number ($fs_type)"
  "${SUDO[@]}" mount -o rw "$root_part" "$mount_dir"
  target_fw="$mount_dir/lib/firmware/brcm"
  "${SUDO[@]}" install -d -m 0755 "$target_fw"
  "${SUDO[@]}" install -m 0644 "$firmware" "$target_fw/brcmfmac43602-pcie.bin"
  if [[ -n $nvram ]]; then
    "${SUDO[@]}" install -m 0644 "$nvram" "$target_fw/brcmfmac43602-pcie.txt"
    "${SUDO[@]}" install -m 0644 "$nvram" "$target_fw/brcmfmac43602-pcie.Apple Inc.-MacBookPro12,1.txt"
  fi

  if [[ $tuning == conservative ]]; then
    "${SUDO[@]}" install -d -m 0755 "$mount_dir/etc/modprobe.d"
    printf '%s\n' '# Reduce BCM43602 firmware roaming-related disconnects; remove if roaming is needed.' \
      'options brcmfmac roamoff=1' | "${SUDO[@]}" tee "$mount_dir/etc/modprobe.d/mbp2015-brcmfmac.conf" >/dev/null
  fi

  if [[ -n $module_bundle ]]; then
    module_bundle=$(absolute_path "$module_bundle")
    shopt -s nullglob
    kernel_dirs=("$mount_dir"/lib/modules/*)
    ((${#kernel_dirs[@]} == 1)) || die "expected exactly one kernel release in root partition $part_number"
    kernel_release=$(basename "${kernel_dirs[0]}")
    bundle_root="$module_bundle/lib/modules/$kernel_release"
    [[ -d $bundle_root ]] || die "module bundle has no release $kernel_release"
    module_count=0
    while IFS= read -r -d '' module; do
      vermagic=$(modinfo -F vermagic "$module")
      [[ $vermagic == "$kernel_release"* ]] || die "module vermagic '$vermagic' does not match '$kernel_release': $module"
      module_count=$((module_count + 1))
    done < <(find "$bundle_root" -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' \) -print0)
    ((module_count > 0)) || die "module bundle contains no kernel modules"
    "${SUDO[@]}" cp -a "$bundle_root/." "$mount_dir/lib/modules/$kernel_release/"
    "${SUDO[@]}" depmod -b "$mount_dir" "$kernel_release"
  fi

  "${SUDO[@]}" "$SCRIPT_DIR/install-diagnostics.sh" "$mount_dir"
  sync
  "${SUDO[@]}" umount "$mount_dir"
done

"${SUDO[@]}" losetup -d "$loop"
loop=''
log "Verifying customized image"
"${SUDO[@]}" "$SCRIPT_DIR/verify-image.sh" "$output"
if [[ -n ${SUDO_UID:-} && -n ${SUDO_GID:-} ]]; then
  chown "$SUDO_UID:$SUDO_GID" "$output"
  if ((output_dir_created)); then
    chown "$SUDO_UID:$SUDO_GID" "$(dirname "$output")"
  fi
fi
log "Done: $output"
