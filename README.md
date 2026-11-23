# Reptile Keeper Simulator — Morph Lab

![Morph Lab — Exotic Breeder Sim](assets/logo.png)

Game simulasi breeding hewan eksotis berbasis web: **ball python, leopard gecko, axolotl, dan kura-kura brazil (red-eared slider)**, dengan genetika morph yang mengikuti pola pewarisan di dunia nyata.

## Cara main

Buka game lewat GitHub Pages, lalu daftar gratis dengan email dan pilih username.

1. Kamu mulai dengan **$5.000**, **2 rak (20 space)**, dan sepasang ball python: jantan Normal het Albino dan betina Albino yang langsung bisa dikawinkan.
2. **Kawinkan** pasangan di tab Kawinkan. Tabel peluang menunjukkan morph apa saja yang mungkin keluar.
3. Tekan **Lanjut bulan**. Betina bisa ovulasi, bertelur, lalu telurnya menetas di **Inkubator**. Suhu inkubasi mengatur peluang anak jantan/betina.
4. **Jual** hewan lewat iklan, jual cepat, kirim ke **pembeli** di tab Pesanan (paling untung), atau pasang di **Pasar Pemain** untuk dijual ke pemain lain dengan harga pilihanmu.
5. Kumpulkan morph di **Morph Dex**, beli gen baru di **Pasar** (toko NPC atau hewan milik pemain lain), buka spesies lain, dan beli rak tambahan ($5.000, lalu naik $5.000 setiap pembelian: $5.000, $10.000, $15.000, $20.000, …). Rak tambahan bisa dijual lagi dengan uang kembali 50% dari harga rak terakhir; 2 rak awal tidak bisa dijual, dan kalau hewan jadi melebihi kapasitas, kelebihannya kena biaya space darurat $15/ekor/bulan.
6. Ikuti **Misi pemula** di samping layar untuk panduan langkah demi langkah.

Game **wajib login**. Setiap aksi dikirim ke server (Edge Function `game`), yang menghitung hasil breeding, pasar, dan uang. Save tidak bisa diubah dari browser, jadi aman dari kecurangan, bisa dilanjutkan dari perangkat mana pun, dan dipakai untuk trading serta papan peringkat.

**Hosting:** game ini berupa halaman statis, jadi bisa dijalankan lewat GitHub Pages (**Settings → Pages → Deploy from a branch → `main` / root**). Panduan menyiapkan server Supabase ada di [SETUP-SUPABASE.md](SETUP-SUPABASE.md).

## Fitur

- **3 spesies**, masing-masing dengan genetika, siklus breeding, dan panduan sendiri
  - **Ball python** (12 gen): resesif Albino, Piebald, Clown, Axanthic · co-dominan dengan bentuk super Pastel, Enchi, Yellow Belly (→ Ivory), Cinnamon, Banana · dominan Spider, Pinstripe · kompleks BEL (Mojave + Lesser)
  - **Leopard gecko** (12 gen): tiga strain albino (Tremper, Bell, Rainwater), Eclipse, Blizzard, Murphy Patternless, Marble Eye, Mack Snow, Giant, Lemon Frost, Enigma, White & Yellow · 4–6 clutch dari sekali kawin · suhu inkubasi menentukan jenis kelamin (termasuk pola "hot female")
    - Kombinasi bernama: RAPTOR, Dreamsicle, Diablo Blanco, Ember, Nova, Super RAPTOR, RADAR, Calcite, Typhoon, Cyclone, Total Eclipse, Blazing Blizzard, Banana Blizzard, Banana Blazing Blizzard
    - Toko NPC: 3 hewan hasil undian (termasuk Normal). Peluang tiap gen mengikuti kelangkaan di dunia nyata: umum (Tremper, Mack Snow), sedang (Bell, Eclipse, Giant, Enigma, Blizzard, White & Yellow), agak langka (Rainwater, Murphy), langka (Marble Eye, Lemon Frost); makin langka makin mahal
  - **Axolotl** (7 gen): Leucistic, Albino, Melanoid, Axanthic, Copper, GFP, RFP · sampai 100 telur per clutch; pilih maksimal 3 bayi, sisanya otomatis dijual
  - **Pilih bayi (v61)**: ball python juga memilih maksimal 3 bayi per clutch dan kura-kura brazil 1 bayi per clutch; sisanya dijual otomatis 60% nilainya. Leopard gecko: semua bayi masuk koleksi
  - **Kura-kura brazil / red-eared slider** (6 gen, v60): resesif Albino, Caramel Pink, Hypo, Charcoal, Leucistic · co-dominan Golden Flame (→ Super Golden Flame) · kombinasi Snow, Lubino, Hybino · 2–4 clutch dari sekali kawin, 6–20 telur per clutch · suhu inkubasi kebalikan ball python (dingin = jantan, panas = betina) · tanpa sifat line-bred
