-- GFB Production: loss report escalation (Prepared -> Checked -> Verified) with email reminders
create extension if not exists pg_net;
create extension if not exists pg_cron;

alter table public.app_users add column if not exists notify_email text;
alter table public.loss_reports
  add column if not exists check_to uuid, add column if not exists check_to_name text,
  add column if not exists verify_to uuid, add column if not exists verify_to_name text,
  add column if not exists verified_by uuid, add column if not exists verified_name text,
  add column if not exists verified_at timestamptz, add column if not exists verify_note text,
  add column if not exists escalated_at timestamptz;

-- ---------- email queue ----------
create table if not exists public.notify_settings (key text primary key, value text);
insert into public.notify_settings values ('enabled','true'), ('app_url','https://gfbtammy-droid.github.io/gfb-production-management/')
on conflict (key) do nothing;
create table if not exists public.notify_outbox (
  id bigserial primary key, to_email text not null, to_name text, subject text not null, body text not null,
  kind text, ref_id bigint, created_at timestamptz not null default now(), sent_at timestamptz,
  attempts int not null default 0, last_error text, claimed_at timestamptz);
alter table public.notify_settings enable row level security;
alter table public.notify_outbox enable row level security;
drop policy if exists "notify_outbox: admin read" on public.notify_outbox;
create policy "notify_outbox: admin read" on public.notify_outbox for select using (public.app_role() = 'admin');
drop policy if exists "notify_settings: admin read" on public.notify_settings;
create policy "notify_settings: admin read" on public.notify_settings for select using (public.app_role() = 'admin');
grant select on public.notify_outbox, public.notify_settings to authenticated;

select vault.create_secret(encode(extensions.gen_random_bytes(24),'hex'), 'notify_key', 'Production email sender key')
 where not exists (select 1 from vault.secrets where name = 'notify_key');

