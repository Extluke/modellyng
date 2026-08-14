# Modellyng — Instructions for Coding Agents

These instructions apply to the entire repository. They are mandatory for
Codex and should be treated as the project contract by other coding assistants.

## Read before changing anything

Read these files in order:

1. `docs/PROJECT_STATUS.md`
2. `docs/ARCHITECTURE.md`
3. `docs/CONTRIBUTING.md`
4. The files and tests directly related to the assigned task

Start every task by inspecting the current branch and `git status`. This is an
existing product, not a greenfield tutorial. Do not scaffold a replacement app
or restart the project from zero.

## Architecture is locked

Preserve this stack unless the team first approves and records a new
architecture decision:

- Flutter frontend
- Riverpod state management
- `go_router` navigation
- Dio HTTP client
- Python FastAPI backend
- Celery worker with Redis
- Local Supabase for PostgreSQL, Auth, Storage, and RLS
- Gemini API through the backend only
- Monorepo layout: `frontend/`, `backend/`, and `supabase/`

Do not replace Flutter with React/Next.js, FastAPI with Node/Laravel, Supabase
with another database, Celery/Redis with an in-process job, or Gemini with a
different provider as part of an ordinary feature task. Propose such a change
in writing and wait for team approval.

## Non-negotiable product rules

- Keep all project and paper data isolated by authenticated owner.
- Keep Supabase RLS enabled. Never solve an access problem by disabling RLS or
  using a service-role key in Flutter.
- AI keys and service-role keys belong only in `backend/.env`; never commit,
  print, paste into frontend code, or include them in documentation/tests.
- Preserve the evidence chain: AI result -> evidence quote -> paper block ->
  page -> original private PDF.
- AI output is never final automatically. It must remain reviewable by a human.
- Never invent evidence, page numbers, metadata, or AI results.
- Uploaded papers remain private. Do not make the storage bucket public.
- Preserve the current 50 MB per-PDF limit unless the product team approves a
  change.
- Preserve existing user data and unrelated working-tree changes.

## Database and API rules

- Flutter uses Supabase directly only for authentication/session needs. Product
  data operations go through the authenticated FastAPI API.
- Worker-only operations may use the backend service-role key.
- Add a new timestamped migration for schema changes. Do not rewrite an already
  applied migration to simulate a new database state.
- Keep response models explicit and update backend and Flutter models together.
- Maintain status flow consistency across projects, papers, jobs, components,
  dashboard metrics, and the Review screen.

## Required workflow

1. Confirm the assigned task and its acceptance criteria.
2. Audit the existing implementation before proposing new files or packages.
3. Make the smallest compatible change; reuse existing repositories, models,
   widgets, and design tokens.
4. Add or update regression tests.
5. Run the relevant checks described in `docs/CONTRIBUTING.md`.
6. Update `docs/PROJECT_STATUS.md` when a feature materially changes status.
7. Report changed files, verification evidence, limitations, and any migration
   or environment step.

Do not silently broaden scope. Do not refactor working foundations during an
unrelated feature. Do not commit generated build output, local runtime files,
database data, `.env`, or API keys.

## Current product priority

The next planned vertical slice is **Structured Paper Result + Evidence PDF
Viewer**. Its definition of done is in `docs/PROJECT_STATUS.md`. Do not skip
ahead to comparative matrices, research-gap generation, billing, or public
deployment unless the team explicitly assigns that work.

