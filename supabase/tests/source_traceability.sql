-- Run after migrations: psql -v ON_ERROR_STOP=1 -f this-file.sql
-- All fixtures are rolled back, including on connection close after an error.
begin;
create temporary table traceability_fixture as select
  gen_random_uuid() a, gen_random_uuid() b,
  gen_random_uuid() project_a, gen_random_uuid() project_b,
  gen_random_uuid() paper_a, gen_random_uuid() paper_b,
  gen_random_uuid() report_a, gen_random_uuid() report_b;
grant select on traceability_fixture to authenticated;
insert into auth.users(id) select a from traceability_fixture union all select b from traceability_fixture;
insert into public.projects(id, owner_id, title)
  select project_a, a, 'Traceability QA A' from traceability_fixture union all
  select project_b, b, 'Traceability QA B' from traceability_fixture;
insert into public.papers(id, project_id, doi)
  select paper_a, project_a, '10.1234/qa-a' from traceability_fixture union all
  select paper_b, project_b, '10.1234/qa-b' from traceability_fixture;
insert into public.paper_source_verifications(id, paper_id, report)
  select report_a, paper_a, '{"status":"unverifiable"}'::jsonb from traceability_fixture union all
  select report_b, paper_b, '{"status":"unverifiable"}'::jsonb from traceability_fixture;

set local role authenticated;
select set_config('request.jwt.claim.sub', a::text, true) from traceability_fixture;
do $$
declare f record;
begin
  select * into f from traceability_fixture;
  if (select count(*) from public.paper_source_verifications where id in (f.report_a, f.report_b)) <> 1 then
    raise exception 'Account A can read Account B reports';
  end if;
  insert into public.paper_source_reviews(verification_id, reviewer_id, decision, note)
    values(f.report_a, f.a, 'reject', 'QA source not found');
  begin
    insert into public.paper_source_verifications(paper_id, report) values(f.paper_b, '{}');
    raise exception 'Account A inserted an Account B report';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.paper_source_reviews(verification_id, reviewer_id, decision, note)
      values(f.report_b, f.a, 'accept', 'Must fail');
    raise exception 'Account A reviewed Account B report';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.paper_source_reviews(verification_id, reviewer_id, decision, note)
      values(f.report_a, f.b, 'accept', 'Must fail');
    raise exception 'Reviewer identity was spoofed';
  exception when insufficient_privilege then null; end;
  begin
    update public.paper_source_verifications set report = '{}' where id = f.report_a;
    raise exception 'Immutable report was overwritten';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.paper_source_reviews where verification_id = f.report_a;
    raise exception 'Review history was deleted';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub', b::text, true) from traceability_fixture;
do $$
declare f record;
begin
  select * into f from traceability_fixture;
  if exists(select 1 from public.paper_source_verifications where id = f.report_a)
     or exists(select 1 from public.paper_source_reviews where verification_id = f.report_a) then
    raise exception 'Account B can read Account A provenance';
  end if;
  if not exists(select 1 from public.paper_source_verifications where id = f.report_b) then
    raise exception 'Account B cannot read its own report';
  end if;
end $$;
reset role;
rollback;
