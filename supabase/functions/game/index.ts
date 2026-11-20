// Edge Function "game": satu-satunya jalan untuk mengubah save online.
// Browser hanya mengirim aksi; hasil acak (telur, gen, pasar) dan uang dihitung di sini.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { handle } from './handler.js';

const url = Deno.env.get('SUPABASE_URL')!;
function secretKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}');
    if (keys && keys.default) return keys.default;
  } catch (_) { /* pakai kunci lama */ }
  return Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
}
const admin = createClient(url, secretKey(), { auth: { persistSession: false, autoRefreshToken: false } });

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (obj: unknown) => new Response(JSON.stringify(obj), { headers: { ...CORS, 'Content-Type': 'application/json' } });

// Akses database dengan kunci server. Hanya baris milik pemain yang memanggil yang disentuh.
const db = {
  async load(uid: string) {
    const { data, error } = await admin.from('saves').select('data, rev, rank').eq('user_id', uid).maybeSingle();
    if (error) throw new Error('db_error');
    return data;
  },
  async insert(uid: string, state: Record<string, unknown>, rank: unknown) {
    const { error } = await admin.from('saves').insert({ user_id: uid, data: state, game_turn: state.turn, rev: 1, rank });
    if (error) { if (error.code === '23505') return false; throw new Error('db_error'); }
    return true;
  },
  async beforeReset(uid: string) {
    const { error } = await admin.rpc('_reset_account', { p_user: uid });
    if (error) throw new Error('db_error');
  },
  // Pasar Pemain: simpan save (cek rev) + buat jualan + escrow dalam satu fungsi database
  async marketList(uid: string, state: Record<string, unknown>, oldRev: number, rank: unknown, m: Record<string, unknown>) {
    const { data, error } = await admin.rpc('_market_list', { p_user: uid, p_data: state, p_old_rev: oldRev, p_rank: rank,
      p_snake: m.snake, p_price: m.price, p_value: m.value, p_name: m.name, p_code: m.code });
    if (error) { const c = (error.message || '').match(/^[a-z_]{2,40}$/); throw new Error(c ? c[0] : 'db_error'); }
    return data || null;
  },
  async update(uid: string, state: Record<string, unknown>, oldRev: number, rank: unknown) {
    const { data, error } = await admin.from('saves')
      .update({ data: state, game_turn: state.turn, rev: oldRev + 1, rank })
      .eq('user_id', uid).eq('rev', oldRev).select('rev');
    if (error) throw new Error('db_error');
    return !!(data && data.length);
  },
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'bad_request' });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: auth, error: authError } = await admin.auth.getUser(jwt);
    if (authError || !auth?.user) return json({ error: 'not_authenticated' });
    const body = await req.json().catch(() => null);
    return json(await handle(body, auth.user.id, db));
  } catch (e) {
    const code = e instanceof Error ? e.message : String(e);
    // Kode error dari game berupa huruf kecil + garis bawah; selain itu jangan bocorkan detail
    return json({ error: /^[a-z_]{2,40}$/.test(code) ? code : 'server_error' });
  }
});
