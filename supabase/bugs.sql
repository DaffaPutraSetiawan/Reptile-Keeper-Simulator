-- =====================================================================
-- Morph Lab — MASUKAN: LAPORAN BUG & SARAN
-- Satu tabel untuk dua jenis masukan (kolom kind):
--   'bug'  : judul, deskripsi, kategori, 1–3 gambar wajib (maks. 2 MB), info perangkat otomatis.
--   'idea' : saran pemain; gambar opsional (0–3). Pemain lain bisa mendukung (👍) sekali per saran.
-- Semua pemain yang login bisa membaca semua masukan & berkomentar.
-- Hanya admin yang bisa mengubah status, membalas, menghapus komentar, dan menghapus masukan.
-- Saran berstatus 'done' dengan nomor versi tampil sebagai "Saran dari ..." di catatan pembaruan game.
-- Jalankan SETELAH schema.sql dan social.sql. Aman dijalankan ulang.
--
-- Menjadikan akun sebagai admin (jalankan di SQL Editor, ganti emailnya):
--   insert into public.admins (user_id) select id from auth.users where lower(email) = 'email@contoh.com'
--   on conflict do nothing;
-- =====================================================================

create table if not exists public.admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;

-- Apakah pemain yang sedang login admin? (dipakai juga oleh policy Storage)
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from public.admins where user_id = auth.uid());
$$;

create table if not exists public.bug_reports (
  id             bigint generated always as identity primary key,
  user_id        uuid references auth.users (id) on delete set null,
  title          text not null check (char_length(title) between 5 and 100),
  description    text not null check (char_length(description) between 10 and 2000),
  kind           text not null default 'bug' check (kind in ('bug', 'idea')),
  category       text not null,                    -- daftar per jenis: lihat constraint di bawah
  version        integer check (version between 1 and 9999),   -- diperbaiki / selesai di versi berapa
  dup_of         bigint references public.bug_reports (id) on delete set null,  -- status duplicate: masukan aslinya
  images         text[] not null default '{}' check (cardinality(images) <= 3),
  info           jsonb not null default '{}',
  status         text not null default 'new',      -- daftar per jenis: lihat constraint di bawah
  admin_reply    text not null default '' check (char_length(admin_reply) <= 2000),
  admin_at       timestamptz,                      -- terakhir admin mengubah status / balasan
  owner_seen_at  timestamptz not null default now(), -- terakhir pelapor membuka laporannya
  resolved_at    timestamptz,                      -- saat status jadi fixed / rejected / duplicate
  images_purged  boolean not null default false,   -- gambar sudah dihapus oleh pembersihan
  created_at     timestamptz not null default now()
);
-- Untuk database yang dibuat sebelum ada saran (aman dijalankan ulang)
alter table public.bug_reports add column if not exists kind text not null default 'bug';
alter table public.bug_reports add column if not exists version integer;
alter table public.bug_reports add column if not exists dup_of bigint references public.bug_reports (id) on delete set null;
alter table public.bug_reports drop constraint if exists bug_reports_kind_check;
alter table public.bug_reports add constraint bug_reports_kind_check check (kind in ('bug', 'idea'));
alter table public.bug_reports drop constraint if exists bug_reports_version_check;
alter table public.bug_reports add constraint bug_reports_version_check check (version between 1 and 9999);
-- Kategori & status bug: gameplay/performance/visual/text/other, new/review/fixed/rejected/duplicate.
-- Kategori & status saran: species/gameplay/economy/visual/social/other, new/review/planned/progress/done/rejected/duplicate.
alter table public.bug_reports drop constraint if exists bug_reports_category_check;
alter table public.bug_reports add constraint bug_reports_category_check check (
  (kind = 'bug' and category in ('gameplay', 'performance', 'visual', 'text', 'other')) or
  (kind = 'idea' and category in ('species', 'gameplay', 'economy', 'visual', 'social', 'other')));
