-- =====================================================================
-- Morph Lab — PASAR PEMAIN (jual-beli hewan antarpemain, harga pas)
-- * Penjual memasang hewan lewat Edge Function "game" (aksi market_list): server menghitung nilai pasar hewan
--   dan menolak harga di bawah 50% nilai. Hewan keluar dari save dan dititipkan (escrow) di market_escrow.
-- * Pembeli membeli langsung (buy_listing): uang terpotong, hewan masuk ke save pembeli, uang dikirim ke penjual
--   lewat deliveries (diklaim otomatis seperti hasil trade).
-- * Tanpa biaya, tanpa batas jumlah jualan. Tayang 14 hari; yang tidak laku kembali ke penjual.
-- * Riwayat harga: rata-rata harga terjual per morph & kelamin dalam 30 hari terakhir.
-- * Admin (tab Admin): daftar jualan aktif & terjual, menurunkan jualan (hewan kembali ke penjual + alasan),
--   dan mengeluarkan penjualan palsu dari riwayat harga. Semua tercatat di admin_log.
-- Jalankan SETELAH schema.sql, social.sql (fungsi bantu trade) dan moderation.sql (admin_log). Aman dijalankan ulang.
-- =====================================================================

create table if not exists public.market_listings (
  id          bigint generated always as identity primary key,
  seller      uuid references auth.users (id) on delete set null,
  seller_name text not null default '',
  sp          text not null check (sp in ('ball', 'leo', 'axo')),
  name        text not null,                         -- nama morph saat dipasang
  sex         text not null check (sex in ('M', 'F')),
  code        text not null default '',              -- ID di koleksi penjual saat dipasang
  preview     jsonb not null,                        -- data hewan untuk pembeli (_public_snake)
  price       integer not null check (price between 1 and 100000000),
  value       integer not null default 0,            -- nilai pasar hewan di save penjual saat dipasang
  status      text not null default 'active' check (status in ('active', 'sold', 'cancelled', 'expired', 'removed')),
  buyer       uuid references auth.users (id) on delete set null,
  buyer_name  text not null default '',
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '14 days',
  resolved_at timestamptz
);
-- kolom tambahan (v36): penjualan yang dikeluarkan admin dari riwayat harga; status 'removed' = diturunkan admin
alter table public.market_listings add column if not exists excluded boolean not null default false;
alter table public.market_listings drop constraint if exists market_listings_status_check;
alter table public.market_listings add constraint market_listings_status_check
  check (status in ('active', 'sold', 'cancelled', 'expired', 'removed'));
-- tindakan admin pasar ikut tercatat di admin_log (moderation.sql)
alter table public.admin_log drop constraint if exists admin_log_action_check;
alter table public.admin_log add constraint admin_log_action_check check (action in ('delete_msg', 'mute', 'unmute',
  'report_actioned', 'report_dismissed', 'mkt_takedown', 'mkt_exclude', 'mkt_include'));
create index if not exists market_active_idx on public.market_listings (status, sp, price) where status = 'active';
create index if not exists market_seller_idx on public.market_listings (seller, id desc);
create index if not exists market_sold_idx on public.market_listings (sp, resolved_at) where status = 'sold';
create index if not exists market_expiry_idx on public.market_listings (expires_at) where status = 'active';

-- Hewan lengkap (genotipe asli) yang sedang dijual. Tertutup untuk browser.
create table if not exists public.market_escrow (
  listing_id bigint primary key references public.market_listings (id) on delete cascade,
  snake      jsonb not null
);

alter table public.market_listings enable row level security;
alter table public.market_escrow enable row level security;
revoke all on public.market_listings, public.market_escrow from anon, authenticated;

