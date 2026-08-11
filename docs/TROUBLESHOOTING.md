# BCM43602 troubleshooting

## Start with a report

From a local ChromeOS shell, run:

```bash
sudo /usr/local/sbin/mbp2015-wifi-diagnose | tee /tmp/wifi-report.txt
```

Remove SSIDs, MAC addresses, IP addresses, and other personal identifiers before
posting the report.

## The adapter is missing

`lspci -nnk` should show device `14e4:43ba` with `brcmfmac` as the active driver.
Also check `rfkill list`.

If the module reports unknown symbols, do not install a module from another Linux
distribution. Remove the custom module bundle or rebuild it against the exact Flex
kernel source, configuration, and `Module.symvers`.

## Firmware load error `-2`

The modified rootfs should contain:

```text
/lib/firmware/brcm/brcmfmac43602-pcie.bin
/lib/firmware/brcm/brcmfmac43602-pcie.txt
/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro12,1.txt
```

Run `verify-image.sh` against the image and confirm that the USB was written from
the modified file rather than the original recovery image.

## Networks appear, but authentication fails

1. Start with WPA2-Personal/AES. Split WPA2 and WPA3 while testing.
2. Give the 2.4 GHz and 5 GHz radios separate SSIDs and test both.
3. Confirm that the NVRAM file contains the MacBook's hardware Wi-Fi address.
4. Forget the saved network and reconnect.
5. Compare against an image built with `--tuning none`.

Do not change `ccode`, `regrev`, SAR values, or power tables at random. They are
part of the card's regulatory and RF calibration data.

## Wi-Fi disappears after sleep

Collect reports immediately before suspend and after resume. Look for firmware
timeouts, `bus is down`, or a missing PCI device. Toggling Wi-Fi in the UI may
recover the card temporarily.

Driver unload/reload workarounds only apply when `brcmfmac` is a module. It may be
built into a particular Flex kernel.

## Wi-Fi breaks after a ChromeOS update

An A/B update can activate a new official rootfs without the added firmware and
NVRAM. Download the current recovery release, build a new image, and test it from
USB again. This project does not disable ChromeOS updates.

## The USB image does not boot

- Run `verify-image.sh` again.
- Check the USB media and rewrite the image.
- Try an image built without `--module-bundle`.
- Check that `make_dev_ssd.sh` reported at least one successfully re-signed kernel.
- Stay in **Try it first** mode until Wi-Fi and sleep/resume are stable.