alter table public.bug_reports drop constraint if exists bug_reports_status_check;
alter table public.bug_reports add constraint bug_reports_status_check check (
  (kind = 'bug' and status in ('new', 'review', 'fixed', 'rejected', 'duplicate')) or
  (kind = 'idea' and status in ('new', 'review', 'planned', 'progress', 'done', 'rejected', 'duplicate')));
create index if not exists bug_reports_kind_idx on public.bug_reports (kind, id desc);
create index if not exists bug_reports_user_idx on public.bug_reports (user_id, created_at desc);
create index if not exists bug_reports_status_idx on public.bug_reports (status, id desc);

create table if not exists public.bug_comments (
  id         bigint generated always as identity primary key,
  report_id  bigint not null references public.bug_reports (id) on delete cascade,
  user_id    uuid references auth.users (id) on delete set null,
  body       text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists bug_comments_report_idx on public.bug_comments (report_id, id);
create index if not exists bug_comments_user_idx on public.bug_comments (user_id, created_at desc);

-- Dukungan saran: satu per pemain per saran. seen_at = terakhir pendukung membuka saran itu
-- (untuk notifikasi saat admin mengubah status).
create table if not exists public.idea_votes (
  report_id  bigint not null references public.bug_reports (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  seen_at    timestamptz not null default now(),
  primary key (report_id, user_id)
);
create index if not exists idea_votes_user_idx on public.idea_votes (user_id);
alter table public.idea_votes enable row level security;
revoke all on public.idea_votes from anon, authenticated;

alter table public.bug_reports enable row level security;
alter table public.bug_comments enable row level security;
drop policy if exists "bug: pemain login boleh baca" on public.bug_reports;
create policy "bug: pemain login boleh baca" on public.bug_reports for select to authenticated using (true);
drop policy if exists "bug komentar: pemain login boleh baca" on public.bug_comments;
create policy "bug komentar: pemain login boleh baca" on public.bug_comments for select to authenticated using (true);
-- Semua perubahan lewat fungsi di bawah (validasi & batas spam di server)
revoke insert, update, delete on public.bug_reports, public.bug_comments from anon, authenticated;

-- ---------------------------------------------------------------------
-- STORAGE: bucket privat "bug-reports". Batas ukuran & jenis file dicek oleh server Storage.
-- Gambar diunggah ke folder <id pemain>/...; semua pemain login boleh melihat; hanya admin boleh menghapus.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bug-reports', 'bug-reports', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Batas unggahan: maks. 9 gambar per 24 jam per pemain (3 laporan × 3 gambar)
create or replace function public.bug_upload_ok()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (
    select count(*) from storage.objects o
     where o.bucket_id = 'bug-reports' and coalesce(o.owner_id, o.owner::text) = auth.uid()::text
       and o.created_at > now() - interval '24 hours') < 9;
$$;

drop policy if exists "bug: login boleh lihat gambar" on storage.objects;
create policy "bug: login boleh lihat gambar" on storage.objects for select to authenticated
  using (bucket_id = 'bug-reports');
drop policy if exists "bug: unggah ke folder sendiri" on storage.objects;
create policy "bug: unggah ke folder sendiri" on storage.objects for insert to authenticated
  with check (bucket_id = 'bug-reports' and (storage.foldername(name))[1] = (select auth.uid()::text)
              and public.bug_upload_ok());
drop policy if exists "bug: admin boleh hapus gambar" on storage.objects;
create policy "bug: admin boleh hapus gambar" on storage.objects for delete to authenticated
  using (bucket_id = 'bug-reports' and public.is_admin());

-- ---------------------------------------------------------------------
-- FUNGSI
-- ---------------------------------------------------------------------
create or replace function public._bug_name(p uuid)
returns text language sql stable security definer set search_path = '' as $$
  select username from public.profiles where id = p;
$$;

-- Ada aktivitas baru (balasan/status admin atau komentar orang lain) sejak pelapor terakhir membuka?
create or replace function public._bug_unread(r public.bug_reports)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(r.admin_at > r.owner_seen_at, false)
      or exists (select 1 from public.bug_comments c where c.report_id = r.id and c.user_id is distinct from r.user_id
                 and c.created_at > r.owner_seen_at);
$$;

-- Sensor kata kasar (moderation.sql). Dilewati kalau file itu belum dijalankan.
create or replace function public._bug_censor(p text)
returns text language plpgsql stable security definer set search_path = '' as $$
begin
  if p is not null and to_regprocedure('public._censor(text)') is not null then
    execute 'select public._censor($1)' into p using p;
  end if;
  return p;
end $$;

-- Pendukung saran ini punya kabar baru (admin mengubah status/balasan sejak terakhir dibuka)?
create or replace function public._vote_unread(r public.bug_reports, p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select r.kind = 'idea' and r.admin_at is not null and exists (
    select 1 from public.idea_votes v where v.report_id = r.id and v.user_id = p_user and r.admin_at > v.seen_at);
$$;

-- Saran masih bisa didukung? (bukan milik sendiri, belum ditolak/selesai/duplikat)
create or replace function public._can_vote(r public.bug_reports, p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select r.kind = 'idea' and r.user_id is distinct from p_user and r.status not in ('rejected', 'done', 'duplicate');
$$;

-- Kirim masukan. p_kind 'bug' (1–3 gambar wajib) atau 'idea' (0–3 gambar).
-- p_images = path gambar yang sudah diunggah ke bucket bug-reports.
drop function if exists public.submit_bug_report(text, text, text, text[], jsonb);
create or replace function public.submit_bug_report(p_title text, p_description text, p_category text,
                                                    p_images text[], p_info jsonb, p_kind text default 'bug')
returns bigint language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); v_id bigint; img text; v_info jsonb := coalesce(p_info, '{}'::jsonb);
        v_kind text := coalesce(p_kind, 'bug'); v_min int;
begin
  if v_kind not in ('bug', 'idea') then raise exception 'bug_kind'; end if;
  p_images := coalesce(p_images, '{}');
  p_title := btrim(coalesce(p_title, '')); p_description := btrim(coalesce(p_description, ''));
  if char_length(p_title) not between 5 and 100 then raise exception 'bug_title'; end if;
  if char_length(p_description) not between 10 and 2000 then raise exception 'bug_desc'; end if;
  if p_category is null or (v_kind = 'bug' and p_category not in ('gameplay', 'performance', 'visual', 'text', 'other'))
     or (v_kind = 'idea' and p_category not in ('species', 'gameplay', 'economy', 'visual', 'social', 'other')) then
    raise exception 'bug_category'; end if;
  v_min := case when v_kind = 'bug' then 1 else 0 end;
  if cardinality(p_images) not between v_min and 3
     or (select count(distinct x) from unnest(p_images) x) <> cardinality(p_images) then
    raise exception 'bug_images'; end if;
  -- maks. 3 laporan bug dan 3 saran per 24 jam
  if (select count(*) from public.bug_reports where user_id = me and kind = v_kind
        and created_at > now() - interval '24 hours') >= 3 then
    raise exception '%', case when v_kind = 'bug' then 'bug_limit' else 'idea_limit' end; end if;
  -- setiap gambar harus benar-benar ada di Storage, milik pelapor, ≤ 2 MB, JPG/PNG/WebP, dan belum dipakai
  foreach img in array p_images loop
    if not exists (select 1 from storage.objects o
                    where o.bucket_id = 'bug-reports' and o.name = img
                      and coalesce(o.owner_id, o.owner::text) = me::text
                      and coalesce((o.metadata ->> 'size')::bigint, 0) between 1 and 2097152
                      and o.metadata ->> 'mimetype' in ('image/jpeg', 'image/png', 'image/webp'))
       or exists (select 1 from public.bug_reports r where img = any (r.images)) then
      raise exception 'bug_images';
    end if;
  end loop;
  -- teks publik: kata kasar disensor
  p_title := left(public._bug_censor(p_title), 100); p_description := left(public._bug_censor(p_description), 2000);
  -- info otomatis (hanya laporan bug): dari browser (dipotong) + data dari save di server
  v_info := case when v_kind = 'idea' then '{}'::jsonb else jsonb_strip_nulls(jsonb_build_object(
    'client', left(v_info ->> 'client', 20), 'server', left(v_info ->> 'server', 20),
    'lang', left(v_info ->> 'lang', 5), 'ua', left(v_info ->> 'ua', 300), 'screen', left(v_info ->> 'screen', 20),
    'turn', (select (s.data ->> 'turn')::int from public.saves s where s.user_id = me),
    'animals', (select jsonb_array_length(s.data -> 'snakes') from public.saves s where s.user_id = me))) end;
  insert into public.bug_reports (user_id, kind, title, description, category, images, info)
  values (me, v_kind, p_title, p_description, p_category, p_images, v_info) returning id into v_id;
  return v_id;
end $$;

-- Daftar masukan. p_kind null = semua jenis; p_mine = milik sendiri; p_voted = saran yang saya dukung.
-- p_sort 'new' (terbaru, halaman berikutnya lewat p_before) atau 'votes' (dukungan terbanyak, lewat p_offset).
drop function if exists public.list_bug_reports(boolean, text, text, bigint);
create or replace function public.list_bug_reports(p_mine boolean default false, p_status text default null,
                                                   p_category text default null, p_before bigint default null,
                                                   p_kind text default null, p_sort text default 'new',
                                                   p_offset integer default 0, p_voted boolean default false)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := public._me(); by_votes boolean := coalesce(p_sort, 'new') = 'votes';
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'kind', q.kind, 'title', q.title,
             'category', q.category, 'status', q.status, 'version', q.version,
             'created_at', q.created_at, 'user', public._bug_name(q.user_id), 'mine', q.user_id = me,
             'deleted_user', q.user_id is null, 'images', cardinality(q.images), 'replied', q.admin_reply <> '',
             'comments', (select count(*) from public.bug_comments c where c.report_id = q.id),
             'votes', q.votes, 'voted', q.voted, 'can_vote', public._can_vote(q.r, me),
             'unread', (q.user_id = me and public._bug_unread(q.r)) or public._vote_unread(q.r, me))
           order by case when by_votes then q.votes end desc nulls last, q.id desc) from (
    select r.*, r as r, (select count(*) from public.idea_votes v where v.report_id = r.id)::int votes,
           exists (select 1 from public.idea_votes v where v.report_id = r.id and v.user_id = me) voted
      from public.bug_reports r
     where (not coalesce(p_mine, false) or r.user_id = me)
       and (not coalesce(p_voted, false) or exists (select 1 from public.idea_votes v where v.report_id = r.id and v.user_id = me))
       and (p_kind is null or r.kind = p_kind)
       and (p_status is null or r.status = p_status)
       and (p_category is null or r.category = p_category)
       and (by_votes or p_before is null or r.id < p_before)
     order by case when by_votes then (select count(*) from public.idea_votes v where v.report_id = r.id) end desc nulls last, r.id desc
     offset case when by_votes then greatest(coalesce(p_offset, 0), 0) else 0 end limit 30) q), '[]'::jsonb);
