alter table public.profiles
  add column if not exists preferences jsonb not null default jsonb_build_object(
    'citation_style', 'apa7',
    'locale', 'id',
    'show_confidence', true
  );

comment on column public.profiles.preferences is
  'Owner-scoped UI and bibliography preferences; never contains secrets.';
