-- Migration: 20261012120000_comparative_synthesis_rls_and_policies.sql
-- Description: Grant INSERT, UPDATE, and DELETE policies on comparative_syntheses to project owners.

create policy "Users can insert syntheses of their projects"
  on public.comparative_syntheses for insert
  with check (
    exists (
      select 1 from public.projects pr
      where pr.id = comparative_syntheses.project_id and pr.owner_id = auth.uid()
    )
  );

create policy "Users can update syntheses of their projects"
  on public.comparative_syntheses for update
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = comparative_syntheses.project_id and pr.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.projects pr
      where pr.id = comparative_syntheses.project_id and pr.owner_id = auth.uid()
    )
  );

create policy "Users can delete syntheses of their projects"
  on public.comparative_syntheses for delete
  using (
    exists (
      select 1 from public.projects pr
      where pr.id = comparative_syntheses.project_id and pr.owner_id = auth.uid()
    )
  );