end $$;

-- Detail masukan + komentar. Pelapor / pendukung yang membuka: notifikasinya dianggap sudah dibaca.
create or replace function public.get_bug_report(p_id bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); r public.bug_reports; adm boolean := public.is_admin(); d public.bug_reports;
begin
  select * into r from public.bug_reports where id = p_id;
  if not found then raise exception 'bug_not_found'; end if;
  if r.user_id = me then update public.bug_reports set owner_seen_at = now() where id = p_id; end if;
  update public.idea_votes set seen_at = now() where report_id = p_id and user_id = me;
  select * into d from public.bug_reports where id = r.dup_of;
  return jsonb_build_object('id', r.id, 'kind', r.kind, 'title', r.title, 'description', r.description,
    'category', r.category, 'status', r.status, 'version', r.version,
    'dup', case when d.id is null then null else jsonb_build_object('id', d.id, 'title', d.title) end,
    'images', case when r.images_purged then '[]'::jsonb else to_jsonb(r.images) end,
    'images_purged', r.images_purged, 'created_at', r.created_at, 'user', public._bug_name(r.user_id),
    'deleted_user', r.user_id is null, 'mine', r.user_id = me,
    'votes', (select count(*) from public.idea_votes v where v.report_id = r.id),
    'voted', exists (select 1 from public.idea_votes v where v.report_id = r.id and v.user_id = me),
    'can_vote', public._can_vote(r, me),
    'info', case when adm or r.user_id = me then r.info else null end,
    'admin_reply', r.admin_reply, 'admin_at', r.admin_at, 'is_admin', adm,
    'comments', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'user', public._bug_name(c.user_id),
        'deleted_user', c.user_id is null, 'body', c.body, 'created_at', c.created_at, 'mine', c.user_id = me,
        'admin', exists (select 1 from public.admins a where a.user_id = c.user_id)) order by c.id)
      from public.bug_comments c where c.report_id = p_id), '[]'::jsonb));
