-- Migration: 20261013090000_project_syntheses.sql
-- Description: Sintesis AI global per project (menu Matriks & Sintesis).
-- Satu baris per project mencakup semua paper terreview. source_hash mencatat
-- data review yang dipakai; bila berbeda dari data terbaru, sintesis ditandai
-- perlu diperbarui. Ditulis idempotent agar aman dijalankan ulang di lokal.

create table if not exists public.project_syntheses (
  project_id uuid primary key references public.projects (id) on delete cascade,
  source_hash text not null,
  content jsonb not null,
  model_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.project_syntheses enable row level security;

drop trigger if exists project_syntheses_set_updated_at on public.project_syntheses;
create trigger project_syntheses_set_updated_at
before update on public.project_syntheses
for each row execute function public.set_updated_at();

drop policy if exists "Users can view syntheses of their own projects"
  on public.project_syntheses;
create policy "Users can view syntheses of their own projects"
  on public.project_syntheses for select
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = project_syntheses.project_id and pr.owner_id = auth.uid()
    )
  );

drop policy if exists "Users can insert syntheses of their own projects"
  on public.project_syntheses;
create policy "Users can insert syntheses of their own projects"
  on public.project_syntheses for insert
  with check (
    exists (
      select 1 from public.projects pr
      where pr.id = project_syntheses.project_id and pr.owner_id = auth.uid()
    )
  );

drop policy if exists "Users can update syntheses of their own projects"
  on public.project_syntheses;
create policy "Users can update syntheses of their own projects"
  on public.project_syntheses for update
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = project_syntheses.project_id and pr.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.projects pr
      where pr.id = project_syntheses.project_id and pr.owner_id = auth.uid()
    )
  );

drop policy if exists "Users can delete syntheses of their own projects"
  on public.project_syntheses;
create policy "Users can delete syntheses of their own projects"
  on public.project_syntheses for delete
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = project_syntheses.project_id and pr.owner_id = auth.uid()
    )
  );
