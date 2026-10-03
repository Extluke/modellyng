alter table public.comparative_syntheses
drop constraint if exists comparative_syntheses_project_id_key;

alter table public.comparative_syntheses
add column paper_ids uuid[] not null default '{}';

-- We ensure that there is only one synthesis for a specific combination of papers in a project.
create unique index comparative_syntheses_project_papers_idx 
on public.comparative_syntheses (project_id, paper_ids);