end $$;

-- Dukung (p_on = true) atau batalkan dukungan. Tidak bisa mendukung saran sendiri; saran yang sudah
-- ditolak / selesai / duplikat tidak bisa didukung lagi (dukungan lama tetap bisa dibatalkan).
create or replace function public.vote_idea(p_id bigint, p_on boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); r public.bug_reports;
begin
  select * into r from public.bug_reports where id = p_id;
  if not found then raise exception 'bug_not_found'; end if;
  if r.kind <> 'idea' then raise exception 'idea_only'; end if;
  if coalesce(p_on, true) then
    if r.user_id = me then raise exception 'idea_own'; end if;
    if not public._can_vote(r, me) then raise exception 'idea_closed'; end if;
    insert into public.idea_votes (report_id, user_id) values (p_id, me) on conflict do nothing;
  else
    delete from public.idea_votes where report_id = p_id and user_id = me;
  end if;
  return jsonb_build_object('votes', (select count(*) from public.idea_votes v where v.report_id = p_id),
    'voted', exists (select 1 from public.idea_votes v where v.report_id = p_id and v.user_id = me));
end $$;

-- Masukan yang mirip judulnya (dipakai saat menulis, supaya tidak dobel). Kata ≥ 4 huruf dicocokkan
-- ke judul masukan jenis yang sama; duplikat dilewati. Maks. 5, paling mirip lalu dukungan terbanyak.
create or replace function public.similar_reports(p_kind text, p_title text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := public._me(); w text[];
begin
  select array_agg(distinct x) into w from regexp_split_to_table(lower(coalesce(p_title, '')), '[^[:alnum:]]+') x
   where char_length(x) >= 4 and x not in ('yang', 'untuk', 'dengan', 'bisa', 'tidak', 'agar', 'supaya', 'lebih',
     'tambah', 'tambahkan', 'fitur', 'game', 'with', 'that', 'this', 'from', 'more', 'have', 'when', 'should', 'please',
     'feature', 'would', 'could', 'make', 'want', 'kalau', 'saat', 'jadi', 'buat', 'pada', 'juga', 'sudah', 'belum');
  if w is null then return '[]'::jsonb; end if;
  w := w[1:8];
  return coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'title', q.title, 'status', q.status,
           'version', q.version, 'votes', q.votes, 'voted', q.voted, 'mine', q.user_id = me, 'can_vote', q.can_vote)
           order by q.score desc, q.votes desc, q.id desc) from (
    select r.id, r.title, r.status, r.version, r.user_id, public._can_vote(r, me) can_vote,
           (select count(*) from unnest(w) x where lower(r.title) like '%' || x || '%')::int score,
           (select count(*) from public.idea_votes v where v.report_id = r.id)::int votes,
           exists (select 1 from public.idea_votes v where v.report_id = r.id and v.user_id = me) voted
      from public.bug_reports r
     where r.kind = coalesce(p_kind, 'bug') and r.status <> 'duplicate'
       and exists (select 1 from unnest(w) x where lower(r.title) like '%' || x || '%')
     order by score desc, votes desc, r.id desc limit 5) q), '[]'::jsonb);
