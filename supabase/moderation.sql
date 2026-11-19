-- =====================================================================
-- Morph Lab — MODERASI CHAT GLOBAL & RINGKASAN ADMIN
-- * Pemain bisa melaporkan pesan di chat global (isi pesan disalin ke laporan, karena chat
--   global hanya menyimpan 50 pesan terakhir).
-- * Admin bisa menghapus pesan, membisukan pemain di chat global (1 jam / 24 jam / 7 hari /
--   selamanya, alasan wajib), dan menutup laporan. Semua tindakan tercatat di admin_log.
-- * Otomatis: kata kasar disensor jadi ★★★ dan pesan yang sama tidak bisa dikirim > 3× dalam 5 menit.
-- * Ringkasan admin: angka pemain, chat, trade, laporan.
-- Admin = tabel public.admins (lihat bugs.sql).
-- Jalankan SETELAH schema.sql, social.sql dan bugs.sql. Aman dijalankan ulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TABEL
-- ---------------------------------------------------------------------
-- Daftar kata yang disensor. Tambah / hapus kata langsung di SQL Editor, contoh:
--   insert into public.chat_banned_words (word) values ('katabaru') on conflict do nothing;
--   delete from public.chat_banned_words where word = 'kata';
-- Huruf kecil a–z saja, minimal 3 huruf. Huruf berulang (mis. "tolooool") dan angka/simbol pengganti
-- (a→4/@, i→1/!, e→3, o→0, s→5/$) ikut tertangkap. Hanya kata utuh yang disensor ("cocok" tidak kena "cok").
create table if not exists public.chat_banned_words (
  word text primary key check (word ~ '^[a-z]{3,30}$')
);
alter table public.chat_banned_words enable row level security;
revoke all on public.chat_banned_words from anon, authenticated;

insert into public.chat_banned_words (word) values
  -- Indonesia / daerah
  ('bangsat'), ('bajingan'), ('brengsek'), ('keparat'), ('kampret'), ('goblok'), ('goblog'), ('tolol'),
  ('idiot'), ('kontol'), ('memek'), ('ngentot'), ('entot'), ('ngewe'), ('jembut'), ('pepek'), ('peler'),
  ('jancok'), ('jancuk'), ('cok'), ('pantek'), ('pukimak'), ('puki'), ('kimak'), ('lonte'), ('pelacur'),
  ('sundal'), ('perek'), ('bencong'), ('banci'), ('coli'), ('bokep'), ('tai'), ('taik'),
  -- Inggris
  ('fuck'), ('fucking'), ('fucker'), ('fucked'), ('motherfucker'), ('shit'), ('shitty'), ('bullshit'),
  ('bitch'), ('bitches'), ('bastard'), ('asshole'), ('dick'), ('dickhead'), ('cunt'), ('pussy'),
  ('slut'), ('whore'), ('retard'), ('retarded'), ('nigger'), ('nigga'), ('faggot'), ('fag')
on conflict do nothing;

