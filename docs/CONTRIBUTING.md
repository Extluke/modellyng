# Team Development Workflow

This workflow is intentionally conservative because multiple people and coding
assistants will work on the same product.

## Before a teammate starts

1. Confirm that the latest completed work has been committed and pushed to the
   shared repository. A local uncommitted workspace cannot be cloned by another
   teammate.
2. Clone the agreed repository, or run `git pull --ff-only` in an existing
   clean checkout.
3. Receive `backend/.env` values through a private team channel. Never place
   secrets in Git, prompts, screenshots, or chat transcripts.
4. Read `AGENTS.md`, `docs/PROJECT_STATUS.md`, and `docs/ARCHITECTURE.md`.
5. First ask the coding assistant for an audit/plan without code changes.

## Branches and ownership

- Do not develop directly on `main`.
- Use one branch and one narrowly scoped pull request per task.
- Codex-created branches should use `codex/<short-task-name>`.
- Agree who owns overlapping files before two developers edit them.
- Commit small coherent checkpoints; avoid a single commit mixing a feature,
  broad refactor, dependency upgrades, and formatting.
- Another teammate reviews the pull request before merge.

Suggested flow:

```powershell
git switch main
git pull --ff-only
git switch -c codex/paper-result-viewer
git status
```

## Safe use of coding assistants

Give the assistant one task with explicit acceptance criteria. Paste the prompt
from `docs/AI_HANDOFF_PROMPT.md`. Require it to:

- summarize the current architecture before editing;
- name the files it expects to change;
- avoid new dependencies unless necessary;
- protect unrelated working-tree changes;
- run tests and show evidence;
- update the project status document.

Reject a proposal if it attempts to generate a new app, replace the selected
stack, disable RLS, expose backend keys to Flutter, make PDFs public, delete
existing migrations/data, or skip human review of AI output.

## Required verification

Backend, from `backend/`:

```powershell
python -m pytest
```

Flutter, from `frontend/`:

```powershell
flutter analyze
flutter test
```

For web-facing changes:

```powershell
flutter build web --release
```

Also test the changed user flow in the browser at desktop and mobile widths.
Authorization-sensitive changes require a two-account isolation test.

## Database changes

- Add a new timestamped file in `supabase/migrations/`.
- Never edit an applied migration to represent new behavior.
- Include forward behavior, constraints/indexes/RLS, and safe rollback notes in
  the pull request.
- Test with local Supabase before merge.
- Never reset the shared database or delete user data without explicit team
  approval and a backup/recovery plan.

## Pull request checklist

- The task matches `docs/PROJECT_STATUS.md` or has explicit team approval.
- Architecture and trust boundaries are preserved.
- No secret, `.env`, private PDF, runtime log, or build output is included.
- RLS and Account A/Account B isolation remain intact.
- AI evidence remains traceable and human-reviewable.
- Tests and manual validation pass.
- Documentation and environment/migration steps are included.

The repository also includes `.github/pull_request_template.md` to make this
checklist visible during review.

