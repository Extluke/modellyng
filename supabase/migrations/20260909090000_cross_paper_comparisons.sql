-- Incremental comparisons: immutable source versions, worker-only results,
-- and append-only human decisions. Existing extraction/gap data is preserved.
create table public.paper_comparisons (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  left_paper_id uuid not null references public.papers(id) on delete cascade,
  right_paper_id uuid not null references public.papers(id) on delete cascade,
  input_hash text not null,
  left_source jsonb not null,
  right_source jsonb not null,
  status text not null default 'queued' check (status in ('queued','processing','completed','failed')),
  result jsonb,
  error_message text,
  claim_token uuid,
  started_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (left_paper_id < right_paper_id),
  check ((status = 'completed') = (result is not null)),
  unique (project_id, left_paper_id, right_paper_id, input_hash)
);
create index paper_comparisons_project_idx on public.paper_comparisons(project_id);
create trigger paper_comparisons_updated before update on public.paper_comparisons
for each row execute function public.set_updated_at();

create table public.paper_comparison_reviews (
  id uuid primary key default gen_random_uuid(),
  pair_id uuid not null references public.paper_comparisons(id) on delete cascade,
  reviewer_id uuid not null references auth.users(id) on delete restrict,
  decision text not null check (decision in ('accepted','rejected')),
  note text not null check (length(btrim(note)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index paper_comparison_reviews_pair_idx on public.paper_comparison_reviews(pair_id, created_at desc);
alter table public.paper_comparisons enable row level security;
alter table public.paper_comparison_reviews enable row level security;
revoke all on public.paper_comparisons, public.paper_comparison_reviews from anon, authenticated;
grant select on public.paper_comparisons, public.paper_comparison_reviews to authenticated;
grant all on public.paper_comparisons, public.paper_comparison_reviews to service_role;
create policy "Owners read comparisons" on public.paper_comparisons for select to authenticated
using (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid()));
create policy "Owners read comparison reviews" on public.paper_comparison_reviews for select to authenticated
using (exists (select 1 from public.paper_comparisons c join public.projects p on p.id = c.project_id
              where c.id = pair_id and p.owner_id = auth.uid()));

-- Sources are assembled by the database, never accepted from client JSON.
-- Only active, human-reviewed components and traceable quotes enter the model.
create function public.comparison_paper_source(p_paper_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'title', coalesce(p.title, p.original_filename, 'Paper'),
    'components', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'parameter', c.parameter,
        'value', coalesce(c.final_value, c.ai_value),
        'evidence', coalesce((
          select jsonb_agg(jsonb_build_object('ref', e.id, 'component_id', c.id,
            'paper_id', p.id, 'parameter', c.parameter, 'quote', e.quote,
            'page_number', b.page_number, 'block_id', b.id, 'section', b.section,
            'subsection', b.subsection, 'evidence_kind', e.evidence_kind,
            'source_label', e.source_label, 'bounding_box', b.bounding_box) order by e.id)
          from public.evidence_spans e join public.paper_blocks b on b.id = e.paper_block_id
          where e.component_id = c.id and b.paper_id = p.id and e.page_number = b.page_number
            and length(btrim(e.quote)) > 0
            and position(regexp_replace(lower(e.quote), '\s+', '', 'g') in
                         regexp_replace(lower(b.content), '\s+', '', 'g')) > 0
        ), '[]'::jsonb)) order by c.parameter, c.id)
      from public.extracted_components c where c.paper_id = p.id and c.is_active
        and c.status in ('verified','edited')
        and c.parameter in ('variables_concepts','research_problem','research_objective',
                            'research_question','dataset_sample','methodology')
    ), '[]'::jsonb))
  from public.papers p where p.id = p_paper_id and p.status = 'ready'
    and not exists (select 1 from public.extracted_components c where c.paper_id = p.id
                    and c.is_active and c.status = 'needs_review');
$$;

create function public.current_comparison_inputs(p_project_id uuid)
returns table(left_paper_id uuid, right_paper_id uuid, input_hash text, left_source jsonb, right_source jsonb)
language sql stable security invoker set search_path = '' as $$
  with sources as materialized (
    select p.id, public.comparison_paper_source(p.id) as source
    from public.papers p where p.project_id = p_project_id and p.status = 'ready'
  )
  select l.id, r.id, encode(extensions.digest('cross-paper-v1:' || l.source::text || r.source::text, 'sha256'), 'hex'),
         l.source, r.source
  from sources l join sources r on l.id < r.id
  where l.source is not null and r.source is not null;
$$;

