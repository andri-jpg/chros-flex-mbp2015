#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -eq 1 ]] || { echo "usage: install-diagnostics.sh ROOTFS" >&2; exit 2; }
root=$1
install -d -m 0755 "$root/usr/local/sbin"
install -m 0755 "$(dirname "$0")/wifi-diagnose.sh" "$root/usr/local/sbin/mbp2015-wifi-diagnose"
