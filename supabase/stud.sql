-- =====================================================================
-- Morph Lab — SEWA PEJANTAN (stud service, v58)
-- * Pemilik menawarkan jantan lewat Edge Function "game" (aksi stud_list): server menghitung nilai jantan dan
--   menolak biaya di bawah 50% nilai. Jantan TETAP di save pemilik (tidak dititipkan) dan tetap bisa dipakai sendiri.
-- * Satu penawaran bisa disewa total 5 kali, tanpa batas waktu. Selesai setelah 5 sewa atau dibatalkan pemilik.
--   Penawaran otomatis batal kalau jantannya sudah tidak ada di save pemilik (dijual, di-trade, mati, akun di-reset)
--   atau sedang diiklankan.
-- * Penyewa menyewa lewat Edge Function (aksi stud_book): server membaca jantan asli dari save pemilik (_stud_peek),
--   logika game memasangkan betina penyewa dengan salinan data jantan itu, lalu _stud_book menyimpan save penyewa,
--   menambah hitungan sewa, dan mengirim uang sewa ke pemilik lewat deliveries — semuanya dalam satu transaksi.
-- * Uang sewa tidak dikembalikan kalau betina gagal ovulasi. Pemain tidak bisa menyewa jantannya sendiri.
-- Jalankan SETELAH schema.sql dan social.sql (fungsi bantu save & kiriman). Aman dijalankan ulang.
-- =====================================================================

create table if not exists public.stud_listings (
  id          bigint generated always as identity primary key,
  owner       uuid not null references auth.users (id) on delete cascade,
  sp          text not null check (sp in ('ball', 'leo', 'axo')),
  snake_id    integer not null,                      -- id jantan di save pemilik
  seed        bigint not null,                       -- seed jantan: memastikan hewannya masih sama
  code        text not null default '',
  name        text not null default '',              -- nama morph (gen) saat ditawarkan
  fee         integer not null check (fee between 1 and 100000000),
  value       integer not null default 0,            -- nilai jantan saat ditawarkan
  uses        integer not null default 0,
  max_uses    integer not null default 5 check (max_uses between 1 and 5),
  status      text not null default 'active' check (status in ('active', 'done', 'cancelled', 'gone')),
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  check (uses between 0 and max_uses)
);
create index if not exists stud_active_idx on public.stud_listings (status, sp, id desc) where status = 'active';
create index if not exists stud_owner_idx on public.stud_listings (owner, id desc);
-- satu penawaran aktif per jantan
create unique index if not exists stud_one_active on public.stud_listings (owner, seed) where status = 'active';

create table if not exists public.stud_bookings (
  id          bigint generated always as identity primary key,
  listing_id  bigint not null references public.stud_listings (id) on delete cascade,
  renter      uuid references auth.users (id) on delete set null,
  renter_name text not null default '',
  female_code text not null default '',
  fee         integer not null,
  created_at  timestamptz not null default now()
);
create index if not exists stud_bookings_listing_idx on public.stud_bookings (listing_id, id);

alter table public.stud_listings enable row level security;
alter table public.stud_bookings enable row level security;
revoke all on public.stud_listings, public.stud_bookings from anon, authenticated;

-- ---------------------------------------------------------------------
-- FUNGSI BANTU
-- ---------------------------------------------------------------------
-- Jantan penawaran ini di save pemilik sekarang (null kalau sudah tidak ada atau sedang diiklankan).
create or replace function public._stud_male(l public.stud_listings)
returns jsonb language sql stable security definer set search_path = '' as $$
  select e from public.saves s, jsonb_array_elements(coalesce(s.data -> 'snakes', '[]'::jsonb)) e
   where s.user_id = l.owner and (e ->> 'id')::int = l.snake_id and (e ->> 'seed')::bigint = l.seed
     and e ->> 'sex' = 'M' and coalesce((e ->> 'listed')::boolean, false) = false
   limit 1;
$$;

