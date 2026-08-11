# ChromeOS Flex untuk MacBook Pro 13-inch Early 2015

Toolkit reproducible untuk membuat image ChromeOS Flex resmi yang sudah diberi
firmware dan konfigurasi Wi-Fi Broadcom BCM43602 (`14e4:43ba`) untuk
`MacBookPro12,1`.

> Status: **belum tervalidasi pada hardware fisik**. Pipeline memiliki pemeriksaan
> image dan ABI, tetapi hasil akhir tetap harus dites dari USB sebelum instalasi.

## Kenapa bukan langsung compile `wl`?

BCM43602 memakai driver kernel open-source **`brcmfmac`**, dan dukungan chip-nya
sudah ada di kernel Linux. Masalah yang umum pada MacBook ini adalah firmware STA
lama/tidak ada dan NVRAM kalibrasi Apple yang hilang. Karena itu default project:

1. mengunduh image Flex terbaru langsung dari manifest Google;
2. mematikan rootfs verification memakai `make_dev_ssd.sh` dan dev key yang berasal
   dari image yang sama;
3. memasukkan firmware BCM43602 terbaru dari `linux-firmware`;
4. memasukkan NVRAM Apple yang dipersonalisasi dengan MAC Wi-Fi laptop;
5. menambahkan tuning roaming konservatif dan alat diagnosis;
6. memverifikasi GPT, kernel command line, firmware, dan kedua slot root.

Penggantian modul kernel tetap didukung melalui `--module-bundle`, tetapi bersifat
eksperimental dan ditolak bila `vermagic` tidak cocok persis. Jangan memakai
`broadcom-sta`/`wl` untuk chip ini.

## Kebutuhan

- Linux native x86-64 atau WSL2 (Ubuntu 24.04; loop-device preflight sudah diuji)
- ruang kosong minimal 25 GB
- akses `sudo` dan loop device
- `curl`, `jq`, `unzip`, `cgpt`, `futility`, `dump_kernel_config`, `losetup`,
  `e2fsprogs`, dan `kmod`

Pada Ubuntu/Debian, nama paket umumnya:

```bash
sudo apt update
sudo apt install make curl jq unzip cgpt vboot-kernel-utils vboot-utils \
  e2fsprogs kmod pciutils rfkill shellcheck
```

Script melakukan preflight dan akan menyebut command yang belum tersedia.
Pada WSL2, clone dan build di filesystem Linux (`~/chros-flex-mbp2015`), bukan
langsung di `/mnt/c` atau `/mnt/d`. Setelah image selesai, salin hasilnya ke
Windows dan tulis USB dengan aplikasi raw-image Windows; USB flash drive tidak
ditangani langsung oleh pipeline WSL.

## Quick start

Catat MAC address Wi-Fi asli **sebelum menghapus macOS**:

```bash
networksetup -getmacaddress Wi-Fi
```

Lalu, di Linux:

```bash
git clone https://github.com/andri-jpg/chros-flex-mbp2015.git
cd chros-flex-mbp2015

./scripts/download-flex.sh --channel stable

sudo ./scripts/build-image.sh \
  --input downloads/chromeos-flex-VERSION-stable.bin \
  --output out/chromeos-flex-mbp2015.bin \
  --fetch-community-nvram \
  --wifi-mac AA:BB:CC:DD:EE:FF
```

Nama input dengan `VERSION` dicetak oleh downloader. `--fetch-community-nvram`
adalah opt-in karena file komunitas tersebut tidak memiliki lisensi redistribusi
yang eksplisit. Project ini mengunduhnya langsung saat build dan tidak
menyimpannya di repository.

Untuk melihat release terbaru tanpa mengunduh image besar:

```bash
./scripts/download-flex.sh --channel stable --dry-run
```

Alternatif yang lebih aman untuk distribusi publik adalah menyediakan file NVRAM
sendiri:

