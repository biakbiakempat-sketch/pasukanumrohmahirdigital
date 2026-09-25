-- LEGACY SQL — DO NOT RUN AGAINST THE LIVE SUPABASE PROJECT.
--
-- This file belongs to the original phase-1/app_members architecture.
-- The live application uses the profiles/member_* architecture documented in
-- supabase/live_contract.md. Keep this file only as historical reference.
-- Live project: insciufudobddaqzxzil
-- Live source branch: supabase-live-v1
--
-- PASUKAN UMROH MAHIR DIGITAL
-- PHASE 1 DATABASE MIGRATION
-- Modules: DATA MEMBER, LEADS, AKTIVITAS SALES, CLOSING
-- Run this once in Supabase SQL Editor.

create extension if not exists pgcrypto;

-- 1) Central member directory.
create table if not exists public.app_members (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  username text not null unique,
  name text not null default '',
  wa text not null default '',
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  day integer not null default 0 check (day between 0 and 60),
  registered_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2) Leads.
create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.app_members(id) on delete cascade,
  lead_date date not null,
  lead_time time,
  name text not null default '',
  city text default '',
  contact text not null default '',
  source text default '',
  response text default '',
  plan text default '',
  funnel text default '',
  closing text default 'Belum Closing',
  closing_date date,
  fu1 date,
  fu1_response text,
  fu2 date,
  fu2_response text,
  fu3 date,
  fu3_response text,
  no_close text,
  cs text,
  note text,
  score integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 3) Daily sales activities.
create table if not exists public.sales_activities (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.app_members(id) on delete cascade,
  activity_date date not null,
  program_day integer not null default 0,
  japri integer not null default 0,
  follow_up integer not null default 0,
  conversation integer not null default 0,
  lead integer not null default 0,
  offer integer not null default 0,
  closing integer not null default 0,
  referral integer not null default 0,
  notes text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(member_id, activity_date)
);

-- 4) Closing / income member.
create table if not exists public.closings (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.app_members(id) on delete cascade,
  closing_name text not null default '',
  invoice integer not null default 1 check (invoice > 0),
  pax integer not null default 1 check (pax > 0),
  travel text not null default '',
  package text not null default '',
  omset numeric(18,2) not null default 0 check (omset >= 0),
  closing_date date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Indexes used by the dashboard filters/reports.
create index if not exists idx_app_members_username on public.app_members(username);
create index if not exists idx_app_members_auth_user_id on public.app_members(auth_user_id);
create index if not exists idx_leads_member_date on public.leads(member_id, lead_date desc);
create index if not exists idx_sales_activities_member_date on public.sales_activities(member_id, activity_date desc);
create index if not exists idx_closings_member_date on public.closings(member_id, closing_date desc);

-- updated_at helper.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists app_members_set_updated_at on public.app_members;
create trigger app_members_set_updated_at
before update on public.app_members
for each row execute function public.set_updated_at();

drop trigger if exists leads_set_updated_at on public.leads;
create trigger leads_set_updated_at
before update on public.leads
for each row execute function public.set_updated_at();

drop trigger if exists sales_activities_set_updated_at on public.sales_activities;
create trigger sales_activities_set_updated_at
before update on public.sales_activities
for each row execute function public.set_updated_at();

drop trigger if exists closings_set_updated_at on public.closings;
create trigger closings_set_updated_at
before update on public.closings
for each row execute function public.set_updated_at();

-- RLS.
alter table public.app_members enable row level security;
alter table public.leads enable row level security;
alter table public.sales_activities enable row level security;
alter table public.closings enable row level security;

-- Remove broad client grants, then allow authenticated clients only.
revoke all on table public.app_members from anon, authenticated;
revoke all on table public.leads from anon, authenticated;
revoke all on table public.sales_activities from anon, authenticated;
revoke all on table public.closings from anon, authenticated;

grant select, insert, update, delete on table public.app_members to authenticated;
grant select, insert, update, delete on table public.leads to authenticated;
grant select, insert, update, delete on table public.sales_activities to authenticated;
grant select, insert, update, delete on table public.closings to authenticated;

-- Drop/recreate policies so the migration is safe to rerun.
do $$
declare p text;
begin
  foreach p in array array[
    'app_members_select',
    'app_members_insert',
    'app_members_update',
    'app_members_delete',
    'leads_select',
    'leads_insert',
    'leads_update',
    'leads_delete',
    'sales_select',
    'sales_insert',
    'sales_update',
    'sales_delete',
    'closings_select',
    'closings_insert',
    'closings_update',
    'closings_delete'
  ] loop
    execute format('drop policy if exists %I on public.%I',
      p,
      case
        when p like 'app_members_%' then 'app_members'
        when p like 'leads_%' then 'leads'
        when p like 'sales_%' then 'sales_activities'
        else 'closings'
      end);
  end loop;
end $$;

-- app_members: member sees own record; Super Admin sees everything.
create policy app_members_select on public.app_members
for select to authenticated
using ((auth_user_id = auth.uid()) or public.is_super_admin());

create policy app_members_insert on public.app_members
for insert to authenticated
with check (public.is_super_admin() or auth_user_id = auth.uid());

create policy app_members_update on public.app_members
for update to authenticated
using ((auth_user_id = auth.uid()) or public.is_super_admin())
with check ((auth_user_id = auth.uid()) or public.is_super_admin());

create policy app_members_delete on public.app_members
for delete to authenticated
using (public.is_super_admin());

-- Leads: member owns rows through app_members.auth_user_id; Super Admin sees all.
create policy leads_select on public.leads
for select to authenticated
using (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = leads.member_id and m.auth_user_id = auth.uid()
  )
);

