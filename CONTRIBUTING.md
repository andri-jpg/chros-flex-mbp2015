# Contributing

Hardware reports untuk `MacBookPro12,1` sangat berguna. Sertakan versi Flex,
kernel release, hasil `verify-image.sh`, jenis access point/security, serta hasil
tes 2.4 GHz, 5 GHz, dan sleep/resume. Sensor semua identifier pribadi.

Sebelum membuka pull request:

```bash
make check
```

Jangan commit image ChromeOS, firmware, NVRAM, MAC address, recovery log mentah,
atau binary module. Patch modul harus disertai referensi source ChromiumOS exact,
config, toolchain, dan alasan kenapa firmware/NVRAM tidak cukup.
