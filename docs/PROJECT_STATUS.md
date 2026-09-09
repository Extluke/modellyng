# Modellyng Project Status

Last updated: 2026-09-09

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

## Completed — Signed Android build for supervised beta (2026-09-08)

- Signed universal release APK build 2: `output/beta/modellyng-0.1.0-beta.1-2.apk`,
  application ID `id.modellyng.beta`, Android 7.0+, version `0.1.0-beta.1` (1).
- Flutter connects through a temporary HTTPS tunnel to a restricted FastAPI
  gateway on this computer. Supabase, private storage, Redis/Celery and backend
  Gemini integration remain in the existing architecture. Native exports use
  the Android document picker; the signing key is kept outside the repository.
- Verification: 102 backend tests, 36 Flutter tests, clean Flutter analysis,
  release web build, signed APK validation and 16 KB native alignment passed.
  Public HTTPS two-account isolation and the real worker/Gemini extraction flow
  passed; browser login layouts were checked at mobile and desktop widths.
- No configured Gemini/service-role credential or private signing/config file
  was found in the decompressed APK. Generated artifacts and local runtime
  configuration remain ignored by Git. See `docs/BETA_ANDROID.md` for operation,
  exact artifact checks and the remaining pilot limits.

## Current limitations

- iOS beta preparation (2026-09-08): the existing Runner project now uses the
  proposed `id.modellyng.beta` identifier and `Modellyng Beta` display name.
  The build attempt is blocked by the Windows-only host; no IPA, Apple signing
  configuration or iPhone validation exists. See `docs/BETA_IOS.md` for the Mac
  handoff, required numeric version, remaining icon work and signing steps.

- Android supervised beta work is described in `docs/BETA_ANDROID.md`. Public
  HTTPS login, private uploads/downloads, two-account isolation, Celery/Gemini
  extraction into 11 review components, and logout passed a live synthetic
  fixture test. This is a temporary computer-hosted beta, not a permanent public
  service. Quick Tunnel URLs can expire and require a rebuilt APK. Native-device
  testing and the previously required Gemini key rotation remain pending.

- The 2026-09-07 source-traceability migration
  `20260907090000_source_traceability.sql` was applied on 2026-09-08. Live
  two-account RLS verification passed. Docker recovered after preserving stale
  socket directories; Windows-reserved ports required moving local Supabase to
  ports 18021–18027. See
  `docs/SOURCE_TRACEABILITY_AUDIT.md` for the six-diagram audit and test evidence.

- The beta gateway enforces shared request quotas. The UI no longer presents a
  fabricated `0 / 5` counter; live remaining-quota display is still pending.
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
- Result evidence clicks now request quote highlighting on the verified PDF
  page. Text matching is best-effort; the viewer reports when it cannot locate
  the quote and retains page-level navigation.
- Review history is read-only and limited to the latest 100 decisions.
- Matrix and map currently include ready papers only. The map reflects the
  reviewed academic components; cross-paper comparison now uses the ordered
  workflow described below and does not claim a confirmed novel gap.
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

## Completed — Ordered cross-paper comparison and research-gap candidates (2026-09-09)

Ready papers in one project can now be compared as independent unordered pairs.
Each pair follows the same auditable order: concept, variables, data/object,
method, then research problem. A `Yes` advances the pair; the first `No`
stops that pair and creates a candidate only for a later aspect. A concept `No`
is classified as unrelated, while missing or invalid evidence is classified as
insufficient and never becomes a gap. Other pairs continue independently.

The backend builds each source snapshot from active `verified`/`edited`
components and evidence whose quote and page still match the private PDF block.
Gemini may propose a prefix of decisions, but deterministic validation owns the
order, stopping rule, allowed evidence references, and outcome. The worker only
writes through service-role paths; the authenticated API can schedule and read
owner-scoped work but cannot forge results. Input hashes preserve completed
results for unchanged pairs and invalidate only pairs touching changed sources.

The Flutter Maps and Comparative Matrix screens share the same pair result.
The flowchart displays `Yes`, `No`, and stopped branches; the matrix provides a
compact cross-paper view. Each step expands to both paper evidence and opens the
authenticated PDF page. Candidates require a reviewer decision and a mandatory
explanation; the UI states that acceptance means “layak ditelusuri”, not proof of
novelty. The old single-paper limitations/future-work map remains available as
an additional evidence view.

