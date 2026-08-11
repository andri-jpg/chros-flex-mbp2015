#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

NVRAM_URL=${NVRAM_URL:-https://gist.githubusercontent.com/MikeRatcliffe/9614c16a8ea09731a9d5e91685bd8c80/raw/brcmfmac43602-pcie.txt}
mac=''
output=''

usage() {
  cat <<'EOF'
Fetch the community BCM43602 Apple NVRAM and personalize its MAC address.

The upstream gist has no explicit redistribution license. This command downloads
it directly for personal use; this repository does not vendor or redistribute it.

Usage: fetch-nvram.sh --wifi-mac AA:BB:CC:DD:EE:FF --output FILE
EOF
}

while (($#)); do
  case $1 in
    --wifi-mac) mac=${2,,}; shift 2 ;;
    --output) output=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n $mac && -n $output ]] || { usage >&2; exit 2; }
valid_mac "$mac" || die "invalid unicast Wi-Fi MAC address: $mac"
need_cmd curl
mkdir -p "$(dirname "$output")"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl --fail --location --retry 4 --silent --show-error "$NVRAM_URL" -o "$tmp"
grep -q '^devid=0x43ba' "$tmp" || die "downloaded NVRAM is not for BCM43602 (14e4:43ba)"
grep -q '^macaddr=' "$tmp" || die "downloaded NVRAM has no macaddr field"
sed -E "s/^macaddr=.*/macaddr=$mac/" "$tmp" >"$output"
grep -q "^macaddr=$mac$" "$output" || die "failed to personalize NVRAM"
log "Wrote personalized NVRAM: $output"