create or replace function public.notify_esc(t text) returns text language sql immutable set search_path = public as $$
  select replace(replace(replace(replace(coalesce(t,''),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;') $$;

create or replace function public.notify_html(p_title text, p_intro text, p_rows jsonb, p_link text, p_btn text)
returns text language plpgsql immutable set search_path = public as $$
declare r jsonb; tbl text := '';
begin
  for r in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    if coalesce(r->>1,'') <> '' then
      tbl := tbl || '<tr><td style="padding:5px 12px 5px 0;color:#6b7280;vertical-align:top;white-space:nowrap">' || notify_esc(r->>0)
                 || '</td><td style="padding:5px 0;color:#111827">' || replace(notify_esc(r->>1), E'\n', '<br>') || '</td></tr>';
    end if;
  end loop;
  return '<div style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#111827;max-width:600px">'
    || '<div style="background:#1f5f4a;color:#fff;padding:14px 18px;border-radius:8px 8px 0 0;font-weight:600">GFB Production Management</div>'
    || '<div style="border:1px solid #e5e7eb;border-top:0;padding:18px;border-radius:0 0 8px 8px">'
    || '<h2 style="margin:0 0 8px;font-size:18px">' || notify_esc(p_title) || '</h2>'
    || '<p style="margin:0 0 14px;color:#374151">' || p_intro || '</p>'
    || case when tbl <> '' then '<table style="border-collapse:collapse;margin-bottom:16px">' || tbl || '</table>' else '' end
    || case when coalesce(p_link,'') <> '' then '<a href="' || notify_esc(p_link) || '" style="display:inline-block;background:#1f5f4a;color:#fff;text-decoration:none;padding:10px 18px;border-radius:6px;font-weight:600">' || notify_esc(p_btn) || '</a>' else '' end
    || '<p style="margin:18px 0 0;font-size:12px;color:#9ca3af">Automatic message from GFB Production Management. Please do not reply to this email.</p>'
    || '</div></div>';
end $$;

create or replace function public.notify_get_key() returns text language sql security definer set search_path = public as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'notify_key' $$;

create or replace function public.notify_kick() returns void language plpgsql security definer set search_path = public as $$
declare k text;
begin
  k := public.notify_get_key();
  if k is null then return; end if;
  perform net.http_post(url := 'https://fwxvuykpovgvufahqtau.supabase.co/functions/v1/notify-send',
                        headers := jsonb_build_object('Content-Type','application/json','x-notify-key',k),
                        body := '{}'::jsonb);
exception when others then null;
end $$;

create or replace function public.notify_enqueue(p_to uuid, p_subject text, p_body text, p_kind text, p_ref bigint)
returns boolean language plpgsql security definer set search_path = public as $$
declare u app_users;
begin
  if coalesce((select value from notify_settings where key='enabled'),'true') <> 'true' then return false; end if;
  select * into u from app_users where user_id = p_to and active;
  if u.user_id is null or coalesce(trim(u.notify_email),'') = '' then return false; end if;
  insert into notify_outbox(to_email, to_name, subject, body, kind, ref_id)
  values (trim(u.notify_email), coalesce(nullif(u.full_name,''), u.username), p_subject, p_body, p_kind, p_ref);
  return true;
end $$;

create or replace function public.notify_claim(p_n int) returns setof public.notify_outbox language sql security definer set search_path = public as $$
  update notify_outbox set claimed_at = now(), attempts = attempts + 1
   where id in (select id from notify_outbox where sent_at is null and attempts < 5
                  and (claimed_at is null or claimed_at < now() - interval '10 minutes')
                order by id limit p_n for update skip locked)
  returning * $$;
create or replace function public.notify_done(p_id bigint, p_ok boolean, p_err text) returns void language sql security definer set search_path = public as $$
  update notify_outbox set sent_at = case when p_ok then now() end, last_error = case when p_ok then null else left(p_err, 500) end,
    claimed_at = case when p_ok then claimed_at end where id = p_id $$;
create or replace function public.notify_status(p_text text) returns void language sql security definer set search_path = public as $$
  insert into notify_settings values ('last_status', left(p_text, 300)) on conflict (key) do update set value = excluded.value $$;

create or replace function public.notify_test() returns jsonb language plpgsql security definer set search_path = public as $$
declare ok boolean;
begin
  if public.app_role() <> 'admin' then raise exception 'Hanya admin. / Admin only.'; end if;
  ok := notify_enqueue(auth.uid(), 'Test email from GFB Production Management',
    notify_html('Email reminders are working', 'If you can read this, the production app can send emails from Microsoft 365.', null,
      (select value from notify_settings where key='app_url'), 'Open the app'), 'test', null);
  if not ok then raise exception 'Isi e-mel anda di Pengguna dahulu. / Add your email under Users first.'; end if;
  perform notify_kick();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.notify_set_enabled(p_on boolean) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if public.app_role() <> 'admin' then raise exception 'Hanya admin. / Admin only.'; end if;
  insert into notify_settings values ('enabled', case when p_on then 'true' else 'false' end)
  on conflict (key) do update set value = excluded.value;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- loss report rules: Prepared -> Checked -> Verified ----------
create or replace function public.loss_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare r text := public.app_role(); me uuid := auth.uid(); uname text; changed text[]; adm boolean;
        checking boolean := false; nm text;
begin
  if me is null then return new; end if;
  if r is null then raise exception 'Tiada kebenaran. / Not permitted.'; end if;
  adm := r = 'admin';
  select full_name into uname from public.app_users where user_id = me;

  if tg_op = 'INSERT' then
    if not public.has_perm('loss_report') then raise exception 'Peranan anda tidak dibenarkan lapor kerugian. / Your role is not allowed to report losses.'; end if;
    new.report_no := 'LOSS-' || lpad(nextval('public.loss_no_seq')::text, 4, '0');
    new.reported_by := me; new.reporter_name := uname;
    new.status := 'OPEN'; new.disposition := null; new.disposition_by := null; new.disposition_name := null; new.disposition_at := null;
    new.verify_to := null; new.verify_to_name := null; new.verified_by := null; new.verified_name := null; new.verified_at := null; new.verify_note := null;
    new.check_to_name := null; new.escalated_at := null;
    if new.check_to is not null then
      select full_name into nm from public.app_users where user_id = new.check_to and active;
      if nm is null then raise exception 'Pilih pengguna aktif. / Choose an active user.'; end if;
      new.check_to_name := nm; new.escalated_at := now();
    end if;
    new.created_at := now(); new.updated_at := now();
    return new;
  end if;

  new.report_no := old.report_no; new.reported_by := old.reported_by; new.reporter_name := old.reporter_name; new.created_at := old.created_at;
  new.updated_at := now();
  new.check_to_name := old.check_to_name; new.verify_to_name := old.verify_to_name; new.escalated_at := old.escalated_at;
  new.disposition_by := old.disposition_by; new.disposition_name := old.disposition_name; new.disposition_at := old.disposition_at;
  new.verified_by := old.verified_by; new.verified_name := old.verified_name; new.verified_at := old.verified_at;
  select coalesce(array_agg(n.key), '{}') into changed from jsonb_each(to_jsonb(new)) n
   where n.key not in ('updated_at') and n.value is distinct from (to_jsonb(old) -> n.key);
  if cardinality(changed) = 0 then return new; end if;

  -- 1. change who checks (reporter, current checker, sign-off roles or admin, while still open)
  if 'check_to' = any(changed) then
    if old.status <> 'OPEN' and not adm then raise exception 'Laporan sudah disemak. / Report is already checked.'; end if;
    if not (adm or old.reported_by = me or old.check_to = me or public.has_perm('loss_signoff')) then
      raise exception 'Anda tidak boleh tukar penyemak. / You cannot change the checker.'; end if;
    if new.check_to is not null then
      select full_name into nm from public.app_users where user_id = new.check_to and active;
      if nm is null then raise exception 'Pilih pengguna aktif. / Choose an active user.'; end if;
      new.check_to_name := nm; new.escalated_at := now();
    else new.check_to_name := null; end if;
  end if;

  -- 2. check = disposition sign-off (OPEN -> CHECKED)
  if changed && array['disposition','corrective_action'] or (new.status is distinct from old.status and old.status = 'OPEN') then
    if not (adm or (old.check_to is not null and old.check_to = me) or (old.check_to is null and public.has_perm('loss_signoff'))) then
      raise exception 'Hanya penyemak yang dipilih boleh semak laporan ini. / Only the chosen checker can check this report.'; end if;
    if old.status = 'CLOSED' and not adm then raise exception 'Laporan sudah ditutup. / Report is closed.'; end if;
    if new.status in ('CHECKED','CLOSED') and new.disposition is null then
      raise exception 'Pilih keputusan bahan dahulu. / Choose a disposition first.'; end if;
    if new.status = 'CLOSED' and old.status = 'OPEN' and not adm then
      raise exception 'Laporan perlu disahkan sebelum tutup. / The report must be verified before it is closed.'; end if;
    if new.disposition is distinct from old.disposition or new.corrective_action is distinct from old.corrective_action or (old.status = 'OPEN' and new.status <> 'OPEN') then
      new.disposition_by := me; new.disposition_name := uname; new.disposition_at := now();
    end if;
    checking := true;
  end if;

  -- 3. choose the verifier (the checker, the reporter, sign-off roles or admin, before it is closed)
  if 'verify_to' = any(changed) then
    if old.status = 'CLOSED' and not adm then raise exception 'Laporan sudah ditutup. / Report is closed.'; end if;
    if not (adm or checking or old.disposition_by = me or old.check_to = me or old.reported_by = me or public.has_perm('loss_signoff')) then
      raise exception 'Anda tidak boleh pilih pengesah. / You cannot choose the verifier.'; end if;
    if new.verify_to is not null then
      select full_name into nm from public.app_users where user_id = new.verify_to and active;
      if nm is null then raise exception 'Pilih pengguna aktif. / Choose an active user.'; end if;
      new.verify_to_name := nm; new.escalated_at := now();
    else new.verify_to_name := null; end if;
  end if;

  -- 4. verify (CHECKED -> CLOSED) or send back (CHECKED -> OPEN)
  if old.status = 'CHECKED' and new.status is distinct from old.status then
    if not (adm or (old.verify_to is not null and old.verify_to = me) or (old.verify_to is null and public.has_perm('loss_signoff') and old.disposition_by is distinct from me)) then
      raise exception 'Hanya pengesah yang dipilih boleh sahkan laporan ini. / Only the chosen verifier can verify this report.'; end if;
    if new.status = 'CLOSED' then
      new.verified_by := me; new.verified_name := uname; new.verified_at := now();
    elsif new.status = 'OPEN' then
      new.disposition_by := null; new.disposition_name := null; new.disposition_at := null; new.escalated_at := now();
    else raise exception 'Status tidak sah. / Invalid status.'; end if;
  elsif old.status = 'CLOSED' and new.status is distinct from old.status then
    if not adm then raise exception 'Hanya admin boleh buka semula. / Only admin can reopen.'; end if;
    new.verified_by := null; new.verified_name := null; new.verified_at := null;
  elsif old.status = 'OPEN' and new.status = 'CLOSED' and adm then
    new.verified_by := me; new.verified_name := uname; new.verified_at := now();
  end if;
  if new.status not in ('OPEN','CHECKED','CLOSED') then raise exception 'Status tidak sah. / Invalid status.'; end if;
  if 'verify_note' = any(changed) and not (adm or old.verify_to = me) then new.verify_note := old.verify_note; end if;

  -- 5. editing the report itself
  if changed && array['occurred_at','job_id','batch_no','stage','loss_type','material','qty_kg','uom','description','immediate_action','photo_paths','item_code','batch_qty','completed_qty','trans_no','location','reason','cmms_ref'] then
    if old.status = 'CLOSED' and not adm then raise exception 'Laporan sudah ditutup. / Report is closed.'; end if;
    if not (adm or public.has_perm('loss_signoff') or old.check_to = me or (old.reported_by = me and public.has_perm('loss_report'))) then
      raise exception 'Hanya pelapor boleh ubah laporan ini. / Only the reporter can edit this report.'; end if;
  end if;
  return new;
end $$;

-- ---------- emails when a report is escalated ----------
create or replace function public.loss_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); link text; rows jsonb; j record; sent boolean := false;
begin
  select job_no, product into j from public.job_orders where id = new.job_id;
  link := coalesce((select value from notify_settings where key='app_url'),'') || '#loss-' || new.id;
  rows := jsonb_build_array(
    jsonb_build_array('Report', new.report_no), jsonb_build_array('Prepared by', new.reporter_name),
    jsonb_build_array('Problem', initcap(replace(coalesce(new.loss_type,''),'_',' '))), jsonb_build_array('Description', new.description),
    jsonb_build_array('Job', case when j.job_no is not null then j.job_no || ' · ' || j.product end),
    jsonb_build_array('Batch no', new.batch_no), jsonb_build_array('Item', new.material),
    jsonb_build_array('Wastage qty', trim(to_char(new.qty_kg, 'FM999,999,990.###')) || ' ' || coalesce(new.uom,'KG')),
    jsonb_build_array('Reason', new.reason), jsonb_build_array('Action', new.immediate_action),
    jsonb_build_array('Checked by', new.disposition_name), jsonb_build_array('Disposition', initcap(replace(coalesce(new.disposition,''),'_',' '))),
    jsonb_build_array('Note from verifier', new.verify_note));

  if new.status = 'OPEN' and new.check_to is not null and new.check_to is distinct from me
     and (tg_op = 'INSERT' or new.check_to is distinct from old.check_to or old.status = 'CHECKED') then
    sent := notify_enqueue(new.check_to, new.report_no || ' wastage report: please check',
      notify_html(new.report_no || ' needs your check',
        case when tg_op = 'UPDATE' and old.status = 'CHECKED' then 'The verifier sent this wastage report back. Please check it again and sign off.'
             else notify_esc(new.reporter_name) || ' has escalated this wastage report to you. Please check it and sign off the disposition.' end,
        rows, link, 'Open and check'), 'loss_check', new.id) or sent;
  end if;
  if new.status = 'CHECKED' and new.verify_to is not null and new.verify_to is distinct from me
     and (tg_op = 'INSERT' or new.verify_to is distinct from old.verify_to or old.status is distinct from 'CHECKED') then
    sent := notify_enqueue(new.verify_to, new.report_no || ' wastage report: please verify',
      notify_html(new.report_no || ' needs your verification', 'This wastage report has been checked by ' || notify_esc(new.disposition_name) || '. Please verify it to close the report.',
        rows, link, 'Open and verify'), 'loss_verify', new.id) or sent;
  end if;
  if tg_op = 'UPDATE' and new.status = 'CLOSED' and old.status is distinct from 'CLOSED' and new.reported_by is distinct from me then
    sent := notify_enqueue(new.reported_by, new.report_no || ' wastage report verified',
      notify_html(new.report_no || ' is verified and closed', 'Verified by ' || notify_esc(new.verified_name) || '.', rows, link, 'Open the report'),
      'loss_closed', new.id) or sent;
  end if;
  if sent then perform notify_kick(); end if;
  return new;
end $$;
drop trigger if exists loss_notify_trg on public.loss_reports;
create trigger loss_notify_trg after insert or update on public.loss_reports for each row execute function public.loss_notify();

-- working days (Mon-Fri, Malaysia time) since a moment
create or replace function public.notify_wdays(p_from timestamptz) returns int language sql stable set search_path = public as $$
  select count(*)::int from generate_series((p_from at time zone 'Asia/Kuala_Lumpur')::date + 1,
                                            (now() at time zone 'Asia/Kuala_Lumpur')::date, interval '1 day') g
  where extract(isodow from g) < 6 $$;

-- 8:00 am working days: one reminder email per person listing reports waiting for them
create or replace function public.notify_daily() returns int language plpgsql security definer set search_path = public as $$
declare r record; html text; n int := 0; base text;
begin
  if coalesce((select value from notify_settings where key='enabled'),'true') <> 'true' then return 0; end if;
  base := coalesce((select value from notify_settings where key='app_url'),'');
  for r in
    with w as (
      select check_to uid, l.*, 'Check' step from loss_reports l where status = 'OPEN' and check_to is not null
      union all
      select verify_to uid, l.*, 'Verify' step from loss_reports l where status = 'CHECKED' and verify_to is not null)
    select uid, count(*) c,
      string_agg('<tr><td style="padding:7px 10px;border-bottom:1px solid #e5e7eb;white-space:nowrap"><a href="' || notify_esc(base || '#loss-' || id) || '" style="color:#1f5f4a;font-weight:600">' || notify_esc(report_no) || '</a></td>'
        || '<td style="padding:7px 10px;border-bottom:1px solid #e5e7eb">' || step || '</td>'
        || '<td style="padding:7px 10px;border-bottom:1px solid #e5e7eb">' || notify_esc(left(coalesce(description,''),80)) || '</td>'
        || '<td style="padding:7px 10px;border-bottom:1px solid #e5e7eb;white-space:nowrap">' || to_char(coalesce(escalated_at, created_at) at time zone 'Asia/Kuala_Lumpur','DD/MM/YYYY') || '</td></tr>', '' order by id) rows
    from w where notify_wdays(coalesce(escalated_at, created_at)) >= 1 group by uid
  loop
    html := notify_html('Wastage reports waiting for you', 'These wastage reports are still waiting for your action. Please follow up today.'
      || '<br><br><table style="border-collapse:collapse;font-size:13px;width:100%"><tr style="background:#f3f4f6;text-align:left"><th style="padding:7px 10px">Report</th><th style="padding:7px 10px">Your step</th><th style="padding:7px 10px">Description</th><th style="padding:7px 10px">Since</th></tr>'
      || r.rows || '</table>', null, base, 'Open the app');
    if notify_enqueue(r.uid, 'Reminder: ' || r.c || ' wastage report(s) waiting for you', html, 'daily', null) then n := n + 1; end if;
  end loop;
  if n > 0 then perform notify_kick(); end if;
  return n;
end $$;

-- access: internal functions are not callable by app users
revoke execute on function public.notify_claim(int), public.notify_done(bigint,boolean,text), public.notify_status(text), public.notify_get_key(),
  public.notify_kick(), public.notify_enqueue(uuid,text,text,text,bigint), public.notify_daily(), public.loss_notify(), public.notify_wdays(timestamptz)
  from public, anon, authenticated;
grant execute on function public.notify_claim(int), public.notify_done(bigint,boolean,text), public.notify_status(text), public.notify_get_key() to service_role;
revoke execute on function public.notify_test(), public.notify_set_enabled(boolean) from public, anon;
grant execute on function public.notify_test(), public.notify_set_enabled(boolean) to authenticated;

select cron.unschedule(jobname) from cron.job where jobname in ('prod-notify-daily','prod-notify-retry');
select cron.schedule('prod-notify-daily', '0 0 * * 1-5', 'select public.notify_daily()');
select cron.schedule('prod-notify-retry', '*/10 * * * *', 'select public.notify_kick()');

-- applied separately the same day
alter table public.loss_reports drop constraint if exists loss_reports_loss_type_check;
alter table public.loss_reports add constraint loss_reports_loss_type_check check (loss_type = any (array['WASTAGE','EXPIRED','SPILLAGE','TORN_BAG','DAMAGED_PACK','MACHINE_FAULT','CONTAMINATION','RESIDUE','OTHER']));
alter table public.loss_reports drop constraint if exists loss_reports_status_check;
alter table public.loss_reports add constraint loss_reports_status_check check (status = any (array['OPEN','CHECKED','CLOSED']));
alter function public.plan_total(jsonb, numeric, int) set search_path = public;
-- Edge Function notify-send (same code as the CMMS one) needs secrets MS_TENANT_ID, MS_CLIENT_ID, MS_CLIENT_SECRET, MAIL_FROM
