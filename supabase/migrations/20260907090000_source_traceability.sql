-- Additive migration. Existing PDFs, blocks, components and decisions stay intact.
alter table public.papers
  add column volume text,
  add column issue text,
  add column pages text,
  add column publication_status text;

alter table public.evidence_spans
  add column evidence_kind text not null default 'text'
    check (evidence_kind in ('text', 'table', 'figure', 'equation', 'result')),
  add column source_label text,
  add constraint evidence_object_label check (
    evidence_kind not in ('table', 'figure', 'equation') or
    (source_label is not null and length(trim(source_label)) > 0)
  );

create table public.paper_source_verifications (
  id uuid primary key default gen_random_uuid(),
  paper_id uuid not null references public.papers(id) on delete cascade,
  report jsonb not null check (jsonb_typeof(report) = 'object'),
  created_at timestamptz not null default now()
);
create index paper_source_verifications_paper_idx
  on public.paper_source_verifications(paper_id, created_at desc);

create table public.paper_source_reviews (
  id uuid primary key default gen_random_uuid(),
  verification_id uuid not null references public.paper_source_verifications(id) on delete cascade,
  reviewer_id uuid not null references auth.users(id) on delete restrict,
  decision text not null check (decision in ('accept', 'reject')),
  note text not null check (length(trim(note)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index paper_source_reviews_verification_idx
  on public.paper_source_reviews(verification_id, created_at desc);

alter table public.paper_source_verifications enable row level security;
alter table public.paper_source_reviews enable row level security;

create policy source_verification_owner_select on public.paper_source_verifications
  for select to authenticated using (exists (
    select 1 from public.papers p join public.projects pr on pr.id = p.project_id
    where p.id = paper_id and pr.owner_id = (select auth.uid())
  ));
create policy source_verification_owner_insert on public.paper_source_verifications
  for insert to authenticated with check (exists (
    select 1 from public.papers p join public.projects pr on pr.id = p.project_id
    where p.id = paper_id and pr.owner_id = (select auth.uid())
  ));
create policy source_review_owner_select on public.paper_source_reviews
  for select to authenticated using (exists (
    select 1 from public.paper_source_verifications v where v.id = verification_id
  ));
create policy source_review_owner_insert on public.paper_source_reviews
  for insert to authenticated with check (
    reviewer_id = (select auth.uid()) and exists (
      select 1 from public.paper_source_verifications v where v.id = verification_id
    )
  );
-- Reports/decisions are append-only to authenticated clients.
revoke all on public.paper_source_verifications, public.paper_source_reviews from anon;
revoke update, delete on public.paper_source_verifications, public.paper_source_reviews from authenticated;
grant select, insert on public.paper_source_verifications, public.paper_source_reviews to authenticated;

-- Rollback: deploy the previous API/worker/frontend first. Back up the two new
-- tables and new column values before removing them; do not reset the database.
