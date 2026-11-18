# Reptile Keeper Simulator — MorphLab

Game simulasi breeding ball python berbasis web, dengan genetika morph yang mengikuti pola pewarisan di dunia nyata.

## Cara main

Buka `index.html` di browser. Tidak perlu install apa pun. Progres tersimpan otomatis di `localStorage` browser.

Bisa juga dimainkan online lewat GitHub Pages: **Settings → Pages → Deploy from a branch → `main` / root**.

## Fitur

- **12 gen ball python**
  - Resesif: Albino, Piebald, Clown, Axanthic
  - Co-dominan dengan bentuk super: Pastel, Enchi, Yellow Belly (→ Ivory), Cinnamon, Banana
  - Dominan: Spider, Pinstripe
  - Kompleks BEL: Mojave + Lesser → Blue-Eyed Leucistic
- **Sistem het & pos het**: bayi dari het × het tercatat 66% pos het, dan induk "terbukti het" setelah menghasilkan anak visual
- **Tabel peluang keturunan** untuk setiap pasangan
- **Siklus breeding bulanan**: musim kawin Okt–Mar, syarat umur & berat, ovulasi, jumlah telur, slug, inkubasi
- **Ekonomi**: biaya pakan & rak, harga pasar yang naik turun dan bisa jenuh, iklan, event, pesanan pembeli
- **Morph Dex** dengan 32 morph target (Bumblebee, Killer Bee, Lemon Blast, Spinner, Snow, dan lainnya)
- **Gambar ular prosedural** yang dibuat dari genetika tiap ular

## Struktur

Saat ini semuanya ada di satu file `index.html` (HTML + CSS + JavaScript) supaya mudah dibuka dan di-hosting.

## Rencana

- [ ] Spesies baru (leopard gecko, bearded dragon, corn snake)
- [ ] Perawatan & kesehatan (suhu, kelembapan, shedding, mogok makan)
- [ ] Silsilah & riwayat clutch
- [ ] Progres, misi, dan achievement
