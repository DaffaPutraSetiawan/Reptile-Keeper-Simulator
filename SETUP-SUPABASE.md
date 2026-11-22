# Setup Supabase (login & cloud save)

Langkah ini cukup dilakukan sekali. Game wajib login, jadi `config.js` harus terisi dan server harus siap sebelum game bisa dimainkan.

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
- **Unfriend** menghapus permanen semua chat di antara kedua pemain dan membatalkan trade yang sedang berlangsung. Game menampilkan peringatan dulu sebelum dijalankan.
- **Global chat**: tabel `global_messages` (bisa dibaca semua pemain yang login, tidak bisa ditulis langsung). Kirim lewat RPC `send_global_message(body)` — maks. 300 karakter, 10 pesan/menit per pemain, wajib punya username — dan setelah setiap pesan baru server hanya menyimpan **50 pesan terakhir** (yang lebih lama dihapus). Dibaca lewat `get_global_messages()` dan realtime (tabel ini ada di publikasi `supabase_realtime`). Pesan pemain yang akunnya dihapus ikut terhapus.
- **Asal-usul ular (origin keeper)**: tiap ular menyimpan `src` (cara pemilik sekarang mendapatkannya: ular awal, pasar, hasil breeding, atau trade), `origin` (pemain pertama yang memeliharanya + caranya), dan `keepers` (pemilik sebelumnya, maks. 10). `src` untuk ular awal/pasar/breeding diisi Edge Function `game`; `origin`, `keepers`, dan `src` trade dicap oleh `_stamp_transfer` di `accept_trade` — hanya saat ular benar-benar pindah tangan, bukan saat escrow atau pengembalian. Data ini ikut tampil di koleksi teman, pratinjau tawaran, dan showcase.
- **Profil pemain**: kolom `profiles.bio` (maks. 160 karakter) dan `profiles.showcase` (maks. 6 id ular). Dibaca lewat RPC `get_profile(username)` (statistik, relasi pertemanan, dan showcase versi publik — het tersembunyi tidak bocor) dan diubah lewat `update_profile(bio, showcase)` yang memeriksa ular itu benar milik pemain. Showcase dikosongkan saat akun di-reset.
- **Multi-spesies (ball python, leopard gecko & axolotl)**: tiap hewan punya kolom `sp` di save (`'ball'` kalau kosong, `'leo'` untuk leopard gecko, `'axo'` untuk axolotl). Bayi axolotl menetas sebagai `broods` di save; pemain memilih maksimal 3 lewat aksi `brood` dan sisanya dijual otomatis. `_valid_snake` memeriksa gen sesuai spesiesnya dan berat minimal 1 g (gecko jauh lebih ringan), sedangkan `_public_snake` menyertakan `sp` dan menyembunyikan het gecko (Tremper/Bell/Rainwater, Eclipse, Blizzard, Murphy, Marble) dan axolotl (Leucistic, Albino, Melanoid, Axanthic, Copper). Angka per spesies (umur kawin, telur, suhu, pasar, batas umur) ada di objek `SPECIES` di `core.js`.
- **Reset & hapus akun oleh pemain** (Akun → Zona bahaya): keduanya memakai 2 verifikasi — "Apakah kamu yakin?" lalu mengetik `RESET` atau `DELETE`. Kata itu juga dicek di server: Edge Function `game` menolak reset tanpa `confirm: 'RESET'` (lalu memanggil `_reset_account` untuk membatalkan tawaran yang belum dijawab dan membuang kiriman lama), dan RPC `delete_my_account('DELETE')` menghapus akun pemain itu sendiri dari `auth.users`.
- **Kalau akun dihapus** (misalnya oleh admin di Authentication → Users), trigger `morphlab_before_user_delete` lebih dulu membatalkan tawaran yang menunggu jawaban akun itu dan mengembalikan barangnya ke penawar. Tawaran yang dikirim akun itu dan belum dijawab ikut dibatalkan. Setelah itu chat, pertemanan, profil, dan save akun tersebut terhapus. Riwayat trade pemain lain dengan akun itu **tetap ada** dan tampil sebagai "(akun dihapus)"; riwayat baru dibuang kalau kedua pemainnya sudah dihapus.
- Server hanya mengubah save milik pemain yang sedang beraksi. Barang untuk pihak lain dikirim sebagai *kiriman* (tabel `deliveries`), yang otomatis diklaim saat game pemiliknya terbuka.
- Genotipe het tersembunyi tidak terlihat saat melihat koleksi atau tawaran teman. Genotipe aslinya baru ikut pindah setelah trade selesai.