```bash
sudo ./scripts/build-image.sh \
  --input downloads/chromeos-flex-VERSION-stable.bin \
  --output out/chromeos-flex-mbp2015.bin \
  --nvram local/brcmfmac43602-pcie.txt
```

Jangan upload image hasil personalisasi: MAC address laptop tertanam di dalamnya.

## Inspeksi dan verifikasi

```bash
sudo ./scripts/inspect-image.sh out/chromeos-flex-mbp2015.bin
sudo ./scripts/verify-image.sh out/chromeos-flex-mbp2015.bin
make check
```

Verifier memeriksa bahwa kernel tidak lagi menunjuk `/dev/dm-*`, root memakai
mode `rw`, dan firmware BCM43602 valid tersedia pada setiap slot root yang aktif.

## Tulis ke USB dan tes

Cari device USB secara hati-hati:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
```

Setelah memastikan target yang benar, tulis image (contoh `/dev/sdX` adalah
placeholder dan seluruh isinya akan dihapus):

```bash
sudo dd if=out/chromeos-flex-mbp2015.bin of=/dev/sdX \
  bs=16M status=progress conv=fsync
```

Boot Mac sambil menahan `Option (⌥)`, pilih **EFI Boot**, lalu gunakan mode
**Try it first**. Uji minimal:

- koneksi WPA2 di 2.4 GHz dan 5 GHz;
- reconnect setelah Wi-Fi dimatikan/dinyalakan;
- sleep/resume beberapa kali;
- throughput dan packet loss selama 15–30 menit;
- Bluetooth bersamaan dengan Wi-Fi 2.4 GHz.

Di shell ChromeOS, laporan diagnosis dapat dibuat dengan:

```bash
sudo /usr/local/sbin/mbp2015-wifi-diagnose
```

Lihat [troubleshooting](docs/TROUBLESHOOTING.md) bila koneksi masih gagal.

## Build modul kernel opsional

Ini hanya masuk akal jika driver bawaan benar-benar tidak mendeteksi perangkat
atau ada patch `brcmfmac` tertentu yang hendak diuji. Dibutuhkan source dan build
tree ChromiumOS yang **persis** sama, termasuk `.config`, generated headers, dan
`Module.symvers`:

```bash
./scripts/build-driver.sh \
  --kernel-source /path/to/exact/chromeos-kernel \
  --kernel-build /path/to/prepared/build-tree \
  --kernel-release EXACT_RELEASE_FROM_INSPECT \
  --output build/modules

sudo ./scripts/build-image.sh ... --module-bundle build/modules
```

Versi kernel upstream yang nomornya terlihat sama belum tentu ABI-compatible.
Builder sengaja fail-closed bila release atau `vermagic` berbeda.

## Batasan penting

- Rootfs verification dinonaktifkan dan kernel ditandatangani ulang dengan dev
  keys. Integritas verified boot resmi Google tidak lagi berlaku pada image ini.
- Update ChromeOS dapat mengganti slot root dan menghapus modifikasi. Build ulang
  dari image Flex terbaru adalah alur maintenance yang didukung project ini.
- `MacBookPro12,1` bukan model yang dijamin dalam daftar sertifikasi Flex Google.
- NVRAM mengandung kalibrasi radio. Gunakan konfigurasi yang tepat dan MAC asli;
  jangan mengubah country code atau batas daya secara sembarang.
- Jangan menonaktifkan update otomatis hanya untuk mempertahankan patch; itu
  menukar masalah driver dengan risiko keamanan browser/OS.

Detail desain ada di [arsitektur](docs/ARCHITECTURE.md). Kontribusi hardware test,
log yang sudah disensor, dan patch dokumentasi sangat diterima.

## Lisensi

Kode project berlisensi MIT. ChromeOS Flex, firmware Broadcom, source ChromiumOS,
dan NVRAM pihak ketiga tetap tunduk pada lisensi masing-masing dan tidak
didistribusikan oleh repository ini.
