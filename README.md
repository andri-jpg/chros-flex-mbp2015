# ChromeOS Flex on the 2015 13-inch MacBook Pro

[![shellcheck](https://github.com/andri-jpg/chros-flex-mbp2015/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/andri-jpg/chros-flex-mbp2015/actions/workflows/shellcheck.yml)

Builds a ChromeOS Flex recovery image with working firmware and board data for
the Broadcom BCM43602 Wi-Fi card found in `MacBookPro12,1`.

The stock Flex image already carries the correct Linux driver (`brcmfmac`). The
usual problem on this Mac is the firmware side: the generic image may be missing
the current STA firmware and the Apple-specific NVRAM calibration data. This
project adds those files without replacing the driver unless an exact-kernel
module bundle is explicitly supplied.

## Current status

- Official stable Flex image discovery and checksum verification: working
- Offline image modification under Ubuntu 24.04 and WSL2: working
- Both ChromeOS kernel slots re-signed with the image's USB recovery keys
- Modified image passes the included GPT, kernel command-line, and firmware checks
- Physical `MacBookPro12,1` testing: in progress

Do not install to the internal SSD before the USB image has survived normal Wi-Fi
use, reconnects, and sleep/resume on your machine.

## What the build does

1. Reads Google's recovery manifest and downloads the latest requested Flex channel.
2. Uses `make_dev_ssd.sh` and recovery keys taken from that same image to remove
   rootfs verification from `KERN-A` and `KERN-B`.
3. Installs the BCM43602 STA firmware from `linux-firmware`.
4. Installs a personalized Apple NVRAM file under both generic and DMI-specific names.
5. Optionally sets `brcmfmac roamoff=1` to avoid firmware roaming-related disconnects.
6. Checks the resulting image before returning it to the caller.

The input image is never modified.

## Requirements

- Native x86-64 Linux or WSL2; Ubuntu 24.04 is the tested build environment
- At least 25 GB of free space
- Root access and a working loop device

Install the build tools on Ubuntu:

```bash
sudo apt update
sudo apt install make curl jq unzip cgpt vboot-kernel-utils vboot-utils \
  e2fsprogs kmod pciutils rfkill shellcheck
```

For WSL2, keep the repository and working images in the Linux filesystem, for
example `~/chros-flex-mbp2015`. Building under `/mnt/c` or `/mnt/d` is much slower.
Copy only the finished image back to Windows for flashing.

## Build an image

Record the Wi-Fi hardware address before removing macOS:

```bash
networksetup -getmacaddress Wi-Fi
```

Clone the repository and download the latest stable image:

```bash
git clone https://github.com/andri-jpg/chros-flex-mbp2015.git
cd chros-flex-mbp2015

./scripts/download-flex.sh --channel stable
```

The downloader prints the exact output path. Use that path when running the
builder:

```bash
sudo ./scripts/build-image.sh \
  --input downloads/chromeos-flex-VERSION-stable.bin \
  --output out/chromeos-flex-mbp2015.bin \
  --fetch-community-nvram \
  --wifi-mac AA:BB:CC:DD:EE:FF
```

`--fetch-community-nvram` is deliberately opt-in. The community NVRAM file does
not carry an explicit redistribution license, so it is fetched directly during a
personal build and is not stored in this repository.

If you already have a suitable NVRAM file, use it directly:

```bash
sudo ./scripts/build-image.sh \
  --input downloads/chromeos-flex-VERSION-stable.bin \
  --output out/chromeos-flex-mbp2015.bin \
  --nvram local/brcmfmac43602-pcie.txt
```

The resulting image contains the machine's hardware address. Keep it private.

To inspect the currently available release without downloading it:

```bash
./scripts/download-flex.sh --channel stable --dry-run
```

## Check the image

The builder runs the verifier automatically. It can also be run separately:

```bash
sudo ./scripts/inspect-image.sh out/chromeos-flex-mbp2015.bin
sudo ./scripts/verify-image.sh out/chromeos-flex-mbp2015.bin
```

Run the repository checks with:

```bash
make check
make test
```

## Flash and test

Write the image with a raw-image tool. If using `dd`, identify the USB device by
model and capacity first. `/dev/sdX` below is only a placeholder and will be
completely overwritten:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
sudo dd if=out/chromeos-flex-mbp2015.bin of=/dev/sdX \
  bs=16M status=progress conv=fsync
```

Hold `Option` while starting the Mac and select **EFI Boot**. Choose **Try it
first** and test at least:

- WPA2 connectivity on 2.4 GHz and 5 GHz
- reconnecting after toggling Wi-Fi
- several sleep/resume cycles
- sustained traffic and packet loss for 15 to 30 minutes
- Bluetooth while using 2.4 GHz Wi-Fi

A small diagnostic script is installed in the image:

```bash
sudo /usr/local/sbin/mbp2015-wifi-diagnose
```

See [Troubleshooting](docs/TROUBLESHOOTING.md) for the common failure modes.

## Replacing the kernel module

This is an advanced fallback, not the normal fix. ChromeOS kernels have their own
patch set, configuration, symbol CRCs, and toolchain. A module built for an
upstream kernel with the same version number is not necessarily compatible.

Given the exact prepared ChromiumOS source and build trees:

```bash
./scripts/build-driver.sh \
  --kernel-source /path/to/chromeos-kernel \
  --kernel-build /path/to/prepared-build-tree \
  --kernel-release EXACT_RELEASE_FROM_INSPECT \
  --output build/modules

sudo ./scripts/build-image.sh ... --module-bundle build/modules
```

The builder checks every module's `vermagic` and refuses mismatched bundles.

## Caveats

- Rootfs verification is disabled and the kernels are re-signed with USB recovery
  keys. The modified image no longer has Google's original verified-boot chain.
- A ChromeOS A/B update can replace the modified rootfs. Rebuild from the newest
  Flex recovery image if Wi-Fi breaks after an update.
- `MacBookPro12,1` is not on Google's currently supported Flex model list.
- Do not guess radio calibration, country-code, SAR, or power-table values.
- Disabling automatic updates is not recommended; an outdated browser is a worse
  trade-off than rebuilding the image when needed.

Implementation details are in [Architecture](docs/ARCHITECTURE.md).

## License

The scripts and documentation in this repository are MIT licensed. ChromeOS Flex,
Broadcom firmware, ChromiumOS source, and third-party NVRAM data remain under
their respective terms and are not redistributed here.