## 7. Mode online: Edge Function `game`

Saat pemain login, game berjalan dalam **mode online ("server-authoritative")**. Browser hanya mengirim *aksi* (lanjut bulan, kawinkan, beli, jual, dan seterusnya). Edge Function `game` yang menjalankannya: mengocok angka acak (telur, gen, ovulasi, pasar), menghitung uang, lalu menyimpan hasilnya. Browser **tidak punya izin menulis** ke tabel `saves`, hanya membaca miliknya sendiri.

- Logika game ada di [`core.js`](core.js). Server menjalankan semua aksi dengan file ini (salinannya ada di `supabase/functions/game/core.js`); browser memakainya hanya untuk menampilkan nama morph, nilai, dan peluang.
- Setiap kali `core.js` diubah, naikkan `VERSION` di bagian atas `core.js` (samakan dengan nomor versi berikutnya di Supabase → Edge Functions → game), jalankan `./scripts/sync-core.sh`, lalu deploy ulang fungsinya. Versi server dan versi web tampil di **Pengaturan → Tentang**; kalau berbeda, pemain diminta memuat ulang halaman.
  ```bash
  supabase functions deploy game --project-ref <project-ref>
  ```
  (Atau minta Claude men-deploy lewat konektor Supabase.)
- Fungsi ini memakai kunci rahasia server yang otomatis tersedia di Supabase (`SUPABASE_SECRET_KEYS`). Kunci itu tidak pernah dikirim ke browser.
- Setiap save punya nomor versi (`rev`). Kalau dua perubahan terjadi bersamaan (misalnya trade diterima saat kamu klik "Lanjut bulan"), server membaca ulang dan mengulang aksinya, jadi tidak ada yang saling menimpa.

### Wajib login

Game hanya bisa dimainkan setelah login. Pengunjung yang belum login melihat halaman sambutan dengan tombol **Masuk** dan **Daftar**. Tidak ada mode offline, jadi tidak ada logika game yang berjalan bebas di browser.

## 8. Masukan: laporan bug & saran

1. Buka **SQL Editor → New query**.
2. Salin seluruh isi [`supabase/bugs.sql`](supabase/bugs.sql), tempel, lalu klik **Run**. Jalankan **setelah** `social.sql`. Skrip ini membuat tabel masukan (`bug_reports`, kolom `kind` = `bug` / `idea`), dukungan saran (`idea_votes`), komentar, bucket Storage privat `bug-reports` (maks. 2 MB per gambar, JPG/PNG/WebP), dan policy-nya.
3. Jadikan akunmu admin (ganti emailnya):

   ```sql
   insert into public.admins (user_id) select id from auth.users where lower(email) = 'email@contoh.com'
   on conflict do nothing;
   ```

Aturan yang dijalankan server:

