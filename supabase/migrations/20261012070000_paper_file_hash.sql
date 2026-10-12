-- Add file_hash column to public.papers for duplicate detection and prevention
alter table public.papers
  add column if not exists file_hash text;

create index if not exists papers_project_file_hash_idx
  on public.papers (project_id, file_hash);

create index if not exists papers_project_filename_idx
  on public.papers (project_id, lower(trim(original_filename)));
