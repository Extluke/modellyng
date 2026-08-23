# Modellyng Project Status

Last updated: 2026-08-23

This file is the shared handoff source for the team and coding assistants. It
describes what exists in the repository today and what should be built next.

## Product position

Modellyng is an evidence-centered academic PDF analysis application. The
current state is a working local MVP that can be demonstrated end-to-end. It is
not yet a public production service.

## Implemented baseline

The items below exist in the active application. “Implemented” must not be read
as production approval: direct QA on 2026-08-23 found integrity blockers in
re-analysis and the synthesis views, documented later in this file and in
`docs/QA_REPORT_2026-08-23.md`.

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
- Flutter web running locally on the documented QA port 3000 (port 8082 also
  remains allowed for alternate local sessions).
- End-to-end test of upload -> worker -> Gemini -> 11 review components ->
  human decisions -> ready project.
- Authenticated Structured Paper Result API and responsive Flutter result page.
- Private Evidence PDF Viewer loaded from authenticated bytes; evidence links
  navigate to the verified source page without making the bucket public.
- Review queue grouped by paper with per-paper progress and project filtering.
- Rejection and re-analysis require a reviewer reason; re-analysis creates a
  fresh Celery job and preserves prior AI output/history, but active-version
  selection is defective and currently duplicates the review queue.
- Auditable review history for the 100 latest decisions.
- Comparative Paper Matrix, Concept / Evidence Map, and Research Gap Map have
  working responsive read views and private-evidence navigation. They are
  currently integrity-blocked because rejected/unsupported components are not
  excluded from knowledge results.
- Authenticated project exports in Word, Excel, UTF-8 CSV, and PowerPoint.
  Exports contain ready papers only and preserve reviewed/original AI values,
  status, confidence, evidence quote, page, block ID, and paper ID.
- QA polish for Flutter web: an immediate startup splash replaces the blank
  boot screen, review dialogs show required-field and request failures,
  private PDF preparation has an explicit loading state, desktop navigation
  activates at logical tablet/desktop widths, and account affordances are
  either functional or honestly marked unavailable.

The last verified automated baseline was:

- Backend: 39 tests passing.
- Flutter: static analysis clean and 12 widget tests passing.
- Flutter web release build passing.
- Dependency health: Redis and local Supabase healthy.

Direct browser QA also exercised real login, project creation, two PDF uploads,
worker/Gemini processing, all review actions, all six requested research
features, all four export formats, search/filter, account/privacy, logout, and
mobile/desktop layouts. The UI paths work, but the run identified two P1 data
integrity defects:

1. Re-analysis leaves old `needs_review` rows active, producing duplicated queue
   entries and even negative progress (`-9/11`).
2. Matrix and both Maps accept rejected/unsupported cells; Matrix additionally
   labels every non-edited cell as verified. Exports inherit the Matrix dataset.

Do not call the affected features production-ready until both defects have
regression coverage and have been retested end-to-end.

## Current limitations

- Re-analysis has no reliable active/superseded component version. Historical
  data is correctly retained, but review queue, progress, and readiness can mix
  rows from multiple analysis jobs.
- Matrix, Concept Map, and Research Gap Map do not yet enforce that knowledge
  results must be `verified` or `edited`; rejected/unsupported values can leak
  into synthesis views and export inputs.
- Daily plan/quota values are static (`0 / 5`) rather than backend usage data.
- Initial private-PDF rendering on mobile can take roughly 15–20 seconds after
  the authenticated download completes.
- Account's Audit log shortcut opens Review but does not jump to history, which
  is inconvenient when the queue is long.
- Only PDFs containing searchable text are supported. Scanned/image-only PDFs
  require OCR, which is not implemented yet.
- Gemini free-tier availability and quotas can interrupt analysis.
- The app runs locally; it has no production domain, HTTPS deployment,
  monitoring, automated backups, or production privacy workflow yet.
