#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

MANIFEST_URL=${FLEX_MANIFEST_URL:-https://dl.google.com/dl/edgedl/chromeos/recovery/cloudready_recovery2.json}
channel=stable
output_dir=downloads
force=0
dry_run=0

usage() {
  cat <<'EOF'
Download the newest official ChromeOS Flex recovery image.

Usage: download-flex.sh [--channel stable|beta|dev|ltc|ltr] [--output-dir DIR] [--dry-run] [--force]
EOF
}

while (($#)); do
  case $1 in
    --channel) channel=${2,,}; shift 2 ;;
    --output-dir) output_dir=$2; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ $channel =~ ^(stable|beta|dev|ltc|ltr)$ ]] || die "unsupported channel: $channel"
need_cmd curl
need_cmd jq
need_cmd unzip
need_cmd sha1sum

mkdir -p "$output_dir"
output_dir=$(absolute_path "$output_dir")
manifest=$(mktemp)
archive=''
tmp_image=''
cleanup() { rm -f "$manifest" "${archive:-}" "${tmp_image:-}"; }
trap cleanup EXIT

log "Reading official Flex manifest"
curl --fail --location --retry 4 --silent --show-error "$MANIFEST_URL" -o "$manifest"
entry=$(jq -cer --arg channel "${channel^^}" '
  map(select(.name == "ChromeOS Flex" and .channel == $channel))
  | sort_by(.version | split(".") | map(tonumber)) | last
' "$manifest") || die "ChromeOS Flex channel '$channel' was not found in the manifest"

version=$(jq -r .version <<<"$entry")
chrome_version=$(jq -r .chrome_version <<<"$entry")
url=$(jq -r .url <<<"$entry")
expected_sha1=$(jq -r .sha1 <<<"$entry")
filename=$(jq -r .file <<<"$entry")
output="$output_dir/chromeos-flex-${version}-${channel}.bin"
metadata="$output.json"

if ((dry_run)); then
  jq '{channel, version, chrome_version, filesize, zipfilesize, sha1, url}' <<<"$entry"
  exit 0
fi

if [[ -f $output && $force -eq 0 ]]; then
  log "Already present: $output"
  printf '%s\n' "$output"
  exit 0
fi

archive=$(mktemp --tmpdir="$output_dir" .flex-download.XXXXXX.zip)
tmp_image=$(mktemp --tmpdir="$output_dir" .flex-image.XXXXXX.bin)
log "Downloading ChromeOS Flex $version (Chrome $chrome_version, $channel)"
curl --fail --location --retry 4 --continue-at - --progress-bar "$url" -o "$archive"

actual_sha1=$(sha1sum "$archive" | awk '{print $1}')
[[ $actual_sha1 == "$expected_sha1" ]] || die "archive checksum mismatch (got $actual_sha1)"
log "Extracting $filename (about 9.5 GB)"
unzip -p "$archive" "$filename" >"$tmp_image"
[[ -s $tmp_image ]] || die "extracted image is empty"
mv -f "$tmp_image" "$output"
tmp_image=''
jq --arg downloaded_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  '. + {downloaded_at: $downloaded_at}' <<<"$entry" >"$metadata"
log "Saved and verified: $output"
printf '%s\n' "$output"
