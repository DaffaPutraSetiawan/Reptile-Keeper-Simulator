# Setup Supabase (login & cloud save)

Langkah ini cukup dilakukan sekali. Selama `config.js` masih kosong, game tetap bisa dimainkan dalam mode offline (save hanya di browser).

## 1. Buat project

1. Daftar atau masuk di [supabase.com](https://supabase.com), lalu klik **New project**.
2. Isi nama project (misalnya `morphlab`) dan password database (simpan baik-baik).
3. Pilih region terdekat dengan pemain, misalnya **Southeast Asia (Singapore)**.

## 2. Buat tabel

1. Buka **SQL Editor → New query**.
2. Salin seluruh isi file [`supabase/schema.sql`](supabase/schema.sql), tempel, lalu klik **Run**.
3. Cek di **Table Editor**: sekarang ada tabel `profiles` dan `saves`, masing-masing dengan Row Level Security aktif.

Row Level Security memastikan setiap pemain hanya bisa membaca dan mengubah save miliknya sendiri.

## 3. Atur login email

1. Buka **Authentication → URL Configuration**.
   - **Site URL**: `https://daffaputrasetiawan.github.io/Reptile-Keeper-Simulator/`
   - **Redirect URLs**: tambahkan URL yang sama. Kalau kamu juga mengetes di komputer sendiri, tambahkan juga alamat lokalnya (misalnya `http://localhost:5500/`).
2. Buka **Authentication → Sign In / Providers → Email**, pastikan aktif.
   - **Confirm email** aktif: pemain harus klik link di email sebelum bisa masuk (disarankan untuk versi publik).
   - **Confirm email** dimatikan: pemain langsung masuk setelah daftar (praktis untuk tahap tes).
3. Layanan email bawaan Supabase punya batas kirim yang kecil dan hanya cocok untuk tes. Kalau pemain mulai banyak, sambungkan SMTP sendiri di **Authentication → Emails → SMTP Settings**.

## 4. Isi `config.js`

1. Buka **Project Settings → API Keys**.
2. Salin **Project URL** dan **Publishable key** (diawali `sb_publishable_`).
3. Isi keduanya di [`config.js`](config.js):

```js
window.MORPHLAB_CONFIG = {
  supabaseUrl: 'https://xxxxxxxxxxxx.supabase.co',
  supabasePublishableKey: 'sb_publishable_xxxxxxxxxxxx'
};
```

Publishable key memang dirancang untuk ditaruh di kode yang bisa dilihat publik, jadi aman di-commit ke GitHub.
**Jangan pernah** memasukkan *secret key* (`sb_secret_...`) atau *service_role key* ke file mana pun di repo ini.

## 5. Coba

1. Commit dan push `config.js`, lalu buka game di GitHub Pages.
2. Klik **☁️ Masuk / Daftar** di pojok kanan atas, lalu buat akun.
3. Mainkan satu bulan. Status di header akan berubah dari *Menyimpan…* ke *Tersimpan*.
4. Buka game di perangkat atau browser lain dan masuk dengan akun yang sama. Progresnya akan ikut termuat.

## 6. Aktifkan fitur teman, chat & trading

1. Buka **SQL Editor → New query**.
2. Salin seluruh isi [`supabase/social.sql`](supabase/social.sql), tempel, lalu klik **Run**. Jalankan **setelah** `schema.sql`.
   Kalau muncul peringatan *destructive operation*, klik **Run this query**. Itu karena ada perintah `drop policy` untuk membuat ulang aturan.
3. Cek di **Table Editor**: sekarang ada tabel `friendships`, `messages`, `trades`, `trade_escrow`, dan `deliveries`.
4. Chat dan notifikasi memakai **Realtime**. Script di atas sudah mendaftarkan tabelnya ke publikasi `supabase_realtime`.
   Untuk memastikan, buka **Database → Publications → supabase_realtime**. Tabel `messages`, `friendships`, `trades`, dan `deliveries` harus tercentang.
   Kalau realtime mati, game tetap memperbarui data setiap 45 detik.

### Cara kerja trading

- Trading hanya bisa dilakukan antar teman.
- Saat tawaran dikirim, ular dan uang yang ditawarkan langsung **dititipkan (escrow)** di server. Barang itu hilang dari koleksi penawar sampai tawaran dijawab, jadi tidak bisa dijual atau ditawarkan dua kali.
- Saat diterima, server menukar barang kedua pihak dalam satu transaksi: semuanya berpindah, atau tidak ada yang berpindah sama sekali.
- Kalau ditolak, dibatalkan, atau pertemanan dihapus, isi escrow dikembalikan utuh ke penawar.
- Server hanya mengubah save milik pemain yang sedang beraksi. Barang untuk pihak lain dikirim sebagai *kiriman* (tabel `deliveries`), yang otomatis diklaim saat game pemiliknya terbuka.
- Genotipe het tersembunyi tidak terlihat saat melihat koleksi atau tawaran teman. Genotipe aslinya baru ikut pindah setelah trade selesai.

## Cara kerja sync

- Save tetap disimpan di browser dan juga dikirim ke cloud sekitar 1,5 detik setelah setiap aksi.
- Setiap save di cloud punya nomor versi (`rev`). Kalau save di akun ternyata sudah diubah dari perangkat lain, game tidak akan menimpanya diam-diam. Pemain diminta memilih: pakai save akun atau save di perangkat ini.
- Saat keluar dari akun, browser kembali ke game baru. Progres akun tetap aman di cloud.

## Catatan keamanan

- Pertemanan, pesan, dan trade hanya bisa diubah lewat fungsi server yang memeriksa siapa pemanggilnya. Pemain tidak bisa memalsukan pertemanan, membaca chat orang lain, menerima tawaran milik orang lain, mengubah isi tawaran, atau menggandakan barang.
- Chat dibatasi 30 pesan per menit per pemain.
- **Yang belum terlindungi:** logika game (breeding, pasar, uang dari penjualan) masih berjalan di browser. Pemain yang paham DevTools bisa mengedit save-nya sendiri, misalnya menambah uang atau membuat ular langka, lalu menukarnya ke teman. Server menolak data ular yang tidak masuk akal, tapi belum bisa membuktikan asal-usulnya. Karena trading hanya antar teman, dampaknya terbatas pada orang yang kamu kenal. Langkah berikutnya untuk menutup celah ini adalah memindahkan logika breeding dan ekonomi ke server.
