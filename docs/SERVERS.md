# Format sumber server

BugTunnel bisa membaca tiga bentuk sumber. Semuanya diisi di **Pengaturan → Sumber server**, satu URL per baris.

## 1. Daftar link langsung

Satu link per baris:

```text
vmess://eyJ2IjoiMiIsInBzIjoiY29udG9oIiwiYWRkIjoiMS4yLjMuNCIsInBvcnQiOiI0NDMiLCJpZCI6InV1aWQiLCJuZXQiOiJ3cyIsInRscyI6InRscyJ9
vless://uuid@host:443?security=tls&type=ws&path=%2F#Nama
trojan://password@host:443?security=tls#Nama
ss://YWVzLTI1Ni1nY206cGFzcw==@host:8388#Nama
```

Baris kosong dan baris komentar (`#` atau `//`) diabaikan.

## 2. Langganan base64

Isi respons adalah base64 dari daftar link di atas. Banyak panel VPN memakai format ini.

## 3. JSON

```json
{
  "servers": [
    "vless://uuid@host:443?security=tls&type=ws&path=%2F#Contoh"
  ]
}
```

Kunci yang dikenali: `servers`, `links`, `configs`, `list`, `data`.

## Catatan

- Aplikasi mengambil maksimal 600 server per sumber dan menguji maksimal 90 kandidat pertama.
- Server diurutkan: yang merespons lebih dulu, lalu ping terendah.
- Bug host hanya mengubah SNI/header Host; ia tidak memperbaiki server yang mati atau kredensial yang salah.
- Jangan menaruh kredensial pribadi di repositori publik. Gunakan URL langganan yang memang kamu miliki.
