# Modellyng Architecture Contract

## Purpose

This document records the architecture the team has already selected and
implemented. It prevents accidental rewrites when a new developer or coding
assistant joins the project.

Architecture may evolve, but an ordinary feature task does not authorize a
stack replacement. A change requires team agreement, a written trade-off
analysis, a migration/rollback plan, and a new decision record.

## Locked technology choices

| Layer | Technology | Role |
|---|---|---|
| Client | Flutter | Responsive web/mobile application |
| State | Riverpod | Auth-aware and user-keyed application state |
| Routing | `go_router` | Route guards and application navigation |
| HTTP | Dio | Authenticated FastAPI communication and uploads |
| API | Python 3.10+ / FastAPI | Authorization boundary and product API |
| Jobs | Celery | Long-running PDF/AI processing |
| Queue | Redis in Docker | Local Celery broker/result backend |
| Data/Auth | Supabase local | PostgreSQL, Auth, Storage, and RLS |
| PDF parsing | PyMuPDF | Local searchable-text/page extraction |
| AI | Gemini API via `google-genai` | Structured academic extraction |
| Repository | Monorepo | `frontend/`, `backend/`, `supabase/` |

## Trust boundaries

```text
Flutter
  |-- Supabase Auth: sign up, sign in, session
  `-- FastAPI with user JWT: projects, PDFs, processing, results, reviews
         |-- Supabase anon + user JWT: owner-scoped application data
         `-- Celery task through Redis
                |-- Supabase service role: trusted worker operations
                `-- Gemini: document text and structured extraction request
```

Rules:

- Flutter never receives the Gemini key or Supabase service-role key.
- FastAPI authenticates the user before product operations.
- RLS is a second authorization boundary, not an optional convenience.
- The private PDF bucket stays private.
- Only trusted backend/worker code may use service-role access.

## Core data/evidence model

```text
User -> Project -> Paper -> Paper Block (page/content)
                  |       -> Analysis Job
                  `-> Extracted Component -> Evidence Span -> Paper Block
                                           `-> Review Action
```

An extracted component stores the original AI value. A human decision stores a
review action and, when edited, a final value. The application must not silently
overwrite the original AI output.

The primary product promise is traceability:

```text
Result -> Evidence quote -> Source page/block -> Original private PDF
```

## Processing lifecycle

```text
Upload PDF
  -> validate private file
  -> enqueue Celery job
  -> extract searchable text locally
  -> call Gemini with structured schema
  -> verify returned quotes against source blocks
  -> save 11 components as needs_review
  -> human accepts/edits/rejects
  -> paper/project becomes ready when no component remains in review
```

## Status consistency

Changes must preserve agreement among:

- `projects.status`
- `papers.status`
- `analysis_jobs.status` and `stage`
- `extracted_components.status`
- Dashboard metrics
- Project paper counters
- Review queue contents

Do not derive a dashboard value from hardcoded UI state when it belongs to
database-backed user data.

## Architecture decision process

For a proposed stack or trust-boundary change, add a document under
`docs/decisions/NNNN-short-title.md` containing:

- problem and constraints;
- considered options;
- security/data-migration impact;
- cost and operational impact;
- chosen decision and why;
- migration, compatibility, and rollback plan;
- team approval.

Until approved, preserve this architecture.

