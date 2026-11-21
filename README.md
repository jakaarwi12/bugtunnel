# BugTunnel

Tunnel otomatis untuk Android. Aplikasi membaca daftar server publik, menguji ping, memilih yang tercepat, lalu menyambung lewat Xray. Satu-satunya isian manual yang benar-benar dibutuhkan adalah **bug host** (opsional).

Dibangun dengan Flutter/Dart dan `flutter_v2ray` (Xray core). APK di-build oleh GitHub Actions dan dipublikasikan ke halaman Releases.

## Fitur

- **Server otomatis** — mengambil beberapa daftar server publik, menguji koneksi TCP, dan memilih ping terendah.
- **Bug host** — secara default hanya menimpa header `Host` pada server WS/HTTP/gRPC. SNI **tidak** diubah kecuali toggle **Bug host sebagai SNI** diaktifkan. Kosongkan bila server tidak memerlukannya.
- **DNS otomatis** — setelah core melaporkan `CONNECTED`, aplikasi menguji DNS lewat SOCKS5 Xray. Bila gagal, aplikasi otomatis mencoba mode DNS lain. Mode yang berhasil **disimpan per server**, jadi tidak diulang terus. Pilih resolver **Otomatis**, **Google (8.8.8.8)**, atau **Cloudflare (1.1.1.1)** di Pengaturan.
- **Failover cepat** — bila server terpilih gagal, aplikasi mencoba hingga tiga server terbaik berikutnya, termasuk percobaan **tanpa bug host**. SNI bug hanya dicoba pada node yang tidak punya SNI sendiri, dan core yang langsung `DISCONNECTED` tidak menunggu 10 detik penuh.
- **Kompatibilitas Xray terbaru** (v1.0.6) — field TLS lama `allowInsecure` otomatis dibuang dari konfigurasi karena sudah ditolak Xray sejak 26.7.11. Saat **Bug host sebagai SNI** aktif pada node bersertifikat, verifikasi memakai `verifyPeerCertByName` dengan nama SNI asli (pengganti resmi dari Xray), jadi koneksi tetap bisa dibangun tanpa melewati verifikasi sertifikat.
- **Mode Game 🎮** — hanya aplikasi yang kamu pilih yang lewat tunnel; aplikasi lain memakai koneksi biasa. Pola ini mengikuti Mode Game di HTTP Injector.
- **Log koneksi** — tab **Log** menampilkan detail pemuatan server, hasil ping, tes server, status Xray, dan error. Semua log bisa disalin atau ditambah dengan log sistem (logcat).
- **Daftar server** — lihat semua server, ping, pilih manual, atau muat ulang.
- **Pembaruan otomatis** — membandingkan versi terpasang dengan rilis terbaru di GitHub dan menawarkan unduhan APK.
- **Tanpa analytics** — pengaturan dan cache server hanya disimpan di perangkat.

## Cara pakai

