# Modellyng Project Status

Last updated: 2026-09-02

This file is the shared handoff source for the team and coding assistants. It
describes what exists in the repository today and what should be built next.

## Product position

Modellyng is an evidence-centered academic PDF analysis application. The
current state is a working local MVP that can be demonstrated end-to-end. It is
not yet a public production service.

## Implemented baseline

The items below exist in the active application. “Implemented” must not be read
as public-production approval. The 2026-08-25 iteration resolved the two data
integrity blockers found on 2026-08-23 and added a visual research workflow;
verification is recorded in `docs/QA_REPORT_2026-08-25.md`.

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
- Human Review queue includes a confirmed “Terima semua” action for the
  currently visible project filter. The owner-scoped batch is transactional,
  accepts only active pending components, preserves audit actions, and updates
  paper/project readiness atomically.
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
  fresh Celery job, preserves prior AI output/history, and atomically promotes
  only the completed result set as the active version.
- Auditable review history for the 100 latest decisions.
- Comparative Paper Matrix, Concept / Evidence Map, and Research Gap Map use
  only active `verified`/`edited` components. Matrix displays every ready paper
  in one horizontally scrollable comparison table on desktop and mobile.
- Concept / Evidence Map converts its owner-scoped graph JSON into sanitized
  Mermaid flowchart syntax in Flutter and renders it immediately with the
  native `flutter_mermaid` painter. Paper, concept, and evidence nodes are
  visually distinct; the diagram supports pan/zoom, and concept/evidence taps
  preserve navigation to the structured result or authenticated PDF page.
- Structured Paper Result adds a research-question table that aligns each
  question with its object/concept and discussion direction, plus a five-column
  methodology table (`isi`, `bentuk`, `kegiatan utama`, `arah kegiatan`, and
  `tujuan akhir`). Both tables can be downloaded as an authenticated PDF.
- Project-scoped RAG chatbot retrieves owner-scoped `paper_blocks` directly
  after searchable-text extraction, including papers still awaiting human
  review. It returns private PDF page sources, blocks unrelated questions
  before provider invocation, rejects generated answers without a valid
  retrieved citation, treats paper text as untrusted data, and uses bounded
  provider timeouts.
- Project chat exchanges are persisted permanently in an owner-scoped,
  RLS-protected message table. Reopening a project restores user questions,
  validated AI answers, citation metadata, page numbers, quotes, and block IDs.
- Chat citations open the authenticated private PDF on the cited page and use
  the source quote to highlight the supporting text. Whitespace and punctuation
  differences between server extraction and viewer text are tolerated; if an
  exact text range cannot be matched, page navigation still succeeds and the
  viewer reports the limitation honestly.
- Private-PDF cold-start work is moved off the evidence-click path: PDFium is
  initialized concurrently during app bootstrap, up to two cited PDFs are
  prefetched after a chat answer, authenticated PDF bytes are retained in a
  bounded 10-minute in-memory cache, and citation matching extracts/searches
  only the known source page instead of scanning every page.
- Chat citations now bypass full-document PDFium startup entirely: the
  authenticated backend authorizes the owner once, fetches the cited block and
  private PDF concurrently, and renders only the cited page as a highlighted
  PNG. Full PDF viewing remains available for non-chat evidence navigation.
- Research Gap Map now provides a persisted, owner-scoped Yes/No decision flow:
  paper -> candidate -> evidence -> decision -> next research action.
- Authenticated project exports in Word, Excel, UTF-8 CSV, and PowerPoint.
  Exports contain ready papers only and preserve reviewed/original AI values,
  status, confidence, evidence quote, page, block ID, and paper ID.
- QA polish for Flutter web: an immediate startup splash replaces the blank
  boot screen, review dialogs show required-field and request failures,
  private PDF preparation has an explicit loading state, desktop navigation
  activates at logical tablet/desktop widths, and account affordances are
  either functional or honestly marked unavailable.

The last verified automated baseline was (2026-08-30):

- Backend: 62 tests passing, including grounded-chat refusal, citation guards,
  and transactional bulk-review validation.
- Flutter: static analysis clean and 23 widget/unit tests passing.
- Flutter web release build passing.
- Dependency health: Redis, Celery, FastAPI, and local Supabase healthy.