- The Gemini key previously used during development must be rotated before a
  public demonstration. Never copy a key into this document or Git.
- Exact quote highlighting inside the PDF is not implemented; navigation is
  currently page-level.
- Review history is read-only and limited to the latest 100 decisions.
- Matrix and map currently include ready papers only. The map reflects the
  reviewed academic components; semantic merging of equivalent concepts across
  differently worded papers is not implemented yet.
- Research Gap Map deliberately does not invent or automatically finalize a
  cross-paper gap. It maps reviewed limitations/future work verbatim as
  candidates; researchers must validate and synthesize them.
- Worker startup now rejects missing Supabase service-role configuration before
  creating a stuck job. Transient Gemini quota/high-demand responses use
  bounded exponential retries and persist an honest retry/failure stage.

## Completed feature — Structured Paper Result + Evidence PDF Viewer

**Structured Paper Result + Evidence PDF Viewer** is complete for the first
vertical slice.

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

## Implemented but QA-blocked — Comparative Matrix + Concept / Evidence + Research Gap Maps

The comparative matrix and evidence map are implemented as evidence-preserving
read views. Matrix cells show values with their supporting evidence.
The map exposes paper -> concept -> evidence chains, and evidence actions open
the authenticated paper result/PDF viewer on the claimed page. Both features
provide responsive mobile and desktop layouts and explicit empty states.
Research Gap Map adds filterable candidate chains sourced from `limitations`
and `future_work` components. Each supported candidate retains
its link to the source paper, evidence quote, and authenticated PDF page, and
the interface clearly warns that candidates are not automatic conclusions.
The backend must still filter all three views to `verified`/`edited`; the current
code can include rejected/unsupported cells and must not be treated as final
research synthesis.

## Current priority — Data integrity fixes

Before any new feature, fix active-version selection for re-analysis while
preserving history, then exclude rejected/unsupported rows from Matrix and both
Maps. Add tests proving repeated re-analysis leaves exactly 11 active parameters,
progress stays within 0–11, readiness uses only the active set, and rejected or
unsupported values never become knowledge nodes/candidates. Only after those
tests and direct browser retest should Review UX refinements resume.

## Completed feature — Evidence-preserving result export

Users can open a project and export all ready-paper results as `.docx`, `.xlsx`,
UTF-8 `.csv`, or `.pptx`. Generation happens behind the authenticated FastAPI
boundary, reusing the owner-scoped comparative result query. Every artifact
distinguishes the reviewed value from the original AI value and retains paper,
page, block, status, confidence, and quote provenance. Projects without a ready
paper receive an explicit action message instead of an empty or fabricated file.
Package generation and download passed direct QA, but the exported dataset
inherits the Matrix status-filter defect; consumers must inspect `status` until
the verified/edited-only synthesis rule is implemented and retested.

## Planned backlog

1. P0: re-analysis active/superseded versioning and regression tests.
2. P0: verified/edited-only synthesis and accurate Matrix status rendering.
3. Review UX follow-up: parameter/status filters, paginated history, and safe
   bulk actions.
4. Real plan/quota enforcement and usage reporting.
5. PDF render feedback/timeout and direct Audit log navigation.
6. Human-curated cross-paper gap synthesis and explicit candidate decisions.
7. OCR for scanned PDFs with an explicit OCR-quality review step.
8. Production privacy, deletion/retention policy, monitoring, backups,
   rate-limiting, and public pilot deployment.

## Local service map

| Service | Local address |
|---|---|
| Flutter web | `http://127.0.0.1:3000` (recommended QA port; 8082 is also allowed) |
| FastAPI | `http://127.0.0.1:8000` |
| FastAPI health | `http://127.0.0.1:8000/health/dependencies` |
| Supabase API | `http://127.0.0.1:54321` |
| Redis | `127.0.0.1:6380` |

Operational startup instructions are maintained in the root `README.md`.

