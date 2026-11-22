# Changelog Morph Lab — Exotic Breeder Sim

Semua perubahan penting, dari yang terbaru. Nomor versi = versi logika game (`core.js` → `VERSION`), sama dengan versi Edge Function `game` di Supabase. Baris bertanda *(web)* hanya mengubah tampilan, tanpa deploy server.

Catatan pembaruan untuk pemain (bahasa yang lebih sederhana, ID & EN) ada di `patchnotes.js` dan tampil di game: **Pengaturan → Tentang → Catatan pembaruan**.

---

## v58 — 22 Nov 2026
**Sewa pejantan (stud service)**
- Aksi baru `stud_list`: pemilik menawarkan jantan siap kawin dengan biaya per kawin (minimal 50% nilai jantan, maks. $100.000.000). Jantan tetap di save pemilik dan tetap bisa dikawinkan sendiri.
- Satu penawaran bisa disewa total 5 kali (`STUD_MAX`), tanpa batas waktu. Satu penawaran aktif per jantan. Penawaran otomatis batal kalau jantannya dijual, di-trade, diiklankan, mati, atau akunnya di-reset.
- Aksi baru `stud_book`: Edge Function membaca jantan asli dari save pemilik (`_stud_peek`). Betina penyewa dipasangkan dengan salinan data jantan itu (`f.stud`, `pairedWith` negatif). Uang terpotong langsung dan tidak kembali kalau gagal ovulasi.
- `_stud_book` menyimpan save penyewa, menambah hitungan sewa (dikunci, tidak bisa lewat 5), mencatat penyewa, dan mengirim uang ke pemilik lewat kiriman, semuanya dalam satu transaksi.
- Ovulasi dari pejantan sewaan memakai peluang biasa. Silsilah anak memakai jantan pemilik (tidak menunjuk hewan penyewa); kawin sedarah dihitung dari data leluhurnya.
- Betina yang sedang kawin sewaan tidak bisa dibatalkan, diiklankan, dijual di Pasar Pemain, atau di-trade.
- `supabase/stud.sql` baru: `stud_listings`, `stud_bookings`, `get_studs`, `get_my_studs`, `cancel_stud`. `claim_deliveries` mencatat uang sewa di statistik pribadi pemilik.
- UI: Pasar → 🧬 Pejantan, layar sewa (pilih betina, peluang anak, inbreeding, biaya), tombol "Tawarkan sebagai pejantan" di detail jantan, penawaran & daftar penyewa di Jualan saya, pasangan sewaan di tab Kawinkan, statistik "Sewa pejantan".

## v57 — 22 Nov 2026
**Ball python: sifat line-bred, kombinasi baru, Morph Dex 46**
- 3 nilai line-bred ball python (`fade`, `inten`, `btone`), belum jelas sampai umur 12 bulan (`LB_REVEAL_SP`):
  - Pudar → **Fader** (60+), ditutup BEL.
  - Intensitas → **High Intensity** (60+), hanya pada ular dengan gen warna (Pastel, Banana, Enchi, Yellow Belly, Cinnamon + bentuk super); ditutup BEL.
  - Nada warna (1 sumbu, nilai awal 44–55) → **Light Line** (< 30) / **Dark Line** (≥ 70); ditutup BEL & Albino.
  - Bonus harga: label $30, tingkat tertinggi $60, ×(1 + 10% per label tambahan, maks. +20%).