-- Tutup penawaran aktif yang jantannya sudah tidak ada / sedang diiklankan.
create or replace function public._stud_sweep(p_owner uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.stud_listings l set status = 'gone', resolved_at = now()
   where l.status = 'active' and (p_owner is null or l.owner = p_owner) and public._stud_male(l) is null;
end $$;

-- Tampilan penawaran untuk browser. Hewan diambil dari save pemilik sekarang (umur & berat ikut terbaru),
-- het tersembunyi disamarkan (_public_snake). Data leluhur (seed saja) ikut supaya peringatan kawin sedarah
-- di browser bisa dihitung.
create or replace function public._stud_row(l public.stud_listings, me uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m jsonb := public._stud_male(l);
begin
  return jsonb_build_object('id', l.id, 'owner_name', public._username(l.owner), 'mine', l.owner = me,
    'rep', (select coalesce((s.rank ->> 'rep')::int, (s.rank ->> 'orders')::int, 0) from public.saves s where s.user_id = l.owner),
    'sp', l.sp, 'code', l.code, 'name', l.name, 'fee', l.fee, 'value', l.value, 'uses', l.uses, 'max_uses', l.max_uses,
    'status', l.status, 'created_at', l.created_at, 'resolved_at', l.resolved_at,
    'snake', case when m is null then null else public._public_snake(m) ||
      jsonb_build_object('anc', m -> 'anc', 'inb', m -> 'inb', 'af', m -> 'af', 'ped', m -> 'ped', 'lastLaid', m -> 'lastLaid') end);
end $$;

-- ---------------------------------------------------------------------
-- UNTUK EDGE FUNCTION "game" (kunci server)
-- ---------------------------------------------------------------------
-- Pasang penawaran. p_data = save pemilik sesudah aksi (rev = p_old_rev + 1; jantannya tetap ada).
-- Mengembalikan id penawaran, atau null kalau save berubah di tengah jalan (Edge Function lalu mengulang aksinya).
create or replace function public._stud_list(p_user uuid, p_data jsonb, p_old_rev bigint, p_rank jsonb,
  p_snake jsonb, p_fee integer, p_value integer, p_name text, p_code text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  if public._username(p_user) is null then raise exception 'no_profile'; end if;
  if not public._valid_snake(p_snake) or p_snake ->> 'sex' <> 'M' then raise exception 'snake_invalid'; end if;
  if p_fee is null or p_fee > 100000000 then raise exception 'price_too_high'; end if;
  if p_fee < greatest(1, ceil(coalesce(p_value, 0) * 0.5)) then raise exception 'price_too_low'; end if;
  if not exists (select 1 from jsonb_array_elements(coalesce(p_data -> 'snakes', '[]'::jsonb)) e
                  where (e ->> 'id')::int = (p_snake ->> 'id')::int and (e ->> 'seed')::bigint = (p_snake ->> 'seed')::bigint) then
    raise exception 'bad_action'; end if;
  perform public._stud_sweep(p_user);
  if exists (select 1 from public.stud_listings where owner = p_user and seed = (p_snake ->> 'seed')::bigint and status = 'active') then
    raise exception 'stud_exists'; end if;
  update public.saves set data = p_data, rev = p_old_rev + 1, game_turn = coalesce((p_data ->> 'turn')::int, game_turn), rank = p_rank
   where user_id = p_user and rev = p_old_rev;
  if not found then return null; end if;
  insert into public.stud_listings (owner, sp, snake_id, seed, code, name, fee, value)
  values (p_user, coalesce(p_snake ->> 'sp', 'ball'), (p_snake ->> 'id')::int, (p_snake ->> 'seed')::bigint,
          left(coalesce(p_code, ''), 20), left(coalesce(p_name, ''), 80), p_fee, greatest(0, coalesce(p_value, 0)))
  returning id into v_id;
  return v_id;
end $$;

-- Baca penawaran + jantan asli (genotipe lengkap) untuk logika game. Hanya untuk Edge Function.
create or replace function public._stud_peek(p_user uuid, p_listing bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare l public.stud_listings; m jsonb;
begin
  select * into l from public.stud_listings where id = p_listing;
  if not found then raise exception 'stud_not_found'; end if;
  if l.owner = p_user then raise exception 'own_stud'; end if;
  if l.status <> 'active' or l.uses >= l.max_uses then raise exception 'stud_closed'; end if;
  m := public._stud_male(l);
  if m is null then raise exception 'stud_closed'; end if;   -- penawarannya ditutup oleh _stud_sweep berikutnya
  return jsonb_build_object('id', l.id, 'sp', l.sp, 'fee', l.fee, 'owner', coalesce(public._username(l.owner), ''),
    'left', l.max_uses - l.uses, 'snake', m);
end $$;

-- Simpan sewa: save penyewa (uang sudah terpotong, betina sudah dipasangkan; rev = p_old_rev + 1), hitungan sewa +1,
-- catatan sewa, dan uang sewa ke pemilik lewat kiriman. Mengembalikan true, atau null kalau save penyewa berubah
-- di tengah jalan (Edge Function lalu mengulang). Penawaran dikunci: dua penyewa bersamaan tidak bisa melewati batas 5.
create or replace function public._stud_book(p_user uuid, p_data jsonb, p_old_rev bigint, p_rank jsonb,
  p_listing bigint, p_fee integer, p_female text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare l public.stud_listings; v_me text := public._username(p_user);
begin
  if v_me is null then raise exception 'no_profile'; end if;
  select * into l from public.stud_listings where id = p_listing for update;
  if not found then raise exception 'stud_not_found'; end if;
  if l.owner = p_user then raise exception 'own_stud'; end if;
  if l.status <> 'active' or l.uses >= l.max_uses or l.fee <> p_fee then raise exception 'stud_closed'; end if;
  if public._stud_male(l) is null then raise exception 'stud_closed'; end if;
  update public.saves set data = p_data, rev = p_old_rev + 1, game_turn = coalesce((p_data ->> 'turn')::int, game_turn), rank = p_rank
   where user_id = p_user and rev = p_old_rev;
  if not found then return null; end if;
  update public.stud_listings set uses = uses + 1,
         status = case when uses + 1 >= max_uses then 'done' else status end,
         resolved_at = case when uses + 1 >= max_uses then now() else resolved_at end
   where id = l.id;
  insert into public.stud_bookings (listing_id, renter, renter_name, female_code, fee)
  values (l.id, p_user, v_me, left(coalesce(p_female, ''), 20), l.fee);
  insert into public.deliveries (user_id, snakes, money, log)
  values (l.owner, '[]'::jsonb, l.fee,
          jsonb_build_object('m', 'l_stud_paid', 'p', jsonb_build_object('c', l.code, 'n', l.name, 'u', v_me, 'p', l.fee,
            'left', l.max_uses - l.uses - 1)));
  return true;
end $$;

-- ---------------------------------------------------------------------
-- UNTUK PEMAIN
-- ---------------------------------------------------------------------
-- Penawaran aktif (maks. 300). p_sp: null = semua spesies. p_sort: new | cheap
create or replace function public.get_studs(p_sp text default null, p_sort text default 'new')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me();
begin
  if p_sp is not null and p_sp not in ('ball', 'leo', 'axo') then raise exception 'bad_species'; end if;
  if coalesce(p_sort, 'new') not in ('new', 'cheap') then raise exception 'bad_sort'; end if;
  perform public._stud_sweep();
  return coalesce((select jsonb_agg(public._stud_row(l, me) order by case when p_sort = 'cheap' then l.fee end asc, l.id desc)
    from (select * from public.stud_listings where status = 'active' and (p_sp is null or sp = p_sp)
           order by case when p_sort = 'cheap' then fee end asc, id desc limit 300) l), '[]'::jsonb);
end $$;

-- Penawaran saya: yang aktif + 30 riwayat terakhir, masing-masing dengan daftar penyewanya.
create or replace function public.get_my_studs()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me();
begin
  perform public._stud_sweep(me);
  return jsonb_build_object(
    'active', coalesce((select jsonb_agg(public._stud_row(l, me) || jsonb_build_object('bookings', public._stud_bk(l.id)) order by l.id desc)
                from public.stud_listings l where l.owner = me and l.status = 'active'), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(public._stud_row(l, me) || jsonb_build_object('bookings', public._stud_bk(l.id)) order by l.resolved_at desc)
                from (select * from public.stud_listings where owner = me and status <> 'active' order by resolved_at desc limit 30) l), '[]'::jsonb));
end $$;

create or replace function public._stud_bk(p_listing bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('u', coalesce(public._username(b.renter), b.renter_name), 'deleted_user', b.renter is null,
           'f', b.female_code, 'p', b.fee, 'at', b.created_at) order by b.id), '[]'::jsonb)
    from public.stud_bookings b where b.listing_id = p_listing;
$$;

-- Batalkan penawaran sendiri (sewa yang sudah terjadi tetap berlaku).
create or replace function public.cancel_stud(p_listing bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); l public.stud_listings;
begin
  select * into l from public.stud_listings where id = p_listing and owner = me for update;
  if not found then raise exception 'stud_not_found'; end if;
  if l.status <> 'active' then raise exception 'stud_closed'; end if;
  update public.stud_listings set status = 'cancelled', resolved_at = now() where id = l.id;
end $$;

-- ---------------------------------------------------------------------
-- HAK AKSES
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['_stud_male(public.stud_listings)', '_stud_sweep(uuid)', '_stud_row(public.stud_listings, uuid)',
                           '_stud_list(uuid, jsonb, bigint, jsonb, jsonb, integer, integer, text, text)',
                           '_stud_peek(uuid, bigint)', '_stud_book(uuid, jsonb, bigint, jsonb, bigint, integer, text)',
                           '_stud_bk(bigint)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['_stud_list(uuid, jsonb, bigint, jsonb, jsonb, integer, integer, text, text)',
                           '_stud_peek(uuid, bigint)', '_stud_book(uuid, jsonb, bigint, jsonb, bigint, integer, text)'] loop
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
  foreach f in array array['get_studs(text, text)', 'get_my_studs()', 'cancel_stud(bigint)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