- **Sistem het & pos het**: peluang het dihitung otomatis saat menetas dan tidak bisa diubah pemain. Contoh untuk anak yang tidak visual: induk visual × normal → 100% het, het × het → 66% pos het, het × normal → 50% pos het, 50% pos het × normal → 25% pos het. Hewan pos het "terbukti het" (naik jadi 100%) begitu menghasilkan anak visual. Nilai hewan ikut naik sesuai peluang het-nya. Hewan milik pemain lain (profil, trade, Pasar Pemain) hanya menampilkan catatan het ini, sedangkan gen resesif yang tidak terlihat disembunyikan server; pembeli baru tahu gen aslinya lewat breeding
- **Tabel peluang keturunan** untuk setiap pasangan
- **Planner breeding** (di tab Kawinkan): centang gen target, lalu planner menunjukkan hewan pembawa tiap gen dan 5 pasangan terbaik di koleksimu (peluang per bayi, perkiraan bayi target per musim, status siap kawin, dan inbreeding) untuk 1 generasi
- **Siklus breeding bulanan**: umur minimal kawin, ovulasi, jumlah telur dipengaruhi berat, telur tidak subur, inkubasi dengan pengaturan suhu, masa pemulihan betina, batas umur
- **Koleksi yang mudah diatur**: cari berdasarkan ID, nama panggilan, morph, atau gen; filter spesies, kelamin, status (siap kawin, dipasangkan, bunting, bayi, tua, inbred, diiklankan), asal, dan gen (visual / visual + het / semua pembawa); urutkan berdasarkan nilai, umur, terbaru, ID, berat, sisa umur, inbreeding, atau nama dengan tombol ↑↓. Ada tampilan kartu & tampilan daftar, dan dari tampilan daftar banyak hewan bisa diiklankan atau dijual cepat sekaligus (dengan konfirmasi & peringatan). Pilihan filter diingat di perangkat.
- **Silsilah 3 generasi** di setiap hewan (ikut pindah saat trade)
- **Sifat line-bred (poligenik), leopard gecko**: selain gen, tiap gecko punya 7 nilai sifat yang berubah pelan-pelan lewat seleksi. Nilai anak kira-kira rata-rata kedua induk ± sedikit acak. Pemain hanya melihat perkiraan tingkatnya, bukan angka.
  - Bayi di bawah 6 bulan belum jelas warnanya: tingkatnya hanya tebakan bertanda ? (bisa meleset satu tingkat), belum ada label, dan bonus harga line-bred baru dihitung saat umur 6 bulan. Saat umur 6 bulan, gecko yang ternyata punya label dicatat di catatan breeder (mis. "✨ LG-0012 sudah 6 bulan dan ternyata Tangerine!")
  - Breeding planner hanya menampilkan sifat kedua induk, tanpa perkiraan anak: pemain menebak sendiri
  - Warna (5): High Yellow, Tangerine (sudah termasuk Carrot Tail), Lavender, Emerine, Black Night. Label muncul di tingkat Tinggi. Black Night tinggi menutupi warna lain (labelnya hilang dan tidak menambah harga, tapi tetap diwariskan)
  - Gen penutup (seperti di dunia nyata): Blizzard menutup semua 7 sifat, Murphy Patternless menutup bintik & pola, Super Snow menutup 5 warna, Enigma menutup pola. Mack Snow tidak menutup. Sifat yang tertutup (termasuk oleh Black Night) tampil "Tidak terlihat" di detail hewan dan breeding planner, tanpa label & bonus harga, tapi nilainya tetap diwariskan. Kombinasi yang memakai sifat tertutup (Sunglow, SHTCT, Red/Bold Stripe) ikut hilang
  - Nama tampilan (v54): label yang terlihat digabung ke depan nama morph gen, mis. "Tangerine Jungle Tremper Albino", "Sunglow RAPTOR"; gecko tanpa gen cukup labelnya ("Emerine"). Dipakai di koleksi, detail, breeding, Pasar Pemain, trade, showcase, papan peringkat, dan catatan breeder. Morph Dex, pesanan pembeli, dan riwayat harga Pasar Pemain tetap memakai nama gen. Bayi di bawah 6 bulan memakai nama gen + "✨ Sifat belum jelas"
  - Gambar gecko ikut label yang terlihat: warna (kuning, oranye, ungu muda, hijau zaitun, hitam), bintik (Bold lebih besar, Hypo berkurang, Super Hypo badan bersih), dan pola (Jungle, Stripe, Reverse Stripe). Bayi dan sifat yang tertutup bergambar biasa. Kartu label di Morph Dex memakai contoh gecko sesuai labelnya. Gambar berlapis: warna dasar dan bintik dari gen, label bintik (Bold/Hypo/Super Hypo) mengganti bintik bawaan gen, label pola (Jungle/Stripe/Reverse Stripe) mengganti cincin ekor dan memanjang sampai ujung ekor, Tangerine punya carrot tail
  - Pasar Pemain & trade (v50): kartu jualan dan daftar hewan trade menampilkan nama dengan label dan tombol "Lihat sifat" (tabel 7 sifat), pencarian Pasar Pemain mengenali label, dan riwayat harga dipisah per morph gen + kelamin + label. Kalau kombinasi label itu belum pernah terjual, yang tampil riwayat morph gen secara umum dengan catatan. Showcase profil juga menampilkan label
  - Bintik (1 sumbu): Bold ↔ Normal ↔ Hypo → Super Hypo. Semua gecko mulai di Normal
  - Pola (1 sumbu): belang → Jungle → Stripe → Reverse Stripe (varian langka)
  - Super Hypo + Tangerine = SHTCT; kalau gecko itu juga albino jadi Sunglow (Tremper), Bell Sunglow, atau Rainwater Sunglow (bonus harga tambahan). Stripe + Tangerine = Red Stripe, Stripe + Bold = Bold Stripe (bonus tambahan). Sifat berlabel menaikkan harga hewan
