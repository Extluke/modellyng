create table if not exists public.project_chat_messages (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  turn_id uuid not null,
  position smallint not null check (position in (0, 1)),
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(btrim(content)) > 0),
  sources jsonb not null default '[]'::jsonb check (jsonb_typeof(sources) = 'array'),
  model_name text,
  review_notice text,
  created_at timestamptz not null default now(),
  unique (turn_id, position),
  check (
    (position = 0 and role = 'user') or
    (position = 1 and role = 'assistant')
  )
);

create index if not exists project_chat_messages_owner_project_created_idx
  on public.project_chat_messages(owner_id, project_id, created_at, position);

alter table public.project_chat_messages enable row level security;

create policy "Owners can read their project chat"
  on public.project_chat_messages
  for select
  using (
    owner_id = auth.uid()
    and exists (
      select 1 from public.projects
      where projects.id = project_chat_messages.project_id
        and projects.owner_id = auth.uid()
    )
  );

create policy "Owners can append their project chat"
  on public.project_chat_messages
  for insert
  with check (
    owner_id = auth.uid()
    and exists (
      select 1 from public.projects
      where projects.id = project_chat_messages.project_id
        and projects.owner_id = auth.uid()
    )
  );

comment on table public.project_chat_messages is
  'Permanent owner-scoped RAG chat history, including evidence citations.';
