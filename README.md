# Reptile Keeper Simulator — Morph Lab

![Morph Lab — Exotic Breeder Sim](assets/logo.png)

Game simulasi breeding hewan eksotis berbasis web: **ball python, leopard gecko, dan axolotl**, dengan genetika morph yang mengikuti pola pewarisan di dunia nyata.

## Cara main

Buka game lewat GitHub Pages, lalu daftar gratis dengan email dan pilih username.

1. Kamu mulai dengan **$5.000**, **2 rak (20 space)**, dan sepasang ball python: jantan Normal het Albino dan betina Albino yang langsung bisa dikawinkan.
2. **Kawinkan** pasangan di tab Kawinkan. Tabel peluang menunjukkan morph apa saja yang mungkin keluar.
3. Tekan **Lanjut bulan**. Betina bisa ovulasi, bertelur, lalu telurnya menetas di **Inkubator**. Suhu inkubasi mengatur peluang anak jantan/betina.
4. **Jual** hewan lewat iklan, jual cepat, atau kirim ke **pembeli** di tab Pesanan (paling untung).
5. Kumpulkan morph di **Morph Dex**, beli gen baru di **Pasar**, buka spesies lain, dan beli rak tambahan ($10.000, lalu naik 2× setiap pembelian).
6. Ikuti **Misi pemula** di samping layar untuk panduan langkah demi langkah.

Game **wajib login**. Setiap aksi dikirim ke server (Edge Function `game`), yang menghitung hasil breeding, pasar, dan uang. Save tidak bisa diubah dari browser, jadi aman dari kecurangan, bisa dilanjutkan dari perangkat mana pun, dan dipakai untuk trading serta papan peringkat.

**Hosting:** game ini berupa halaman statis, jadi bisa dijalankan lewat GitHub Pages (**Settings → Pages → Deploy from a branch → `main` / root**). Panduan menyiapkan server Supabase ada di [SETUP-SUPABASE.md](SETUP-SUPABASE.md).

## Fitur

- **3 spesies**, masing-masing dengan genetika, siklus breeding, dan panduan sendiri
  - **Ball python** (12 gen): resesif Albino, Piebald, Clown, Axanthic · co-dominan dengan bentuk super Pastel, Enchi, Yellow Belly (→ Ivory), Cinnamon, Banana · dominan Spider, Pinstripe · kompleks BEL (Mojave + Lesser)
  - **Leopard gecko** (12 gen): tiga strain albino (Tremper, Bell, Rainwater), Eclipse, Blizzard, Murphy Patternless, Marble Eye, Mack Snow, Giant, Lemon Frost, Enigma, White & Yellow · 4–6 clutch dari sekali kawin · suhu inkubasi menentukan jenis kelamin (termasuk pola "hot female")
  - **Axolotl** (7 gen): Leucistic, Albino, Melanoid, Axanthic, Copper, GFP, RFP · sampai 100 telur per clutch; pilih maksimal 3 bayi, sisanya otomatis dijual
