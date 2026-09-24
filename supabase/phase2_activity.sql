-- PHASE B1: MEMBER ACTIVITY SALES -> SUPABASE
-- Uses a short-lived custom member session token because members do not use Supabase Auth.
create schema if not exists private;

create table if not exists public.member_sessions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days')
);

create index if not exists member_sessions_member_id_idx
  on public.member_sessions(member_id);
create index if not exists member_sessions_expires_at_idx
  on public.member_sessions(expires_at);

alter table public.member_sessions enable row level security;
revoke all on table public.member_sessions from anon, authenticated;

create unique index if not exists sales_activities_member_date_unique
  on public.sales_activities(member_id, activity_date);

create or replace function public.member_login(p_username text,p_password text)
returns json language plpgsql security definer set search_path=''
as $$
declare
  v_profile public.profiles;
  v_token text;
  v_token_hash text;
begin
  select * into v_profile
  from public.profiles
  where lower(username)=lower(trim(p_username)) and role='member'
  limit 1;

  if not found then
    return json_build_object('success',false,'message','Username atau password salah.');
  end if;

  if v_profile.password_hash is null
     or extensions.crypt(coalesce(p_password,''),v_profile.password_hash) <> v_profile.password_hash then
    return json_build_object('success',false,'message','Username atau password salah.');
  end if;

  if coalesce(v_profile.status,'pending') <> 'approved' then
    return json_build_object(
      'success',false,
      'status',v_profile.status,
      'message',case
        when v_profile.status='pending' then 'Akun masih menunggu approval Super Admin.'
        when v_profile.status='rejected' then 'Pendaftaran ditolak.'
        else 'Akun tidak aktif.'
      end
    );
  end if;

  delete from public.member_sessions
  where member_id=v_profile.id or expires_at<now();

  v_token=encode(extensions.gen_random_bytes(32),'hex');
  v_token_hash=encode(extensions.digest(v_token,'sha256'),'hex');

  insert into public.member_sessions(member_id,token_hash,expires_at)
  values(v_profile.id,v_token_hash,now()+interval '30 days');

  return json_build_object(
    'success',true,
    'token',v_token,
    'profile',json_build_object(
      'id',v_profile.id,
      'name',v_profile.name,
      'username',v_profile.username,
      'wa',v_profile.wa,
      'role',v_profile.role,
      'status',v_profile.status,
      'day',coalesce(v_profile.day,1),
      'registered_at',v_profile.registered_at,
      'approved_at',v_profile.approved_at
    )
  );
end;
$$;

create or replace function public.member_activity_list(p_token text)
returns json language plpgsql security definer set search_path=''
as $$
declare
  v_member_id uuid;
  v_rows json;
begin
  select s.member_id into v_member_id
  from public.member_sessions s
  where s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
    and s.expires_at>now()
  limit 1;

  if v_member_id is null then
    return json_build_object('success',false,'message','Sesi member tidak valid atau sudah kedaluwarsa.');
  end if;

  select coalesce(json_agg(row_to_json(x) order by x.activity_date desc), '[]'::json)
    into v_rows
  from (
    select id,activity_date,program_day,japri,follow_up,conversation,lead,offer,closing,referral,notes
    from public.sales_activities
    where member_id=v_member_id
    order by activity_date desc
  ) x;

  return json_build_object('success',true,'rows',v_rows);
end;
$$;

create or replace function public.member_activity_upsert(
  p_token text,
  p_activity_date date,
  p_program_day integer,
  p_japri integer,
  p_follow_up integer,
  p_conversation integer,
  p_lead integer,
  p_offer integer,
  p_closing integer,
  p_referral integer,
  p_notes text
)
returns json language plpgsql security definer set search_path=''
as $$
declare
  v_member_id uuid;
  v_id bigint;
begin
  select s.member_id into v_member_id
  from public.member_sessions s
  where s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
    and s.expires_at>now()
  limit 1;

  if v_member_id is null then
    return json_build_object('success',false,'message','Sesi member tidak valid atau sudah kedaluwarsa.');
  end if;

  insert into public.sales_activities(
    member_id,activity_type,description,activity_date,program_day,
    japri,follow_up,conversation,lead,offer,closing,referral,notes
  )
  values(
    v_member_id,'daily','Aktivitas harian member',p_activity_date,p_program_day,
    greatest(0,coalesce(p_japri,0)),greatest(0,coalesce(p_follow_up,0)),
    greatest(0,coalesce(p_conversation,0)),greatest(0,coalesce(p_lead,0)),
    greatest(0,coalesce(p_offer,0)),greatest(0,coalesce(p_closing,0)),
    greatest(0,coalesce(p_referral,0)),coalesce(p_notes,'')
  )
  on conflict (member_id,activity_date) do update set
    program_day=excluded.program_day,
    japri=excluded.japri,
    follow_up=excluded.follow_up,
    conversation=excluded.conversation,
    lead=excluded.lead,
    offer=excluded.offer,
    closing=excluded.closing,
    referral=excluded.referral,
    notes=excluded.notes
  returning id into v_id;

  return json_build_object('success',true,'id',v_id);
end;
$$;

create or replace function public.member_session_logout(p_token text)
returns json language plpgsql security definer set search_path=''
as $$
begin
  delete from public.member_sessions
  where token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex');
  return json_build_object('success',true);
end;
$$;

revoke execute on function public.member_login(text,text) from public,authenticated;
grant execute on function public.member_login(text,text) to anon;

revoke execute on function public.member_activity_list(text) from public,authenticated;
grant execute on function public.member_activity_list(text) to anon;

revoke execute on function public.member_activity_upsert(text,date,integer,integer,integer,integer,integer,integer,integer,integer,text) from public,authenticated;
grant execute on function public.member_activity_upsert(text,date,integer,integer,integer,integer,integer,integer,integer,integer,text) to anon;

revoke execute on function public.member_session_logout(text) from public,authenticated;
grant execute on function public.member_session_logout(text) to anon;
