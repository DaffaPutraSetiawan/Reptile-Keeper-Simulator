# Reptile Keeper Simulator — Morph Lab

![Morph Lab — Reptile Breeder Sim](assets/logo.png)

Game simulasi breeding ball python berbasis web, dengan genetika morph yang mengikuti pola pewarisan di dunia nyata.

## Cara main

Buka game lewat GitHub Pages, lalu masuk atau daftar.

Game **wajib login** (daftar gratis dengan email). Setiap aksi dikirim ke server (Edge Function `game`), yang menghitung hasil breeding, pasar, dan uang. Save tidak bisa diubah dari browser, jadi aman dari kecurangan, bisa dilanjutkan dari perangkat mana pun, dan dipakai untuk trading.

Panduan menyiapkan server ada di [SETUP-SUPABASE.md](SETUP-SUPABASE.md).

Bisa juga dimainkan online lewat GitHub Pages: **Settings → Pages → Deploy from a branch → `main` / root**.

## Fitur

- **12 gen ball python**
  - Resesif: Albino, Piebald, Clown, Axanthic
  - Co-dominan dengan bentuk super: Pastel, Enchi, Yellow Belly (→ Ivory), Cinnamon, Banana
  - Dominan: Spider, Pinstripe
  - Kompleks BEL: Mojave + Lesser → Blue-Eyed Leucistic
- **Sistem het & pos het**: bayi dari het × het tercatat 66% pos het, dan induk "terbukti het" setelah menghasilkan anak visual
- **Tabel peluang keturunan** untuk setiap pasangan
- **Siklus breeding bulanan**: kawin kapan saja asal cukup umur (jantan ≥10 bln, betina ≥24 bln), ovulasi, jumlah telur, slug, inkubasi, masa pemulihan betina
- **Ekonomi**: biaya pakan & rak, harga pasar yang naik turun dan bisa jenuh, iklan, event, pesanan pembeli
- **Morph Dex** dengan 32 morph target (Bumblebee, Killer Bee, Lemon Blast, Spinner, Snow, dan lainnya)
- **Gambar ular prosedural** yang dibuat dari genetika tiap ular
- **Teman, chat & trading**: tambah teman lewat username, chat real-time, dan tukar ular/uang dengan sistem escrow yang dijalankan server (lihat SETUP-SUPABASE.md)
- **Dua bahasa: Indonesia & Inggris**, bisa diganti kapan saja lewat tombol ID / EN di header. Bahasa awal mengikuti bahasa browser, lalu pilihan pemain diingat.

## Struktur

| File | Isi |
|---|---|
| `index.html` | Tampilan game (HTML + CSS + JavaScript) |
| `core.js` | Logika inti game (genetika, ekonomi, aksi); dihitung di server, dipakai browser untuk tampilan |
| `config.js` | URL & publishable key Supabase |
| `supabase/schema.sql` | Tabel `profiles` & `saves` dengan Row Level Security |
| `supabase/functions/game/` | Edge Function mode online (`index.ts`, `handler.js`, salinan `core.js`) |
| `scripts/sync-core.sh` | Menyalin `core.js` ke Edge Function |
| `supabase/social.sql` | Teman, chat, trading (escrow) + fungsi server & realtime |
| `assets/` | Logo, favicon, dan ikon aplikasi |
| `SETUP-SUPABASE.md` | Panduan menyiapkan login & cloud save |

## Rencana

- [x] Login & cloud save (Supabase)
- [x] Teman, chat & trading antar teman (escrow, divalidasi server)
- [x] Mode online server-authoritative (breeding & ekonomi dihitung server)

- [ ] Spesies baru (leopard gecko, bearded dragon, corn snake)
- [ ] Perawatan & kesehatan (suhu, kelembapan, shedding, mogok makan)
- [ ] Silsilah & riwayat clutch
- [ ] Progres, misi, dan achievement