create function public.get_project_comparisons(p_project_id uuid) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare ready_count integer;
begin
  if not exists (select 1 from public.projects p where p.id = p_project_id and p.owner_id = auth.uid()) then
    raise exception 'Project not found' using errcode = 'P0002';
  end if;
  select count(*) into ready_count from public.papers p where p.project_id = p_project_id
    and public.comparison_paper_source(p.id) is not null;
  return jsonb_build_object('project_id', p_project_id, 'ready_papers', ready_count,
    'total_papers', (select count(*) from public.papers p where p.project_id = p_project_id),
    'expected_pairs', ready_count * (ready_count - 1) / 2,
    'pairs', coalesce((
      select jsonb_agg((to_jsonb(c) - 'claim_token' - 'input_hash') || jsonb_build_object('reviews', coalesce((
        select jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc)
        from public.paper_comparison_reviews r where r.pair_id = c.id
      ), '[]'::jsonb)) order by c.left_paper_id, c.right_paper_id)
      from public.current_comparison_inputs(p_project_id) i
      join public.paper_comparisons c on c.project_id = p_project_id
        and c.left_paper_id = i.left_paper_id and c.right_paper_id = i.right_paper_id and c.input_hash = i.input_hash
    ), '[]'::jsonb));
end;
$$;

create function public.sync_project_comparisons(p_project_id uuid, p_retry boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.projects p where p.id = p_project_id and p.owner_id = auth.uid()) then
    raise exception 'Project not found' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_project_id::text, 0));
  insert into public.paper_comparisons(project_id, left_paper_id, right_paper_id, input_hash, left_source, right_source)
    select p_project_id, i.* from public.current_comparison_inputs(p_project_id) i
    on conflict (project_id, left_paper_id, right_paper_id, input_hash) do nothing;
  if p_retry then
    update public.paper_comparisons c set status = 'queued', error_message = null, claim_token = null
    from public.current_comparison_inputs(p_project_id) i
    where c.project_id = p_project_id and c.left_paper_id = i.left_paper_id
      and c.right_paper_id = i.right_paper_id and c.input_hash = i.input_hash
      and (c.status = 'failed' or (c.status = 'processing' and c.started_at < now() - interval '10 minutes'));
  end if;
  return public.get_project_comparisons(p_project_id);
end;
$$;

-- Lease and token prevent duplicated queue deliveries and obsolete workers from
-- overwriting a newer attempt. These RPCs are executable only by service_role.
create function public.claim_paper_comparison(p_pair_id uuid, p_token uuid)
returns setof public.paper_comparisons language sql security invoker set search_path = '' as $$
  update public.paper_comparisons c set status = 'processing', claim_token = p_token,
    started_at = now(), error_message = null
  where c.id = p_pair_id and (c.status = 'queued' or (c.status = 'processing' and c.started_at < now() - interval '10 minutes'))
    and exists (select 1 from public.current_comparison_inputs(c.project_id) i
      where i.left_paper_id = c.left_paper_id and i.right_paper_id = c.right_paper_id and i.input_hash = c.input_hash)
  returning c.*;
$$;

create function public.review_paper_comparison(p_pair_id uuid, p_decision text, p_note text)
returns public.paper_comparison_reviews language plpgsql security definer set search_path = '' as $$
declare comparison public.paper_comparisons; saved public.paper_comparison_reviews;
begin
  select c.* into comparison from public.paper_comparisons c join public.projects p on p.id = c.project_id
    where c.id = p_pair_id and p.owner_id = auth.uid() for update of c;
  if not found then raise exception 'Comparison not found' using errcode = 'P0002'; end if;
  -- Lock source papers/components against concurrent edits while checking freshness.
  perform 1 from public.papers where id in (comparison.left_paper_id, comparison.right_paper_id) for share;
  perform 1 from public.extracted_components where paper_id in (comparison.left_paper_id, comparison.right_paper_id) for share;
  if comparison.status <> 'completed' or comparison.result->>'outcome' is distinct from 'candidate_gap'
    or not exists (select 1 from public.current_comparison_inputs(comparison.project_id) i
       where i.left_paper_id = comparison.left_paper_id and i.right_paper_id = comparison.right_paper_id
         and i.input_hash = comparison.input_hash) then
    raise exception 'Only current gap candidates can be reviewed' using errcode = '22023';
  end if;
  insert into public.paper_comparison_reviews(pair_id, reviewer_id, decision, note)
    values (p_pair_id, auth.uid(), p_decision, btrim(p_note)) returning * into saved;
  return saved;
end;
$$;

revoke all on function public.comparison_paper_source(uuid), public.current_comparison_inputs(uuid),
  public.get_project_comparisons(uuid), public.sync_project_comparisons(uuid,boolean),
  public.review_paper_comparison(uuid,text,text), public.claim_paper_comparison(uuid,uuid) from public, anon;
revoke all on function public.claim_paper_comparison(uuid,uuid) from authenticated;
grant execute on function public.comparison_paper_source(uuid), public.current_comparison_inputs(uuid),
  public.get_project_comparisons(uuid), public.sync_project_comparisons(uuid,boolean),
  public.review_paper_comparison(uuid,text,text) to authenticated;
grant execute on function public.comparison_paper_source(uuid), public.current_comparison_inputs(uuid),
  public.claim_paper_comparison(uuid,uuid) to service_role;