end $$;

-- Saran yang sudah dikerjakan (status done + nomor versi): untuk "Saran dari ..." di catatan pembaruan.
create or replace function public.done_ideas()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('v', r.version, 'id', r.id, 'title', r.title,
           'user', public._bug_name(r.user_id), 'deleted_user', r.user_id is null) order by r.version desc, r.id), '[]'::jsonb)
    from public.bug_reports r where r.kind = 'idea' and r.status = 'done' and r.version is not null;
$$;

-- Komentar (semua pemain). Batas spam: 30 komentar per 24 jam (admin tidak dibatasi).
create or replace function public.add_bug_comment(p_id bigint, p_body text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); v_id bigint;
begin
  p_body := btrim(coalesce(p_body, ''));
  if char_length(p_body) not between 1 and 1000 then raise exception 'bug_comment'; end if;
  p_body := left(public._bug_censor(p_body), 1000);
  if not exists (select 1 from public.bug_reports where id = p_id) then raise exception 'bug_not_found'; end if;
  if not public.is_admin() and (select count(*) from public.bug_comments
       where user_id = me and created_at > now() - interval '24 hours') >= 30 then
    raise exception 'bug_comment_limit'; end if;
  insert into public.bug_comments (report_id, user_id, body) values (p_id, me, p_body) returning id into v_id;
  -- pelapor yang berkomentar di laporannya sendiri otomatis dianggap sudah membaca
  update public.bug_reports set owner_seen_at = now() where id = p_id and user_id = me;
  return v_id;
