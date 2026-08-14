# Modellyng Project Status

Last updated: 2026-08-14

This file is the shared handoff source for the team and coding assistants. It
describes what exists in the repository today and what should be built next.

## Product position

Modellyng is an evidence-centered academic PDF analysis application. The
current state is a working local MVP that can be demonstrated end-to-end. It is
not yet a public production service.

## Completed and verified

- Supabase local registration, login, and session handling.
- Per-user project isolation through authenticated API requests and RLS.
- Project creation and project dashboard.
- Private PDF upload with validation and a 50 MB limit.
- Asynchronous processing through Celery and local Redis.
- Searchable-text extraction, page count, basic metadata, and language
  detection through PyMuPDF.
- Gemini structured extraction through the backend worker.
- Eleven academic parameters:
  `research_problem`, `research_objective`, `research_question`,
  `methodology`, `dataset_sample`, `variables_concepts`, `results_findings`,
  `contribution`, `limitations`, `future_work`, and `key_claims`.
- Server-side verification that every stored evidence quote exists in a source
  paper block on the claimed page.
- Human Review queue with Accept, Edit, and Reject actions.
- Paper/project status transition from processing to review and back to ready
  after the review queue is complete.
- Dynamic dashboard totals for papers, projects, papers waiting for review,
  and verified/edited knowledge nodes.
- Flutter web release running locally on port 8082.
- End-to-end test of upload -> worker -> Gemini -> 11 review components ->
  human decisions -> ready project.

The last verified automated baseline was:

- Backend: 13 tests passing.
- Flutter: static analysis clean and 4 widget tests passing.
- Flutter web release build passing.
- Dependency health: Redis and local Supabase healthy.

## Current limitations

- Only PDFs containing searchable text are supported. Scanned/image-only PDFs
  require OCR, which is not implemented yet.
- Gemini free-tier availability and quotas can interrupt analysis.
- The app runs locally; it has no production domain, HTTPS deployment,
  monitoring, automated backups, or production privacy workflow yet.
- The Gemini key previously used during development must be rotated before a
  public demonstration. Never copy a key into this document or Git.
- Review results exist, but a dedicated structured result page and integrated
  PDF evidence viewer do not exist yet.

## Next feature — P0

Build **Structured Paper Result + Evidence PDF Viewer**.

### User outcome

From a project, the user can open one processed paper, understand all extracted
academic components in one coherent page, and trace every supported result to
the original private PDF page.

### Required scope

- Add an authenticated paper-result API that returns metadata, all extracted
  components, their final/AI values, status, confidence, and verified evidence.
- Add a paper result screen reachable from the paper card/tile.
- Group and label the eleven academic components consistently with Review.
- Display loading, empty, processing, failed, and success states.
- Display human-edited/final values without deleting the original AI value.
- Add a private PDF viewing path that enforces ownership.
- Allow an evidence item to navigate the viewer to its source page.
- Deliver a responsive layout: side-by-side viewer/result on wide screens and a
  practical stacked/tabbed experience on mobile.
- Reuse the existing theme, repositories, status enums, auth flow, and RLS.
- Add backend authorization tests and Flutter model/widget tests.

### Definition of done

- Account A cannot request or view Account B's result or PDF.
- All eleven components are shown for a completed extraction.
- Each supported evidence item displays its quote and page.
- Clicking evidence opens the correct PDF page.
- AI values, human corrections, and review status remain distinguishable.
- Existing upload, processing, dashboard, and Review flows still pass tests.
- `docs/PROJECT_STATUS.md` and any API documentation are updated.

Highlighting the exact quote inside the PDF is desirable but may be a second
increment after reliable page navigation. Do not block the first slice on
pixel-perfect highlighting.

## Planned backlog after P0

1. Review UX: group by paper, review progress (for example 7/11), filters,
   rejection reasons, history, and safe bulk actions.
2. Comparative matrix across multiple fully reviewed papers.
3. Evidence-backed candidate research-gap generation.
4. Export to Word, Excel/CSV, and presentation-ready reports.
5. OCR for scanned PDFs with an explicit OCR-quality review step.
6. Real plan/quota enforcement and usage reporting.
7. Production privacy, deletion/retention policy, monitoring, backups,
   rate-limiting, and public pilot deployment.

## Local service map

| Service | Local address |
|---|---|
| Flutter web | `http://127.0.0.1:8082` |
| FastAPI | `http://127.0.0.1:8000` |
| FastAPI health | `http://127.0.0.1:8000/health/dependencies` |
| Supabase API | `http://127.0.0.1:54321` |
| Redis | `127.0.0.1:6380` |

Operational startup instructions are maintained in the root `README.md`.

