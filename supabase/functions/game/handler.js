// Logika Edge Function "game": terima AKSI dari pemain, jalankan di server, simpan hasilnya.
// Dipisah dari index.ts supaya bisa diuji tanpa Supabase (db disuntikkan).
import './core.js';

const C = globalThis.MorphCore;
const MAX_RETRY = 4;

/**
 * @param {object} body  isi request: { action: { type, ... } }
 * @param {string} uid   id pemain yang sudah diverifikasi
 * @param {object} db    { load(uid) -> {data, rev, rank} | null, insert(uid, data, rank) -> bool, update(uid, data, oldRev, rank) -> bool,
 *                         (rank = angka papan peringkat dari C.rankStats, disimpan di kolom saves.rank)
 *                         beforeReset(uid) -> void,
 *                         marketList(uid, data, oldRev, rank, {snake, price, value, name, code}) -> id listing | null (save berubah) }
 * @returns {Promise<object>} { state, rev, head?, toast? }  (melempar Error(kode) kalau gagal)
 */
export async function handle(body, uid, db) {
  // Setiap balasan menyertakan versi server supaya browser bisa menampilkannya di Pengaturan.
  return { ...(await run(body, uid, db)), server: C.VERSION };
}

async function run(body, uid, db) {
  const action = body && body.action;
  if (!action || typeof action !== 'object' || typeof action.type !== 'string') throw new Error('bad_action');
  if (action.type === 'reset') {
    // Mulai ulang akun hanya kalau pemain mengetik RESET.
    if (action.confirm !== 'RESET') throw new Error('confirm_mismatch');
    // Batalkan tawaran trade yang belum dijawab & buang kiriman lama supaya tidak masuk ke game baru.
    if (db.beforeReset) await db.beforeReset(uid);
  }

  for (let attempt = 0; attempt < MAX_RETRY; attempt++) {
    const row = await db.load(uid);
    const valid = row && C.isState(row.data);

    // Buat game baru kalau pemain belum punya save (atau minta mulai ulang).
    if (action.type === 'init' || action.type === 'reset') {
      if (action.type === 'init' && valid) {
        // Save lama dengan format pasar lama: ubah sekali ke pasar baru lalu simpan.
        C.use(row.data);
        // save tanpa angka peringkat (pemain lama) ikut disimpan ulang supaya langsung masuk papan peringkat
        // save yang belum menjalankan perbaikan inbreeding v31 juga disimpan ulang sekali
        const inbOk = !!(row.data.fx && row.data.fx.inb);
        // leopard gecko tanpa nilai sifat line-bred (save sebelum v42, termasuk susunan lama v41) diberi nilai awal sekali, lalu disimpan
        if (C.marketOk() && row.rank && inbOk && C.lbOk()) return { state: row.data, rev: row.rev };
        C.ensureMarket();
        C.addLb();
        if (!inbOk) { C.repairInb(); row.data.fx = Object.assign(row.data.fx || {}, { inb: 1 }); }
        row.data.rev = row.rev + 1;
        if (await db.update(uid, row.data, row.rev, C.rankStats(row.data))) return { state: row.data, rev: row.data.rev };
        continue;
      }
      const fresh = C.newGame();
      if (row) {
        fresh.rev = row.rev + 1;
        if (await db.update(uid, fresh, row.rev, C.rankStats(fresh))) return { state: fresh, rev: fresh.rev, toast: action.type === 'reset' ? 't_reset' : null };
      } else {
        fresh.rev = 1;
        if (await db.insert(uid, fresh, C.rankStats(fresh))) return { state: fresh, rev: 1 };
      }
      continue; // ada perubahan bersamaan, ulangi
    }

    if (!valid) throw new Error('no_save');
    const state = row.data;
    const result = C.applyAction(state, action);   // melempar Error(kode) kalau aksi tidak sah
    state.rev = row.rev + 1;
    if (result.market) {
      // Pasar Pemain: save baru + daftar jualan + escrow disimpan dalam satu transaksi database
      if (!db.marketList) throw new Error('bad_action');
      const id = await db.marketList(uid, state, row.rev, C.rankStats(state), result.market);
      if (id) return { state, rev: state.rev, toast: result.toast || null, quests: result.quests || null, listing: id };
      continue;
    }
    if (await db.update(uid, state, row.rev, C.rankStats(state))) return { state, rev: state.rev, head: result.head || null, toast: result.toast || null, quests: result.quests || null };
    // save berubah di tengah jalan (mis. trade diterima): baca ulang dan ulangi aksinya
  }
  throw new Error('busy_retry');
}