- **Kawin sedarah (inbreeding)**: koefisien inbreeding dihitung dari leluhur 5 generasi. Ada peringatan sebelum memasangkan kerabat, dan efeknya nyata: telur tidak subur dan gagal menetas masing-masing naik 0,4 × F, hewan inbred tumbuh (1 − F/2)× dan betinanya berovulasi (1 − F)× dari biasanya (F 25% untuk saudara kandung atau induk × anak). Nilai inbreeding terbawa di setiap clutch dari sekali kawin
- **Ekonomi**: biaya pakan & rak, harga pasar yang naik turun dan bisa jenuh, pasar tiap spesies (bayi 10× / siap kawin 20× harga dasar), iklan, jual cepat, event, pesanan pembeli (membayar hadiah atau 200% nilai hewan), dan **pratinjau saldo bulan depan**. Keseimbangannya diuji dengan simulasi ratusan game.
- **Statistik pribadi** (tombol 📊 Statistik saya di profil sendiri, hanya terlihat oleh pemiliknya): ringkasan kekayaan bersih, uang, nilai koleksi, hewan & kapasitas, bulan dimainkan, dan reputasi; **grafik uang & kekayaan bersih** per bulan (12 bulan / 5 tahun / semua, dengan tooltip, tanda event, dan tampilan tabel; data bulanan disimpan untuk 10 tahun game terakhir, yang lebih lama diringkas per tahun); breeding (bayi menetas, clutch, rata-rata telur, telur tidak subur, gagal menetas, menetas per spesies, morph baru per tahun); **penjualan per saluran** (pesanan, pembeli besar, iklan, jual cepat, brood axolotl, Pasar Pemain); 5 morph paling menguntungkan; dan pengeluaran (pakan, listrik & rak, space darurat, beli hewan, beli rak). Rinciannya dicatat server mulai v36
- **Catatan breeder** di samping layar: 100 kejadian terakhir (kawin, bertelur, menetas, penjualan, trade, Pasar Pemain, event), ikut berganti bahasa
- **Misi pemula** sebagai tutorial (9 misi, hadiah total $2.000)
- **Konfirmasi Lanjut bulan** kalau masih ada betina yang bisa dikawinkan
- **Halaman masuk** dengan logo Morph Lab
- **Sifat line-bred ball python (v57)**: 3 nilai yang berubah lewat seleksi; sifat bayi **belum jelas sampai umur 12 bulan** (tingkat bertanda ?, lalu catatan breeder saat terungkap)
  - Pudar: Fader (pola memudar)
  - Intensitas: High Intensity (warna gen lebih pekat). Hanya pada ular dengan gen warna (Pastel, Banana, Enchi, Yellow Belly, Cinnamon)
  - Nada warna (1 sumbu, nilai awal 44–55): Light Line di bawah 30, Dark Line 70+. Ditutup Albino; BEL menutup semua sifat
  - Kombinasi gen baru: Pewter, Super Blast, Silver Bullet, Queen Bee, Sterling, Bumble Belly, Killer Pied, Pumpkin Pied, Savannah. Gambar Mojave, Lesser, Enchi, Yellow Belly, Cinnamon, dan Spinner dibedakan lebih jelas
