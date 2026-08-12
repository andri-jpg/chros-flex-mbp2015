# Architecture

## Inputs

| Input | Source | Handling |
|---|---|---|
| ChromeOS Flex | Google's official recovery manifest | URL and vendor SHA-1 are read at download time |
| BCM43602 STA firmware | `linux-firmware` | Downloaded during the build; SHA-256 is logged |
| Apple NVRAM | Local file or explicit community download | Personalized with the machine's Wi-Fi address |
| vboot scripts and USB recovery keys | `ROOT-A` in the input image | Always taken from the release being modified |
| Optional kernel modules | Exact ChromiumOS kernel build | Checked against the target kernel's `vermagic` |

## Build flow

```text
Google recovery manifest -> verified archive -> official Flex image
                                                   |
                                      copy to a separate output
                                                   |
                              extract vboot tools from ROOT-A
                                                   |
                         re-sign KERN-A/B without dm-verity
                                                   |
                         enable the local EFI developer path
                                                   |
                           mount each usable root partition
                                                   |
                     install firmware, NVRAM, and diagnostics
                                                   |
                           unmount and verify read-only
```

ChromeOS uses paired kernel and root partitions: `KERN-A`/`ROOT-A` are partitions
2 and 3; `KERN-B`/`ROOT-B` are partitions 4 and 5. Recovery images often carry a
minimal or empty B root. The builder modifies only root partitions that contain a
mountable ext filesystem.

## Why firmware comes first

PCI ID `14e4:43ba` is supported by the in-tree `brcmfmac` driver and maps to
`brcmfmac43602-pcie`. Replacing the driver is therefore unnecessary unless a
specific kernel patch is being tested. Supplying current STA firmware and the
correct Apple board data fixes the missing part while keeping the image's own
driver ABI intact.

An optional module bundle must use this layout:

```text
lib/modules/RELEASE/kernel/drivers/net/wireless/broadcom/brcm80211/*.ko
```

Each module is checked with `modinfo -F vermagic` before it is copied. `depmod` is
then run against the target rootfs.

## Integrity and traceability

- The selected recovery-manifest entry is saved next to the downloaded image as
  `IMAGE.bin.json`.
- The recovery ZIP is checked against Google's published checksum. SHA-1 is used
  here as the vendor-provided download checksum, not as a new security guarantee.
- The firmware SHA-256 is printed in the build log.
- Generated images, firmware, NVRAM data, and module binaries are ignored by Git.
- CI covers shell analysis and small deterministic tests. Boot and radio behavior
  still require the physical MacBook.
