alter table public.extracted_components add column is_implicit boolean not null default false;

create table public.paper_structures (
  id uuid primary key default gen_random_uuid(),
  paper_id uuid not null references public.papers (id) on delete cascade,
  part_name varchar(100) not null,
  status varchar(100) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(paper_id, part_name)
);

create table public.comparative_syntheses (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  similarities text not null,
  differences text not null,
  research_patterns text not null,
  approach_differences text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id)
);

alter table public.paper_structures enable row level security;
alter table public.comparative_syntheses enable row level security;

create policy "Users can view paper structures of their projects"
  on public.paper_structures for select
  using (
    exists (
      select 1 from public.papers p
      join public.projects pr on p.project_id = pr.id
      where p.id = paper_structures.paper_id and pr.owner_id = auth.uid()
    )
  );

create policy "Users can view syntheses of their projects"
  on public.comparative_syntheses for select
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = comparative_syntheses.project_id and pr.owner_id = auth.uid()
    )
  );