- Semua pemain yang login bisa membaca semua laporan dan berkomentar. Info perangkat hanya terlihat oleh pelapor & admin.
- Setiap laporan wajib punya judul, deskripsi, kategori, dan 1–3 gambar. Gambar dicek ulang di server (ada di Storage, milik pelapor, ≤ 2 MB, JPG/PNG/WebP).
- Batas spam: 3 laporan dan 9 gambar per 24 jam, serta 30 komentar per 24 jam (admin tidak dibatasi).
- Hanya admin yang bisa mengubah status, membalas, menghapus komentar, dan menghapus laporan.
- Saran (`kind = 'idea'`): gambar opsional (0–3), batas 3 saran per 24 jam (terpisah dari batas laporan bug), tanpa info perangkat. Pemain lain bisa mendukung lewat `vote_idea` (sekali per saran; tidak untuk saran sendiri atau saran yang sudah Selesai/Ditolak/Duplikat). `similar_reports` mencari judul yang mirip saat pemain menulis.
- Status saran: `new`, `review`, `planned`, `progress`, `done`, `rejected`, `duplicate`. Admin bisa mengisi versi (untuk `fixed` / `done`) dan ID masukan asli (untuk `duplicate`). Pengirim dan pendukung mendapat notifikasi saat status berubah (`feedback_unread`). Saran `done` dengan versi muncul di catatan pembaruan game sebagai "Saran dari …" (`done_ideas`).
- Kata kasar di judul, deskripsi, dan komentar disensor dengan daftar kata dari `moderation.sql` (dilewati kalau file itu belum dijalankan).
- Pembersihan: saat admin membuka tab Masukan, gambar dari laporan yang selesai lebih dari 90 hari dan gambar yatim (diunggah > 1 hari tapi tidak dipakai laporan) dihapus otomatis.

## 9. Papan peringkat

1. Buka **SQL Editor → New query**.
2. Salin seluruh isi [`supabase/leaderboard.sql`](supabase/leaderboard.sql), tempel, lalu klik **Run**. Jalankan **sebelum** men-deploy Edge Function `game` versi 28 ke atas, karena fungsi itu menulis ke kolom `saves.rank`.

Angka peringkat (kekayaan, Morph Dex, hewan termahal per spesies, bayi menetas, pesanan, reputasi) dihitung oleh Edge Function `game` setiap kali save disimpan, jadi tidak bisa dipalsukan dari browser. Pemain lama otomatis masuk papan peringkat saat login berikutnya. Kategori reputasi butuh `leaderboard.sql` versi terbaru (jalankan ulang file itu; aman dijalankan ulang).

## 10. Moderasi chat & tab Admin

1. Buka **SQL Editor → New query**.
2. Salin seluruh isi [`supabase/moderation.sql`](supabase/moderation.sql), tempel, lalu klik **Run**. Jalankan **setelah** `bugs.sql` (admin memakai tabel `admins` yang sama).

- Pemain bisa melaporkan pesan di chat global. Isi pesan disalin ke laporan, karena chat global hanya menyimpan 50 pesan terakhir.
- Admin melihat tab **Admin**: ringkasan angka, antrean laporan, pemain yang dibisukan, dan log tindakan. Dari tab itu atau langsung dari chat, admin bisa menghapus pesan dan membisukan pemain di chat global (chat pribadi tidak terpengaruh).
- Kata yang disensor ada di tabel `chat_banned_words` dan bisa diubah tanpa deploy ulang:
  ```sql
  insert into public.chat_banned_words (word) values ('katabaru') on conflict do nothing;
  delete from public.chat_banned_words where word = 'kata';
  select word from public.chat_banned_words order by word;
  ```
  Huruf a–z saja, minimal 3 huruf. Huruf berulang dan angka/simbol pengganti (a→4/@, i→1/!, e→3, o→0, s→5/$) ikut tertangkap; hanya kata utuh yang disensor.
- Pembersihan otomatis saat admin membuka tab Admin: laporan chat yang sudah ditutup > 90 hari, statistik chat > 30 hari, dan log admin > 1 tahun.

## 11. Pasar Pemain

1. Buka **SQL Editor → New query**.
2. Salin seluruh isi [`supabase/market.sql`](supabase/market.sql), tempel, lalu klik **Run**. Jalankan **setelah** `social.sql` (memakai fungsi bantu trade dan tabel `deliveries`) dan `moderation.sql` (log admin), lalu deploy ulang Edge Function `game` (aksi `market_list`).