- 9 kombinasi baru: Pewter, Super Blast, Silver Bullet, Queen Bee, Sterling, Bumble Belly, Killer Pied, Pumpkin Pied, Savannah. Urutan nama: pola → Pied → warna, jadi nama kombinasi lama tidak berubah.
- Morph Dex ball python: 42 morph gen + 4 label = 46.
- Catatan "sudah N bulan dan ternyata …" memakai umur per spesies; ular awal & ball python lama diberi nilai awal.
- Gambar: lapisan line-bred, pembeda Mojave/Lesser/Enchi/Yellow Belly/Cinnamon/Spinner, tampilan Pewter/Silver Bullet/Sterling. Panduan spesies diperbarui.
- *(web)* Pengaturan bahasa tanpa emoji bendera (tampil sebagai huruf GB/ID di Windows).
- *(web)* Catatan pembaruan di game & `CHANGELOG.md` ini.
- *(web + database)* Tab Laporan bug jadi **Masukan**: laporan bug & **saran** dalam satu tab (`bug_reports.kind`).
  - Saran: kategori sendiri (Spesies & gen baru, Gameplay, Ekonomi, Tampilan, Sosial, Lainnya), gambar opsional, maks. 3 saran per 24 jam.
  - Dukungan 👍 (`idea_votes`, `vote_idea`), urutan dukungan terbanyak, filter "Saya dukung".
  - Masukan mirip saat menulis judul (`similar_reports`).
  - Status saran: Direncanakan, Sedang dikerjakan, Selesai di vXX; admin bisa mengisi versi & ID masukan asli untuk Duplikat.
  - Notifikasi untuk pengirim & pendukung (`feedback_unread`); saran Selesai tampil di catatan pembaruan sebagai "Saran dari …" (`done_ideas`).
  - Sensor kata kasar di judul, deskripsi, dan komentar masukan; ringkasan admin memisahkan bug & saran.

## v56 — 22 Nov 2026
**Axolotl: sifat line-bred, Mac & Copper, Morph Dex 28**
- 3 nilai line-bred axolotl (`iri`, `dspot`, `tone`), **langsung terlihat sejak menetas**:
  - Kilau → **High Iridophore**; Golden Albino + HI = **Sunburst**, Copper + HI = **Moonburst**. Ditutup Melanoid.
  - Bintik gelap → **Dirty Leucistic** (60+), **Piebald** (85+); hanya pada Leucistic non-albino.
  - Nada warna → **Light Wild** / **Dark Wild**; hanya pada Wild Type.
  - Bonus harga: label $8, tertinggi $15, Sunburst/Moonburst +$10.
- Brood menyimpan nilai per bayi; layar pilih bayi dikelompokkan per tingkat sifat.
- Kombinasi **Mac** (Axanthic + Copper + Melanoid); Dex axolotl + Copper Axanthic, Copper Melanoid, Copper Leucistic, Mac, RFP Leucistic + 7 label.
- Gambar axolotl berlapis + pembeda kombinasi Copper; panduan spesies diperbarui.
- Perbaikan: jendela jual Pasar Pemain mencari riwayat harga dengan nama gen (sempat memakai nama tampilan sejak v54).

## v55 — 22 Nov 2026
- `rankStats` menyimpan label line-bred yang terlihat (`top[sp].l`), jadi gambar hewan termahal di papan peringkat ikut berwarna.
- *(web)* Gambar gecko berlapis: Hypo/Super Hypo/Bold mengganti bintik gen, Jungle/Stripe/Reverse Stripe mengganti cincin ekor dan memanjang sampai ujung ekor, carrot tail untuk Tangerine.
- *(web)* Mata: Super Snow memakai mata biasa (solid hanya kalau juga Eclipse); Eclipse albino per strain (RAPTOR, RADAR, Typhoon).

## v54 — 22 Nov 2026
**Label line-bred masuk Morph Dex & nama tampilan**
- 17 label leopard gecko jadi target Morph Dex (51), dihitung di misi & papan peringkat.
- Nama tampilan = label terlihat + nama gen (mis. "Tangerine Jungle Tremper Albino", "Emerine"); Dex, pesanan & riwayat harga tetap memakai nama gen.
- Hapus akun: kutipan pesan global akun itu di balasan pemain lain jadi "pesan dihapus" (migrasi `_on_user_deleted`).
- *(web)* Gambar gecko menampilkan label line-bred; kartu label Dex memakai contoh gecko.
- *(web)* Pembeda gambar keluarga Blizzard, Leucistic axolotl, tiga Sunglow.

## v53 — 22 Nov 2026
- Morph Dex: Normal / Wild Type jadi target di setiap spesies.

## v52 — 22 Nov 2026
- Morph Dex: target leopard gecko ditambah kombinasi v46; bagian "morph lain" dihapus; hitungan Dex hanya morph target (`DEX_TARGETS`, `dexCount`).

## v51 — 22 Nov 2026
- Jual rak: uang kembali 50% harga rak terakhir; 2 rak awal tidak bisa dijual; boleh melebihi kapasitas (biaya space darurat).
- *(web)* Balas pesan (reply) di chat teman & global chat (migrasi `chat_reply`).

