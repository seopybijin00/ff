-- 자기 관리 연습실: 손톱 관리 — Supabase 스키마
-- Supabase 대시보드 > SQL Editor 에 통째로 붙여 넣고 Run 하세요. (여러 번 실행해도 안전합니다)
--
-- 보안 방식
--  · 학생(로그인 없이 태블릿 사용): 표에 직접 접근할 수 없고, 아래 함수(RPC)로만 자기 이름 카드·4자리 숫자를 확인한 뒤 진도를 읽고 씁니다.
--    4자리 숫자는 서버에 암호화(bcrypt)해서 저장하고, 5번 틀리면 1분 동안 잠깁니다.
--  · 선생님: Supabase 로그인(이메일+비밀번호). teachers 표에 등록된 계정만 모든 데이터와 인증 사진을 볼 수 있습니다.
--  · 인증 사진은 선생님 계정만 읽을 수 있습니다. 학생은 올리기만 할 수 있습니다.

create extension if not exists pgcrypto with schema extensions;

-- ───────── 표 ─────────
create table if not exists public.settings (
  id int primary key default 1 check (id = 1),
  def_auto boolean not null default false          -- 손님·새 학생의 "자동 읽기" 기본값
);
insert into public.settings (id) values (1) on conflict do nothing;

create table if not exists public.teachers (
  user_id uuid primary key references auth.users (id) on delete cascade
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 10),
  avatar text not null default '🙂',
  pin_hash text not null,                           -- bcrypt 값(원래 숫자는 저장하지 않음)
  unl jsonb not null default '{"find":false,"master":false,"expert":false}',
  prog jsonb not null default '{"master":0,"expert":0}',
  auto_read boolean,                                -- null이면 settings.def_auto를 따름
  last_at timestamptz,
  help jsonb,                                       -- {n: 누른 횟수, t: 시각(ms), at: 어느 활동·단계}
  fail_count int not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  unique (name)
);

create table if not exists public.cert_photos (
  id text primary key,
  student_id uuid not null references public.students (id) on delete cascade,
  taken_at timestamptz not null default now(),
  img text not null check (img like 'data:image/jpeg;base64,%' and char_length(img) < 300000)
);
create index if not exists cert_photos_student_idx on public.cert_photos (student_id);

-- ───────── 보안(RLS): 기본은 모두 막고, 선생님만 연다 ─────────
alter table public.settings   enable row level security;
alter table public.teachers   enable row level security;
alter table public.students   enable row level security;
alter table public.cert_photos enable row level security;

create or replace function public.is_teacher() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.teachers t where t.user_id = auth.uid());
$$;

drop policy if exists teacher_all_students on public.students;
create policy teacher_all_students on public.students for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());

drop policy if exists teacher_all_photos on public.cert_photos;
create policy teacher_all_photos on public.cert_photos for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());

drop policy if exists teacher_all_settings on public.settings;
create policy teacher_all_settings on public.settings for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());

drop policy if exists teacher_read_teachers on public.teachers;
create policy teacher_read_teachers on public.teachers for select to authenticated
  using (user_id = auth.uid());

-- ───────── 학생용 함수(로그인 없이 호출) ─────────
-- 이름 카드 목록: 이름·그림·도움 표시 여부만 돌려준다(진도·비밀번호는 안 줌)
create or replace function public.get_roster() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'def_auto', (select def_auto from public.settings where id = 1),
    'students', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name, 'avatar', s.avatar, 'help', s.help is not null) order by s.created_at)
      from public.students s), '[]'::jsonb));
$$;