- **Sistem het & pos het**: peluang het dihitung otomatis, dan induk "terbukti het" setelah menghasilkan anak visual
- **Tabel peluang keturunan** untuk setiap pasangan
- **Siklus breeding bulanan**: umur minimal kawin, ovulasi, jumlah telur dipengaruhi berat, telur tidak subur, inkubasi dengan pengaturan suhu, masa pemulihan betina, batas umur
- **Silsilah 3 generasi** di setiap hewan (ikut pindah saat trade)
- **Kawin sedarah (inbreeding)**: koefisien inbreeding dihitung dari leluhur 5 generasi. Ada peringatan sebelum memasangkan kerabat, dan efeknya nyata: telur tidak subur, gagal menetas, pertumbuhan lebih lambat, dan ovulasi lebih jarang
- **Ekonomi**: biaya pakan & rak, harga pasar yang naik turun dan bisa jenuh, pasar tiap spesies (bayi 10× / siap kawin 20× harga dasar), iklan, jual cepat, event, pesanan pembeli (membayar hadiah atau 125% nilai hewan), dan **pratinjau saldo bulan depan**. Keseimbangannya diuji dengan simulasi ratusan game.
- **Misi pemula** sebagai tutorial (9 misi, hadiah total $2.000)
- **Konfirmasi Lanjut bulan** kalau masih ada betina yang bisa dikawinkan
- **Morph Dex** per spesies, berisi morph target dan kombinasi terkenal (Bumblebee, Killer Bee, RAPTOR, White Albino, dan lainnya)
- **Gambar hewan prosedural** yang dibuat dari genetika tiap hewan
- **Teman, chat & trading**: tambah teman lewat username, chat real-time & global chat, profil dengan etalase, dan tukar hewan/uang dengan sistem escrow yang dijalankan server. Riwayat pemilik hewan (origin keeper) ikut tercatat.
- **Papan peringkat global** (di tab Global): kekayaan, Morph Dex, hewan termahal (per spesies), breeder produktif, dan pesanan. Ada top 50, posisi kamu, dan filter teman saja.
- **Laporan bug**: pemain melapor dengan judul, deskripsi, kategori, dan 1–3 screenshot. Semua pemain bisa membaca & berkomentar; admin mengubah status, membalas, dan menghapus. Pelapor mendapat notifikasi saat ada balasan.
- **Dua bahasa: Indonesia & Inggris**, bisa diganti kapan saja. Bahasa awal mengikuti bahasa browser, lalu pilihan pemain diingat.
- **3 tema warna** (Terrarium, Hutan Hujan, Samudra Malam) di Pengaturan

## Struktur

| File | Isi |
|---|---|
| `index.html` | Tampilan game (HTML + CSS + JavaScript) |
| `core.js` | Logika inti game (genetika, ekonomi, aksi, misi, angka peringkat); dihitung di server, dipakai browser untuk tampilan |
| `config.js` | URL & publishable key Supabase |
| `supabase/functions/game/` | Edge Function `game` (`index.ts`, `handler.js`, salinan `core.js`) |
| `supabase/schema.sql` | Tabel `profiles` & `saves` dengan Row Level Security |
| `supabase/social.sql` | Teman, chat, global chat, profil, trading (escrow) + fungsi server & realtime |
| `supabase/bugs.sql` | Laporan bug, komentar, admin, dan bucket Storage untuk screenshot |
| `supabase/leaderboard.sql` | Papan peringkat global (kolom `saves.rank` & fungsi `get_leaderboard`) |
| `scripts/sync-core.sh` | Menyalin `core.js` ke Edge Function |
| `scripts/sim-economy.cjs` | Simulasi ekonomi: bot memainkan ratusan game untuk menguji keseimbangan harga |
| `assets/` | Logo, favicon, dan ikon aplikasi |
| `SETUP-SUPABASE.md` | Panduan menyiapkan login, database, Storage, dan Edge Function |

Urutan menjalankan SQL di Supabase: `schema.sql` → `social.sql` → `bugs.sql` → `leaderboard.sql`, lalu deploy Edge Function `game`.

## Rencana

Sudah selesai:

- [x] Login & cloud save (Supabase)
- [x] Teman, chat & trading antar teman (escrow, divalidasi server)
- [x] Mode online server-authoritative (breeding & ekonomi dihitung server)
- [x] Spesies baru: leopard gecko & axolotl
- [x] Silsilah 3 generasi & kawin sedarah
- [x] Penyeimbangan ekonomi dengan simulasi (`scripts/sim-economy.cjs`)
- [x] Misi pemula (tutorial)
- [x] Laporan bug dengan komentar & panel admin
- [x] Papan peringkat global (sepanjang masa)

Berikutnya:

- [ ] Reputasi breeder & achievement: membuka spesies, pembeli besar, dan gelar di profil
- [ ] Peringkat musiman
- [ ] Event berkala & kompetisi morph
- [ ] Pasar antarpemain (tidak hanya antar teman)
- [ ] Spesies berikutnya (corn snake atau bearded dragon) & sifat line-bred (poligenik)
- [ ] Perawatan & kesehatan (suhu, kelembapan, shedding, mogok makan)
- [ ] Versi aplikasi (PWA)
