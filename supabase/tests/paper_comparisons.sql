-- Run with psql -v ON_ERROR_STOP=1. All fixtures roll back.
begin;
create temporary table comparison_fixture as select gen_random_uuid() a, gen_random_uuid() b,
  gen_random_uuid() project_a, gen_random_uuid() project_b;
grant select on comparison_fixture to authenticated;
insert into auth.users(id) select a from comparison_fixture union all select b from comparison_fixture;
insert into public.projects(id, owner_id, title)
  select project_a, a, 'Comparison isolation A' from comparison_fixture union all
  select project_b, b, 'Comparison isolation B' from comparison_fixture;
insert into public.papers(project_id, title, doi, status)
  select project_a, 'Paper ' || n, '10.1234/comparison-qa-' || n, 'ready'::public.paper_status
  from comparison_fixture cross join generate_series(1,3) n;
insert into public.analysis_jobs(project_id) select project_a from comparison_fixture;
insert into public.extracted_components(paper_id, analysis_job_id, parameter, ai_value, final_value, status, model_name, prompt_version)
  select p.id, j.id, 'variables_concepts', 'Waste behavior', 'Reviewed waste behavior', 'verified', 'fixture', 'fixture'
  from public.papers p join public.analysis_jobs j on j.project_id = p.project_id
  where p.project_id = (select project_a from comparison_fixture);
insert into public.paper_blocks(paper_id, block_index, page_number, content, section)
  select id, 0, 3, 'We studied waste management behavior among households.', 'Methods'
  from public.papers where project_id = (select project_a from comparison_fixture);
insert into public.evidence_spans(component_id, paper_block_id, quote, page_number)
  select c.id, b.id, 'We studied waste management behavior among households.', 3
  from public.extracted_components c join public.paper_blocks b on b.paper_id = c.paper_id
  where c.paper_id in (select id from public.papers where project_id = (select project_a from comparison_fixture));
-- Corrupted page and fabricated text must never reach comparison input.
insert into public.evidence_spans(component_id, paper_block_id, quote, page_number)
  select c.id, b.id, 'This quotation does not exist.', 3
  from public.extracted_components c join public.paper_blocks b on b.paper_id = c.paper_id
  where c.paper_id in (select id from public.papers where project_id = (select project_a from comparison_fixture));
insert into public.evidence_spans(component_id, paper_block_id, quote, page_number)
  select c.id, b.id, 'We studied waste management behavior among households.', 99
  from public.extracted_components c join public.paper_blocks b on b.paper_id = c.paper_id
  where c.paper_id in (select id from public.papers where project_id = (select project_a from comparison_fixture));

set local role authenticated;
select set_config('request.jwt.claim.sub', a::text, true) from comparison_fixture;
do $$
declare f record; overview jsonb; source jsonb;
begin
  select * into f from comparison_fixture;
  overview := public.sync_project_comparisons(f.project_a);
  if jsonb_array_length(overview->'pairs') <> 3 or (overview->>'expected_pairs')::int <> 3 then
    raise exception 'Three papers must create exactly three unordered pairs';
  end if;
  perform public.sync_project_comparisons(f.project_a);
  if (select count(*) from public.paper_comparisons where project_id = f.project_a) <> 3 then
    raise exception 'Duplicate sources created duplicate work';
  end if;
  source := overview->'pairs'->0->'left_source';
  if jsonb_array_length(source->'components'->0->'evidence') <> 1 then
    raise exception 'Invalid quote or page entered the comparison source';
  end if;
  begin
    perform public.sync_project_comparisons(f.project_b);
    raise exception 'A scheduled work for B';
  exception when no_data_found then null; end;
  begin
    update public.paper_comparisons set status = 'failed' where project_id = f.project_a;
    raise exception 'Client can forge worker results';
  exception when insufficient_privilege then null; end;
  begin
    perform public.claim_paper_comparison((overview->'pairs'->0->>'id')::uuid, gen_random_uuid());
    raise exception 'Client can claim worker tasks';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- Worker lease is single-winner even when the queue delivers the same ID twice.
do $$
declare pair uuid; claimed integer;
begin
  select id into pair from public.paper_comparisons where project_id = (select project_a from comparison_fixture) limit 1;
  select count(*) into claimed from public.claim_paper_comparison(pair, gen_random_uuid());
  if claimed <> 1 then raise exception 'Worker could not claim pair'; end if;
  select count(*) into claimed from public.claim_paper_comparison(pair, gen_random_uuid());
  if claimed <> 0 then raise exception 'Duplicate worker claimed pair'; end if;
end $$;
update public.paper_comparisons set status = 'completed', result = '{"outcome":"candidate_gap"}'
  where project_id = (select project_a from comparison_fixture);

set local role authenticated;
select set_config('request.jwt.claim.sub', a::text, true) from comparison_fixture;
do $$
declare pair uuid; review public.paper_comparison_reviews;
begin
  select id into pair from public.paper_comparisons where project_id = (select project_a from comparison_fixture) limit 1;
  review := public.review_paper_comparison(pair, 'accepted', 'Investigate population scope; novelty not established.');
  if review.reviewer_id <> (select a from comparison_fixture) then raise exception 'Reviewer identity mismatch'; end if;
  perform public.review_paper_comparison(pair, 'rejected', 'Later review finds the scopes equivalent.');
  if (select count(*) from public.paper_comparison_reviews where pair_id = pair) <> 2 then
    raise exception 'Review history was overwritten';
  end if;
  begin
    perform public.review_paper_comparison(pair, 'accepted', '   ');
    raise exception 'Blank review accepted';
  exception when check_violation then null; end;
  begin
    update public.paper_comparison_reviews set note = 'Overwrite' where pair_id = pair;
    raise exception 'Immutable history can be overwritten';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub', b::text, true) from comparison_fixture;
do $$
begin
  if exists(select 1 from public.paper_comparisons where project_id = (select project_a from comparison_fixture))
    or exists(select 1 from public.paper_comparison_reviews) then
    raise exception 'B can read A comparison or review';
  end if;
  begin
    perform public.get_project_comparisons((select project_a from comparison_fixture));
    raise exception 'B can fetch A analysis';
  exception when no_data_found then null; end;
end $$;
reset role;

-- Editing one source invalidates only its two pairs. Other results are reused.
create temporary table old_comparisons as select id from public.paper_comparisons
where project_id = (select project_a from comparison_fixture);
grant select on old_comparisons to authenticated;
update public.extracted_components set final_value = 'Changed reviewed concept'
where paper_id = (select id from public.papers where project_id = (select project_a from comparison_fixture) order by id limit 1);
set local role authenticated;
select set_config('request.jwt.claim.sub', a::text, true) from comparison_fixture;
do $$
declare f record; overview jsonb; old_pair uuid;
begin
  select * into f from comparison_fixture;
  overview := public.get_project_comparisons(f.project_a);
  if jsonb_array_length(overview->'pairs') <> 1 then raise exception 'Stale results still appear as current'; end if;
  select id into old_pair from old_comparisons where id <> (overview->'pairs'->0->>'id')::uuid limit 1;
  begin
    perform public.review_paper_comparison(old_pair, 'accepted', 'Stale decision');
    raise exception 'Stale candidate was reviewable';
  exception when invalid_parameter_value then null; end;
  overview := public.sync_project_comparisons(f.project_a);
  if jsonb_array_length(overview->'pairs') <> 3 then raise exception 'Changed pairs not scheduled'; end if;
  if (select count(*) from public.paper_comparisons where project_id = f.project_a) <> 5 then
    raise exception 'Unchanged pair was recomputed or history was lost';
  end if;
end $$;
reset role;
rollback;