- Memasang jualan lewat Edge Function `game`: server menghitung nilai hewan dan menolak harga di bawah 50% nilai atau di atas $100.000.000. Hewan keluar dari save dan dititipkan di `market_escrow` dalam satu transaksi (`_market_list`, hanya bisa dipanggil kunci server).
- Membeli (`buy_listing`) dan membatalkan (`cancel_listing`) adalah fungsi database. Baris jualan dikunci saat dibeli, jadi kalau dua pemain membeli bersamaan hanya satu yang berhasil. Uang untuk penjual dan hewan yang kembali dikirim lewat `deliveries` dan diklaim otomatis, sama seperti hasil trade.
- Jualan yang lewat 14 hari dikembalikan ke penjual setiap kali seseorang membuka Pasar Pemain. Kalau penjual me-reset atau menghapus akun, jualan aktifnya dibuang.
- Riwayat harga (`get_market_prices`) dihitung dari penjualan 30 hari terakhir per morph & kelamin: median, rentang tengah (kuartil 25%–75%), dan harga termahal.
- Moderasi di tab Admin: `admin_market` (daftar jualan aktif / terjual + tanda mencurigakan), `admin_market_takedown` (turunkan jualan dengan alasan; hewan kembali ke penjual) dan `admin_market_exclude` (keluarkan / masukkan lagi penjualan ke riwayat harga). Semua tindakan tercatat di `admin_log`, jadi jalankan `market.sql` **setelah** `moderation.sql`.
- Tabel `market_listings` dan `market_escrow` tertutup untuk browser (RLS tanpa policy); semua akses lewat fungsi server.

## 12. Sewa pejantan

1. Buka **SQL Editor → New query**.
2. Salin seluruh isi [`supabase/stud.sql`](supabase/stud.sql), tempel, lalu klik **Run**. Jalankan **setelah** `social.sql` (memakai fungsi bantu save dan tabel `deliveries`), lalu deploy ulang Edge Function `game` (aksi `stud_list` & `stud_book`).

- Menawarkan jantan lewat Edge Function `game`: server menghitung nilai jantan dan menolak biaya di bawah 50% nilai atau di atas $100.000.000. Jantannya tetap di save pemilik. `_stud_list` menyimpan save dan penawaran dalam satu transaksi.
- Menyewa lewat Edge Function: `_stud_peek` membaca jantan asli dari save pemilik (genotipe lengkap, hanya untuk server), logika game memasangkan betina penyewa, lalu `_stud_book` menyimpan save penyewa, menambah hitungan sewa, mencatat penyewa, dan mengirim uang ke pemilik lewat `deliveries`. Baris penawaran dikunci, jadi batas 5 sewa tidak bisa dilewati walaupun ada penyewa bersamaan.
- Penawaran yang jantannya sudah tidak ada di save pemilik (dijual, di-trade, mati, akun di-reset) atau sedang diiklankan ditutup otomatis setiap kali daftar dibuka.
- Fungsi untuk browser: `get_studs` (daftar aktif, het tersembunyi disamarkan), `get_my_studs` (penawaran saya + penyewa), `cancel_stud`.
- Tabel `stud_listings` dan `stud_bookings` tertutup untuk browser (RLS tanpa policy).

## Catatan keamanan

- **Save online hanya bisa diubah server**: Edge Function `game` dan fungsi trading di `social.sql`. Mengubah uang atau ular lewat DevTools hanya mengubah tampilan di layar sendiri, dan akan kembali ke angka server setelah aksi berikutnya.
- Semua aksi divalidasi di server: umur dan kesiapan ular, uang cukup, listing pasar masih ada, ular cocok dengan pesanan, dan seterusnya. Aksi karangan ditolak.
- Pertemanan, pesan, dan trade hanya bisa diubah lewat fungsi server yang memeriksa siapa pemanggilnya. Chat dibatasi 30 pesan per menit.
- Yang masih bisa dilakukan pemain hanyalah mengatur waktu klik, misalnya menekan "Lanjut bulan" berkali-kali. Itu memang bagian dari permainan.
