alter table public.extracted_components
add column is_active boolean not null default true;

update public.extracted_components as component
set is_active = false
where exists (
  select 1
  from public.extracted_components as newer_component
  join public.analysis_jobs as newer_job
    on newer_job.id = newer_component.analysis_job_id
  join public.analysis_jobs as current_job
    on current_job.id = component.analysis_job_id
  where newer_component.paper_id = component.paper_id
    and newer_job.created_at > current_job.created_at
);

create unique index extracted_components_active_parameter_idx
on public.extracted_components (paper_id, parameter)
where is_active;

create table public.research_gap_decisions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  paper_id uuid not null references public.papers (id) on delete cascade,
  parameter varchar(80) not null check (parameter in ('limitations', 'future_work')),
  decision varchar(20) not null check (decision in ('accepted', 'rejected')),
  note text check (char_length(note) <= 2000),
  reviewer_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, paper_id, parameter, reviewer_id)
);

create index research_gap_decisions_project_idx
on public.research_gap_decisions (project_id, reviewer_id, updated_at desc);

create trigger research_gap_decisions_set_updated_at
before update on public.research_gap_decisions
for each row execute function public.set_updated_at();

alter table public.research_gap_decisions enable row level security;

create policy "Project owners can read their gap decisions"
on public.research_gap_decisions for select
to authenticated
using (
  reviewer_id = auth.uid()
  and exists (
    select 1
    from public.papers
    join public.projects on projects.id = papers.project_id
    where papers.id = research_gap_decisions.paper_id
      and papers.project_id = research_gap_decisions.project_id
      and projects.owner_id = auth.uid()
  )
);

create policy "Project owners can create their gap decisions"
on public.research_gap_decisions for insert
to authenticated
with check (
  reviewer_id = auth.uid()
  and exists (
    select 1
    from public.papers
    join public.projects on projects.id = papers.project_id
    where papers.id = research_gap_decisions.paper_id
      and papers.project_id = research_gap_decisions.project_id
      and projects.owner_id = auth.uid()
  )
);

create policy "Project owners can update their gap decisions"
on public.research_gap_decisions for update
to authenticated
using (
  reviewer_id = auth.uid()
  and exists (
    select 1 from public.projects
    where projects.id = research_gap_decisions.project_id
      and projects.owner_id = auth.uid()
  )
)
with check (
  reviewer_id = auth.uid()
  and exists (
    select 1
    from public.papers
    join public.projects on projects.id = papers.project_id
    where papers.id = research_gap_decisions.paper_id
      and papers.project_id = research_gap_decisions.project_id
      and projects.owner_id = auth.uid()
  )
);

create or replace function public.activate_analysis_components(
  p_job_id uuid,
  p_paper_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.analysis_jobs
    join public.papers
      on papers.project_id = analysis_jobs.project_id
    where analysis_jobs.id = p_job_id
      and papers.id = p_paper_id
  ) then
    raise exception 'Analysis job and paper do not belong to the same project';
  end if;

  update public.extracted_components
  set is_active = false
  where paper_id = p_paper_id
    and analysis_job_id <> p_job_id
    and is_active;

  update public.extracted_components
  set is_active = true
  where paper_id = p_paper_id
    and analysis_job_id = p_job_id;
end;
$$;

revoke all on function public.activate_analysis_components(uuid, uuid) from public;
revoke all on function public.activate_analysis_components(uuid, uuid) from anon;
revoke all on function public.activate_analysis_components(uuid, uuid) from authenticated;
grant execute on function public.activate_analysis_components(uuid, uuid) to service_role;

comment on column public.extracted_components.is_active is
  'Exactly one successful analysis version per paper/parameter is active; older rows remain audit history.';
comment on table public.research_gap_decisions is
  'Owner-scoped human Yes/No decisions for evidence-backed gap candidates.';
