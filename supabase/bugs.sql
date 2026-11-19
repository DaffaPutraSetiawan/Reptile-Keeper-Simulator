-- =====================================================================
-- Morph Lab — LAPORAN BUG
-- Pemain melaporkan bug (judul, deskripsi, kategori, 1–3 gambar maks. 2 MB).
-- Semua pemain yang login bisa membaca semua laporan & berkomentar.
-- Hanya admin yang bisa mengubah status, membalas, menghapus komentar, dan menghapus laporan.
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
  category       text not null check (category in ('gameplay', 'performance', 'visual', 'text', 'other')),
  images         text[] not null default '{}' check (cardinality(images) <= 3),
  info           jsonb not null default '{}',
  status         text not null default 'new' check (status in ('new', 'review', 'fixed', 'rejected', 'duplicate')),
  admin_reply    text not null default '' check (char_length(admin_reply) <= 2000),
  admin_at       timestamptz,                      -- terakhir admin mengubah status / balasan
  owner_seen_at  timestamptz not null default now(), -- terakhir pelapor membuka laporannya
  resolved_at    timestamptz,                      -- saat status jadi fixed / rejected / duplicate
  images_purged  boolean not null default false,   -- gambar sudah dihapus oleh pembersihan
  created_at     timestamptz not null default now()
);
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

-- Kirim laporan. p_images = path gambar yang sudah diunggah ke bucket bug-reports.
create or replace function public.submit_bug_report(p_title text, p_description text, p_category text,
                                                    p_images text[], p_info jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); v_id bigint; img text; v_info jsonb := coalesce(p_info, '{}'::jsonb);
begin
  p_title := btrim(coalesce(p_title, '')); p_description := btrim(coalesce(p_description, ''));
  if char_length(p_title) not between 5 and 100 then raise exception 'bug_title'; end if;
  if char_length(p_description) not between 10 and 2000 then raise exception 'bug_desc'; end if;
  if p_category is null or p_category not in ('gameplay', 'performance', 'visual', 'text', 'other') then
    raise exception 'bug_category'; end if;
  if p_images is null or cardinality(p_images) not between 1 and 3
     or (select count(distinct x) from unnest(p_images) x) <> cardinality(p_images) then
    raise exception 'bug_images'; end if;
  if (select count(*) from public.bug_reports where user_id = me and created_at > now() - interval '24 hours') >= 3 then
    raise exception 'bug_limit'; end if;
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
  -- info otomatis: dari browser (dipotong) + data dari save di server
  v_info := jsonb_strip_nulls(jsonb_build_object(
    'client', left(v_info ->> 'client', 20), 'server', left(v_info ->> 'server', 20),
    'lang', left(v_info ->> 'lang', 5), 'ua', left(v_info ->> 'ua', 300), 'screen', left(v_info ->> 'screen', 20),
    'turn', (select (s.data ->> 'turn')::int from public.saves s where s.user_id = me),
    'animals', (select jsonb_array_length(s.data -> 'snakes') from public.saves s where s.user_id = me)));
  insert into public.bug_reports (user_id, title, description, category, images, info)
  values (me, p_title, p_description, p_category, p_images, v_info) returning id into v_id;
  return v_id;
end $$;

