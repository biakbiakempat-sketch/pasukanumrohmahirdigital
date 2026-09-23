-- PHASE A: MEMBER DATABASE AUTH (NO SUPABASE AUTH FOR MEMBERS)
create extension if not exists pgcrypto;

alter table public.profiles add column if not exists password_hash text;

create unique index if not exists profiles_username_lower_unique
on public.profiles (lower(username)) where username is not null;

create or replace function public.member_register(p_name text,p_username text,p_wa text,p_password text)
returns json language plpgsql security definer set search_path=''
as $$
declare v_id uuid := gen_random_uuid(); v_username text := lower(trim(p_username));
begin
  if length(trim(coalesce(p_name,''))) < 2 or length(v_username) < 3
     or length(trim(coalesce(p_wa,''))) < 6 or length(coalesce(p_password,'')) < 8 then
    return json_build_object('success',false,'message','Data pendaftaran tidak lengkap atau password minimal 8 karakter.');
  end if;
  if exists(select 1 from public.profiles where lower(username)=v_username) then
    return json_build_object('success',false,'message','Username sudah digunakan.');
  end if;
  insert into public.profiles(id,name,username,wa,role,status,day,registered_at,password_hash)
  values(v_id,trim(p_name),v_username,trim(p_wa),'member','pending',0,now(),crypt(p_password,gen_salt('bf',12)));
  return json_build_object('success',true,'id',v_id,'username',v_username,'status','pending','message','Pendaftaran berhasil. Tunggu approval Super Admin.');
exception when unique_violation then
  return json_build_object('success',false,'message','Username sudah digunakan.');
end;
$$;

create or replace function public.member_login(p_username text,p_password text)
returns json language plpgsql security definer set search_path=''
as $$
declare v_profile public.profiles;
begin
  select * into v_profile from public.profiles
  where lower(username)=lower(trim(p_username)) and role='member' limit 1;
  if not found then return json_build_object('success',false,'message','Username atau password salah.'); end if;
  if v_profile.password_hash is null or crypt(coalesce(p_password,''),v_profile.password_hash) <> v_profile.password_hash then
    return json_build_object('success',false,'message','Username atau password salah.');
  end if;
  if coalesce(v_profile.status,'pending') <> 'approved' then
    return json_build_object('success',false,'status',v_profile.status,
      'message',case when v_profile.status='pending' then 'Akun masih menunggu approval Super Admin.'
                      when v_profile.status='rejected' then 'Pendaftaran ditolak.'
                      else 'Akun tidak aktif.' end);
  end if;
  return json_build_object('success',true,'profile',json_build_object(
    'id',v_profile.id,'name',v_profile.name,'username',v_profile.username,'wa',v_profile.wa,
    'role',v_profile.role,'status',v_profile.status,'day',coalesce(v_profile.day,1),
    'registered_at',v_profile.registered_at,'approved_at',v_profile.approved_at));
end;
$$;

create or replace function public.member_approve(p_member_id uuid)
returns json language plpgsql security definer set search_path=''
as $$
begin
  if not public.is_super_admin() then return json_build_object('success',false,'message','Akses ditolak.'); end if;
  update public.profiles set status='approved',day=case when coalesce(day,0)<1 then 1 else day end,approved_at=now()
  where id=p_member_id and role='member';
  if not found then return json_build_object('success',false,'message','Member tidak ditemukan.'); end if;
  return json_build_object('success',true,'message','Member berhasil di-approve.');
end;
$$;

create or replace function public.member_reject(p_member_id uuid)
returns json language plpgsql security definer set search_path=''
as $$
begin
  if not public.is_super_admin() then return json_build_object('success',false,'message','Akses ditolak.'); end if;
  delete from public.profiles where id=p_member_id and role='member' and status='pending';
  if not found then return json_build_object('success',false,'message','Member pending tidak ditemukan.'); end if;
  return json_build_object('success',true,'message','Pendaftaran dihapus.');
end;
$$;

create or replace function public.member_admin_update(p_member_id uuid,p_name text,p_wa text,p_password text default null)
returns json language plpgsql security definer set search_path=''
as $$
begin
  if not public.is_super_admin() then return json_build_object('success',false,'message','Akses ditolak.'); end if;
  update public.profiles set name=trim(p_name),wa=trim(p_wa),
    password_hash=case when nullif(trim(coalesce(p_password,'')),'') is null then password_hash else crypt(p_password,gen_salt('bf',12)) end
  where id=p_member_id and role='member';
  if not found then return json_build_object('success',false,'message','Member tidak ditemukan.'); end if;
  return json_build_object('success',true,'message','Data member berhasil diperbarui.');
end;
$$;

create or replace function public.member_admin_create(p_name text,p_username text,p_wa text,p_password text)
returns json language plpgsql security definer set search_path=''
as $$
declare v_id uuid := gen_random_uuid(); v_username text := lower(trim(p_username));
begin
  if not public.is_super_admin() then return json_build_object('success',false,'message','Akses ditolak.'); end if;
  if length(trim(coalesce(p_name,''))) < 2 or length(v_username) < 3 or length(trim(coalesce(p_wa,''))) < 6 or length(coalesce(p_password,'')) < 8 then
    return json_build_object('success',false,'message','Data member tidak lengkap atau password minimal 8 karakter.');
  end if;
  if exists(select 1 from public.profiles where lower(username)=v_username) then return json_build_object('success',false,'message','Username sudah digunakan.'); end if;
  insert into public.profiles(id,name,username,wa,role,status,day,registered_at,approved_at,password_hash)
  values(v_id,trim(p_name),v_username,trim(p_wa),'member','approved',1,now(),now(),crypt(p_password,gen_salt('bf',12)));
  return json_build_object('success',true,'id',v_id,'message','Member berhasil ditambahkan.');
exception when unique_violation then return json_build_object('success',false,'message','Username sudah digunakan.');
end;
$$;

create or replace function public.member_admin_delete(p_member_id uuid)
returns json language plpgsql security definer set search_path=''
as $$
begin
  if not public.is_super_admin() then return json_build_object('success',false,'message','Akses ditolak.'); end if;
  delete from public.profiles where id=p_member_id and role='member';
  if not found then return json_build_object('success',false,'message','Member tidak ditemukan.'); end if;
  return json_build_object('success',true,'message','Member berhasil dihapus.');
end;
$$;

revoke execute on function public.member_register(text,text,text,text) from public,authenticated;
grant execute on function public.member_register(text,text,text,text) to anon;
revoke execute on function public.member_login(text,text) from public,authenticated;
grant execute on function public.member_login(text,text) to anon;
revoke execute on function public.member_approve(uuid) from public,anon,authenticated;
grant execute on function public.member_approve(uuid) to authenticated;
revoke execute on function public.member_reject(uuid) from public,anon,authenticated;
grant execute on function public.member_reject(uuid) to authenticated;
revoke execute on function public.member_admin_update(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.member_admin_update(uuid,text,text,text) to authenticated;
revoke execute on function public.member_admin_create(text,text,text,text) from public,anon,authenticated;
grant execute on function public.member_admin_create(text,text,text,text) to authenticated;
revoke execute on function public.member_admin_delete(uuid) from public,anon,authenticated;
grant execute on function public.member_admin_delete(uuid) to authenticated;
