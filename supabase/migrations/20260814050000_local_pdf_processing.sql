alter table public.analysis_jobs
add column if not exists paper_id uuid;

create index if not exists analysis_jobs_paper_created_idx
on public.analysis_jobs (paper_id, created_at desc)
where paper_id is not null;

create unique index if not exists analysis_jobs_one_active_per_paper_idx
on public.analysis_jobs (paper_id)
where paper_id is not null
  and status in ('queued', 'processing');

comment on column public.analysis_jobs.paper_id is
'Paper processed by this job. Null is retained only for legacy project-level jobs.';

alter table public.papers
add constraint papers_id_project_unique unique (id, project_id);

alter table public.analysis_jobs
add constraint analysis_jobs_paper_matches_project
foreign key (paper_id, project_id)
references public.papers (id, project_id)
on delete cascade;