-- ---------------------------------------------------------------------
-- MEMASANG JUALAN (hanya untuk Edge Function "game" dengan kunci server)
-- ---------------------------------------------------------------------
-- p_data = save baru (hewan sudah dikeluarkan, rev = p_old_rev + 1). Mengembalikan id jualan,
-- atau null kalau save berubah di tengah jalan (Edge Function lalu mengulang aksinya).
create or replace function public._market_list(p_user uuid, p_data jsonb, p_old_rev bigint, p_rank jsonb,
  p_snake jsonb, p_price integer, p_value integer, p_name text, p_code text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_name text := public._username(p_user); v_id bigint;
begin
  if v_name is null then raise exception 'no_profile'; end if;
  if not public._valid_snake(p_snake) then raise exception 'snake_invalid'; end if;
  if not public._tradeable(p_snake) then raise exception 'snake_not_tradeable'; end if;
  if p_price is null or p_price > 100000000 then raise exception 'price_too_high'; end if;
  if p_price < greatest(1, ceil(coalesce(p_value, 0) * 0.5)) then raise exception 'price_too_low'; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p_data -> 'snakes', '[]'::jsonb)) e
              where (e ->> 'id')::int = (p_snake ->> 'id')::int) then raise exception 'bad_action'; end if;
  update public.saves set data = p_data, rev = p_old_rev + 1, game_turn = coalesce((p_data ->> 'turn')::int, game_turn), rank = p_rank
   where user_id = p_user and rev = p_old_rev;
  if not found then return null; end if;
  insert into public.market_listings (seller, seller_name, sp, name, sex, code, preview, price, value)
  values (p_user, v_name, coalesce(p_snake ->> 'sp', 'ball'), left(coalesce(p_name, ''), 80), p_snake ->> 'sex', left(coalesce(p_code, ''), 20),
          public._public_snake(p_snake), p_price, greatest(0, coalesce(p_value, 0)))
  returning id into v_id;
  insert into public.market_escrow (listing_id, snake) values (v_id, p_snake);
  return v_id;
end $$;

-- Kembalikan hewan jualan ke penjual lewat kiriman (dibatalkan / kedaluwarsa / diturunkan admin dengan alasan).
drop function if exists public._market_return(public.market_listings, text);
create or replace function public._market_return(p_l public.market_listings, p_status text, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_snake jsonb;
begin
  select snake into v_snake from public.market_escrow where listing_id = p_l.id;
  update public.market_listings set status = p_status, resolved_at = now() where id = p_l.id;
  if p_l.seller is not null and v_snake is not null then
    insert into public.deliveries (user_id, snakes, money, log)
    values (p_l.seller, jsonb_build_array(v_snake), 0,
            jsonb_build_object('m', 'l_mkt_back', 'p', jsonb_build_object('c', p_l.code, 'n', p_l.name, 'why', p_status)
              || case when p_reason is null then '{}'::jsonb else jsonb_build_object('r', p_reason) end));
  end if;
  delete from public.market_escrow where listing_id = p_l.id;
end $$;

-- Jualan yang lewat 14 hari dikembalikan ke penjual. Dipanggil di awal fungsi pasar lainnya.
create or replace function public._market_expire()
returns void language plpgsql security definer set search_path = '' as $$
declare l public.market_listings;
begin
  for l in select * from public.market_listings where status = 'active' and expires_at < now() for update skip locked loop
    perform public._market_return(l, 'expired');
  end loop;
end $$;

-- Akun di-reset / dihapus: jualan aktifnya dibuang (hewannya tidak dikembalikan ke game baru).
create or replace function public._market_reset(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.market_listings set status = 'cancelled', resolved_at = now() where seller = p_user and status = 'active';
  delete from public.market_escrow where listing_id in (select id from public.market_listings where seller = p_user and status = 'cancelled');
end $$;

create or replace function public._market_on_user_deleted()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public._market_reset(old.id);
  return old;
end $$;
drop trigger if exists morphlab_market_before_user_delete on auth.users;
create trigger morphlab_market_before_user_delete before delete on auth.users
  for each row execute function public._market_on_user_deleted();

-- ---------------------------------------------------------------------
-- UNTUK PEMAIN
-- ---------------------------------------------------------------------
create or replace function public._market_row(l public.market_listings, me uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', l.id, 'seller_name', coalesce(public._username(l.seller), l.seller_name),
    'rep', (select coalesce((s.rank ->> 'rep')::int, (s.rank ->> 'orders')::int, 0) from public.saves s where s.user_id = l.seller),
    'sp', l.sp, 'name', l.name, 'sex', l.sex, 'code', l.code, 'snake', l.preview, 'price', l.price, 'value', l.value,
    'status', l.status, 'created_at', l.created_at, 'expires_at', l.expires_at, 'resolved_at', l.resolved_at,
    'buyer_name', l.buyer_name, 'mine', l.seller = me);
$$;

-- Jualan aktif (maks. 300). p_sp: null = semua spesies. p_sort: new | cheap | ending | value
create or replace function public.get_market(p_sp text default null, p_sort text default 'new')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me();
begin
  perform public._market_expire();
  if p_sp is not null and p_sp not in ('ball', 'leo', 'axo') then raise exception 'bad_species'; end if;
  if coalesce(p_sort, 'new') not in ('new', 'cheap', 'ending', 'value') then raise exception 'bad_sort'; end if;
  return coalesce((select jsonb_agg(public._market_row(l, me) order by
      case when p_sort = 'cheap' then l.price end asc,
      case when p_sort = 'value' then l.value end desc,
      case when p_sort = 'ending' then l.expires_at end asc,
      l.id desc)
    from (select * from public.market_listings
           where status = 'active' and (p_sp is null or sp = p_sp)
           order by case when p_sort = 'cheap' then price end asc, case when p_sort = 'value' then value end desc,
                    case when p_sort = 'ending' then expires_at end asc, id desc
           limit 300) l), '[]'::jsonb);
end $$;

-- Jualan saya: semua yang aktif + 30 riwayat terakhir (terjual / dibatalkan / kedaluwarsa)
create or replace function public.get_my_listings()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me();
begin
  perform public._market_expire();
  return jsonb_build_object(
    'active', coalesce((select jsonb_agg(public._market_row(l, me) order by l.id desc) from public.market_listings l
                         where l.seller = me and l.status = 'active'), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(public._market_row(l, me) order by l.resolved_at desc) from (
                          select * from public.market_listings where seller = me and status <> 'active'
                           order by resolved_at desc limit 30) l), '[]'::jsonb));
end $$;

-- Riwayat harga per morph & kelamin dalam 30 hari terakhir:
--   med = median (harga tengah), lo–hi = rentang tengah (kuartil 25%–75%: seperempat termurah & termahal dibuang),
--   max = penjualan termahal, n = jumlah terjual. Browser menampilkan rentang tengah mulai 5 penjualan.
create or replace function public.get_market_prices(p_sp text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('sp', sp, 'name', name, 'sex', sex, 'n', n, 'med', med, 'lo', lo, 'hi', hi, 'max', mx)), '[]'::jsonb)
    from (select sp, name, sex, count(*) n,
                 round(percentile_cont(0.5) within group (order by price))::int med,
                 round(percentile_cont(0.25) within group (order by price))::int lo,
                 round(percentile_cont(0.75) within group (order by price))::int hi,
                 max(price) mx
            from public.market_listings
           where status = 'sold' and not excluded and resolved_at > now() - interval '30 days' and (p_sp is null or sp = p_sp)
           group by sp, name, sex) x;
