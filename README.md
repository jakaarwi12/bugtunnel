# BugTunnel

Tunnel otomatis untuk Android. Aplikasi membaca daftar server publik, menguji ping, memilih yang tercepat, lalu menyambung lewat Xray. Satu-satunya isian manual yang benar-benar dibutuhkan adalah **bug host** (opsional).

Dibangun dengan Flutter/Dart dan `flutter_v2ray` (Xray core). APK di-build oleh GitHub Actions dan dipublikasikan ke halaman Releases.

## Fitur

- **Server otomatis** — mengambil beberapa daftar server publik, menguji koneksi TCP, dan memilih ping terendah.
- **Bug host** — secara default hanya menimpa header `Host` pada server WS/HTTP/gRPC. SNI **tidak** diubah kecuali toggle **Bug host sebagai SNI** diaktifkan. Kosongkan bila server tidak memerlukannya.
- **DNS otomatis** — setelah core melaporkan `CONNECTED`, aplikasi menguji DNS lewat SOCKS5 Xray. Bila gagal, aplikasi otomatis mencoba mode DNS lain. Toggle **DNS lewat server** tersedia di Pengaturan.
- **Failover** — bila server terpilih gagal, aplikasi mencoba hingga tiga server terbaik berikutnya, termasuk percobaan **tanpa bug host** bila bug host membuat koneksi gagal.
- **Log koneksi** — tab **Log** menampilkan detail pemuatan server, hasil ping, tes server, status Xray, dan error. Semua log bisa disalin atau ditambah dengan log sistem (logcat).
- **Daftar server** — lihat semua server, ping, pilih manual, atau muat ulang.
- **Pembaruan otomatis** — membandingkan versi terpasang dengan rilis terbaru di GitHub dan menawarkan unduhan APK.
- **Tanpa analytics** — pengaturan dan cache server hanya disimpan di perangkat.

## Cara pakai