Direct browser QA on 2026-08-23 exercised real login, project creation, two PDF uploads,
worker/Gemini processing, all review actions, all six requested research
features, all four export formats, search/filter, account/privacy, logout, and
mobile/desktop layouts. On 2026-08-25 an authenticated live smoke test used the
same QA account and real project data to verify active-version selection,
verified/edited-only Matrix data, both gap-decision branches, structured PDF
download, and an evidence-linked chatbot response. Browser-control QA for this
iteration could not be repeated because the in-app browser was locked on its
internal connection-error URL and its security policy rejected navigation;
responsive click behavior is covered by 15 Flutter widget tests instead.

On 2026-09-02, direct browser QA rendered the production Mermaid flowchart
widget with representative graph JSON at desktop and 390 px mobile widths.
Styled paper/concept/evidence nodes, responsive compact labels, pan, wheel
zoom, and node-tap callbacks all worked without overflow or console errors.
An authenticated full-stack replay could not run because Docker Desktop failed
before local Supabase/API startup on a stale Windows AF_UNIX runtime socket;
the renderer itself was exercised through a temporary QA entrypoint that was
removed immediately after testing.

## Current limitations

- Daily plan/quota values are static (`0 / 5`) rather than backend usage data.
- Initial private-PDF rendering on mobile can take roughly 15–20 seconds after
  the authenticated download completes.
- Account's Audit log shortcut opens Review but does not jump to history, which
  is inconvenient when the queue is long.
- Only PDFs containing searchable text are supported. Scanned/image-only PDFs
  require OCR, which is not implemented yet.
- Gemini free-tier availability and quotas can interrupt analysis.
- Chatbot responses depend on Gemini availability. Requests are bounded to two
  short provider attempts and fail honestly instead of spinning indefinitely.
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

## Completed — Comparative Matrix + Concept / Evidence + Research Gap Maps

The comparative matrix and evidence map are implemented as evidence-preserving
read views. Matrix cells show values with their supporting evidence.
The map exposes paper -> concept -> evidence chains as a responsive Mermaid
flowchart generated from backend JSON. Rendering stays in Flutter without a
WebView or a second AI call; generated node IDs and sanitized bounded labels
prevent paper text from becoming Mermaid instructions. Pan/zoom is available,
and evidence actions open the authenticated paper result/PDF viewer on the
claimed page. Both features provide responsive mobile and desktop layouts and
explicit empty states.
Research Gap Map adds filterable candidate chains sourced from `limitations`
and `future_work` components. Each supported candidate retains
its link to the source paper, evidence quote, and authenticated PDF page, and
the interface clearly warns that candidates are not automatic conclusions.
The backend filters all three views to the single active component version and
to `verified`/`edited` status. Gap candidates remain human-reviewable rather
than being promoted to research conclusions automatically.

## Completed — Visual research workflow and project chatbot

Research-question and methodology outputs now have dedicated tabular views and
an authenticated PDF download. Narrative list-like values render as readable
bullets. The mobile Matrix no longer hides other papers behind a selector: one
combined table contains every paper. Research Gap candidates have persisted
Yes/No choices and an explicit next-step flow. The project chatbot retrieves
searches extracted private-PDF text and returns source links to the supporting
pages. Human review remains required for structured extraction outputs, while
chat explicitly refuses questions whose terms cannot be grounded in the PDFs.

## Completed feature — Evidence-preserving result export

Users can open a project and export all ready-paper results as `.docx`, `.xlsx`,
UTF-8 `.csv`, or `.pptx`. Generation happens behind the authenticated FastAPI
boundary, reusing the owner-scoped comparative result query. Every artifact
distinguishes the reviewed value from the original AI value and retains paper,
page, block, status, confidence, and quote provenance. Projects without a ready
paper receive an explicit action message instead of an empty or fabricated file.
Package generation and download passed direct QA, but the exported dataset
now inherits the Matrix active-version and `verified`/`edited` filters, so
rejected, unsupported, and superseded components are excluded.

## Planned backlog

1. Direct browser regression of the 2026-08-25 visual workflow once a fresh
   controllable browser tab is available.
2. Review UX follow-up: parameter/status filters, paginated history, and safe
   bulk actions.
3. Real plan/quota enforcement and usage reporting.
4. PDF render feedback/timeout and direct Audit log navigation.
5. Human-curated synthesis across accepted gap candidates.
6. OCR for scanned PDFs with an explicit OCR-quality review step.
7. Production privacy, deletion/retention policy, monitoring, backups,
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