create policy leads_insert on public.leads
for insert to authenticated
with check (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = leads.member_id and m.auth_user_id = auth.uid()
  )
);

create policy leads_update on public.leads
for update to authenticated
using (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = leads.member_id and m.auth_user_id = auth.uid()
  )
)
with check (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = leads.member_id and m.auth_user_id = auth.uid()
  )
);

create policy leads_delete on public.leads
for delete to authenticated
using (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = leads.member_id and m.auth_user_id = auth.uid()
  )
);

-- Activities.
create policy sales_select on public.sales_activities
for select to authenticated
using (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = sales_activities.member_id and m.auth_user_id = auth.uid()
  )
);

create policy sales_insert on public.sales_activities
for insert to authenticated
with check (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = sales_activities.member_id and m.auth_user_id = auth.uid()
  )
);

create policy sales_update on public.sales_activities
for update to authenticated
using (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = sales_activities.member_id and m.auth_user_id = auth.uid()
  )
)
with check (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = sales_activities.member_id and m.auth_user_id = auth.uid()
  )
);

create policy sales_delete on public.sales_activities
for delete to authenticated
using (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = sales_activities.member_id and m.auth_user_id = auth.uid()
  )
);

-- Closings.
create policy closings_select on public.closings
for select to authenticated
using (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = closings.member_id and m.auth_user_id = auth.uid()
  )
);

create policy closings_insert on public.closings
for insert to authenticated
with check (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = closings.member_id and m.auth_user_id = auth.uid()
  )
);

create policy closings_update on public.closings
for update to authenticated
using (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = closings.member_id and m.auth_user_id = auth.uid()
  )
)
with check (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = closings.member_id and m.auth_user_id = auth.uid()
  )
);

create policy closings_delete on public.closings
for delete to authenticated
using (
  public.is_super_admin()
  or exists (
    select 1 from public.app_members m
    where m.id = closings.member_id and m.auth_user_id = auth.uid()
  )
);

-- Quick verification.
select table_name, rowsecurity
from pg_tables
where schemaname='public'
and table_name in ('app_members','leads','sales_activities','closings')
order by table_name;