1. Unduh APK terbaru dari [Releases](https://github.com/jakaarwi12/bugtunnel/releases).
2. Pasang APK (izinkan "instal dari sumber tidak dikenal" bila diminta).
3. Buka aplikasi, tekan **Muat daftar server** di tab Server.
4. Isi **Bug host** bila server/operatormu memerlukannya.
5. Tekan tombol besar di Beranda, lalu izinkan permintaan VPN Android.

Saat pertama kali menyambung, Android akan menampilkan dialog izin VPN. Ini wajib agar lalu lintas perangkat bisa dialirkan melalui tunnel.

## Bug host itu apa?

Bug host adalah nama host yang dipakai sebagai header **Host** (dan opsional **SNI**) saat berkomunikasi dengan server. Sebagian server gratis memakai trik ini agar koneksi terlihat menuju host lain (misalnya host layanan yang tidak dihitung kuotanya oleh operator).

Mulai v1.0.3, BugTunnel **hanya mengganti header Host** secara default. SNI dibiarkan sesuai konfigurasi server karena mengganti SNI ke host lain sering membuat handshake TLS gagal. Jika server memang mengharuskan SNI ikut diganti, aktifkan **Pengaturan → Bug host sebagai SNI**.

Isi tanpa `https://`, misalnya:

```
bug.example.com
```

## Sumber server

Bawaan aplikasi memakai beberapa daftar publik yang bisa berubah kapan saja:

- `peasoft/NoMoreWalls`
- `ermaozi/get_subscribe`
- `mahdibland/ShadowsocksAggregator`
- `ripaojiedian/freenode`
- `freefq/free`

Kamu bisa mengganti atau menambah URL di **Pengaturan → Sumber server**. Format yang didukung:

- daftar link langsung (`vmess://`, `vless://`, `trojan://`, `ss://`), satu per baris;
- langganan base64 dari daftar yang sama;
- JSON sederhana dengan kunci `servers`, `links`, `configs`, `list`, atau `data`.

Server publik tidak dijamin hidup, cepat, atau aman. BugTunnel tidak memiliki, menjual, atau memverifikasi server tersebut. Gunakan hanya server yang kamu berhak pakai dan patuhi hukum yang berlaku di tempatmu.

## Build sendiri

APK dibangun otomatis di GitHub Actions (`.github/workflows/build-apk.yml`):

```text
flutter create --platforms=android --org com.jakaarwi --project-name bugtunnel .
python3 tool/patch_android.py
flutter pub get
flutter build apk --release
```

Workflow memerlukan secrets berikut agar tanda tangan APK stabil antar-rilis:

| Secret | Isi |
|---|---|
| `KEYSTORE_BASE64` | keystore JKS dalam base64 |
| `KEYSTORE_PASSWORD` | password keystore |
| `KEY_PASSWORD` | password key |
| `KEY_ALIAS` | alias key |

Tanpa tanda tangan yang stabil, Android akan menolak memperbarui aplikasi yang sudah terpasang.

## Rilis & pembaruan

- Setiap push ke `main` menghasilkan artifact APK.
- Push tag `v*` (contoh `v1.0.0`) membuat GitHub Release dan melampirkan `bugtunnel.apk`.
- Aplikasi memeriksa `releases/latest` saat dibuka (maksimal sekali per sesi) dan menampilkan dialog bila versi tag lebih baru dari versi terpasang.

## Struktur

```text
lib/
  main.dart
  src/
    app_state.dart          # state, koneksi, pemilihan server, update
    models.dart
    theme.dart
    services/
      link_parser.dart      # vmess/vless/trojan/ss + base64 + JSON
      server_source.dart    # fetch daftar publik
      latency.dart          # ping TCP
      xray_config.dart      # konfigurasi Xray + bug host/SNI + routing DNS
      dns_probe.dart        # uji DNS lewat SOCKS5 Xray
      update_service.dart   # GitHub Releases API
    ui/
      root_shell.dart
      home_page.dart
      servers_page.dart
      settings_page.dart
      widgets.dart
tool/
  patch_android.py          # minSdk, signing, useLegacyPackaging, izin VPN
  icon/                     # ikon aplikasi
```

## Batasan

- Hanya Android (paket `flutter_v2ray` tidak mendukung iOS/desktop).
- Tes ping memakai koneksi TCP, bukan handshake proxy penuh. Server bisa terlihat hidup tetapi tetap gagal saat dipakai; tes `generate_204` dan failover menangani kasus ini.
- Bug host hanya menimpa Host (dan SNI bila diaktifkan). Tidak ada manipulasi payload atau kuota operator.
- Node VLESS tanpa TLS ke IP publik dilewati karena ditolak Xray. Tampil sebagai peringatan di log, bukan error fatal.
- Aplikasi tidak menyediakan server, akun, atau langganan.

## Troubleshooting

**Tersambung tetapi Chrome/YouTube tidak bisa internet (mis. `ping 8.8.8.8` lolos, `ping google.com` gagal)**

1. Buka tab **Log**, tekan **Hapus log**, lalu **Tes server terpilih**.
2. Kosongkan **Bug host** dan pastikan **Bug host sebagai SNI nonaktif**, lalu sambung lagi. Aplikasi juga otomatis mencoba tanpa bug host.
3. Perhatikan baris `DNS ...`. Bila tertulis `DNS gagal`, aktifkan **Pengaturan → DNS lewat server** (atau biarkan aplikasi mencoba otomatis saat connecting).
4. Set **Private DNS** Android ke **Off** atau **Automatic**.
5. Muat ulang daftar server; server publik sering mati.
6. Salin log lewat **Salin semua** bila masih gagal.

**Semua server gagal**

Salin log dari tab **Log** (tombol **Salin semua**) dan periksa baris `ERROR`. Baris `Tes ... gagal` berarti server tidak lolos uji; `Log sistem` berisi pesan asli dari Xray/tun2socks.

## Lisensi

Kode aplikasi ini ditulis untuk proyek ini. `flutter_v2ray`, Xray, dan daftar server pihak ketiga memiliki lisensi masing-masing. Lihat `THIRD_PARTY.md`.
