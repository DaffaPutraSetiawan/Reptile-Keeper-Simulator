// Logika Edge Function "game": terima AKSI dari pemain, jalankan di server, simpan hasilnya.
// Dipisah dari index.ts supaya bisa diuji tanpa Supabase (db disuntikkan).
import './core.js';

const C = globalThis.MorphCore;
const MAX_RETRY = 4;

/**
 * @param {object} body  isi request: { action: { type, ... } }
 * @param {string} uid   id pemain yang sudah diverifikasi
 * @param {object} db    { load(uid) -> {data, rev} | null, insert(uid, data) -> bool, update(uid, data, oldRev) -> bool,
 *                         beforeReset(uid) -> void }
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
        if (C.marketOk()) return { state: row.data, rev: row.rev };
        C.ensureMarket();
        row.data.rev = row.rev + 1;
        if (await db.update(uid, row.data, row.rev)) return { state: row.data, rev: row.data.rev };
        continue;
      }
      const fresh = C.newGame();
      if (row) {
        fresh.rev = row.rev + 1;
        if (await db.update(uid, fresh, row.rev)) return { state: fresh, rev: fresh.rev, toast: action.type === 'reset' ? 't_reset' : null };
      } else {
        fresh.rev = 1;
        if (await db.insert(uid, fresh)) return { state: fresh, rev: 1 };
      }
      continue; // ada perubahan bersamaan, ulangi
    }

    if (!valid) throw new Error('no_save');
    const state = row.data;
    const result = C.applyAction(state, action);   // melempar Error(kode) kalau aksi tidak sah
    state.rev = row.rev + 1;
    if (await db.update(uid, state, row.rev)) return { state, rev: state.rev, head: result.head || null, toast: result.toast || null };
    // save berubah di tengah jalan (mis. trade diterima): baca ulang dan ulangi aksinya
  }
  throw new Error('busy_retry');
}
