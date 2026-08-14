# ADR 0001: Preserve the MVP Architecture

- Status: Accepted
- Date: 2026-08-14
- Decision owners: Modellyng product team

## Context

Modellyng has a tested local vertical slice covering authentication, private
PDF upload, asynchronous processing, Gemini structured extraction, verified
evidence, human review, and dashboard metrics. A new developer or coding
assistant rebuilding a layer with a different framework would create duplicate
systems, break the evidence/security model, and delay product validation.

## Decision

Continue with the implemented monorepo and technology choices:

- Flutter, Riverpod, `go_router`, and Dio;
- FastAPI on Python;
- Celery with Redis;
- Supabase PostgreSQL, Auth, private Storage, and RLS;
- PyMuPDF for local text/page extraction;
- Gemini called only from the backend/worker.

The team will extend the existing repositories, schemas, migrations, UI theme,
and tests. Ordinary feature work must not replace these foundations.

## Consequences

- New contributors must first understand the current implementation.
- Stack changes require a new approved ADR with migration and rollback plans.
- Security boundaries, evidence traceability, and human review remain design
  constraints for every feature.
- Short-term feature delivery is prioritized over broad architectural rewrites.

## Reconsider when

A production requirement cannot be met safely or economically by the current
stack, and the team has measured evidence, an incremental migration path, a
data/security impact analysis, and a rollback plan.