-- Pemain yang dibisukan di chat global. until = null → selamanya.
create table if not exists public.chat_mutes (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  until      timestamptz,
  reason     text not null check (char_length(reason) between 3 and 300),
  by_admin   uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.chat_mutes enable row level security;
-- Pemain hanya boleh melihat status bisunya sendiri (dipakai realtime); semua perubahan lewat fungsi admin.
drop policy if exists "bisu: baca milik sendiri" on public.chat_mutes;
create policy "bisu: baca milik sendiri" on public.chat_mutes for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.chat_mutes from anon, authenticated;

-- Laporan pesan. Satu baris per pelapor; admin melihatnya dikelompokkan per pesan.
create table if not exists public.chat_reports (
  id          bigint generated always as identity primary key,
  message_id  bigint not null,                    -- tanpa FK: pesannya bisa sudah tergeser keluar dari 50 pesan terakhir
  reporter    uuid references auth.users (id) on delete set null,
  sender      uuid references auth.users (id) on delete cascade,
  sender_name text not null,
  body        text not null,                      -- salinan isi pesan saat dilaporkan
  msg_at      timestamptz not null,
  reason      text not null check (reason in ('spam', 'abusive', 'scam', 'other')),
  note        text not null default '' check (char_length(note) <= 300),
  status      text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  resolved_by uuid references auth.users (id) on delete set null,
  resolved_at timestamptz,
  created_at  timestamptz not null default now(),
  unique (message_id, reporter)
);
create index if not exists chat_reports_status_idx on public.chat_reports (status, message_id);
create index if not exists chat_reports_reporter_idx on public.chat_reports (reporter, created_at desc);
create index if not exists chat_reports_sender_idx on public.chat_reports (sender) where status = 'open';
alter table public.chat_reports enable row level security;
revoke all on public.chat_reports from anon, authenticated;

-- Catatan tindakan admin
create table if not exists public.admin_log (
  id          bigint generated always as identity primary key,
  admin_id    uuid references auth.users (id) on delete set null,
  admin_name  text not null default '',
  action      text not null check (action in ('delete_msg', 'mute', 'unmute', 'report_actioned', 'report_dismissed')),
  target_id   uuid references auth.users (id) on delete set null,
  target_name text not null default '',
  detail      jsonb not null default '{}',
  created_at  timestamptz not null default now()
);
create index if not exists admin_log_id_idx on public.admin_log (id desc);
alter table public.admin_log enable row level security;
revoke all on public.admin_log from anon, authenticated;

-- Jumlah pesan global per jam (chat global sendiri hanya menyimpan 50 pesan, jadi tidak bisa dihitung dari sana)
create table if not exists public.chat_stats (
  hour timestamptz primary key,
  n    integer not null default 0
);
alter table public.chat_stats enable row level security;
revoke all on public.chat_stats from anon, authenticated;

-- ---------------------------------------------------------------------
-- FUNGSI BANTU (internal)
-- ---------------------------------------------------------------------
-- Pola regex dari daftar kata: tiap huruf boleh berulang & diganti angka/simbol yang mirip.
create or replace function public._censor_pattern()
returns text language sql stable security definer set search_path = '' as $$
  select '(?<![[:alnum:]_])(' || string_agg(p, '|' order by char_length(word) desc, word) || ')(?![[:alnum:]_])'
    from (select w.word, string_agg(
            case ch when 'a' then '[a4@]' when 'i' then '[i1!]' when 'e' then '[e3]' when 'o' then '[o0]'
                    when 's' then '[s5$]' else ch end || '+', '' order by n) p
            from public.chat_banned_words w,
                 lateral unnest(string_to_array(w.word, null)) with ordinality as c(ch, n)
           group by w.word) x;
$$;

create or replace function public._censor(p_body text)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_pat text := public._censor_pattern();
begin
  if v_pat is null or p_body is null then return p_body; end if;
  return regexp_replace(p_body, v_pat, '★★★', 'gi');
end $$;

-- Status bisu yang masih berlaku (null kalau tidak dibisukan)
create or replace function public._active_mute(p_user uuid)
returns public.chat_mutes language sql stable security definer set search_path = '' as $$
  select * from public.chat_mutes where user_id = p_user and (until is null or until > now());
$$;

-- Dipanggil send_global_message (social.sql) tepat sebelum pesan disimpan. Mengembalikan isi pesan yang sudah disensor.
create or replace function public._chat_guard(p_user uuid, p_body text)
returns text language plpgsql security definer set search_path = '' as $$
declare v text;
begin
  if (public._active_mute(p_user)).user_id is not null then raise exception 'muted'; end if;
  v := public._censor(p_body);
  if (select count(*) from public.global_messages
       where sender = p_user and created_at > now() - interval '5 minutes' and lower(body) = lower(v)) >= 3 then
    raise exception 'duplicate_message';
  end if;
  insert into public.chat_stats (hour, n) values (date_trunc('hour', now()), 1)
  on conflict (hour) do update set n = public.chat_stats.n + 1;
  return v;
end $$;

create or replace function public._mod_log(p_action text, p_target uuid, p_detail jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.admin_log (admin_id, admin_name, action, target_id, target_name, detail)
  values (auth.uid(), coalesce(public._username(auth.uid()), ''), p_action, p_target,
          coalesce(public._username(p_target), ''), coalesce(p_detail, '{}'::jsonb));
$$;

-- ---------------------------------------------------------------------
-- PEMAIN
-- ---------------------------------------------------------------------
-- Status bisu sendiri: null, atau {until (null = selamanya), reason}
create or replace function public.get_chat_mute()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m public.chat_mutes := public._active_mute(public._me());
begin
  if m.user_id is null then return null; end if;
  return jsonb_build_object('until', m.until, 'reason', m.reason);
end $$;

-- Laporkan pesan di chat global. Maks. 10 laporan per 24 jam; satu pesan sekali per pelapor.
create or replace function public.report_global_message(p_id bigint, p_reason text, p_note text default '')
returns bigint language plpgsql security definer set search_path = '' as $$
declare me uuid := public._me(); g public.global_messages; v_id bigint;
begin
  select * into g from public.global_messages where id = p_id;
  if not found then raise exception 'msg_not_found'; end if;
  if g.sender = me then raise exception 'cannot_report_self'; end if;
  if p_reason not in ('spam', 'abusive', 'scam', 'other') then raise exception 'bad_reason'; end if;
  p_note := btrim(regexp_replace(coalesce(p_note, ''), '[\x01-\x1f\x7f]+', ' ', 'g'));
  if char_length(p_note) > 300 then raise exception 'note_too_long'; end if;
  if exists (select 1 from public.chat_reports where message_id = p_id and reporter = me) then
    raise exception 'already_reported';
  end if;
  if (select count(*) from public.chat_reports where reporter = me and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'report_limit';
  end if;
  insert into public.chat_reports (message_id, reporter, sender, sender_name, body, msg_at, reason, note)
  values (g.id, me, g.sender, g.username, g.body, g.created_at, p_reason, p_note) returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- ADMIN
-- ---------------------------------------------------------------------
-- Laporan dikelompokkan per pesan. p_open = true → antrean yang belum ditangani; false → 50 riwayat terakhir.
create or replace function public.admin_list_chat_reports(p_open boolean default true)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public._bug_need_admin();
  return coalesce((
    select jsonb_agg(x order by x.last_at desc) from (
      select r.message_id, r.status,
             (array_agg(r.sender))[1] as sender,
             coalesce(public._username((array_agg(r.sender))[1]), (array_agg(r.sender_name))[1]) as sender_name,
             (array_agg(r.body))[1] as body, min(r.msg_at) as msg_at,
             count(*) as n, min(r.created_at) as first_at, max(r.created_at) as last_at,
             jsonb_agg(jsonb_build_object('by', coalesce(public._username(r.reporter), ''), 'reason', r.reason,
                                          'note', r.note, 'at', r.created_at) order by r.id) as reports,
             exists (select 1 from public.global_messages g where g.id = r.message_id) as live,
             (public._active_mute((array_agg(r.sender))[1])).user_id is not null as muted,
             coalesce(public._username((array_agg(r.resolved_by))[1]), '') as resolved_by,
             max(r.resolved_at) as resolved_at
        from public.chat_reports r
       where (p_open and r.status = 'open') or (not p_open and r.status <> 'open')
       group by r.message_id, r.status
       order by max(r.created_at) desc
       limit 50) x), '[]'::jsonb);
end $$;

-- Tutup semua laporan terbuka untuk satu pesan: 'actioned' (ditindak) atau 'dismissed' (tidak melanggar)
create or replace function public.admin_resolve_chat_report(p_message bigint, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_sender uuid; v_body text; v_n int;
begin
  perform public._bug_need_admin();
  if p_status not in ('actioned', 'dismissed') then raise exception 'bad_status'; end if;
  update public.chat_reports set status = p_status, resolved_by = auth.uid(), resolved_at = now()
   where message_id = p_message and status = 'open';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'report_not_found'; end if;
  select sender, body into v_sender, v_body from public.chat_reports where message_id = p_message limit 1;
  perform public._mod_log('report_' || p_status, v_sender, jsonb_build_object('message_id', p_message, 'body', v_body, 'reports', v_n));
end $$;

-- Hapus pesan dari chat global (hilang realtime di layar semua pemain). Laporan terbuka untuk pesan itu ikut ditutup sebagai 'actioned'.
create or replace function public.admin_delete_global_message(p_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare g public.global_messages;
begin
  perform public._bug_need_admin();
  delete from public.global_messages where id = p_id returning * into g;
  if g.id is null then raise exception 'msg_not_found'; end if;
  update public.chat_reports set status = 'actioned', resolved_by = auth.uid(), resolved_at = now()
   where message_id = p_id and status = 'open';
  perform public._mod_log('delete_msg', g.sender, jsonb_build_object('message_id', g.id, 'body', g.body));
end $$;

-- Bisukan pemain di chat global. p_hours: 1, 24, 168 (7 hari) atau null (selamanya). Alasan wajib.
-- p_purge = true → semua pesannya yang masih ada di chat global ikut dihapus.
-- Laporan terbuka terhadap pemain ini ditutup sebagai 'actioned'.
create or replace function public.admin_mute(p_user uuid, p_hours integer, p_reason text, p_purge boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_until timestamptz; v_purged int := 0;
begin
  perform public._bug_need_admin();
  if p_user is null or not exists (select 1 from auth.users where id = p_user) then raise exception 'not_found'; end if;
  if exists (select 1 from public.admins where user_id = p_user) then raise exception 'cannot_mute_admin'; end if;
  if p_hours is not null and p_hours not in (1, 24, 168) then raise exception 'bad_duration'; end if;
  p_reason := btrim(regexp_replace(coalesce(p_reason, ''), '[\x01-\x1f\x7f]+', ' ', 'g'));
  if char_length(p_reason) < 3 or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  v_until := case when p_hours is null then null else now() + make_interval(hours => p_hours) end;
  insert into public.chat_mutes (user_id, until, reason, by_admin, created_at)
  values (p_user, v_until, p_reason, auth.uid(), now())
  on conflict (user_id) do update set until = excluded.until, reason = excluded.reason,
    by_admin = excluded.by_admin, created_at = excluded.created_at;
  if coalesce(p_purge, false) then
    delete from public.global_messages where sender = p_user;
    get diagnostics v_purged = row_count;
  end if;
  update public.chat_reports set status = 'actioned', resolved_by = auth.uid(), resolved_at = now()
   where sender = p_user and status = 'open';
  perform public._mod_log('mute', p_user, jsonb_build_object('hours', p_hours, 'reason', p_reason, 'purged', v_purged));
  return jsonb_build_object('until', v_until, 'purged', v_purged);
end $$;

create or replace function public.admin_unmute(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public._bug_need_admin();
  if (public._active_mute(p_user)).user_id is null then raise exception 'not_muted'; end if;
  delete from public.chat_mutes where user_id = p_user;
  perform public._mod_log('unmute', p_user, '{}'::jsonb);
end $$;

-- Pemain yang sedang dibisukan
create or replace function public.admin_list_mutes()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public._bug_need_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'username', coalesce(public._username(m.user_id), ''),
             'until', m.until, 'reason', m.reason, 'by', coalesce(public._username(m.by_admin), ''), 'at', m.created_at)
           order by m.created_at desc)
      from public.chat_mutes m where m.until is null or m.until > now()), '[]'::jsonb);
end $$;

-- Log tindakan admin, 30 per halaman (p_before = id terakhir yang sudah tampil)
create or replace function public.admin_get_log(p_before bigint default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public._bug_need_admin();
  return coalesce((
    select jsonb_agg(to_jsonb(l) - 'admin_id' order by l.id desc) from (
      select * from public.admin_log where p_before is null or id < p_before order by id desc limit 30) l), '[]'::jsonb);
end $$;

-- Angka ringkasan untuk tab admin. Sekalian membersihkan data lama
-- (laporan chat yang sudah ditutup > 90 hari, statistik chat > 30 hari, log admin > 1 tahun, bisu yang sudah habis).
create or replace function public.admin_summary()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform public._bug_need_admin();
  delete from public.chat_reports where status <> 'open' and resolved_at < now() - interval '90 days';
  delete from public.chat_stats where hour < now() - interval '30 days';
  delete from public.admin_log where created_at < now() - interval '365 days';
  delete from public.chat_mutes where until is not null and until < now() - interval '30 days';
  return jsonb_build_object(
    'players',    (select count(*) from auth.users),
    'new_24h',    (select count(*) from auth.users where created_at > now() - interval '24 hours'),
    'new_7d',     (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'active_24h', (select count(*) from public.saves where updated_at > now() - interval '24 hours'),
    'active_7d',  (select count(*) from public.saves where updated_at > now() - interval '7 days'),
    'msgs_24h',   (select coalesce(sum(n), 0) from public.chat_stats where hour > now() - interval '24 hours'),
    'msgs_7d',    (select coalesce(sum(n), 0) from public.chat_stats where hour > now() - interval '7 days'),
    'trades_7d',  (select count(*) from public.trades where created_at > now() - interval '7 days'),
    'trades_ok_7d', (select count(*) from public.trades where status = 'accepted' and resolved_at > now() - interval '7 days'),
    'reports_open', (select count(distinct message_id) from public.chat_reports where status = 'open'),
    'mutes',      (select count(*) from public.chat_mutes where until is null or until > now()),
    'bugs',       coalesce((select jsonb_object_agg(status, n) from
                     (select status, count(*) n from public.bug_reports group by status) b), '{}'::jsonb));
end $$;

-- ---------------------------------------------------------------------
-- HAK AKSES FUNGSI
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['_censor_pattern()', '_censor(text)', '_active_mute(uuid)', '_chat_guard(uuid, text)',
                           '_mod_log(text, uuid, jsonb)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
  foreach f in array array[
    'get_chat_mute()', 'report_global_message(bigint, text, text)',
    'admin_list_chat_reports(boolean)', 'admin_resolve_chat_report(bigint, text)', 'admin_delete_global_message(bigint)',
    'admin_mute(uuid, integer, text, boolean)', 'admin_unmute(uuid)', 'admin_list_mutes()', 'admin_get_log(bigint)',
    'admin_summary()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- REALTIME: pemain langsung tahu saat dibisukan (status bisu sendiri), dan pesan yang dihapus admin
-- hilang dari layar semua pemain (global_messages sudah ada di publikasi lewat social.sql).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_mutes') then
    alter publication supabase_realtime add table public.chat_mutes;
  end if;
end $$;