1. Unduh APK terbaru dari [Releases](https://github.com/jakaarwi12/bugtunnel/releases).
2. Pasang APK (izinkan "instal dari sumber tidak dikenal" bila diminta).
3. Buka aplikasi, tekan **Muat daftar server** di tab Server.
4. Isi **Bug host** bila server/operatormu memerlukannya.
5. Di Pengaturan, pilih **Resolver DNS** (Cloudflare sering lebih baik bila Google lambat).
6. Aktifkan **Mode Game** dan pilih aplikasi yang boleh lewat tunnel bila hanya ingin mem-tunnel game.
7. Tekan tombol besar di Beranda, lalu izinkan permintaan VPN Android.

Saat pertama kali menyambung, Android akan menampilkan dialog izin VPN. Ini wajib agar lalu lintas perangkat bisa dialirkan melalui tunnel.

## Bug host itu apa?

Bug host adalah nama host yang dipakai sebagai header **Host** (dan opsional **SNI**) saat berkomunikasi dengan server. Sebagian server gratis memakai trik ini agar koneksi terlihat menuju host lain (misalnya host layanan yang tidak dihitung kuotanya oleh operator).

Mulai v1.0.3, BugTunnel **hanya mengganti header Host** secara default. SNI dibiarkan sesuai konfigurasi server karena mengganti SNI ke host lain sering membuat handshake TLS gagal. Jika server memang mengharuskan SNI ikut diganti, aktifkan **Pengaturan → Bug host sebagai SNI**.

Isi tanpa `https://`, misalnya:

```
bug.example.com
```

## Mode Game

Mode Game meniru perilaku HTTP Injector: hanya aplikasi dalam daftar **Aplikasi yang diizinkan** yang lalu lintasnya lewat VPN. Aplikasi lain memakai jaringan biasa. Daftar berisi package name (misalnya `com.roblox.client`), dipilih lewat Pengaturan → **Aplikasi yang diizinkan**.

Mode Game tidak menambah server atau akun. Ia hanya mengatur pengecualian aplikasi pada VPN Android. Bila daftar kosong atau daftar aplikasi tidak bisa dibaca, BugTunnel otomatis membiarkan semua aplikasi lewat tunnel dan menulis peringatan di tab **Log**.

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
      installed_apps.dart   # daftar aplikasi Mode Game lewat MethodChannel
      update_service.dart   # GitHub Releases API
    ui/
      root_shell.dart
      home_page.dart
      servers_page.dart
      settings_page.dart
      widgets.dart
tool/
  patch_android.py          # minSdk, signing, useLegacyPackaging, izin VPN + QUERY_ALL_PACKAGES
  icon/                     # ikon aplikasi
```

## Batasan

- Hanya Android (paket `flutter_v2ray` tidak mendukung iOS/desktop).
- Tes ping memakai koneksi TCP, bukan handshake proxy penuh. Server bisa terlihat hidup tetapi tetap gagal saat dipakai; tes `generate_204` dan failover menangani kasus ini.
- Bug host hanya menimpa Host (dan SNI bila diaktifkan). Tidak ada manipulasi payload atau kuota operator.
- Node VLESS tanpa TLS ke IP publik dilewati karena ditolak Xray. Tampil sebagai peringatan di log, bukan error fatal.
- Aplikasi tidak menyediakan server, akun, atau langganan.
- Konfigurasi `.ehi` HTTP Injector dan akun SSH bawaan aplikasi tersebut tidak bisa dipindahkan ke BugTunnel. BugTunnel memakai Xray, bukan konektor SSH; SNI seperti `facebook.com` pada HTTP Injector adalah penyamar TLS untuk SSH, bukan SNI node VLESS/VMess.
- Mode Game memakai daftar package name. Aplikasi yang tidak terpasang tidak bisa dipilih dan akan muncul sebagai peringatan di log.

## Troubleshooting

**Tersambung tetapi Chrome/YouTube tidak bisa internet (mis. `ping 8.8.8.8` lolos, `ping google.com` gagal)**

Sejak **v1.0.5**, setelah core melaporkan `CONNECTED` aplikasi tidak hanya menguji DNS, tetapi juga menguji **HTTPS nyata lewat tunnel** (permintaan `generate_204`). Jadi "tersambung" belum berarti internet benar-benar jalan. Node yang lolos `CONNECTED` tetapi gagal tes HTTPS **ditolak** dan aplikasi lanjut failover. Baris log penentunya adalah `Tes internet lewat tunnel OK` atau `Tes internet lewat tunnel gagal`.

1. Buka tab **Log**, tekan **Hapus log**, lalu **Tes server terpilih**.
2. Kosongkan **Bug host** dan pastikan **Bug host sebagai SNI nonaktif**, lalu sambung lagi. Aplikasi juga otomatis mencoba tanpa bug host.
3. Perhatikan baris `DNS ...` hanya sebagai diagnostik. Dengan mode DNS `direct`, DNS dijawab jaringan Android, jadi baris ini **bukan** bukti tunnel bisa internet. Yang menentukan adalah baris `Tes internet lewat tunnel ...`.
4. Bila tes tunnel gagal, biarkan aplikasi mencoba mode DNS lain (mode yang lolos disimpan per server), lalu coba **Pengaturan → Resolver DNS → Cloudflare**. Toggle **DNS lewat server** tetap tersedia sebagai cadangan.
5. Set **Private DNS** Android ke **Off** atau **Automatic**.
6. Muat ulang daftar server; server publik sering mati.
7. Salin log lewat **Salin semua** bila masih gagal.

Catatan: opsi **Izinkan TLS insecure** yang ada di v1.0.5 sudah dihapus di v1.0.6. Xray 26.7.11+ tidak mengenal field itu lagi, sehingga mengaktifkannya justru membuat konfigurasi ditolak dan semua node gagal terhubung.

**Mode Game aktif tetapi aplikasi tertentu tidak bisa internet**

Pastikan package name aplikasi itu benar-benar dicentang di **Pengaturan → Aplikasi yang diizinkan**, lalu sambung ulang. Perubahan daftar aplikasi baru berlaku pada koneksi berikutnya. Baris `Mode Game: N aplikasi diizinkan, M aplikasi lain tidak lewat tunnel` di tab **Log** menunjukkan filter yang dipakai.

**Semua server gagal**

Salin log dari tab **Log** (tombol **Salin semua**) dan periksa baris `ERROR`. Baris `Tes ... gagal` berarti server tidak lolos uji; `Log sistem` berisi pesan asli dari Xray/tun2socks.

## Lisensi

Kode aplikasi ini ditulis untuk proyek ini. `flutter_v2ray`, Xray, dan daftar server pihak ketiga memiliki lisensi masing-masing. Lihat `THIRD_PARTY.md`.
