#!/usr/bin/env bash
# Shared-library globals are consumed by the scripts that source this file.
# shellcheck disable=SC2034

log() { printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "command '$1' is required"
}

sudo_prefix() {
  if [[ ${EUID} -eq 0 ]]; then
    SUDO=()
  else
    need_cmd sudo
    SUDO=(sudo)
  fi
}

absolute_path() {
  local path=$1
  if [[ -d $path ]]; then
    (cd "$path" && pwd -P)
  else
    local dir base
    dir=$(dirname "$path")
    base=$(basename "$path")
    printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
  fi
}

partition_path() {
  local loop=$1 number=$2
  if [[ $loop =~ [0-9]$ ]]; then
    printf '%sp%s\n' "$loop" "$number"
  else
    printf '%s%s\n' "$loop" "$number"
  fi
}

valid_mac() {
  local mac=${1,,} first
  [[ $mac =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]] || return 1
  [[ $mac != 00:00:00:00:00:00 && $mac != ff:ff:ff:ff:ff:ff ]] || return 1
  first=${mac%%:*}
  (( (16#$first & 1) == 0 ))
}
