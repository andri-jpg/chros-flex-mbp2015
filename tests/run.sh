#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"

valid_mac '02:11:22:33:44:55' || die 'locally administered unicast MAC should be valid'
! valid_mac '03:11:22:33:44:55' || die 'multicast MAC should be rejected'
! valid_mac '00:00:00:00:00:00' || die 'zero MAC should be rejected'
! valid_mac 'not-a-mac' || die 'malformed MAC should be rejected'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

manifest_path="$ROOT/tests/fixtures/manifest.json"
if command -v cygpath >/dev/null 2>&1; then
  manifest_url="file:///$(cygpath -m "$manifest_path")"
else
  manifest_url="file://$manifest_path"
fi
result=$(FLEX_MANIFEST_URL="$manifest_url" \
  "$ROOT/scripts/download-flex.sh" --channel stable --output-dir "$work/out" --dry-run)
[[ $(jq -r .version <<<"$result") == 16700.60.0 ]] || die 'downloader did not select the newest stable release'

printf 'all tests passed\n'