$$;

-- Beli: atomik. Kalau dua pembeli bersamaan, hanya satu yang berhasil (baris jualan dikunci).
create or replace function public.buy_listing(p_listing bigint, p_expected_rev bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); l public.market_listings; v_save public.saves; v_data jsonb; v_snake jsonb; v_turn int; v_me text;
begin
  select * into l from public.market_listings where id = p_listing for update;
  if not found then raise exception 'listing_not_found'; end if;
  if l.status = 'active' and l.expires_at < now() then raise exception 'listing_closed'; end if;   -- dikembalikan oleh _market_expire()
  if l.status <> 'active' then raise exception 'listing_closed'; end if;
  if l.seller = me then raise exception 'own_listing'; end if;
  v_me := public._username(me);
  if v_me is null then raise exception 'no_profile'; end if;
  v_save := public._lock_save(me, p_expected_rev);
  v_data := public._add_money(v_save.data, -l.price);           -- 'not_enough_money' kalau kurang
  select snake into v_snake from public.market_escrow where listing_id = l.id;
  if v_snake is null then raise exception 'listing_closed'; end if;
  v_turn := coalesce((v_data ->> 'turn')::int, 0);
  v_snake := public._stamp_transfer(jsonb_build_array(v_snake), l.seller) -> 0;
  v_snake := v_snake || jsonb_build_object('src', jsonb_build_object('t', 'pmarket', 'from', coalesce(public._username(l.seller), l.seller_name), 'turn', v_turn));
  v_data := public._add_snakes(v_data, jsonb_build_array(v_snake));
  v_data := public._push_log(v_data, 'l_mkt_bought', jsonb_build_object('n', l.name, 'u', coalesce(public._username(l.seller), l.seller_name), 'p', l.price));
  if l.seller is not null then
    insert into public.deliveries (user_id, snakes, money, log)
    values (l.seller, '[]'::jsonb, l.price,
            jsonb_build_object('m', 'l_mkt_sold', 'p', jsonb_build_object('c', l.code, 'n', l.name, 'u', v_me, 'p', l.price)));
  end if;
  update public.market_listings set status = 'sold', buyer = me, buyer_name = v_me, resolved_at = now() where id = l.id;
  delete from public.market_escrow where listing_id = l.id;
  return public._write_save(me, v_data);
end $$;

-- Batalkan jualan sendiri: hewan kembali lewat kiriman
create or replace function public.cancel_listing(p_listing bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); l public.market_listings;
begin
  select * into l from public.market_listings where id = p_listing and seller = me for update;
  if not found then raise exception 'listing_not_found'; end if;
  if l.status <> 'active' then raise exception 'listing_closed'; end if;
  perform public._market_return(l, 'cancelled');
