# Troubleshooting BCM43602

## Ambil log terlebih dahulu

Masuk ke shell lokal ChromeOS dan jalankan:

```bash
sudo /usr/local/sbin/mbp2015-wifi-diagnose | tee /tmp/wifi-report.txt
```

Sebelum membagikan laporan, hapus SSID, MAC address, alamat IP, dan identifier
pribadi lain.

## Adapter tidak muncul

Pastikan `lspci -nnk` menampilkan `14e4:43ba` dan `Kernel driver in use:
brcmfmac`. Periksa `rfkill list`. Jika modul tidak ada atau probe menghasilkan
unknown symbol, jangan memaksa modul distro lain; build ulang terhadap exact
kernel Flex atau kembali ke modul bawaan.

## Firmware load error `-2`

Nama yang seharusnya tersedia:

```text
/lib/firmware/brcm/brcmfmac43602-pcie.bin
/lib/firmware/brcm/brcmfmac43602-pcie.txt
/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro12,1.txt
```

Jalankan `verify-image.sh` pada image, lalu pastikan USB memang ditulis dari file
hasil build dan bukan image resmi yang lama.

## SSID terlihat tetapi autentikasi gagal

1. Uji WPA2-Personal/AES terlebih dahulu. Pisahkan WPA2 dan WPA3 selama diagnosis.
2. Uji 2.4 GHz dan 5 GHz dengan SSID berbeda.
3. Pastikan MAC pada file NVRAM sama dengan MAC hardware laptop.
4. Hapus profil jaringan dan sambungkan ulang.
5. Coba build dengan `--tuning none` untuk membandingkan efek `roamoff=1`.

Jangan langsung mengubah `ccode`, `regrev`, SAR, atau power table. Nilai tersebut
berhubungan dengan regulasi dan kalibrasi RF.

## Putus setelah sleep/resume

Kumpulkan dua laporan: sebelum suspend dan segera setelah resume. Cari pesan
`bus is down`, timeout firmware, atau perangkat PCI yang hilang. Coba matikan dan
nyalakan Wi-Fi dari UI. Workaround unload/reload driver hanya mungkin bila
`brcmfmac` dibangun sebagai modul; jangan berasumsi driver selalu modular.

## Setelah update ChromeOS masalah kembali

Update A/B dapat mengaktifkan rootfs resmi baru tanpa firmware/NVRAM tambahan.
Unduh release Flex terbaru, build ulang image, dan uji lagi. Project sengaja tidak
mematikan update otomatis karena browser yang tidak terpatch adalah risiko yang
lebih besar.

## Image tidak boot

- Verifikasi ulang dengan `verify-image.sh`.
- Tulis ulang USB dan cek checksum/storage media.
- Coba build tanpa `--module-bundle`.
- Pastikan `make_dev_ssd.sh` menyatakan setidaknya satu kernel berhasil di-resign.
- Jangan instal ke internal disk sebelum mode **Try it first** berhasil stabil.