- **Sifat line-bred axolotl (v56)**: 3 nilai yang berubah lewat seleksi dan **langsung terlihat sejak menetas** (pilihan bayi di inkubator dikelompokkan per tingkat sifat)
  - Kilau: High Iridophore (Golden Albino + High Iridophore = Sunburst, Copper + High Iridophore = Moonburst). Ditutup Melanoid
  - Bintik gelap: Dirty Leucistic, lalu Piebald. Hanya terlihat pada Leucistic yang tidak albino
  - Nada warna: Light Wild atau Dark Wild. Hanya terlihat pada Wild Type
  - Kombinasi gen baru: Mac (Axanthic + Copper + Melanoid). Label ikut nama tampilan, gambar, harga, dan Morph Dex
- **Morph Dex** per spesies, hanya berisi gen tunggal dan kombinasi yang punya nama sendiri (v62), ditambah label line-bred: ball python 39 (20 gen tunggal + 15 combo bernama seperti Bumblebee, Pewter, Queen Bee, Killer Pied + 4 label line-bred), leopard gecko 51 (16 gen tunggal + 18 combo bernama seperti RAPTOR, Calcite, Cyclone + 17 label line-bred seperti Emerine, SHTCT, Sunglow), axolotl 17 (8 gen tunggal + White Albino & MAC + 7 label line-bred), kura-kura brazil 11 (8 gen tunggal + Snow, Lubino, Hybino) (termasuk Normal / Wild Type). Gabungan yang namanya hanya nama gen-gennya (mis. Pastel Albino, Copper Leucistic) tidak punya kartu. Label line-bred tercatat saat labelnya terlihat pada gecko milikmu (umur 6 bulan ke atas). Misi Morph Dex dan papan peringkat hanya menghitung morph target ini
- **Gambar hewan prosedural** yang dibuat dari genetika tiap hewan
- **Teman, chat & trading**: tambah teman lewat username, chat real-time & global chat (bisa membalas pesan tertentu dengan tombol ↩: kutipan disimpan bersama balasan, klik kutipan untuk melompat ke pesan asli, kutipan pesan yang dihapus admin atau milik akun yang dihapus jadi "pesan dihapus"), profil dengan etalase, dan tukar hewan/uang dengan sistem escrow yang dijalankan server. Menu trade menampilkan ID hewan, dan setiap tawaran maupun penerimaan trade punya langkah konfirmasi dengan peringatan (nilai timpang, hadiah, hewan terakhir satu spesies, kapasitas rak penuh, uang besar). Riwayat pemilik hewan (origin keeper) ikut tercatat.
- **Pasar Pemain** (di tab Pasar): jual hewan ke pemain lain dengan harga pas, tanpa biaya. Harga minimal 50% dari nilai hewan (dicek server), tanpa batas atas, dan tidak ada batas jumlah jualan. Jualan tayang 14 hari; kalau tidak laku atau dibatalkan, hewannya kembali otomatis. Pembeli bisa menyaring spesies, kelamin, gen (termasuk het), rentang harga, dan hewan dewasa, lalu mengurutkan berdasarkan terbaru, termurah, segera berakhir, atau nilai. Setiap jualan menampilkan ID, het, penjual + level reputasi, sisa waktu, dan **riwayat harga** 30 hari untuk morph & kelamin yang sama: **median** (harga tengah), **rentang tengah** (harga yang paling sering terjadi, yaitu kuartil 25%–75%; seperempat termurah & termahal tidak dihitung, tampil mulai 5 penjualan), dan **penjualan termahal**. Sebelum membeli ada konfirmasi "Yakin beli?" (dengan peringatan kalau rak jadi penuh). Saat memasang jualan, kolom harga dibiarkan kosong supaya penjual menentukan harganya sendiri (harga minimum dan riwayat harga tampil sebagai panduan). Bagian **Jualan saya** berisi jualan aktif dan riwayatnya.
- **Sewa pejantan** (di tab Pasar → 🧬 Pejantan): tawarkan jantan dewasa untuk disewa pemain lain dengan biaya per kawin (minimal 50% nilai jantan, tanpa batas atas). Satu penawaran bisa disewa sampai 5 kali tanpa batas waktu; jantan tetap di koleksi pemilik dan tetap bisa dikawinkan sendiri. Penyewa memilih betinanya, melihat peluang anak & peringatan kawin sedarah, lalu membayar di muka (tidak kembali kalau gagal ovulasi). Anaknya milik penyewa, silsilahnya mencatat jantan & pemiliknya. Uang sewa masuk ke pemilik lewat kiriman.
- **Reputasi breeder**: setiap pesanan yang dipenuhi memberi ⭐ +1 reputasi (uang tetap dibayar). Reputasi & level tampil di profil setiap pemain, di bawah namanya. Level naik di 10, 30, 60, 100 … reputasi (kebutuhan tiap level bertambah 10). Mulai level 2 datang **pembeli besar**: pesanan 2 hewan berbeda yang dikirim sekaligus, dibayar hadiah atau 250% nilai kedua hewan, dan memberi ⭐ +3. Maksimal 3 pesanan biasa + 1 pesanan pembeli besar.
- **Papan peringkat global** (di tab Global): kekayaan, Morph Dex, hewan termahal (per spesies), breeder produktif, pesanan, dan reputasi. Ada top 50, posisi kamu, dan filter teman saja.
- **Moderasi chat global**: pemain bisa melaporkan pesan (spam, kasar, penipuan trade, lainnya). Kata kasar otomatis disensor jadi ★★★ dan pesan yang sama tidak bisa dikirim lebih dari 3× dalam 5 menit. Admin bisa menghapus pesan dan membisukan pemain di chat global (1 jam, 24 jam, 7 hari, atau selamanya, dengan alasan yang terlihat oleh pemain).
- **Tab Admin** (hanya untuk admin): ringkasan angka pemain, chat, trade & laporan, antrean laporan chat, daftar pemain yang dibisukan, log tindakan admin, dan **moderasi Pasar Pemain**: daftar jualan aktif & penjualan terbaru dengan tanda mencurigakan (harga > 5× nilai, pasangan penjual–pembeli berulang, penjual & pembeli berteman), tombol **turunkan jualan** (hewan kembali ke penjual dengan alasan yang tampil di catatan breeder-nya), dan tombol **keluarkan dari riwayat harga** untuk transaksi palsu (bisa dimasukkan lagi).
- **Masukan (laporan bug & saran)**: pemain melaporkan bug (judul, deskripsi, kategori, 1–3 screenshot wajib) atau mengirim saran (gambar opsional). Semua pemain bisa membaca & berkomentar, dan mendukung saran dengan 👍 (sekali per saran, tidak bisa untuk saran sendiri); saran bisa diurutkan dari dukungan terbanyak. Saat menulis judul, muncul masukan yang mirip supaya tidak dobel. Admin mengubah status (saran: Baru, Ditinjau, Direncanakan, Sedang dikerjakan, Selesai di vXX, Ditolak, Duplikat), membalas, dan menghapus. Pengirim & pendukung mendapat notifikasi saat status berubah; saran yang Selesai tampil di catatan pembaruan sebagai "Saran dari …". Kata kasar di judul, deskripsi, dan komentar disensor. Batas: 3 laporan bug + 3 saran per 24 jam.
- **Dua bahasa: Indonesia & Inggris**, bisa diganti kapan saja. Bahasa awal mengikuti bahasa browser, lalu pilihan pemain diingat.
- **3 tema warna** (Terrarium, Hutan Hujan, Samudra Malam) di Pengaturan
- **Catatan pembaruan** di Pengaturan → Tentang (semua versi, ID & EN), plus popup sekali saat ada versi baru. Riwayat teknis per versi ada di [`CHANGELOG.md`](CHANGELOG.md)