## v50 — 22 Nov 2026
- Sifat line-bred tampil di Pasar Pemain & trade (tombol "✨ Lihat sifat"); `_public_snake` menyertakan `lb`.
- Riwayat harga Pasar Pemain per label (`market_listings.lbl`) dengan cadangan riwayat per morph gen.
- *(web)* Showcase profil menampilkan label; hewan awal ditampilkan & difilter sebagai "dibeli dari pasar".

## v49 — 22 Nov 2026
- Gen penutup sifat line-bred (seperti dunia nyata): Blizzard (semua), Murphy (bintik & pola), Super Snow (warna), Enigma (pola), Black Night (warna lain). Sifat tertutup tampil "Tidak terlihat", tetap diwariskan.

## v48 — 22 Nov 2026
- Catatan breeder saat sifat line-bred bayi gecko terungkap di umur 6 bulan.

## v47 — 22 Nov 2026
- Sifat line-bred bayi gecko belum jelas sampai 6 bulan (tebakan bertanda ?, tanpa label & bonus harga).
- Breeding planner menampilkan tabel sifat line-bred kedua induk (tanpa perkiraan anak).

## v46 — 22 Nov 2026
- Kombinasi leopard gecko baru: Calcite, Cyclone, Banana Blizzard, Banana Blazing Blizzard.
- Label line-bred Red Stripe (Stripe + Tangerine) & Bold Stripe (Stripe + Bold), bonus +$50.

## v45 — 22 Nov 2026
- Label Sunglow / Bell Sunglow / Rainwater Sunglow untuk SHTCT albino, bonus +$110.

## v44 — 22 Nov 2026
- Nilai awal sumbu bintik leopard gecko jadi 44–55.

## v43 — 22 Nov 2026
- Nilai awal sumbu bintik leopard gecko jadi 45–55.

## v42 — 22 Nov 2026
- Sifat line-bred leopard gecko disusun ulang: 5 warna (High Yellow, Tangerine, Lavender, Emerine, Black Night) + sumbu bintik (Bold – Hypo – Super Hypo) + sumbu pola (Jungle – Stripe – Reverse Stripe). SHTCT = Super Hypo + Tangerine. Carrot Head, Baldy, Bandit dihapus; nilai susunan v41 diganti.

## v41 — 22 Nov 2026
- Sifat line-bred (poligenik) pertama untuk leopard gecko: nilai 0–100, anak = rata-rata induk ± acak, perkiraan 5 tingkat, label & bonus harga.

## v40 — 21 Nov 2026
- Hapus kode "hewan selalu tersedia" di toko NPC yang tidak dipakai lagi.

## v39 — 21 Nov 2026
- Toko leopard gecko kembali 3 slot undian; Normal masuk undian lagi.

## v38 — 21 Nov 2026
- Penyeimbangan leopard gecko: harga dasar $35, nilai gen mengikuti kelangkaan dunia nyata, tiket undian toko per kelangkaan.

## v37 — 21 Nov 2026
- Harga rak naik $5.000 per pembelian ($5.000, $10.000, $15.000, …).

## v36 — 20 Nov 2026
- Statistik pribadi di profil sendiri: grafik uang/kekayaan/jumlah hewan, saluran penjualan, top morph, pengeluaran, data breeding.

## v35 — 20 Nov 2026
- Catatan breeder maksimal 100 entri.
- Riwayat harga Pasar Pemain: median, rentang tengah (kuartil 25–75%), penjualan termahal.
- Alat admin Pasar Pemain (jualan mencurigakan, turunkan jualan, kelola riwayat harga).

## v34 — 20 Nov 2026
- **Pasar Pemain**: jual-beli hewan antarpemain dengan harga pas (min. 50% nilai), escrow, tayang 14 hari, riwayat harga 30 hari.

## v33 — 20 Nov 2026
- Koleksi: pencarian, filter lengkap, urutan, tampilan daftar, dan aksi sekaligus (`bulk`: iklankan / batalkan / jual cepat).

## v32 — 20 Nov 2026
- Inbreeding: efek telur lebih ringan (+0,4×F).
- Trade: ID hewan, konfirmasi & peringatan saat menawarkan/menerima.
- *(web)* Breeding planner 1 generasi di tab Kawinkan.

## v31 — 20 Nov 2026
- Perbaikan: inbreeding clutch ke-2 dst. leopard gecko tercatat 0%; save lama diperbaiki sekali.

