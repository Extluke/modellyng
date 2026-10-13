-- Migration: 20261012150000_research_flow_maps.sql
-- Description: Cache peta alur riset (kanvas menu Maps GAP), satu baris per
-- project. source_hash mencatat data matriks terverifikasi yang dipakai saat
-- peta dibuat; bila data berubah, backend membuat ulang petanya.
-- Ditulis idempotent agar aman dijalankan ulang di database lokal.

create table if not exists public.research_flow_maps (
  project_id uuid primary key references public.projects (id) on delete cascade,
  source_hash text not null,
  content jsonb not null,
  model_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.research_flow_maps enable row level security;

drop trigger if exists research_flow_maps_set_updated_at on public.research_flow_maps;
create trigger research_flow_maps_set_updated_at
before update on public.research_flow_maps
for each row execute function public.set_updated_at();

drop policy if exists "Users can view research flow maps of their projects"
  on public.research_flow_maps;
create policy "Users can view research flow maps of their projects"
  on public.research_flow_maps for select
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = research_flow_maps.project_id and pr.owner_id = auth.uid()
    )
  );

drop policy if exists "Users can insert research flow maps of their projects"
  on public.research_flow_maps;
create policy "Users can insert research flow maps of their projects"
  on public.research_flow_maps for insert
  with check (
    exists (
      select 1 from public.projects pr
      where pr.id = research_flow_maps.project_id and pr.owner_id = auth.uid()
    )
  );

drop policy if exists "Users can update research flow maps of their projects"
  on public.research_flow_maps;
create policy "Users can update research flow maps of their projects"
  on public.research_flow_maps for update
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = research_flow_maps.project_id and pr.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.projects pr
      where pr.id = research_flow_maps.project_id and pr.owner_id = auth.uid()
    )
  );

drop policy if exists "Users can delete research flow maps of their projects"
  on public.research_flow_maps;
create policy "Users can delete research flow maps of their projects"
  on public.research_flow_maps for delete
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = research_flow_maps.project_id and pr.owner_id = auth.uid()
    )
  );