## Struktur

| File | Isi |
|---|---|
| `index.html` | Tampilan game (HTML + CSS + JavaScript) |
| `core.js` | Logika inti game (genetika, ekonomi, aksi, misi, angka peringkat); dihitung di server, dipakai browser untuk tampilan |
| `config.js` | URL & publishable key Supabase |
| `patchnotes.js` | Catatan pembaruan untuk pemain (ID & EN), tampil di game |
| `CHANGELOG.md` | Riwayat perubahan per versi |
| `supabase/functions/game/` | Edge Function `game` (`index.ts`, `handler.js`, salinan `core.js`) |
| `supabase/schema.sql` | Tabel `profiles` & `saves` dengan Row Level Security |
| `supabase/social.sql` | Teman, chat, global chat, profil, trading (escrow) + fungsi server & realtime |
| `supabase/bugs.sql` | Masukan (laporan bug & saran), dukungan saran, komentar, admin, dan bucket Storage untuk screenshot |
| `supabase/leaderboard.sql` | Papan peringkat global (kolom `saves.rank` & fungsi `get_leaderboard`) |
| `supabase/moderation.sql` | Moderasi chat global (laporan, bisu, sensor kata), log & ringkasan admin |
| `supabase/market.sql` | Pasar Pemain: jualan harga pas, escrow, beli/batal, riwayat harga |
| `supabase/stud.sql` | Sewa pejantan: penawaran, sewa atomik, uang ke pemilik, riwayat penyewa |
| `scripts/sync-core.sh` | Menyalin `core.js` ke Edge Function |
| `scripts/sim-economy.cjs` | Simulasi ekonomi: bot memainkan ratusan game untuk menguji keseimbangan harga |
| `assets/` | Logo, favicon, dan ikon aplikasi |
| `SETUP-SUPABASE.md` | Panduan menyiapkan login, database, Storage, dan Edge Function |

