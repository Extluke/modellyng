-- Update extraction parameters to remove key_claims and keep consistency
-- In Postgres, altering enum types by removing values is difficult, 
-- but we can just stop using 'key_claims' and the application logic will not use it anymore.

-- Create table for research_gaps
create table public.research_gaps (
  id uuid primary key default gen_random_uuid(),
  paper_id uuid not null references public.papers (id) on delete cascade,
  analysis_job_id uuid not null references public.analysis_jobs (id) on delete cascade,
  gap_statement text not null,
  gap_type varchar(50) not null,
  supporting_section varchar(200) not null,
  confidence float not null default 1.0,
  is_explicit boolean not null default false,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- We can store the primary evidence for the gap directly here for simplicity,
-- or use a separate table. Let's just add the primary evidence columns to research_gaps.
alter table public.research_gaps
  add column paper_block_id uuid references public.paper_blocks (id) on delete set null,
  add column evidence_quote text,
  add column page_number integer;

alter table public.research_gaps enable row level security;

create policy "Users can view research gaps of their projects"
  on public.research_gaps for select
  using (
    exists (
      select 1 from public.papers p
      join public.projects pr on p.project_id = pr.id
      where p.id = research_gaps.paper_id and pr.owner_id = auth.uid()
    )
  );

create policy "Service role can manage research gaps"
  on public.research_gaps for all
  using (auth.jwt()->>'role' = 'service_role');

-- Create paper_structures if it doesn't exist (it was created in 20261003223000 but let's adjust it)
-- Add analysis_job_id to paper_structures
alter table public.paper_structures
  add column analysis_job_id uuid references public.analysis_jobs (id) on delete cascade,
  add column is_present boolean not null default false,
  add column page_number integer;
