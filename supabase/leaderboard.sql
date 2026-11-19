-- =====================================================================
-- Morph Lab — PAPAN PERINGKAT GLOBAL (sepanjang masa)
-- Angka peringkat dihitung Edge Function "game" setiap kali save disimpan (kolom saves.rank),
-- jadi tidak bisa dipalsukan dari browser. Jalankan SETELAH schema.sql dan social.sql. Aman dijalankan ulang.
--
-- Kategori: wealth (uang + nilai hewan), dex (jumlah morph), top (hewan termahal, bisa per spesies),
--           hatched (bayi menetas), orders (pesanan dipenuhi), rep (reputasi breeder).
-- =====================================================================

alter table public.saves add column if not exists rank jsonb;
alter table public.saves add column if not exists dex_at timestamptz;   -- kapan jumlah Morph Dex terakhir bertambah

-- Catat waktu Morph Dex bertambah: kalau jumlahnya seri, yang lebih dulu mencapainya ada di atas.
create or replace function public._rank_dex_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' or coalesce(new.rank ->> 'dex', '') is distinct from coalesce(old.rank ->> 'dex', '') then
    new.dex_at := now();
  end if;
  return new;
end $$;
drop trigger if exists saves_rank_dex_at on public.saves;
create trigger saves_rank_dex_at before insert or update of rank on public.saves
  for each row execute function public._rank_dex_at();

-- Papan peringkat: 50 teratas + posisi pemain yang meminta.
--   p_category: wealth | dex | top | hatched | orders | rep
--   p_friends : true = hanya teman (dan diri sendiri)
--   p_species : untuk kategori top: null (semua spesies) | ball | leo | axo
create or replace function public.get_leaderboard(p_category text, p_friends boolean default false,
                                                  p_species text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := public._me(); v jsonb;
begin
  if p_category is null or p_category not in ('wealth', 'dex', 'top', 'hatched', 'orders', 'rep') then
    raise exception 'bad_category'; end if;
  if p_species is not null and p_species not in ('ball', 'leo', 'axo') then raise exception 'bad_species'; end if;
  with base as (
    select s.user_id, p.username, s.rank r, s.dex_at, (s.rank ->> 'turn')::int as turn,
      -- hewan termahal: per spesies, atau yang paling mahal dari semua spesies
      case when p_category = 'top' then
        case when p_species is not null then case when s.rank -> 'top' ? p_species
               then (s.rank -> 'top' -> p_species) || jsonb_build_object('sp', p_species) end
             else (select t.value || jsonb_build_object('sp', t.key) from jsonb_each(s.rank -> 'top') t
                    order by (t.value ->> 'v')::numeric desc limit 1) end
      end as animal
      from public.saves s join public.profiles p on p.id = s.user_id
     where s.rank is not null
       and (not coalesce(p_friends, false) or s.user_id = me or public._are_friends(me, s.user_id))
  ), scored as (
    select b.*, case p_category
        when 'wealth'  then (b.r ->> 'nw')::numeric
        when 'dex'     then (b.r ->> 'dex')::numeric
        when 'hatched' then (b.r ->> 'hatched')::numeric
        when 'orders'  then (b.r ->> 'orders')::numeric
        -- save yang belum disimpan ulang sejak v29 belum punya 'rep': reputasinya sama dengan jumlah pesanan
        when 'rep'     then coalesce(b.r ->> 'rep', b.r ->> 'orders')::numeric
        else (b.animal ->> 'v')::numeric end as score
      from base b
  ), ranked as (
    select s.*, row_number() over (order by s.score desc,
             case when p_category = 'dex' then s.dex_at end asc nulls last, s.username) as pos
      from scored s where s.score is not null
  )
  select jsonb_build_object(
    'total', (select count(*) from ranked),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('pos', pos, 'user', username, 'turn', turn, 'score', score,
              'animal', animal, 'me', user_id = me) order by pos) from ranked where pos <= 50), '[]'::jsonb),
    'me', (select jsonb_build_object('pos', pos, 'user', username, 'turn', turn, 'score', score, 'animal', animal, 'me', true)
             from ranked where user_id = me))
    into v;
  return v;
end $$;

revoke all on function public._rank_dex_at() from public, anon, authenticated;
revoke all on function public.get_leaderboard(text, boolean, text) from public, anon;
grant execute on function public.get_leaderboard(text, boolean, text) to authenticated;
