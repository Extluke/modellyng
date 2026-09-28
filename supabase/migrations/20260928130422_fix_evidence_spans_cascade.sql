-- Fix evidence_spans cascading deletion
alter table public.evidence_spans
  drop constraint if exists evidence_spans_paper_block_id_fkey,
  add constraint evidence_spans_paper_block_id_fkey
    foreign key (paper_block_id)
    references public.paper_blocks(id)
    on delete cascade;
