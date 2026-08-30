create or replace function public.accept_review_components(
  p_component_ids uuid[]
)
returns table(accepted_count integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_requested_count integer;
  v_eligible_count integer;
  v_paper_ids uuid[];
  v_project_ids uuid[];
begin
  v_requested_count := cardinality(p_component_ids);
  if v_requested_count is null or v_requested_count < 1 or v_requested_count > 200 then
    raise exception 'Pilih antara 1 dan 200 komponen review';
  end if;
  if (select count(distinct value) from unnest(p_component_ids) as ids(value))
      <> v_requested_count then
    raise exception 'Daftar komponen review memuat ID ganda';
  end if;

  perform components.id
  from public.extracted_components components
  join public.papers on papers.id = components.paper_id
  join public.projects on projects.id = papers.project_id
  where components.id = any(p_component_ids)
  for update of components;

  select count(*),
         array_agg(distinct components.paper_id),
         array_agg(distinct papers.project_id)
  into v_eligible_count, v_paper_ids, v_project_ids
  from public.extracted_components components
  join public.papers on papers.id = components.paper_id
  join public.projects on projects.id = papers.project_id
  where components.id = any(p_component_ids)
    and components.status = 'needs_review'
    and components.is_active
    and projects.owner_id = auth.uid();

  if v_eligible_count <> v_requested_count then
    raise exception 'Sebagian komponen bukan milik pengguna, tidak aktif, atau sudah ditinjau';
  end if;

  insert into public.review_actions (
    component_id,
    reviewer_id,
    action,
    original_ai_value,
    corrected_value,
    note
  )
  select components.id,
         auth.uid(),
         'accept',
         components.ai_value,
         null,
         'Diterima melalui aksi massal'
  from public.extracted_components components
  where components.id = any(p_component_ids);

  update public.extracted_components components
  set status = 'verified',
      final_value = components.ai_value
  where components.id = any(p_component_ids);

  update public.papers papers
  set status = 'ready'
  where papers.id = any(v_paper_ids)
    and not exists (
      select 1
      from public.extracted_components pending
      where pending.paper_id = papers.id
        and pending.status = 'needs_review'
        and pending.is_active
    );

  update public.projects projects
  set status = 'ready'
  where projects.id = any(v_project_ids)
    and not exists (
      select 1
      from public.papers papers
      where papers.project_id = projects.id
        and papers.status <> 'ready'
    );

  return query select v_requested_count;
end;
$$;

revoke all on function public.accept_review_components(uuid[]) from public;
revoke all on function public.accept_review_components(uuid[]) from anon;
grant execute on function public.accept_review_components(uuid[]) to authenticated;

comment on function public.accept_review_components(uuid[]) is
  'Atomically accepts active owner-scoped review components and refreshes paper/project readiness.';