end $$;

-- Jumlah masukan dengan kabar baru: milik sendiri (aktivitas baru) + saran yang didukung (status berubah)
create or replace function public.feedback_unread()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := public._me();
begin
  return jsonb_build_object(
    'mine', (select count(*) from public.bug_reports r where r.user_id = me and public._bug_unread(r)),
    'voted', (select count(*) from public.bug_reports r join public.idea_votes v on v.report_id = r.id and v.user_id = me
               where public._vote_unread(r, me)));
end $$;

create or replace function public.bug_unread_count()
returns integer language sql stable security definer set search_path = '' as $$
  select (x ->> 'mine')::int + (x ->> 'voted')::int from (select public.feedback_unread() x) s;
$$;

-- ---------------------------------------------------------------------
-- KHUSUS ADMIN
-- ---------------------------------------------------------------------
create or replace function public._bug_need_admin()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  perform public._me();
  if not public.is_admin() then raise exception 'not_admin'; end if;
end $$;

-- p_version: diperbaiki / selesai di versi berapa (hanya status fixed / done).
-- p_dup: id masukan asli (hanya status duplicate, jenis yang sama).
drop function if exists public.admin_update_bug(bigint, text, text);
create or replace function public.admin_update_bug(p_id bigint, p_status text, p_reply text,
                                                   p_version integer default null, p_dup bigint default null)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.bug_reports;
