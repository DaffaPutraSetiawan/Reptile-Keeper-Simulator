-- =====================================================================
-- MorphLab / Reptile Keeper Simulator — skema database Supabase
-- Jalankan sekali di Supabase Dashboard → SQL Editor → New query → Run.
-- Aman dijalankan ulang (idempoten).
-- =====================================================================

-- ---------- PROFIL PEMAIN ----------
-- Username publik, nanti dipakai untuk trading antar pemain.
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  username   text not null unique
             check (username ~ '^[A-Za-z0-9_]{3,20}$'),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles: semua pemain login boleh lihat" on public.profiles;
create policy "profiles: semua pemain login boleh lihat"
  on public.profiles for select
  to authenticated
  using (true);

drop policy if exists "profiles: buat milik sendiri" on public.profiles;
create policy "profiles: buat milik sendiri"
  on public.profiles for insert
  to authenticated
  with check ((select auth.uid()) = id);

-- Username tidak bisa diganti dari browser (tidak ada policy UPDATE),
-- supaya riwayat trading nanti tetap konsisten.

-- Username unik tanpa membedakan huruf besar/kecil (Daffa = daffa).
create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username));


-- ---------- SAVE GAME ----------
-- Satu baris per pemain. Kolom rev naik setiap kali save berubah, dipakai
-- server untuk mencegah dua perubahan bersamaan saling menimpa.
create table if not exists public.saves (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  data       jsonb not null,
  game_turn  integer not null default 0,
  rev        bigint not null default 1,
  updated_at timestamptz not null default now(),
  constraint saves_data_size check (octet_length(data::text) < 2000000)
);

alter table public.saves enable row level security;

drop policy if exists "saves: baca milik sendiri" on public.saves;
create policy "saves: baca milik sendiri"
  on public.saves for select
  to authenticated
  using ((select auth.uid()) = user_id);

-- Mode online "server-authoritative": browser TIDAK boleh menulis save.
-- Semua perubahan lewat Edge Function "game" (pakai kunci server) dan fungsi
-- trading di social.sql. Browser hanya boleh membaca save miliknya sendiri.
drop policy if exists "saves: buat milik sendiri" on public.saves;
drop policy if exists "saves: ubah milik sendiri" on public.saves;
drop policy if exists "saves: hapus milik sendiri" on public.saves;
revoke insert, update, delete on public.saves from anon, authenticated;
grant select on public.saves to authenticated;

-- updated_at diisi otomatis oleh server
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists saves_touch_updated_at on public.saves;
create trigger saves_touch_updated_at
  before update on public.saves
  for each row execute function public.touch_updated_at();