## v30 — 20 Nov 2026
- Pembeli besar dibuka di level reputasi 2; reputasi & level tampil di profil.

## v29 — 20 Nov 2026
- Reputasi breeder (+1 pesanan, +3 pembeli besar), level, pembeli besar (2 hewan, 150% nilai), kategori Reputasi di papan peringkat.

## v28 — 20 Nov 2026
- Papan peringkat global (Kekayaan, Morph Dex, Hewan termahal, Breeder produktif, Pesanan).
- Moderasi chat global (laporan pesan, sensor kata, bisukan) & tab Admin.
- *(web)* Logo Morph Lab di halaman masuk.

## v27 — 19–20 Nov 2026
- Misi pemula (9 misi, hadiah total $2.000).
- Laporan bug: formulir dengan gambar, komentar, status, notifikasi, panel admin.

## v26 — 19 Nov 2026
- Ekonomi: uang awal $5.000; rak mulai $10.000 lalu naik 2× (diuji dengan simulasi ekonomi `scripts/sim-economy.cjs`).
- *(web)* Konfirmasi Lanjut bulan kalau masih ada betina yang bisa dikawinkan.

## v25 — 19 Nov 2026
- Kawin sedarah: koefisien inbreeding (kinship 5 generasi), peringatan, efek telur/pertumbuhan/ovulasi.

## v24 — 19 Nov 2026
- Silsilah 3 generasi yang ikut pindah saat trade.

## v23 — 19 Nov 2026
- Harga toko: bayi 10×, siap kawin 20× harga dasar.

## v22 — 19 Nov 2026
- Harga rak mulai $25.000, naik 2× tiap pembelian.

## v21 — 19 Nov 2026
- Harga toko: bayi 5×, siap kawin 10×; bayaran pesanan dibulatkan ke atas (selalu ≥ 125% nilai).

## v20 — 19 Nov 2026
- Pesanan selalu lebih untung: dibayar hadiah atau 125% nilai hewan.

## v19 — 19 Nov 2026
- Pesanan: bentuk super memenuhi gen aslinya (Ivory untuk Yellow Belly, BEL untuk Mojave/Lesser, dst.), 60 nama pemesan.

## v18 — 19 Nov 2026
- Harga rak naik 8× tiap pembelian; event harga pakan berlaku untuk semua spesies.

## v17 — 19 Nov 2026
- **Axolotl** sebagai spesies ketiga (5 gen resesif + GFP & RFP), bayi menetas berkelompok (pilih 3). "Tub" jadi "space"; judul jadi "Exotic Breeder Sim".

## v16 — 19 Nov 2026
- Leopard gecko: sekali kawin menghasilkan 4–6 clutch berturut-turut. Teks umum memakai "hewan".

## v15 — 19 Nov 2026
- **Leopard gecko** sebagai spesies kedua (12 gen, 10 kombinasi bernama); panduan genetika jadi Panduan spesies.

## v14 — 19 Nov 2026
- Harga rak naik 4× tiap pembelian.

## v13 — 19 Nov 2026
- Batas umur ball python 30 tahun; label Tua & sisa umur.

## v12 — 19 Nov 2026
- Harga rak naik 2× tiap pembelian + konfirmasi beli rak; game baru otomatis setelah save di-reset admin.

## v11 — 19 Nov 2026
- Pengaturan → Tentang menampilkan versi server & versi web (nomor versi mulai dicatat di `core.js`).

## Versi awal (sebelum v11) — 18–19 Nov 2026
- Game breeding ball python berbasis web: genetika resesif / co-dominan / dominan / kompleks BEL, het & pos het, siklus bulanan, ekonomi, pesanan pembeli, Morph Dex.
- Login & cloud save Supabase; logo Morph Lab; bahasa Indonesia & Inggris.
- Teman, chat, dan trading dengan escrow; global chat; profil pemain dengan bio & showcase; asal-usul hewan (origin keeper).
- Mode online server-authoritative (logika dihitung Edge Function `game`), wajib login, mode offline dihapus.
- Breeding kapan saja (tanpa musim kawin); suhu inkubator mengatur peluang jenis kelamin; pasar 3 hewan bergen tunggal.
- Reset & hapus akun dengan 2 verifikasi; pratinjau saldo bulan depan; ular awal sepasang siap kawin; Pengaturan dengan 3 tema warna.