Migration: `supabase/migrations/20260909090000_cross_paper_comparisons.sql`.
The migration includes owner RLS, service-role worker leases, stale-result
invalidation, append-only review history, and a two-account SQL isolation test.
The feature was verified with synthetic private PDFs through the real FastAPI,
Celery, Redis, local Supabase, and Gemini path: the household example reached
`concept=yes`, `variables=yes`, `data_object=no`, stopped before method, and
blocked the second account from reading/reviewing the pair or its PDF.

## Completed — Intelligence report, references, and personalization (2026-09-09)

The Matrix now exposes an owner-scoped intelligence report that combines the
existing reviewed values and evidence chain without inventing metadata. It
provides APA 7, IEEE, Harvard, Vancouver, and Chicago bibliography entries,
paper identity plus compressed research structure, relationship edges from
paper to component/result/evidence, deterministic topic/concept/method
clusters, explicit unsupported-claim items, comparison/gap counts, and a
candidate-only synthesis. Unsupported or evidence-less active components stay
visible for human review instead of being silently included in the matrix.

The report is available at `GET /api/v1/projects/{project_id}/intelligence-report`
and as an evidence-preserving JSON download at
`GET /api/v1/projects/{project_id}/intelligence-report.json`; its citation style
is selectable in the Matrix UI. Account preferences are
persisted in the owner profile through `GET/PUT /api/v1/account/settings`;
the migration is `20260909120000_account_preferences.sql`. This completes the
requested reference, traceability-report, structural-analysis, cluster, and
personalization layer while preserving RLS and private-PDF provenance.

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

## Implemented — Paper/source verification and typed evidence (2026-09-07)

The result screen now includes a bibliographic validation panel with a manual
DOI check against Crossref and a DataCite fallback. Every metadata field retains
separate paper and registry values, provider URLs, unavailable/mismatch states,
and a timestamped snapshot. Authenticated reviewers append Accept/Reject
decisions with required notes. These decisions do not automatically finalize AI
claims or change paper/project readiness. Reports and reviews use owner-scoped
RLS tables; only the DOI is sent to the public registries.

Publisher, volume, issue, publication pages and publication status are carried
through the worker, API and Flutter models. Evidence supports text, table,
figure, equation and result kinds, literal object labels and section/subsection
locations derived from searchable source text. Unsupported labels are dropped;
unsupported quotes are still discarded. All eleven result components now retain
their own evidence cards, including question and methodology alongside their
existing tables. Existing evidence remains readable without fabricated backfill.

This is bibliographic/source traceability with human review, not an automatic
authenticity, journal-quality, image-understanding or retraction certification.
Initial verification: 95 backend tests and 31 Flutter tests passed; Flutter
analysis was clean and the main web release build succeeded. The new panel also
passed browser QA with synthetic fixtures at desktop/mobile widths. The Docker
startup blocker was resolved on 2026-09-08: the live migration and transactional
two-account RLS tests passed. Updated beta verification is recorded above.
The full mapping, remaining limits and migration steps are maintained in
`docs/SOURCE_TRACEABILITY_AUDIT.md`.

## Planned backlog

1. Direct browser regression of the 2026-08-25 visual workflow once a fresh
   controllable browser tab is available.
2. Review UX follow-up: parameter/status filters, paginated history, and safe
   bulk actions.
3. Real plan/quota enforcement and usage reporting.
4. PDF render feedback/timeout and direct Audit log navigation.
5. Human-curated synthesis across accepted gap candidates (the current report
   remains deterministic and candidate-only).
6. OCR for scanned PDFs with an explicit OCR-quality review step.
7. Production privacy, deletion/retention policy, monitoring, backups,
   rate-limiting, and public pilot deployment.

## Local service map

| Service | Local address |
|---|---|
| Flutter web | `http://127.0.0.1:3000` (recommended QA port; 8082 is also allowed) |
| FastAPI | `http://127.0.0.1:8000` |
| FastAPI health | `http://127.0.0.1:8000/health/dependencies` |
| Supabase API | `http://127.0.0.1:18021` |
| Redis | `127.0.0.1:6380` |

Operational startup instructions are maintained in the root `README.md`.

