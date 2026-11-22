-- =====================================================================
-- Morph Lab — fitur sosial: teman, chat, dan trading antar teman
-- Jalankan SETELAH schema.sql, di Supabase Dashboard → SQL Editor → Run.
-- Aman dijalankan ulang (idempoten).
--
-- Prinsip keamanan:
--  * Semua perubahan (pertemanan, pesan, trade) hanya lewat fungsi di bawah,
--    yang memeriksa auth.uid(). Tabel tidak punya policy INSERT/UPDATE/DELETE.
--  * Server hanya mengubah save milik pemain yang sedang memanggil fungsi,
--    dan hanya kalau versi save (rev) cocok. Barang untuk pemain lain
--    dikirim lewat tabel deliveries dan diklaim oleh pemiliknya sendiri.
--  * Ular & uang yang ditawarkan langsung masuk escrow, jadi tidak bisa
--    dijual/ditawarkan dua kali, dan kembali utuh kalau trade batal.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TABEL
-- ---------------------------------------------------------------------
create table if not exists public.friendships (
  id          bigint generated always as identity primary key,
  requester   uuid not null references auth.users (id) on delete cascade,
  addressee   uuid not null references auth.users (id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at  timestamptz not null default now(),
  accepted_at timestamptz,
  constraint friendships_not_self check (requester <> addressee)
);
create unique index if not exists friendships_pair_idx
  on public.friendships (least(requester, addressee), greatest(requester, addressee));
create index if not exists friendships_addressee_idx on public.friendships (addressee);

create table if not exists public.messages (
  id         bigint generated always as identity primary key,
  sender     uuid not null references auth.users (id) on delete cascade,
  recipient  uuid not null references auth.users (id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists messages_pair_idx
  on public.messages (least(sender, recipient), greatest(sender, recipient), id desc);
create index if not exists messages_unread_idx on public.messages (recipient, sender) where read_at is null;
create index if not exists messages_sender_time_idx on public.messages (sender, created_at desc);
-- Balas pesan (reply): id pesan yang dibalas + salinan nama pengirim & potongan isinya (maks. 120 karakter),
-- supaya kutipan tetap terbaca walaupun pesan aslinya sudah hilang. reply_to ada tapi reply_body null = pesan asli dihapus admin.
alter table public.messages add column if not exists reply_to bigint;
alter table public.messages add column if not exists reply_name text;
alter table public.messages add column if not exists reply_body text;

create table if not exists public.trades (
  id              bigint generated always as identity primary key,
  -- null = akun pemain itu sudah dihapus (riwayat tetap tampil sebagai "(akun dihapus)")
  from_user       uuid references auth.users (id) on delete set null,
  to_user         uuid references auth.users (id) on delete set null,
  offer_money     integer not null default 0 check (offer_money between 0 and 10000000),
  request_money   integer not null default 0 check (request_money between 0 and 10000000),
  offer_preview   jsonb not null default '[]'::jsonb,   -- ular yang ditawarkan (tanpa gen het tersembunyi)
  request_ids     integer[] not null default '{}',      -- id ular milik penerima yang diminta
  request_preview jsonb not null default '[]'::jsonb,
  note            text check (char_length(note) <= 200),
  status          text not null default 'pending'
                  check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at      timestamptz not null default now(),
  resolved_at     timestamptz,
  constraint trades_not_self check (from_user <> to_user)
);
-- Database lama: riwayat trade tidak ikut terhapus saat akun salah satu pemain dihapus.
alter table public.trades alter column from_user drop not null, alter column to_user drop not null;
alter table public.trades drop constraint if exists trades_from_user_fkey, drop constraint if exists trades_to_user_fkey;
alter table public.trades
  add constraint trades_from_user_fkey foreign key (from_user) references auth.users (id) on delete set null,
  add constraint trades_to_user_fkey foreign key (to_user) references auth.users (id) on delete set null;
create index if not exists trades_from_idx on public.trades (from_user, id desc);
create index if not exists trades_to_idx on public.trades (to_user, id desc);

-- Isi escrow lengkap (dengan genotipe asli). Tidak bisa dibaca dari browser.
create table if not exists public.trade_escrow (
  trade_id bigint primary key references public.trades (id) on delete cascade,
  snakes   jsonb not null default '[]'::jsonb
);

-- Kiriman barang ke pemain (hasil trade / pengembalian escrow).
create table if not exists public.deliveries (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  trade_id   bigint references public.trades (id) on delete set null,
  snakes     jsonb not null default '[]'::jsonb,
  money      integer not null default 0,
  log        jsonb,
  created_at timestamptz not null default now(),
  claimed_at timestamptz
);
create index if not exists deliveries_unclaimed_idx on public.deliveries (user_id) where claimed_at is null;

-- ---------------------------------------------------------------------
-- ROW LEVEL SECURITY: pemain hanya bisa MEMBACA data yang melibatkan dirinya
-- ---------------------------------------------------------------------
alter table public.friendships  enable row level security;
alter table public.messages     enable row level security;
alter table public.trades       enable row level security;
alter table public.trade_escrow enable row level security;
alter table public.deliveries   enable row level security;

drop policy if exists "friendships: lihat milik sendiri" on public.friendships;
create policy "friendships: lihat milik sendiri" on public.friendships
  for select to authenticated using ((select auth.uid()) in (requester, addressee));

drop policy if exists "messages: lihat percakapan sendiri" on public.messages;
create policy "messages: lihat percakapan sendiri" on public.messages
  for select to authenticated using ((select auth.uid()) in (sender, recipient));

drop policy if exists "trades: lihat milik sendiri" on public.trades;
create policy "trades: lihat milik sendiri" on public.trades
  for select to authenticated using ((select auth.uid()) in (from_user, to_user));

drop policy if exists "deliveries: lihat milik sendiri" on public.deliveries;
create policy "deliveries: lihat milik sendiri" on public.deliveries
  for select to authenticated using ((select auth.uid()) = user_id);

-- trade_escrow sengaja tanpa policy: tertutup untuk browser.
revoke all on public.trade_escrow from anon, authenticated;
-- Tabel lain: browser hanya boleh SELECT (perubahan lewat fungsi).
revoke insert, update, delete on public.friendships, public.messages, public.trades, public.deliveries from anon, authenticated;
grant select on public.friendships, public.messages, public.trades, public.deliveries to authenticated;

-- ---------------------------------------------------------------------
-- FUNGSI BANTU (internal, tidak bisa dipanggil dari browser)
-- ---------------------------------------------------------------------
create or replace function public._me()
returns uuid language plpgsql stable set search_path = '' as $$
declare v uuid := auth.uid();
begin
  if v is null then raise exception 'not_authenticated'; end if;
  return v;
end $$;

create or replace function public._are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.friendships f
                 where f.status = 'accepted'
                   and least(f.requester, f.addressee) = least(a, b)
                   and greatest(f.requester, f.addressee) = greatest(a, b));
$$;

create or replace function public._username(u uuid)
returns text language sql stable security definer set search_path = '' as $$
  select username from public.profiles where id = u;
$$;

-- Versi publik seekor ular: gen resesif yang tidak tampak (het tersembunyi) disembunyikan.
create or replace function public._public_snake(s jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare k text; g jsonb := coalesce(s -> 'g', '{}'::jsonb);
begin
  -- gen resesif yang tidak terlihat (het) disembunyikan dari pemain lain
  foreach k in array array['albino', 'piebald', 'clown', 'axanthic',
                           'tremper', 'bell', 'rainwater', 'eclipse', 'blizzard', 'murphy', 'marble',
                           'axleu', 'axalb', 'axmel', 'axaxa', 'axcop'] loop
    if g ? k and (g -> k) <> '[1, 1]'::jsonb then
      g := jsonb_set(g, array[k], '[0, 0]'::jsonb);
    end if;
  end loop;
  return jsonb_build_object('id', s -> 'id', 'sp', coalesce(s -> 'sp', '"ball"'::jsonb), 'sex', s -> 'sex', 'age', s -> 'age', 'w', s -> 'w',
    'g', g, 'hp', coalesce(s -> 'hp', '{}'::jsonb), 'gen', s -> 'gen', 'seed', s -> 'seed',
    'sire', s -> 'sire', 'dam', s -> 'dam', 'nick', coalesce(s -> 'nick', '""'::jsonb),
    'src', s -> 'src', 'origin', s -> 'origin', 'keepers', s -> 'keepers',
    'lb', s -> 'lb');   -- v50: nilai sifat line-bred (leopard gecko), supaya pemain lain melihat label, tingkat & nilainya
end $$;

-- Validasi dasar data ular (menolak data rusak / tidak masuk akal).
create or replace function public._valid_snake(s jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare k text; a jsonb; v jsonb; maxv int; v_sp text := coalesce(s ->> 'sp', 'ball');
begin
  if jsonb_typeof(s) <> 'object' or jsonb_typeof(s -> 'g') <> 'object' then return false; end if;
  if v_sp not in ('ball', 'leo', 'axo') then return false; end if;   -- spesies yang dikenal game
  if coalesce(s ->> 'sex', '') not in ('M', 'F') then return false; end if;
  if jsonb_typeof(s -> 'age') <> 'number' or (s ->> 'age')::numeric not between 0 and 600 then return false; end if;
  if jsonb_typeof(s -> 'w') <> 'number' or (s ->> 'w')::numeric not between 1 and 6000 then return false; end if;
  for k, a in select * from jsonb_each(s -> 'g') loop
    if v_sp = 'ball' and k not in ('pastel','bel','enchi','yb','cinnamon','banana','spider','pinstripe','albino','piebald','clown','axanthic') then return false; end if;
    if v_sp = 'leo' and k not in ('tremper','bell','rainwater','eclipse','blizzard','murphy','marble','macksnow','giant','lemonfrost','enigma','wy') then return false; end if;
    if v_sp = 'axo' and k not in ('axleu','axalb','axmel','axaxa','axcop','gfp','rfp') then return false; end if;
    if jsonb_typeof(a) <> 'array' or jsonb_array_length(a) <> 2 then return false; end if;
    maxv := case when k = 'bel' then 2 else 1 end;
    for v in select * from jsonb_array_elements(a) loop
      if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric not in (0, 1, 2) or (v #>> '{}')::numeric > maxv then return false; end if;
    end loop;
  end loop;
  return true;
end $$;

-- Ular boleh ditukar kalau tidak bunting, tidak diiklankan, dan tidak sedang dipasangkan.
create or replace function public._tradeable(s jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(jsonb_typeof(s -> 'gravid'), 'null') = 'null'
     and coalesce((s ->> 'listed')::boolean, false) = false
     and coalesce(jsonb_typeof(s -> 'pairedWith'), 'null') = 'null'
     and coalesce((s ->> 'pairs')::int, 0) = 0;
$$;

-- Ambil save pemain untuk diubah; menolak kalau versinya tidak cocok.
create or replace function public._lock_save(p_user uuid, p_expected_rev bigint)
returns public.saves language plpgsql security definer set search_path = '' as $$
declare r public.saves;
begin
  select * into r from public.saves where user_id = p_user for update;
  if not found then raise exception 'no_save'; end if;
  if p_expected_rev is null or r.rev <> p_expected_rev then raise exception 'stale_save'; end if;
  return r;
end $$;

-- Keluarkan ular (berdasarkan id) dari save. Mengembalikan {data, picked}.
create or replace function public._take_snakes(p_data jsonb, p_ids integer[])
returns jsonb language plpgsql set search_path = '' as $$
declare v_picked jsonb; v_rest jsonb; s jsonb; v_turn int := coalesce((p_data ->> 'turn')::int, 0);
begin
  p_ids := coalesce(p_ids, '{}');
  if cardinality(p_ids) <> (select count(distinct x) from unnest(p_ids) x) then raise exception 'duplicate_snake'; end if;
  select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_picked
    from jsonb_array_elements(coalesce(p_data -> 'snakes', '[]'::jsonb)) with ordinality t(e, o)
   where (e ->> 'id')::int = any (p_ids);
  if jsonb_array_length(v_picked) <> cardinality(p_ids) then raise exception 'snake_not_found'; end if;
  for s in select * from jsonb_array_elements(v_picked) loop
    if not public._tradeable(s) then raise exception 'snake_not_tradeable'; end if;
    if not public._valid_snake(s) then raise exception 'snake_invalid'; end if;
  end loop;
  -- simpan "sudah berapa bulan sejak bertelur" supaya masa pemulihan ikut pindah
  select coalesce(jsonb_agg(e || jsonb_build_object('xferAgo',
           greatest(0, v_turn - coalesce((e ->> 'lastLaid')::int, -99)))), '[]'::jsonb)
    into v_picked from jsonb_array_elements(v_picked) e;
  select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_rest
    from jsonb_array_elements(coalesce(p_data -> 'snakes', '[]'::jsonb)) with ordinality t(e, o)
   where not ((e ->> 'id')::int = any (p_ids));
  return jsonb_build_object('data', jsonb_set(p_data, '{snakes}', v_rest), 'picked', v_picked);
end $$;

-- Masukkan ular ke save dengan id baru.
-- Catat asal-usul saat ular berpindah pemilik lewat trade (dipanggil saat trade diterima, bukan saat escrow/refund).
--  origin  : pemain pertama yang memelihara ular ini + caranya (bred / market / starter); tidak berubah lagi
--  keepers : pemilik sebelumnya, urut dari yang pertama (maks. 10: pertama + 9 terakhir)
--  src     : {t:'trade', from: pemberi}; turn diisi oleh _add_snakes sesuai turn penerima
create or replace function public._stamp_transfer(p_snakes jsonb, p_giver uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_name text := coalesce(public._username(p_giver), '?'); s jsonb; v_out jsonb := '[]'::jsonb; v_how text; v_keep jsonb; n int;
begin
  for s in select * from jsonb_array_elements(coalesce(p_snakes, '[]'::jsonb)) loop
    if coalesce(jsonb_typeof(s -> 'origin'), 'null') <> 'object' then
      v_how := coalesce(s -> 'src' ->> 't', case when coalesce((s ->> 'gen')::int, 0) > 0 then 'bred' else 'unknown' end);
      if v_how not in ('bred', 'market', 'starter') then v_how := 'unknown'; end if;
      s := s || jsonb_build_object('origin', jsonb_build_object('u', v_name, 'how', v_how));
    end if;
    v_keep := (case when jsonb_typeof(s -> 'keepers') = 'array' then s -> 'keepers' else '[]'::jsonb end) || jsonb_build_array(v_name);
    n := jsonb_array_length(v_keep);
    if n > 10 then
      select jsonb_build_array(v_keep -> 0) || jsonb_agg(e order by o) into v_keep
        from jsonb_array_elements(v_keep) with ordinality t(e, o) where o > n - 9;
    end if;
    s := s || jsonb_build_object('keepers', v_keep, 'src', jsonb_build_object('t', 'trade', 'from', v_name));
    v_out := v_out || jsonb_build_array(s);
  end loop;
  return v_out;
end $$;

create or replace function public._add_snakes(p_data jsonb, p_snakes jsonb)
returns jsonb language plpgsql set search_path = '' as $$
declare s jsonb; v_next int := coalesce((p_data ->> 'nextId')::int, 1);
        v_turn int := coalesce((p_data ->> 'turn')::int, 0); v_list jsonb := coalesce(p_data -> 'snakes', '[]'::jsonb);
begin
  for s in select * from jsonb_array_elements(coalesce(p_snakes, '[]'::jsonb)) loop
    if s -> 'src' ->> 't' = 'trade' and s -> 'src' -> 'turn' is null then
      s := jsonb_set(s, '{src,turn}', to_jsonb(v_turn));   -- turn penerima saat ular masuk
    end if;
    s := (s - 'xferAgo') || jsonb_build_object('id', v_next, 'listed', false, 'pairedWith', null, 'pairs', 0,
           'gravid', null, 'lastLaid', v_turn - least(coalesce((s ->> 'xferAgo')::int, 99), 99));
    v_list := v_list || jsonb_build_array(s);
    v_next := v_next + 1;
  end loop;
  return p_data || jsonb_build_object('snakes', v_list, 'nextId', v_next);
end $$;

create or replace function public._add_money(p_data jsonb, p_amount numeric)
returns jsonb language plpgsql set search_path = '' as $$
declare v numeric := coalesce((p_data ->> 'money')::numeric, 0) + p_amount;
begin
  if v < 0 then raise exception 'not_enough_money'; end if;
  return jsonb_set(p_data, '{money}', to_jsonb(v));
end $$;

-- Statistik pribadi (S.ps di core.js): tambah angka ke p_kind ('ch' penjualan per saluran / 'mp' per morph: {n, v};
-- 'ex' pengeluaran: angka). Dipakai untuk kejadian yang terjadi di database (Pasar Pemain).
create or replace function public._ps_add(p_data jsonb, p_kind text, p_key text, p_n numeric, p_v numeric)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare v_ps jsonb := p_data -> 'ps'; v_g jsonb;
begin
  if v_ps is null or jsonb_typeof(v_ps) <> 'object' then v_ps := jsonb_build_object('since', coalesce((p_data ->> 'turn')::int, 0)); end if;
  v_g := case when jsonb_typeof(v_ps -> p_kind) = 'object' then v_ps -> p_kind else '{}'::jsonb end;
  if p_kind = 'ex' then
    v_g := v_g || jsonb_build_object(p_key, coalesce((v_g ->> p_key)::numeric, 0) + round(p_v));
  else
    v_g := v_g || jsonb_build_object(p_key, jsonb_build_object('n', coalesce((v_g -> p_key ->> 'n')::numeric, 0) + p_n,
                                                              'v', coalesce((v_g -> p_key ->> 'v')::numeric, 0) + round(p_v)));
  end if;
  return jsonb_set(p_data, '{ps}', v_ps || jsonb_build_object(p_kind, v_g));
end $$;

-- Tambah catatan ke log save (format kunci + parameter yang dipakai game).
create or replace function public._push_log(p_data jsonb, p_key text, p_params jsonb, p_kind text default 'star')
returns jsonb language plpgsql set search_path = '' as $$
declare v_log jsonb := jsonb_build_array(jsonb_build_object('w', coalesce((p_data ->> 'turn')::int, 0),
          'm', p_key, 'p', coalesce(p_params, '{}'::jsonb), 'k', p_kind)) || coalesce(p_data -> 'log', '[]'::jsonb);
begin
  select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_log
    from jsonb_array_elements(v_log) with ordinality t(e, o) where o <= 100;  -- maks. 100 catatan (sama dengan LOG_MAX di core.js), yang paling lama terhapus
  return jsonb_set(p_data, '{log}', v_log);
end $$;

create or replace function public._write_save(p_user uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_rev bigint;
begin
  update public.saves set data = p_data || jsonb_build_object('rev', rev + 1),
         rev = rev + 1, game_turn = coalesce((p_data ->> 'turn')::int, game_turn)
   where user_id = p_user returning rev into v_rev;
  return jsonb_build_object('rev', v_rev, 'data', p_data || jsonb_build_object('rev', v_rev));
end $$;

-- Batalkan trade & kirim isi escrow kembali ke penawar.
create or replace function public._refund_trade(p_trade public.trades, p_status text, p_by uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_snakes jsonb;
begin
  select snakes into v_snakes from public.trade_escrow where trade_id = p_trade.id;
  -- p_status 'deleted' (akun dihapus) / 'reset' (akun di-reset) dicatat sebagai 'cancelled'; alasannya ada di log
  update public.trades set status = case when p_status in ('deleted', 'reset') then 'cancelled' else p_status end, resolved_at = now() where id = p_trade.id;
  insert into public.deliveries (user_id, trade_id, snakes, money, log)
  values (p_trade.from_user, p_trade.id, coalesce(v_snakes, '[]'::jsonb), p_trade.offer_money,
          jsonb_build_object('m', 'l_trade_back', 'p', jsonb_build_object(
            'u', public._username(case when p_by = p_trade.from_user then p_trade.to_user else p_by end),
            'why', p_status, 'n', jsonb_array_length(coalesce(v_snakes, '[]'::jsonb)), 'mo', p_trade.offer_money)));
  delete from public.trade_escrow where trade_id = p_trade.id;
end $$;

-- ---------------------------------------------------------------------
-- TEMAN
-- ---------------------------------------------------------------------
create or replace function public.send_friend_request(p_username text)
returns text language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); v_other uuid; f public.friendships;
begin
  if not exists (select 1 from public.profiles where id = me) then return 'no_profile'; end if;
  select id into v_other from public.profiles where lower(username) = lower(trim(p_username));
  if v_other is null then return 'not_found'; end if;
  if v_other = me then return 'self'; end if;
  select * into f from public.friendships
   where least(requester, addressee) = least(me, v_other) and greatest(requester, addressee) = greatest(me, v_other)
   for update;
  if found then
    if f.status = 'accepted' then return 'already_friends'; end if;
    if f.requester = me then return 'already_sent'; end if;
    update public.friendships set status = 'accepted', accepted_at = now() where id = f.id;  -- dia sudah minta duluan
    return 'accepted';
  end if;
  if (select count(*) from public.friendships where requester = me and status = 'pending') >= 50 then return 'too_many'; end if;
  insert into public.friendships (requester, addressee) values (me, v_other);
  return 'sent';
exception when unique_violation then return 'already_sent';
end $$;

create or replace function public.respond_friend_request(p_id bigint, p_accept boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me();
begin
  if p_accept then
    update public.friendships set status = 'accepted', accepted_at = now()
     where id = p_id and addressee = me and status = 'pending';
    return case when found then 'accepted' else 'not_found' end;
  end if;
  delete from public.friendships where id = p_id and addressee = me and status = 'pending';
  return case when found then 'declined' else 'not_found' end;
end $$;

-- Hapus teman / batalkan permintaan. Semua chat di antara keduanya dihapus permanen,
-- dan trade yang masih pending dibatalkan (barang kembali ke penawar).
create or replace function public.remove_friend(p_other uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); t public.trades;
begin
  delete from public.friendships
   where least(requester, addressee) = least(me, p_other) and greatest(requester, addressee) = greatest(me, p_other);
  delete from public.messages
   where least(sender, recipient) = least(me, p_other) and greatest(sender, recipient) = greatest(me, p_other);
  for t in select * from public.trades
            where status = 'pending' and ((from_user = me and to_user = p_other) or (from_user = p_other and to_user = me))
            for update loop
    perform public._refund_trade(t, 'cancelled', me);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- CHAT
-- ---------------------------------------------------------------------
-- p_reply = id pesan di percakapan ini yang dibalas (boleh null)
drop function if exists public.send_message(uuid, text);
create or replace function public.send_message(p_to uuid, p_body text, p_reply bigint default null)
returns public.messages language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); m public.messages; q public.messages;
begin
  p_body := trim(coalesce(p_body, ''));
  if char_length(p_body) = 0 then raise exception 'empty_message'; end if;
  if char_length(p_body) > 1000 then raise exception 'message_too_long'; end if;
  if not public._are_friends(me, p_to) then raise exception 'not_friends'; end if;
  if (select count(*) from public.messages where sender = me and created_at > now() - interval '1 minute') >= 30 then
    raise exception 'rate_limited';
  end if;
  if p_reply is not null then
    select * into q from public.messages where id = p_reply
       and least(sender, recipient) = least(me, p_to) and greatest(sender, recipient) = greatest(me, p_to);
    if q.id is null then raise exception 'reply_gone'; end if;
  end if;
  insert into public.messages (sender, recipient, body, reply_to, reply_name, reply_body)
  values (me, p_to, p_body, q.id, case when q.id is null then null else public._username(q.sender) end, left(q.body, 120))
  returning * into m;
  return m;
end $$;

create or replace function public.get_messages(p_friend uuid, p_before bigint default null, p_limit int default 50)
returns setof public.messages language sql stable security invoker set search_path = '' as $$
  select * from (
    select * from public.messages
     where least(sender, recipient) = least(auth.uid(), p_friend)
       and greatest(sender, recipient) = greatest(auth.uid(), p_friend)
       and (p_before is null or id < p_before)
     order by id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)
  ) x order by id;
$$;

create or replace function public.mark_read(p_friend uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.messages set read_at = now()
   where recipient = public._me() and sender = p_friend and read_at is null;
end $$;

-- Semua data sosial untuk tab Teman dalam satu panggilan.
create or replace function public.get_social()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := public._me();
begin
  return jsonb_build_object(
    'friends', coalesce((
      select jsonb_agg(jsonb_build_object('fid', f.id, 'id', o.id, 'username', p.username, 'since', f.accepted_at,
               'unread', (select count(*) from public.messages m where m.recipient = me and m.sender = o.id and m.read_at is null),
               'last', (select max(m.id) from public.messages m
                         where least(m.sender, m.recipient) = least(me, o.id) and greatest(m.sender, m.recipient) = greatest(me, o.id)))
             order by p.username)
        from public.friendships f
        cross join lateral (select case when f.requester = me then f.addressee else f.requester end as id) o
        join public.profiles p on p.id = o.id
       where f.status = 'accepted' and me in (f.requester, f.addressee)), '[]'::jsonb),
    'incoming', coalesce((
      select jsonb_agg(jsonb_build_object('fid', f.id, 'id', f.requester, 'username', p.username, 'at', f.created_at) order by f.id desc)
        from public.friendships f join public.profiles p on p.id = f.requester
       where f.addressee = me and f.status = 'pending'), '[]'::jsonb),
    'outgoing', coalesce((
      select jsonb_agg(jsonb_build_object('fid', f.id, 'id', f.addressee, 'username', p.username, 'at', f.created_at) order by f.id desc)
        from public.friendships f join public.profiles p on p.id = f.addressee
       where f.requester = me and f.status = 'pending'), '[]'::jsonb),
    'trades', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'dir', case when t.from_user = me then 'out' else 'in' end,
               'other', case when t.from_user = me then t.to_user else t.from_user end,
               'username', public._username(case when t.from_user = me then t.to_user else t.from_user end),
               'offer_money', t.offer_money, 'request_money', t.request_money,
               'offer', t.offer_preview, 'request', t.request_preview, 'note', t.note,
               'status', t.status, 'at', t.created_at, 'resolved', t.resolved_at) order by t.id desc)
        from (select * from public.trades where me in (from_user, to_user)
               order by (status = 'pending') desc, id desc limit 40) t), '[]'::jsonb),
    'deliveries', (select count(*) from public.deliveries where user_id = me and claimed_at is null)
  );
end $$;

-- Koleksi teman (versi publik) untuk memilih ular yang diminta.
create or replace function public.get_friend_collection(p_friend uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := public._me();
begin
  if not public._are_friends(me, p_friend) then raise exception 'not_friends'; end if;
  return jsonb_build_object('username', public._username(p_friend), 'snakes', coalesce((
    select jsonb_agg(public._public_snake(e) || jsonb_build_object('tradeable', public._tradeable(e)) order by o)
      from public.saves s, jsonb_array_elements(coalesce(s.data -> 'snakes', '[]'::jsonb)) with ordinality t(e, o)
     where s.user_id = p_friend), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------
-- GLOBAL CHAT: semua pemain yang login bisa membaca & menulis; hanya 50 pesan terakhir disimpan
-- ---------------------------------------------------------------------
create table if not exists public.global_messages (
  id         bigint generated always as identity primary key,
  sender     uuid not null references auth.users (id) on delete cascade,
  username   text not null,                      -- disalin saat kirim supaya realtime langsung bisa menampilkan nama
  body       text not null check (char_length(body) between 1 and 300),
  created_at timestamptz not null default now()
);
create index if not exists global_messages_sender_idx on public.global_messages (sender, created_at desc);
-- Balas pesan (reply), sama seperti chat teman. Kutipan disalin karena chat global hanya menyimpan 50 pesan terakhir.
alter table public.global_messages add column if not exists reply_to bigint;
alter table public.global_messages add column if not exists reply_name text;
alter table public.global_messages add column if not exists reply_body text;
alter table public.global_messages enable row level security;
drop policy if exists "global: pemain login boleh baca" on public.global_messages;
create policy "global: pemain login boleh baca" on public.global_messages for select to authenticated using (true);
revoke insert, update, delete on public.global_messages from anon, authenticated;

drop function if exists public.send_global_message(text);
create or replace function public.send_global_message(p_body text, p_reply bigint default null)
returns public.global_messages language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); v_name text; m public.global_messages; v_cut bigint; q public.global_messages;
begin
  select username into v_name from public.profiles where id = me;
  if v_name is null then raise exception 'no_profile'; end if;
  p_body := btrim(regexp_replace(coalesce(p_body, ''), '[\x01-\x1f\x7f]+', ' ', 'g'));
  if char_length(p_body) = 0 then raise exception 'empty_message'; end if;
  if char_length(p_body) > 300 then raise exception 'message_too_long'; end if;
  if (select count(*) from public.global_messages where sender = me and created_at > now() - interval '1 minute') >= 10 then
    raise exception 'rate_limited';
  end if;
  -- Moderasi (moderation.sql): cek bisu, pesan berulang, sensor kata kasar. Dilewati kalau file itu belum dijalankan.
  if to_regprocedure('public._chat_guard(uuid,text)') is not null then
    execute 'select public._chat_guard($1, $2)' into p_body using me, p_body;
  end if;
  if p_reply is not null then
    select * into q from public.global_messages where id = p_reply;
    if q.id is null then raise exception 'reply_gone'; end if;   -- sudah tergeser keluar dari 50 terakhir / dihapus
  end if;
  insert into public.global_messages (sender, username, body, reply_to, reply_name, reply_body)
  values (me, v_name, p_body, q.id, q.username, left(q.body, 120)) returning * into m;
  -- simpan hanya 50 pesan terakhir: yang lebih lama dihapus
  select id into v_cut from public.global_messages order by id desc offset 50 limit 1;
  if v_cut is not null then delete from public.global_messages where id <= v_cut; end if;
  return m;
end $$;

-- 50 pesan terakhir, urut dari yang paling lama
create or replace function public.get_global_messages()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(g) order by g.id), '[]'::jsonb)
    from (select * from public.global_messages order by id desc limit 50) g;
$$;

-- ---------------------------------------------------------------------
-- PROFIL: lihat profil sendiri / orang lain, edit bio & showcase
-- ---------------------------------------------------------------------
-- Profil publik pemain (berdasarkan username). Showcase memakai versi publik ular
-- (gen het yang belum terbukti tidak dibocorkan) dan hanya ular yang masih dimiliki.
create or replace function public.get_profile(p_username text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := public._me(); p public.profiles; v_data jsonb; v_rel text; v_fid bigint; f public.friendships;
begin
  select * into p from public.profiles where lower(username) = lower(btrim(coalesce(p_username, '')));
  if not found then raise exception 'not_found'; end if;
  select data into v_data from public.saves where user_id = p.id;
  v_data := coalesce(v_data, '{}'::jsonb);
  if p.id = me then v_rel := 'self';
  else
    select * into f from public.friendships
     where least(requester, addressee) = least(me, p.id) and greatest(requester, addressee) = greatest(me, p.id);
    if not found then v_rel := 'none';
    elsif f.status = 'accepted' then v_rel := 'friends'; v_fid := f.id;
    elsif f.requester = me then v_rel := 'pending_out'; v_fid := f.id;
    else v_rel := 'pending_in'; v_fid := f.id;
    end if;
  end if;
  return jsonb_build_object(
    'id', p.id, 'username', p.username, 'bio', p.bio, 'joined', p.created_at, 'relation', v_rel, 'fid', v_fid,
    'stats', jsonb_build_object(
      'turn', coalesce((v_data ->> 'turn')::int, 0),
      'snakes', jsonb_array_length(coalesce(v_data -> 'snakes', '[]'::jsonb)),
      'morphs', (select count(*) from jsonb_object_keys(coalesce(v_data -> 'dex', '{}'::jsonb))),
      'hatched', coalesce((v_data -> 'stats' ->> 'hatched')::int, 0),
      -- reputasi breeder (save lama tanpa 'rep': sama dengan jumlah pesanan yang dipenuhi)
      'rep', coalesce((v_data ->> 'rep')::int, (v_data -> 'stats' ->> 'orders')::int, 0),
      'friends', (select count(*) from public.friendships where status = 'accepted' and p.id in (requester, addressee))),
    'showcase', coalesce((
      select jsonb_agg(public._public_snake(e) order by array_position(p.showcase, (e ->> 'id')::int))
        from jsonb_array_elements(coalesce(v_data -> 'snakes', '[]'::jsonb)) e
       where (e ->> 'id')::int = any (p.showcase)), '[]'::jsonb));
end $$;

-- Ubah bio (maks. 160 karakter) & showcase (maks. 6 ular milik sendiri, urutan dipertahankan).
create or replace function public.update_profile(p_bio text, p_showcase integer[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); v_bio text; v_ids integer[]; v_owned integer[]; v_name text;
begin
  -- buang karakter kontrol kecuali baris baru
  v_bio := btrim(regexp_replace(coalesce(p_bio, ''), '[\x01-\x09\x0b-\x1f\x7f]', '', 'g'));
  if char_length(v_bio) > 160 then raise exception 'bio_too_long'; end if;
  select coalesce(array_agg(x order by o), '{}') into v_ids
    from (select x, min(o) as o from unnest(coalesce(p_showcase, '{}'::integer[])) with ordinality u(x, o)
           where x is not null group by x) q;
  if cardinality(v_ids) > 6 then raise exception 'showcase_too_many'; end if;
  select coalesce(array_agg((e ->> 'id')::int), '{}') into v_owned
    from public.saves s, jsonb_array_elements(coalesce(s.data -> 'snakes', '[]'::jsonb)) e where s.user_id = me;
  if not (v_ids <@ v_owned) then raise exception 'snake_not_found'; end if;
  update public.profiles set bio = v_bio, showcase = v_ids where id = me returning username into v_name;
  if v_name is null then raise exception 'no_profile'; end if;
  return public.get_profile(v_name);
end $$;

-- ---------------------------------------------------------------------
-- TRADING
-- ---------------------------------------------------------------------
-- Buat tawaran: ular & uang milik penawar langsung masuk escrow.
create or replace function public.create_trade(
  p_to uuid, p_offer_ids integer[], p_offer_money integer,
  p_request_ids integer[], p_request_money integer, p_note text, p_expected_rev bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); v_save public.saves; v_take jsonb; v_data jsonb; v_trade bigint;
        v_their jsonb; v_req_preview jsonb; v_out jsonb;
begin
  p_offer_ids := coalesce(p_offer_ids, '{}'); p_request_ids := coalesce(p_request_ids, '{}');
  p_offer_money := coalesce(p_offer_money, 0); p_request_money := coalesce(p_request_money, 0);
  if p_to = me then raise exception 'self_trade'; end if;
  if not public._are_friends(me, p_to) then raise exception 'not_friends'; end if;
  if p_offer_money < 0 or p_request_money < 0 or p_offer_money > 10000000 or p_request_money > 10000000 then raise exception 'bad_money'; end if;
  if cardinality(p_offer_ids) > 10 or cardinality(p_request_ids) > 10 then raise exception 'too_many_snakes'; end if;
  -- harus ada yang ditawarkan (hadiah tanpa meminta apa pun boleh)
  if cardinality(p_offer_ids) = 0 and p_offer_money = 0 then raise exception 'empty_offer'; end if;
  if char_length(coalesce(p_note, '')) > 200 then raise exception 'note_too_long'; end if;
  if (select count(*) from public.trades where from_user = me and status = 'pending') >= 20 then raise exception 'too_many_trades'; end if;
  if cardinality(p_request_ids) <> (select count(distinct x) from unnest(p_request_ids) x) then raise exception 'duplicate_snake'; end if;

  -- cek ular yang diminta (pengecekan final tetap saat diterima)
  select coalesce(jsonb_agg(public._public_snake(e) order by o), '[]'::jsonb) into v_req_preview
    from public.saves s, jsonb_array_elements(coalesce(s.data -> 'snakes', '[]'::jsonb)) with ordinality t(e, o)
   where s.user_id = p_to and (e ->> 'id')::int = any (p_request_ids) and public._tradeable(e);
  if jsonb_array_length(v_req_preview) <> cardinality(p_request_ids) then raise exception 'request_unavailable'; end if;

  v_save := public._lock_save(me, p_expected_rev);
  v_take := public._take_snakes(v_save.data, p_offer_ids);
  v_data := public._add_money(v_take -> 'data', -p_offer_money);

  insert into public.trades (from_user, to_user, offer_money, request_money, offer_preview, request_ids, request_preview, note)
  values (me, p_to, p_offer_money, p_request_money,
          coalesce((select jsonb_agg(public._public_snake(e)) from jsonb_array_elements(v_take -> 'picked') e), '[]'::jsonb),
          p_request_ids, v_req_preview, nullif(trim(coalesce(p_note, '')), ''))
  returning id into v_trade;
  insert into public.trade_escrow (trade_id, snakes) values (v_trade, v_take -> 'picked');

  v_data := public._push_log(v_data, 'l_trade_sent',
              jsonb_build_object('u', public._username(p_to), 'n', jsonb_array_length(v_take -> 'picked'), 'mo', p_offer_money), 'info');
  v_out := public._write_save(me, v_data);
  return v_out || jsonb_build_object('trade_id', v_trade);
end $$;

-- Terima tawaran: pertukaran atomik. Barang untuk penawar dikirim lewat deliveries.
create or replace function public.accept_trade(p_trade bigint, p_expected_rev bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); t public.trades; v_save public.saves; v_take jsonb; v_data jsonb; v_escrow jsonb;
begin
  select * into t from public.trades where id = p_trade and to_user = me for update;
  if not found then raise exception 'trade_not_found'; end if;
  if t.status <> 'pending' then raise exception 'trade_closed'; end if;
  if not public._are_friends(me, t.from_user) then raise exception 'not_friends'; end if;

  v_save := public._lock_save(me, p_expected_rev);
  begin
    v_take := public._take_snakes(v_save.data, t.request_ids);
  exception when others then raise exception 'request_unavailable';
  end;
  v_data := public._add_money(v_take -> 'data', -t.request_money);   -- error 'not_enough_money' kalau kurang
  select snakes into v_escrow from public.trade_escrow where trade_id = t.id;
  v_data := public._add_snakes(v_data, public._stamp_transfer(coalesce(v_escrow, '[]'::jsonb), t.from_user));
  v_data := public._add_money(v_data, t.offer_money);
  v_data := public._push_log(v_data, 'l_trade_done', jsonb_build_object('u', public._username(t.from_user),
              'n', jsonb_array_length(coalesce(v_escrow, '[]'::jsonb)), 'mo', t.offer_money));

  insert into public.deliveries (user_id, trade_id, snakes, money, log)
  values (t.from_user, t.id, public._stamp_transfer(v_take -> 'picked', me), t.request_money,
          jsonb_build_object('m', 'l_trade_done', 'p', jsonb_build_object('u', public._username(me),
            'n', jsonb_array_length(v_take -> 'picked'), 'mo', t.request_money)));
  update public.trades set status = 'accepted', resolved_at = now() where id = t.id;
  delete from public.trade_escrow where trade_id = t.id;
  return public._write_save(me, v_data);
end $$;

create or replace function public.decline_trade(p_trade bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); t public.trades;
begin
  select * into t from public.trades where id = p_trade and to_user = me and status = 'pending' for update;
  if not found then raise exception 'trade_not_found'; end if;
  perform public._refund_trade(t, 'declined', me);
end $$;

create or replace function public.cancel_trade(p_trade bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); t public.trades;
begin
  select * into t from public.trades where id = p_trade and from_user = me and status = 'pending' for update;
  if not found then raise exception 'trade_not_found'; end if;
  perform public._refund_trade(t, 'cancelled', me);
end $$;

-- Klaim semua kiriman (hasil trade / escrow yang kembali) ke save sendiri.
create or replace function public.claim_deliveries(p_expected_rev bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); v_save public.saves; v_data jsonb; d public.deliveries; n int := 0;
begin
  if not exists (select 1 from public.deliveries where user_id = me and claimed_at is null) then
    return jsonb_build_object('count', 0);
  end if;
  v_save := public._lock_save(me, p_expected_rev);
  v_data := v_save.data;
  for d in select * from public.deliveries where user_id = me and claimed_at is null order by id for update loop
    v_data := public._add_snakes(v_data, d.snakes);
    v_data := public._add_money(v_data, d.money);
    if d.log is not null then
      v_data := public._push_log(v_data, d.log ->> 'm', d.log -> 'p', 'star');
      -- uang hasil Pasar Pemain ikut tercatat di statistik pribadi penjual
      if d.log ->> 'm' = 'l_mkt_sold' then
        v_data := public._ps_add(v_data, 'ch', 'pmarket', 1, d.money);
        if d.log -> 'p' ? 'k' then v_data := public._ps_add(v_data, 'mp', d.log -> 'p' ->> 'k', 1, d.money); end if;
      end if;
    end if;
    update public.deliveries set claimed_at = now() where id = d.id;
    n := n + 1;
  end loop;
  return public._write_save(me, v_data) || jsonb_build_object('count', n);
end $$;

-- ---------------------------------------------------------------------
-- AKUN DIHAPUS (oleh admin / pemain): kembalikan barang penawar dulu
-- ---------------------------------------------------------------------
-- Tanpa ini, tawaran KE akun yang dihapus ikut terhapus (cascade) beserta
-- escrow-nya, sehingga ular & uang penawar hilang. Trigger ini membatalkan
-- tawaran tersebut dan mengirim isinya kembali ke penawar sebagai kiriman.
-- Chat, pertemanan, profil, dan save akun itu ikut terhapus. Riwayat trade pemain lain tetap ada.
-- Batalkan semua tawaran yang belum dijawab yang melibatkan p_user.
--  * tawaran KE p_user: isinya dikembalikan ke penawar (alasan p_why: 'deleted' / 'reset')
--  * tawaran DARI p_user: dibatalkan, isi escrow dibuang (akunnya dihapus atau dimulai ulang)
create or replace function public._cancel_pending_trades(p_user uuid, p_why text)
returns void language plpgsql security definer set search_path = '' as $$
declare t public.trades;
begin
  for t in select * from public.trades where to_user = p_user and status = 'pending' for update loop
    perform public._refund_trade(t, p_why, p_user);
  end loop;
  delete from public.trade_escrow
   where trade_id in (select id from public.trades where from_user = p_user and status = 'pending');
  update public.trades set status = 'cancelled', resolved_at = now()
   where from_user = p_user and status = 'pending';
end $$;

-- Dipanggil Edge Function "game" (kunci server) sebelum save di-reset: tawaran yang belum dijawab
-- dibatalkan dan kiriman yang belum diambil dibuang, supaya barang lama tidak masuk ke game baru.
create or replace function public._reset_account(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public._cancel_pending_trades(p_user, 'reset');
  -- jualan aktif di Pasar Pemain ikut dibuang (market.sql); dilewati kalau file itu belum dijalankan
  if to_regprocedure('public._market_reset(uuid)') is not null then execute 'select public._market_reset($1)' using p_user; end if;
  delete from public.deliveries where user_id = p_user and claimed_at is null;
  -- id ular dimulai lagi dari 1 setelah reset, jadi showcase lama tidak berlaku lagi
  update public.profiles set showcase = '{}' where id = p_user;
end $$;

-- Pemain menghapus akunnya sendiri. Harus mengetik DELETE. Trigger di bawah ikut berjalan.
create or replace function public.delete_my_account(p_confirm text)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me();
begin
  if p_confirm is distinct from 'DELETE' then raise exception 'confirm_mismatch'; end if;
  delete from auth.users where id = me;
end $$;

create or replace function public._on_user_deleted()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- 1+2) batalkan semua tawaran yang belum dijawab (lihat _cancel_pending_trades)
  perform public._cancel_pending_trades(old.id, 'deleted');
  -- 3) riwayat dengan pemain yang akunnya juga sudah dihapus: tidak ada lagi yang bisa melihatnya
  delete from public.trades
   where (from_user = old.id and to_user is null) or (to_user = old.id and from_user is null);
  -- Riwayat lainnya tetap ada; kolom akun ini otomatis jadi null (on delete set null).
  return old;
end $$;

drop trigger if exists morphlab_before_user_delete on auth.users;
create trigger morphlab_before_user_delete
  before delete on auth.users
  for each row execute function public._on_user_deleted();

-- ---------------------------------------------------------------------
-- HAK AKSES FUNGSI
-- ---------------------------------------------------------------------
-- Fungsi internal (diawali _) tidak boleh dipanggil dari browser.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like '\_%' escape '\' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
-- _reset_account hanya untuk Edge Function (kunci server)
grant execute on function public._reset_account(uuid) to service_role;
-- touch_updated_at (dari schema.sql) juga internal
revoke all on function public.touch_updated_at() from public, anon, authenticated;

-- Fungsi publik: hanya untuk pemain yang sudah login.
do $$
declare f text;
begin
  foreach f in array array[
    'send_friend_request(text)', 'respond_friend_request(bigint, boolean)', 'remove_friend(uuid)',
    'send_message(uuid, text, bigint)', 'get_messages(uuid, bigint, integer)', 'mark_read(uuid)',
    'get_social()', 'get_friend_collection(uuid)',
    'create_trade(uuid, integer[], integer, integer[], integer, text, bigint)',
    'accept_trade(bigint, bigint)', 'decline_trade(bigint)', 'cancel_trade(bigint)', 'claim_deliveries(bigint)', 'delete_my_account(text)',
    'get_profile(text)', 'update_profile(text, integer[])',
    'send_global_message(text, bigint)', 'get_global_messages()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- REALTIME: kabari browser saat ada pesan, permintaan teman, trade, kiriman
-- ---------------------------------------------------------------------
do $$
declare tb text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach tb in array array['messages', 'friendships', 'trades', 'deliveries', 'global_messages'] loop
      if not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = tb) then
        execute format('alter publication supabase_realtime add table public.%I', tb);
      end if;
    end loop;
  end if;
end $$;