-- 내부용: 숫자 4자리 확인(잠금 포함). 외부에서 직접 부를 수 없다.
create or replace function public._check_pin(p_id uuid, p_pin text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students%rowtype;
begin
  select * into s from public.students where id = p_id for update;
  if not found then return 'no'; end if;
  if s.locked_until is not null and s.locked_until > now() then return 'locked'; end if;
  if p_pin ~ '^[0-9]{4}$' and s.pin_hash = crypt(p_pin, s.pin_hash) then
    if s.fail_count > 0 or s.locked_until is not null then
      update public.students set fail_count = 0, locked_until = null where id = p_id;
    end if;
    return 'ok';
  end if;
  if s.fail_count + 1 >= 5 then
    update public.students set fail_count = 0, locked_until = now() + interval '1 minute' where id = p_id;
    return 'locked';
  end if;
  update public.students set fail_count = s.fail_count + 1 where id = p_id;
  return 'no';
end $$;

create or replace function public.student_login(p_id uuid, p_pin text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r text; s public.students%rowtype;
begin
  r := public._check_pin(p_id, p_pin);
  if r <> 'ok' then return jsonb_build_object('ok', false, 'locked', r = 'locked'); end if;
  update public.students set last_at = now() where id = p_id returning * into s;
  return jsonb_build_object('ok', true, 'student', jsonb_build_object(
    'id', s.id, 'name', s.name, 'avatar', s.avatar, 'unl', s.unl, 'prog', s.prog,
    'auto_read', s.auto_read, 'last_at', s.last_at, 'help', s.help));
end $$;

create or replace function public.student_save(p_id uuid, p_pin text, p_unl jsonb, p_prog jsonb, p_auto boolean)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if public._check_pin(p_id, p_pin) <> 'ok' then return false; end if;
  update public.students set
    unl = jsonb_build_object(
      'find',   coalesce((p_unl->>'find')::boolean, false),
      'master', coalesce((p_unl->>'master')::boolean, false),
      'expert', coalesce((p_unl->>'expert')::boolean, false)),
    prog = jsonb_build_object(
      'master', least(5, greatest(0, coalesce((p_prog->>'master')::int, 0))),
      'expert', least(9, greatest(0, coalesce((p_prog->>'expert')::int, 0)))),
    auto_read = p_auto,
    last_at = now()
  where id = p_id;
  return true;
end $$;

create or replace function public.student_help(p_id uuid, p_pin text, p_at text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if public._check_pin(p_id, p_pin) <> 'ok' then return false; end if;
  update public.students set help = jsonb_build_object(
      'n', coalesce((help->>'n')::int, 0) + 1,
      't', (extract(epoch from now()) * 1000)::bigint,
      'at', left(coalesce(p_at, ''), 40))
  where id = p_id;
  return true;
end $$;

create or replace function public.student_add_photo(p_id uuid, p_pin text, p_photo_id text, p_img text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if public._check_pin(p_id, p_pin) <> 'ok' then return false; end if;
  insert into public.cert_photos (id, student_id, img) values (left(p_photo_id, 80), p_id, p_img)
  on conflict (id) do update set img = excluded.img, taken_at = now()
  where public.cert_photos.student_id = p_id;
  return true;
end $$;

-- ───────── 선생님용 함수(선생님 로그인 필요) ─────────
create or replace function public.teacher_add_student(p_name text, p_pin text, p_avatar text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare new_id uuid;
begin
  if not public.is_teacher() then raise exception 'teacher only'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'pin must be 4 digits'; end if;
  insert into public.students (name, avatar, pin_hash) values (btrim(p_name), coalesce(p_avatar, '🙂'), crypt(p_pin, gen_salt('bf')))
  returning id into new_id;
  return new_id;
end $$;

create or replace function public.teacher_set_student_pin(p_id uuid, p_pin text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_teacher() then raise exception 'teacher only'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'pin must be 4 digits'; end if;
  update public.students set pin_hash = crypt(p_pin, gen_salt('bf')), fail_count = 0, locked_until = null where id = p_id;
  return found;
end $$;

-- ───────── 함수 실행 권한 ─────────
revoke all on function public._check_pin(uuid, text) from public, anon, authenticated;
revoke all on function public.get_roster() from public;
revoke all on function public.student_login(uuid, text) from public;
revoke all on function public.student_save(uuid, text, jsonb, jsonb, boolean) from public;
revoke all on function public.student_help(uuid, text, text) from public;
revoke all on function public.student_add_photo(uuid, text, text, text) from public;
revoke all on function public.teacher_add_student(text, text, text) from public, anon;
revoke all on function public.teacher_set_student_pin(uuid, text) from public, anon;
revoke all on function public.is_teacher() from public;
grant execute on function public.get_roster() to anon, authenticated;
grant execute on function public.student_login(uuid, text) to anon, authenticated;
grant execute on function public.student_save(uuid, text, jsonb, jsonb, boolean) to anon, authenticated;
grant execute on function public.student_help(uuid, text, text) to anon, authenticated;
grant execute on function public.student_add_photo(uuid, text, text, text) to anon, authenticated;
grant execute on function public.teacher_add_student(text, text, text) to authenticated;
grant execute on function public.teacher_set_student_pin(uuid, text) to authenticated;
grant execute on function public.is_teacher() to authenticated;

-- 학생·사진·설정 표는 선생님만 직접 다룸(위 정책). 로그인 안 한 사용자는 표를 직접 읽거나 쓸 수 없음
revoke all on public.students, public.cert_photos, public.settings, public.teachers from anon;

-- ───────── 실시간 알림(선생님 화면의 도움 불빛) ─────────
do $$ begin
  alter publication supabase_realtime add table public.students;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.cert_photos;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- ───────── 선생님 계정 등록(1회) ─────────
-- 1) 대시보드 > Authentication > Users 에서 선생님 이메일·비밀번호로 사용자를 만든 뒤
-- 2) 아래 이메일을 바꿔서 실행하세요.
-- insert into public.teachers (user_id) select id from auth.users where email = '선생님이메일@example.com';
