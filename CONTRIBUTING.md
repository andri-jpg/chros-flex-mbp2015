# Contributing

Reports from a real `MacBookPro12,1` are the most useful contribution right now.
Please include:

- ChromeOS Flex and kernel versions
- whether the image was built with the default tuning
- access-point security mode and frequency band
- results for 2.4 GHz, 5 GHz, reconnect, and sleep/resume
- relevant output from `mbp2015-wifi-diagnose`

Remove SSIDs, MAC addresses, IP addresses, and other personal data from logs.

Before opening a pull request:

```bash
make check
make test
```

Do not commit ChromeOS images, firmware blobs, NVRAM files, hardware addresses,
raw diagnostic logs, or compiled modules. Kernel-module changes should document
the exact ChromiumOS source revision, configuration, toolchain, and why a
firmware/NVRAM-only fix is insufficient.
