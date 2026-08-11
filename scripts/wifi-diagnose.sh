#!/usr/bin/env bash
set -u

echo '=== hardware ==='
lspci -nnk 2>/dev/null | grep -A4 -i 'network controller' || true
echo '=== brcmfmac module ==='
modinfo brcmfmac 2>/dev/null | grep -E '^(filename|version|vermagic|firmware|parm):' || true
echo '=== firmware files ==='
find /lib/firmware/brcm -maxdepth 1 -iname 'brcmfmac43602*' -printf '%f %s bytes\n' 2>/dev/null | sort
echo '=== rfkill ==='
rfkill list 2>/dev/null || true
echo '=== kernel log ==='
dmesg 2>/dev/null | grep -Ei 'brcmfmac|brcmutil|cfg80211|firmware' | tail -n 150 || true
echo '=== interfaces ==='
ip -brief link 2>/dev/null || true
echo '=== shill ==='
if command -v dbus-send >/dev/null 2>&1; then
  dbus-send --system --print-reply --dest=org.chromium.flimflam / org.chromium.flimflam.Manager.GetProperties 2>/dev/null || true
fi
