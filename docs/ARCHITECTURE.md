# Arsitektur pipeline

## Sumber artefak

| Artefak | Sumber | Perlakuan |
|---|---|---|
| ChromeOS Flex | Manifest recovery resmi Google | URL dan SHA-1 dibaca dinamis |
| Firmware STA BCM43602 | Repository `linux-firmware` | Diunduh saat build, ukuran dan SHA-256 dicatat |
| NVRAM Apple | File lokal atau gist komunitas opt-in | MAC address wajib dipersonalisasi |
| Vboot tools/dev keys | ROOT-A image input | Selalu seversi dengan image yang diproses |
| Modul opsional | Exact ChromiumOS kernel tree | `vermagic` diverifikasi sebelum injeksi |

## Urutan build

```text
manifest Google -> ZIP terverifikasi -> image resmi
                                        |
                                        v
                           salin ke output (input immutable)
                                        |
                     ekstrak make_dev_ssd + devkeys dari ROOT-A
                                        |
                       resign KERN-A/B + nonaktifkan dm-verity
                                        |
                  mount ROOT-A/B yang valid dan suntikkan artefak
                                        |
                      unmount + verifier read-only + image akhir
```

ChromeOS memakai layout GPT dengan pasangan `KERN-A`/`ROOT-A` (partisi 2/3) dan
`KERN-B`/`ROOT-B` (4/5). Recovery image bisa memiliki slot B yang kosong; script
hanya memodifikasi filesystem ext yang benar-benar ada.

## Keputusan driver

ID PCI `14e4:43ba` dipetakan oleh driver kernel `brcmfmac` ke firmware
`brcmfmac43602-pcie`. Karena driver sudah in-tree, firmware dan board/NVRAM data
adalah lapisan pertama yang diperbaiki. Mengganti `.ko` meningkatkan risiko karena
kernel ChromeOS mempunyai config, symbol CRC, toolchain, dan patchset sendiri.

Jalur modul opsional mengharuskan satu bundle dengan struktur:

```text
lib/modules/RELEASE/kernel/drivers/net/wireless/broadcom/brcm80211/*.ko
```

Semua modul diperiksa dengan `modinfo -F vermagic`, disalin, lalu indeks modul
dibangun ulang dengan `depmod` di rootfs target.

## Reproducibility dan supply chain

- Manifest hasil download disimpan berdampingan sebagai `IMAGE.bin.json`.
- ZIP Google diverifikasi terhadap SHA-1 yang dipublikasikan manifest. SHA-1 di
  sini berfungsi sebagai checksum vendor, bukan klaim ketahanan kriptografis baru.
- Firmware dicatat SHA-256-nya di log build.
- Image besar dan material berlisensi pihak ketiga dikecualikan dari Git.
- CI hanya melakukan static shell analysis; hardware validation tetap manual.
