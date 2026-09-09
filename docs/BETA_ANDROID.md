# Modellyng Android beta — supervised computer-hosted pilot

This pilot keeps Flutter, FastAPI, Celery/Redis and private local Supabase.
It incurs no hosting rental. Electricity, internet, Gemini free quotas and
Cloudflare Quick Tunnel restrictions still apply. It is not a permanent public
service or a 24/7 availability commitment.

## Android artifact

- Application ID: `id.modellyng.beta`.
- Version: `0.1.0-beta.1`, version code `1`.
- Universal APK build 2 built on 2026-09-08:
  `output/beta/modellyng-0.1.0-beta.1-2.apk` (76,637,384 bytes / 73.1 MiB).
- Android 7.0+ (minimum API 24), target API 36; ARM64, ARMv7 and x86_64.
- SHA-256: `40ebeb3ec3abddf9d6cd5a9dd7f8446626d6805802135b5b46ff12c641470f24`.
- SHA-256 sidecar sits beside the APK. Share the APK only, never signing files,
  backend configuration, logs, database backups, or research PDFs.
- Dedicated RSA release signing, no debug signing fallback. Back up the signing
  directory privately at `%USERPROFILE%/.modellyng/signing`. Losing the key
  prevents updates to the installed application with this application ID.
- Android internet permission and HTTPS-only transport are explicit. Native
  exports use the document picker without broad storage permission.

Install the APK on Android by allowing installation from the app that opens
the APK. Register/sign in while the beta server is running. Use only public,
non-confidential documents that may be processed by the AI provider. Gemini
unpaid input/output may be used for product improvement and human review.

## Start the supervised beta

Start Docker Desktop first. From the repository root, using PowerShell:

```powershell
docker compose up -d
supabase start
supabase db push --local
.\backend\.venv\Scripts\python.exe backend/beta_runtime.py
.\scripts\Build-BetaApk.ps1 -BuildNumber 1
```

`supabase start` can display local credentials: never share its raw output.
The runtime launcher reads private keys from `backend/.env` and reads the local
Supabase port from `supabase/config.toml`. It overrides the backend Supabase URL
for its child processes, leaving the existing `.env` unchanged. It produces
`.tool-state/beta/client.json` containing only HTTPS URLs and the anonymous
client key. The APK build validates this config and the public gateway first.

Windows reserved ports 54293–54392 on the verified machine. Supabase therefore
uses API **18021**, database **18022**, Studio **18023**, mail viewer **18024**,
analytics **18027**, shadow database **18020** and optional pooler **18029**.
Existing persistent volumes and the project ID `modellying` were preserved.
For manual API/worker commands, set:

```powershell
$env:MODELLYNG_SUPABASE_URL = 'http://127.0.0.1:18021'
```

Runtime processes/log locations are recorded in `.tool-state/beta/`. API is
loopback port 8000; restricted gateway is loopback port 8001. Only the gateway
is exposed through the tunnel. Do not forward router ports to Supabase, Studio,
PostgreSQL, Redis, or the development API.

Keep the computer awake, online, and all runtime processes running throughout
the test session. These processes are not installed as boot services. The
launcher refuses to create duplicate servers on occupied ports.

On this 8 GB RAM computer, optional local Studio, metadata, analytics, realtime,
edge-runtime and vector containers were stopped during the build. The beta uses
the running database, Auth, REST, private Storage and Redis services. Running
`supabase start` again may also restart the optional services and increase RAM
usage; they are not required for this beta's application flows.

## Endpoint lifetime and connectivity

Cloudflare Quick Tunnel assigns a new hostname when restarted. An earlier
tunnel expired during this task. **If the tunnel stops or its hostname changes,
the existing APK cannot reconnect to a different hostname automatically.**
Start a new supervised session, rebuild with a higher build number, and share
the replacement APK signed by the same key. There is no silent background
deployment or permanent domain in this pilot.

The operator's normal DNS returned NXDOMAIN for fresh tunnel hostnames. Public
resolvers may also disagree while negative answers remain cached. Build/QA
preflight tries Google and Cloudflare DNS-over-HTTPS and can use resolved IPs with
`curl --resolve`, retaining certificate and hostname verification. The APK uses
normal device DNS; connectivity must be checked on each tester's network.
No TLS verification was disabled.

## Restricted ingress and limits

- `/api/v1/` remains authenticated and owner-scoped through FastAPI and RLS.
- Only signup, password/refresh-token login, user, logout, health and settings
  are exposed from Supabase Auth. Admin, Storage REST, Data REST, Studio, docs
  and detailed dependency diagnostics are not publicly routed.
- A Redis record of the hash of an actually issued login token is required at
  ingress. This adds protection around a local Supabase installation; it does
  not replace GoTrue JWT validation or database/storage RLS.
- Redis failure fails closed. Logout removes the current ingress session.
- Shared daily request limits: **20 analysis/upload/re-analysis attempts** and
  **50 chat attempts**, reset at UTC midnight (07:00 WIB). Invalid/failed
  attempts may count. These are not guaranteed Gemini provider allowances.
- HTTP and authentication burst limits are enforced through Redis counters.
- One Celery worker processes jobs sequentially; each PDF retains the 50 MB limit.
- Only searchable-text PDFs are supported. Human review remains required.

Gemini extraction sends a compact JSON grammar and validates the response with
the full Pydantic constraints afterwards. Bounds are not relaxed for persisted
data or evidence. Provider connection failures/timeouts use bounded job retries.

## Verification and remaining release limits

- `20260907090000_source_traceability.sql` applied successfully to the preserved
  local database. The transactional two-account RLS SQL test passed and rolled
  back its fixtures.
- A real HTTPS smoke test registered two test accounts, created a project,
  uploaded/downloaded a synthetic PDF, denied cross-account access, processed
  it through Celery/Gemini into 11 review components, and checked logout.
- The full backend suite passed 102 tests; Flutter passed 36 tests. Flutter
  static analysis and the release web build also passed. The final extraction
  schema correction was rechecked with the targeted backend regression tests.
- The signed release APK passed `apksigner verify` (RSA 3072, APK signature v2),
  ZIP alignment and all bundled 64-bit native-library 16 KB load-alignment
  checks. Package metadata and Android internet permission were inspected.
- Decompressed APK contents include the intended HTTPS endpoint and contain
  neither configured backend credential (Gemini/service-role), private `.env`,
  signing keystore nor `key.properties`. The ignored artifact directory contains
  `verification.json` with the hash and inspection results.
- Browser QA checked the beta welcome/login screens at 390 px mobile and
  1280 px desktop widths. The beta notice, login fields and navigation fit.
  Synthetic live test projects, users and PDFs were removed after testing;
  existing user data was preserved. Public HTTPS health and Celery ping passed
  the final runtime check.
- No Android device/emulator was connected during the initial checks. APK
  signing/package inspection is not a replacement for an on-device smoke test
  of login, upload, PDF viewing, native save and resume.
- Account deletion/retention automation, comprehensive backups, monitoring,
  durable public addressing and recovery from every worker/network failure
  remain outstanding. Keep participation supervised and limited.
- The development Gemini key rotation noted in PROJECT_STATUS remains an
  operator step before broader distribution; no billing account was enabled.

References: [Flutter Android release](https://docs.flutter.dev/deployment/android),
[Quick Tunnel limitations](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/),
[Gemini unpaid terms](https://ai.google.dev/gemini-api/terms).