-- Daftar laporan (semua atau milik sendiri), terbaru dulu. p_before = id terakhir untuk halaman berikutnya.
create or replace function public.list_bug_reports(p_mine boolean default false, p_status text default null,
                                                   p_category text default null, p_before bigint default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := public._me();
begin
  return coalesce((select jsonb_agg(x order by (x ->> 'id')::bigint desc) from (
    select jsonb_build_object('id', r.id, 'title', r.title, 'category', r.category, 'status', r.status,
             'created_at', r.created_at, 'user', public._bug_name(r.user_id), 'mine', r.user_id = me,
             'deleted_user', r.user_id is null, 'images', cardinality(r.images), 'replied', r.admin_reply <> '',
             'comments', (select count(*) from public.bug_comments c where c.report_id = r.id),
             'unread', r.user_id = me and public._bug_unread(r)) x
      from public.bug_reports r
     where (not coalesce(p_mine, false) or r.user_id = me)
       and (p_status is null or r.status = p_status)
       and (p_category is null or r.category = p_category)
       and (p_before is null or r.id < p_before)
     order by r.id desc limit 30) q), '[]'::jsonb);
end $$;

-- Detail laporan + komentar. Kalau pelapor yang membuka, notifikasinya dianggap sudah dibaca.
create or replace function public.get_bug_report(p_id bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); r public.bug_reports; adm boolean := public.is_admin();
begin
  select * into r from public.bug_reports where id = p_id;
  if not found then raise exception 'bug_not_found'; end if;
  if r.user_id = me then update public.bug_reports set owner_seen_at = now() where id = p_id; end if;
  return jsonb_build_object('id', r.id, 'title', r.title, 'description', r.description, 'category', r.category,
    'status', r.status, 'images', case when r.images_purged then '[]'::jsonb else to_jsonb(r.images) end,
    'images_purged', r.images_purged, 'created_at', r.created_at, 'user', public._bug_name(r.user_id),
    'deleted_user', r.user_id is null, 'mine', r.user_id = me,
    'info', case when adm or r.user_id = me then r.info else null end,
    'admin_reply', r.admin_reply, 'admin_at', r.admin_at, 'is_admin', adm,
    'comments', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'user', public._bug_name(c.user_id),
        'deleted_user', c.user_id is null, 'body', c.body, 'created_at', c.created_at, 'mine', c.user_id = me,
        'admin', exists (select 1 from public.admins a where a.user_id = c.user_id)) order by c.id)
      from public.bug_comments c where c.report_id = p_id), '[]'::jsonb));
end $$;

-- Komentar (semua pemain). Batas spam: 30 komentar per 24 jam (admin tidak dibatasi).
create or replace function public.add_bug_comment(p_id bigint, p_body text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); v_id bigint;
begin
  p_body := btrim(coalesce(p_body, ''));
  if char_length(p_body) not between 1 and 1000 then raise exception 'bug_comment'; end if;
  if not exists (select 1 from public.bug_reports where id = p_id) then raise exception 'bug_not_found'; end if;
  if not public.is_admin() and (select count(*) from public.bug_comments
       where user_id = me and created_at > now() - interval '24 hours') >= 30 then
    raise exception 'bug_comment_limit'; end if;
  insert into public.bug_comments (report_id, user_id, body) values (p_id, me, p_body) returning id into v_id;
  -- pelapor yang berkomentar di laporannya sendiri otomatis dianggap sudah membaca
  update public.bug_reports set owner_seen_at = now() where id = p_id and user_id = me;
  return v_id;
end $$;

-- Jumlah laporan milik sendiri yang punya aktivitas baru (untuk tanda notifikasi)
create or replace function public.bug_unread_count()
returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.bug_reports r where r.user_id = public._me() and public._bug_unread(r);
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

create or replace function public.admin_update_bug(p_id bigint, p_status text, p_reply text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public._bug_need_admin();
  p_reply := btrim(coalesce(p_reply, ''));
  if p_status not in ('new', 'review', 'fixed', 'rejected', 'duplicate') then raise exception 'bug_status'; end if;
  if char_length(p_reply) > 2000 then raise exception 'bug_reply'; end if;
  update public.bug_reports set status = p_status, admin_reply = p_reply, admin_at = now(),
    resolved_at = case when p_status in ('fixed', 'rejected', 'duplicate') then coalesce(resolved_at, now()) end
   where id = p_id;
  if not found then raise exception 'bug_not_found'; end if;
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
  foreach f in array array['_bug_name(uuid)', '_bug_unread(public.bug_reports)', '_bug_need_admin()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['is_admin()', 'bug_upload_ok()',
    'submit_bug_report(text, text, text, text[], jsonb)', 'list_bug_reports(boolean, text, text, bigint)',
    'get_bug_report(bigint)', 'add_bug_comment(bigint, text)', 'bug_unread_count()',
    'admin_update_bug(bigint, text, text)', 'admin_delete_bug_comment(bigint)', 'admin_delete_bug(bigint)',
    'admin_bug_cleanup()', 'admin_bug_mark_purged(bigint[])'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