Urutan menjalankan SQL di Supabase: `schema.sql` → `social.sql` → `bugs.sql` → `leaderboard.sql` → `moderation.sql` → `market.sql` → `stud.sql`, lalu deploy Edge Function `game`.

## Rencana

Sudah selesai:

- [x] Login & cloud save (Supabase)
- [x] Teman, chat & trading antar teman (escrow, divalidasi server)
- [x] Mode online server-authoritative (breeding & ekonomi dihitung server)
- [x] Spesies baru: leopard gecko, axolotl & kura-kura brazil (v60)
- [x] Silsilah 3 generasi & kawin sedarah
- [x] Penyeimbangan ekonomi dengan simulasi (`scripts/sim-economy.cjs`)
- [x] Misi pemula (tutorial)
- [x] Laporan bug dengan komentar & panel admin
- [x] Kotak saran dengan dukungan 👍 (tab Masukan)
- [x] Papan peringkat global (sepanjang masa)
- [x] Moderasi chat global & ringkasan admin
- [x] Reputasi breeder & pembeli besar
- [x] Planner breeding & alat koleksi (filter, urutkan, aksi sekaligus)
- [x] Pasar Pemain (jual-beli antarpemain, harga pas, riwayat harga)

Berikutnya:

- [ ] Achievement & gelar di profil
- [ ] Peringkat musiman
- [ ] Event berkala & kompetisi morph
- [x] Sifat line-bred (poligenik) untuk leopard gecko: 7 nilai (warna, bintik, pola), pewarisan, label & harga
- [x] Sifat line-bred di breeding planner (tampilan induk saja, pemain menebak)
- [x] Sifat line-bred tampil di Pasar Pemain & trade (label, tabel sifat, pencarian, riwayat harga per label)
- ~~Sifat line-bred di pesanan pembeli~~ (tidak jadi, keputusan pemilik game)
- [x] Sifat line-bred untuk ball python dan axolotl
- [ ] Spesies berikutnya (corn snake atau bearded dragon)
- [ ] Perawatan & kesehatan (suhu, kelembapan, shedding, mogok makan)
- [ ] Versi aplikasi (PWA)
