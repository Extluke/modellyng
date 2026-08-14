-- Modellyng initial schema for local Supabase development.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists vector with schema extensions;

create type public.project_status as enum (
  'ready',
  'processing',
  'needs_review'
);

create type public.paper_status as enum (
  'validating',
  'ready',
  'processing',
  'needs_review',
  'failed'
);

create type public.job_status as enum (
  'queued',
  'processing',
  'completed',
  'failed',
  'cancelled'
);

create type public.verification_status as enum (
  'needs_review',
  'verified',
  'edited',
  'unsupported',
  'rejected'
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  institution text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  organization_id uuid,
  title varchar(180) not null,
  description text not null default '',
  status public.project_status not null default 'ready',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.papers (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  storage_key text,
  original_filename varchar(255),
  mime_type text,
  file_size_bytes bigint check (
    file_size_bytes is null
    or file_size_bytes between 1 and 52428800
  ),
  page_count integer check (page_count is null or page_count > 0),
  language_code varchar(10),
  title text,
  authors jsonb not null default '[]'::jsonb,
  publication_year integer check (
    publication_year is null
    or publication_year between 1500 and 2200
  ),
  journal text,
  doi text,
  publisher text,
  status public.paper_status not null default 'validating',
  metadata_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint paper_has_source check (
    storage_key is not null
    or doi is not null
  ),
  constraint paper_pdf_mime_type check (
    mime_type is null
    or mime_type = 'application/pdf'
  )
);

create table public.paper_blocks (
  id uuid primary key default gen_random_uuid(),
  paper_id uuid not null references public.papers (id) on delete cascade,
  block_index integer not null check (block_index >= 0),
  page_number integer not null check (page_number > 0),
  section text,
  subsection text,
  content text not null,
  bounding_box jsonb,
  embedding extensions.vector,
  created_at timestamptz not null default now(),
  unique (paper_id, block_index)
);

create table public.analysis_jobs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  status public.job_status not null default 'queued',
  stage text not null default 'queued',
  progress numeric(5, 4) not null default 0 check (progress between 0 and 1),
  parameters jsonb not null default '{}'::jsonb,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.extracted_components (
  id uuid primary key default gen_random_uuid(),
  paper_id uuid not null references public.papers (id) on delete cascade,
  analysis_job_id uuid not null references public.analysis_jobs (id) on delete cascade,
  parameter varchar(80) not null,
  ai_value text not null,
  final_value text,
  status public.verification_status not null default 'needs_review',
  confidence numeric(5, 4) check (confidence between 0 and 1),
  model_name text not null,
  prompt_version text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (analysis_job_id, paper_id, parameter)
);

create table public.evidence_spans (
  id uuid primary key default gen_random_uuid(),
  component_id uuid not null references public.extracted_components (id) on delete cascade,
  paper_block_id uuid not null references public.paper_blocks (id) on delete restrict,
  quote text not null,
  page_number integer not null check (page_number > 0),
  section text,
  subsection text,
  bounding_box jsonb,
  created_at timestamptz not null default now()
);

create table public.review_actions (
  id uuid primary key default gen_random_uuid(),
  component_id uuid not null references public.extracted_components (id) on delete cascade,
  reviewer_id uuid not null references auth.users (id) on delete restrict,
  action varchar(40) not null check (
    action in ('accept', 'edit', 'reject', 'request_reanalysis')
  ),
  original_ai_value text not null,
  corrected_value text,
  note text,
  created_at timestamptz not null default now()
);

create index projects_owner_idx on public.projects (owner_id);
create index papers_project_idx on public.papers (project_id);
create index paper_blocks_paper_page_idx on public.paper_blocks (paper_id, page_number);
create index analysis_jobs_project_status_idx on public.analysis_jobs (project_id, status);
create index extracted_components_paper_status_idx on public.extracted_components (paper_id, status);
create index evidence_component_idx on public.evidence_spans (component_id);
create index review_actions_component_idx on public.review_actions (component_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', '')
  );
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger projects_set_updated_at
before update on public.projects
for each row execute function public.set_updated_at();

create trigger papers_set_updated_at
before update on public.papers
for each row execute function public.set_updated_at();

create trigger analysis_jobs_set_updated_at
before update on public.analysis_jobs
for each row execute function public.set_updated_at();

create trigger extracted_components_set_updated_at
before update on public.extracted_components
for each row execute function public.set_updated_at();

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.papers enable row level security;
alter table public.paper_blocks enable row level security;
alter table public.analysis_jobs enable row level security;
alter table public.extracted_components enable row level security;
alter table public.evidence_spans enable row level security;
alter table public.review_actions enable row level security;

create policy "Users can read their profile"
on public.profiles for select
to authenticated
using (id = auth.uid());

create policy "Users can update their profile"
on public.profiles for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy "Users can create their projects"
on public.projects for insert
to authenticated
with check (owner_id = auth.uid());

create policy "Users can read their projects"
on public.projects for select
to authenticated
using (owner_id = auth.uid());

create policy "Users can update their projects"
on public.projects for update
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "Users can delete their projects"
on public.projects for delete
to authenticated
using (owner_id = auth.uid());

create policy "Project owners can manage papers"
on public.papers for all
to authenticated
using (
  exists (
    select 1 from public.projects
    where projects.id = papers.project_id
      and projects.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.projects
    where projects.id = papers.project_id
      and projects.owner_id = auth.uid()
  )
);

create policy "Project owners can manage paper blocks"
on public.paper_blocks for all
to authenticated
using (
  exists (
    select 1
    from public.papers
    join public.projects on projects.id = papers.project_id
    where papers.id = paper_blocks.paper_id
      and projects.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.papers
    join public.projects on projects.id = papers.project_id
    where papers.id = paper_blocks.paper_id
      and projects.owner_id = auth.uid()
  )
);

create policy "Project owners can manage analysis jobs"
on public.analysis_jobs for all
to authenticated
using (
  exists (
    select 1 from public.projects
    where projects.id = analysis_jobs.project_id
      and projects.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.projects
    where projects.id = analysis_jobs.project_id
      and projects.owner_id = auth.uid()
  )
);

create policy "Project owners can manage extracted components"
on public.extracted_components for all
to authenticated
using (
  exists (
    select 1
    from public.papers
    join public.projects on projects.id = papers.project_id
    where papers.id = extracted_components.paper_id
      and projects.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.papers
    join public.projects on projects.id = papers.project_id
    where papers.id = extracted_components.paper_id
      and projects.owner_id = auth.uid()
  )
);

create policy "Project owners can manage evidence"
on public.evidence_spans for all
to authenticated
using (
  exists (
    select 1
    from public.extracted_components
    join public.papers on papers.id = extracted_components.paper_id
    join public.projects on projects.id = papers.project_id
    where extracted_components.id = evidence_spans.component_id
      and projects.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.extracted_components
    join public.papers on papers.id = extracted_components.paper_id
    join public.projects on projects.id = papers.project_id
    where extracted_components.id = evidence_spans.component_id
      and projects.owner_id = auth.uid()
  )
);

create policy "Project owners can read review actions"
on public.review_actions for select
to authenticated
using (
  exists (
    select 1
    from public.extracted_components
    join public.papers on papers.id = extracted_components.paper_id
    join public.projects on projects.id = papers.project_id
    where extracted_components.id = review_actions.component_id
      and projects.owner_id = auth.uid()
  )
);

create policy "Project owners can create review actions"
on public.review_actions for insert
to authenticated
with check (
  reviewer_id = auth.uid()
  and exists (
    select 1
    from public.extracted_components
    join public.papers on papers.id = extracted_components.paper_id
    join public.projects on projects.id = papers.project_id
    where extracted_components.id = review_actions.component_id
      and projects.owner_id = auth.uid()
  )
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'private-papers',
  'private-papers',
  false,
  52428800,
  array['application/pdf']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Users can upload paper files to their folder"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'private-papers'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can read their paper files"
on storage.objects for select
to authenticated
using (
  bucket_id = 'private-papers'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can update their paper files"
on storage.objects for update
to authenticated
using (
  bucket_id = 'private-papers'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'private-papers'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can delete their paper files"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'private-papers'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- PostgREST roles need table privileges before row-level policies are evaluated.
grant usage on schema public to authenticated, service_role;

grant select, insert, update, delete
on all tables in schema public
to authenticated;

grant all privileges
on all tables in schema public
to service_role;

grant usage, select
on all sequences in schema public
to authenticated, service_role;

grant execute
on all functions in schema public
to authenticated, service_role;

alter default privileges for role postgres in schema public
grant select, insert, update, delete on tables to authenticated;

alter default privileges for role postgres in schema public
grant all privileges on tables to service_role;

alter default privileges for role postgres in schema public
grant usage, select on sequences to authenticated, service_role;

alter default privileges for role postgres in schema public
grant execute on functions to authenticated, service_role;
