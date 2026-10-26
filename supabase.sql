-- Supabase SQL Editor에서 전체 실행하세요.
-- 수업 시연용: URL을 아는 누구나 읽고 업데이트할 수 있습니다.
-- 실제 내부 연구용으로 전환할 때는 사용자 인증 및 팀별 권한 정책이 필요합니다.
begin;

create table if not exists public.research_projects (
  id text primary key check (id in ('arc','video','blast','knowledge')),
  checks boolean[] not null default array[false,false,false,false,false]
    check (array_length(checks,1) = 5 and array_position(checks,null) is null),
  status text not null default '진행 중'
    check (status in ('진행 중','검토 요청','도움 필요','완료')),
  next_task text not null default '' check (char_length(next_task) <= 150),
  md text not null default '' check (octet_length(md) <= 200000),
  version integer not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.research_updates (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.research_projects(id),
  author text not null check (char_length(trim(author)) between 1 and 30),
  message text not null check (char_length(trim(message)) between 1 and 2000),
  status text not null check (status in ('진행 중','검토 요청','도움 필요','완료')),
  md text check (octet_length(md) <= 200000),
  md_diff text check (octet_length(md_diff) <= 500000),
  created_at timestamptz not null default now()
);
create index if not exists research_updates_created_idx on public.research_updates(created_at desc);
insert into public.research_projects(id) values ('arc'),('video'),('blast'),('knowledge')
on conflict (id) do nothing;

alter table public.research_projects enable row level security;
alter table public.research_updates enable row level security;
drop policy if exists research_projects_read on public.research_projects;
create policy research_projects_read on public.research_projects for select to anon, authenticated using (true);
drop policy if exists research_updates_read on public.research_updates;
create policy research_updates_read on public.research_updates for select to anon, authenticated using (true);
revoke all on public.research_projects, public.research_updates from anon, authenticated;
grant select on public.research_projects, public.research_updates to anon, authenticated;

-- 현황과 변경 이력을 하나의 트랜잭션에서 저장합니다.
create or replace function public.save_research_update(
  p_project text, p_version integer, p_author text, p_message text,
  p_status text, p_next text, p_checks boolean[], p_md text default null,
  p_diff text default null
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.research_projects
  set checks = p_checks, status = p_status, next_task = coalesce(p_next,''),
      md = coalesce(p_md, md), version = version + 1, updated_at = now()
  where id = p_project and version = p_version;
  if not found then
    raise exception '다른 사용자가 수정했습니다. 새로고침 후 다시 저장해 주세요.';
  end if;
  insert into public.research_updates(project_id,author,message,status,md,md_diff)
  values (p_project,trim(p_author),trim(p_message),p_status,p_md,p_diff);
end;
$$;
revoke all on function public.save_research_update(text,integer,text,text,text,text,boolean[],text,text) from public;
grant execute on function public.save_research_update(text,integer,text,text,text,text,boolean[],text,text) to anon, authenticated;
commit;