end $$;

-- ---------------------------------------------------------------------
-- ADMIN
-- ---------------------------------------------------------------------
-- Daftar untuk tab Admin. p_kind: 'active' (sedang dijual) | 'sold' (terjual). 30 per halaman, terbaru dulu.
-- Tanda: hi = harga > 5× nilai hewan · pair = penjual & pembeli ini bertransaksi ≥ 2× dalam 30 hari · fr = berteman
create or replace function public.admin_market(p_kind text default 'sold', p_before bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform public._bug_need_admin();
  perform public._market_expire();
  if p_kind not in ('active', 'sold') then raise exception 'bad_action'; end if;
  return jsonb_build_object(
    'active_n', (select count(*) from public.market_listings where status = 'active'),
    'sold_7d',  (select count(*) from public.market_listings where status = 'sold' and resolved_at > now() - interval '7 days'),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', l.id,
        'seller', l.seller, 'seller_name', coalesce(public._username(l.seller), l.seller_name),
        'buyer_name', coalesce(public._username(l.buyer), l.buyer_name),
        'sp', l.sp, 'name', l.name, 'sex', l.sex, 'code', l.code, 'snake', l.preview, 'price', l.price, 'value', l.value,
        'created_at', l.created_at, 'expires_at', l.expires_at, 'resolved_at', l.resolved_at, 'excluded', l.excluded,
        'hi', l.value > 0 and l.price > 5 * l.value,
        'pair', l.status = 'sold' and l.seller is not null and l.buyer is not null and (select count(*) from public.market_listings x
                 where x.status = 'sold' and x.seller = l.seller and x.buyer = l.buyer and x.resolved_at > now() - interval '30 days') >= 2,
        'fr', l.seller is not null and l.buyer is not null and public._are_friends(l.seller, l.buyer)) order by l.id desc)
      from (select * from public.market_listings
             where status = case when p_kind = 'active' then 'active' else 'sold' end and (p_before is null or id < p_before)
             order by id desc limit 30) l), '[]'::jsonb));
end $$;

-- Turunkan jualan aktif: hewan dikirim kembali ke penjual bersama alasannya (terlihat di catatan breeder penjual).
create or replace function public.admin_market_takedown(p_listing bigint, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare l public.market_listings;
begin
  perform public._bug_need_admin();
  p_reason := btrim(regexp_replace(coalesce(p_reason, ''), '[\x01-\x1f\x7f]+', ' ', 'g'));
  if char_length(p_reason) < 3 or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  select * into l from public.market_listings where id = p_listing for update;
  if not found then raise exception 'listing_not_found'; end if;
  if l.status <> 'active' then raise exception 'listing_closed'; end if;
  perform public._market_return(l, 'removed', p_reason);
  perform public._mod_log('mkt_takedown', l.seller, jsonb_build_object('id', l.id, 'c', l.code, 'n', l.name, 'p', l.price, 'reason', p_reason));
end $$;

-- Keluarkan (p_exclude = true) atau masukkan lagi penjualan ke riwayat harga.
create or replace function public.admin_market_exclude(p_listing bigint, p_exclude boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare l public.market_listings;
begin
  perform public._bug_need_admin();
  select * into l from public.market_listings where id = p_listing for update;
  if not found then raise exception 'listing_not_found'; end if;
  if l.status <> 'sold' then raise exception 'listing_not_sold'; end if;
  if l.excluded = coalesce(p_exclude, false) then return; end if;
  update public.market_listings set excluded = coalesce(p_exclude, false) where id = l.id;
  perform public._mod_log(case when p_exclude then 'mkt_exclude' else 'mkt_include' end, l.seller,
    jsonb_build_object('id', l.id, 'c', l.code, 'n', l.name, 'p', l.price, 'b', coalesce(public._username(l.buyer), l.buyer_name)));
end $$;

-- ---------------------------------------------------------------------
-- HAK AKSES
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['_market_list(uuid, jsonb, bigint, jsonb, jsonb, integer, integer, text, text)',
                           '_market_return(public.market_listings, text, text)', '_market_expire()', '_market_reset(uuid)',
                           '_market_row(public.market_listings, uuid)', '_market_on_user_deleted()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
  execute 'grant execute on function public._market_list(uuid, jsonb, bigint, jsonb, jsonb, integer, integer, text, text) to service_role';
  foreach f in array array['get_market(text, text)', 'get_my_listings()', 'get_market_prices(text)',
                           'buy_listing(bigint, bigint)', 'cancel_listing(bigint)',
                           'admin_market(text, bigint)', 'admin_market_takedown(bigint, text)', 'admin_market_exclude(bigint, boolean)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