begin
  perform public._bug_need_admin();
  select * into r from public.bug_reports where id = p_id;
  if not found then raise exception 'bug_not_found'; end if;
  p_reply := btrim(coalesce(p_reply, ''));
  if (r.kind = 'bug' and p_status not in ('new', 'review', 'fixed', 'rejected', 'duplicate'))
     or (r.kind = 'idea' and p_status not in ('new', 'review', 'planned', 'progress', 'done', 'rejected', 'duplicate'))
     or p_status is null then raise exception 'bug_status'; end if;
  if char_length(p_reply) > 2000 then raise exception 'bug_reply'; end if;
  if p_status not in ('fixed', 'done') then p_version := null; end if;
  if p_version is not null and p_version not between 1 and 9999 then raise exception 'bug_version'; end if;
  if p_status <> 'duplicate' then p_dup := null; end if;
  if p_dup is not null and (p_dup = p_id or not exists (select 1 from public.bug_reports d where d.id = p_dup and d.kind = r.kind)) then
    raise exception 'bug_dup'; end if;
  update public.bug_reports set status = p_status, admin_reply = p_reply, admin_at = now(), version = p_version, dup_of = p_dup,
    resolved_at = case when p_status in ('fixed', 'done', 'rejected', 'duplicate') then coalesce(resolved_at, now()) end
   where id = p_id;
end $$;

create or replace function public.admin_delete_bug_comment(p_comment bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public._bug_need_admin();
  delete from public.bug_comments where id = p_comment;
  if not found then raise exception 'bug_comment_not_found'; end if;
end $$;

-- Hapus laporan; mengembalikan path gambarnya supaya browser admin menghapusnya dari Storage.
create or replace function public.admin_delete_bug(p_id bigint)
returns text[] language plpgsql security definer set search_path = '' as $$
declare v text[];
begin
  perform public._bug_need_admin();
  delete from public.bug_reports where id = p_id returning images into v;
  if not found then raise exception 'bug_not_found'; end if;
  return v;
end $$;

-- Pembersihan: gambar dari laporan yang sudah selesai > 90 hari, dan gambar yatim
-- (diunggah > 1 hari lalu tapi tidak dipakai laporan mana pun). Browser admin menghapusnya dari Storage
-- lalu memanggil admin_bug_mark_purged.
create or replace function public.admin_bug_cleanup()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public._bug_need_admin();
  return jsonb_build_object(
    'ids', coalesce((select jsonb_agg(r.id) from public.bug_reports r
       where not r.images_purged and r.resolved_at < now() - interval '90 days'), '[]'::jsonb),
    'paths', coalesce((select jsonb_agg(p) from (
       select unnest(r.images) p from public.bug_reports r
        where not r.images_purged and r.resolved_at < now() - interval '90 days'
       union
       select o.name from storage.objects o
        where o.bucket_id = 'bug-reports' and o.created_at < now() - interval '1 day'
          and not exists (select 1 from public.bug_reports r where o.name = any (r.images))) q), '[]'::jsonb));
end $$;

create or replace function public.admin_bug_mark_purged(p_ids bigint[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public._bug_need_admin();
  update public.bug_reports set images_purged = true where id = any (coalesce(p_ids, '{}'));
end $$;

-- ---------------------------------------------------------------------
-- HAK AKSES
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['_bug_name(uuid)', '_bug_unread(public.bug_reports)', '_bug_need_admin()', '_bug_censor(text)',
    '_vote_unread(public.bug_reports, uuid)', '_can_vote(public.bug_reports, uuid)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['is_admin()', 'bug_upload_ok()',
    'submit_bug_report(text, text, text, text[], jsonb, text)',
    'list_bug_reports(boolean, text, text, bigint, text, text, integer, boolean)',
    'get_bug_report(bigint)', 'add_bug_comment(bigint, text)', 'bug_unread_count()', 'feedback_unread()',
    'vote_idea(bigint, boolean)', 'similar_reports(text, text)', 'done_ideas()',
    'admin_update_bug(bigint, text, text, integer, bigint)', 'admin_delete_bug_comment(bigint)', 'admin_delete_bug(bigint)',
    'admin_bug_cleanup()', 'admin_bug_mark_purged(bigint[])'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
