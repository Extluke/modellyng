-- Migration: 20261014090000_gap_recommendations.sql
-- Description: Rekomendasi tindak lanjut AI per research gap (tombol "Selesai"
-- di detail gap, menu Maps GAP). Satu baris per gap. source_hash mencatat isi
-- gap dan kutipan yang dipakai; bila berbeda, rekomendasi disusun ulang.
-- Ditulis idempotent agar aman dijalankan ulang di lokal.
-- Rollback: drop table if exists public.gap_recommendations;

create table if not exists public.gap_recommendations (
  gap_id uuid primary key references public.knowledge_graph_nodes (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  source_hash text not null,
  content jsonb not null,
  model_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists gap_recommendations_project_id_idx
  on public.gap_recommendations (project_id);

alter table public.gap_recommendations enable row level security;

drop trigger if exists gap_recommendations_set_updated_at on public.gap_recommendations;
create trigger gap_recommendations_set_updated_at
before update on public.gap_recommendations
for each row execute function public.set_updated_at();

drop policy if exists "Users can view recommendations of their own gaps"
  on public.gap_recommendations;
create policy "Users can view recommendations of their own gaps"
  on public.gap_recommendations for select
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = gap_recommendations.project_id and pr.owner_id = auth.uid()
    )
  );

-- Penulisan mewajibkan gap berada di proyek yang sama dan proyek itu milik
-- pengguna, sehingga baris tidak bisa ditautkan ke gap milik orang lain.
drop policy if exists "Users can insert recommendations of their own gaps"
  on public.gap_recommendations;
create policy "Users can insert recommendations of their own gaps"
  on public.gap_recommendations for insert
  with check (
    exists (
      select 1
      from public.knowledge_graph_nodes node
      join public.projects pr on pr.id = node.project_id
      where node.id = gap_recommendations.gap_id
        and node.project_id = gap_recommendations.project_id
        and pr.owner_id = auth.uid()
    )
  );

drop policy if exists "Users can update recommendations of their own gaps"
  on public.gap_recommendations;
create policy "Users can update recommendations of their own gaps"
  on public.gap_recommendations for update
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = gap_recommendations.project_id and pr.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.knowledge_graph_nodes node
      join public.projects pr on pr.id = node.project_id
      where node.id = gap_recommendations.gap_id
        and node.project_id = gap_recommendations.project_id
        and pr.owner_id = auth.uid()
    )
  );

drop policy if exists "Users can delete recommendations of their own gaps"
  on public.gap_recommendations;
create policy "Users can delete recommendations of their own gaps"
  on public.gap_recommendations for delete
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = gap_recommendations.project_id and pr.owner_id = auth.uid()
    )
  );
