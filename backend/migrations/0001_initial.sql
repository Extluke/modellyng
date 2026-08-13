CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TYPE project_status AS ENUM ('ready', 'processing', 'needs_review');
CREATE TYPE paper_status AS ENUM ('validating', 'ready', 'processing', 'needs_review', 'failed');
CREATE TYPE job_status AS ENUM ('queued', 'processing', 'completed', 'failed', 'cancelled');
CREATE TYPE verification_status AS ENUM ('needs_review', 'verified', 'edited', 'unsupported', 'rejected');

CREATE TABLE projects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id uuid NOT NULL,
    organization_id uuid,
    title varchar(180) NOT NULL,
    description text NOT NULL DEFAULT '',
    status project_status NOT NULL DEFAULT 'ready',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE papers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    storage_key text,
    original_filename varchar(255),
    title text,
    authors jsonb NOT NULL DEFAULT '[]'::jsonb,
    publication_year integer,
    journal text,
    doi text,
    status paper_status NOT NULL DEFAULT 'validating',
    metadata_verified boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT paper_has_source CHECK (storage_key IS NOT NULL OR doi IS NOT NULL)
);

CREATE TABLE paper_blocks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    paper_id uuid NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
    block_index integer NOT NULL,
    page_number integer NOT NULL CHECK (page_number > 0),
    section text,
    subsection text,
    content text NOT NULL,
    bounding_box jsonb,
    embedding vector,
    UNIQUE (paper_id, block_index)
);

CREATE TABLE analysis_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    status job_status NOT NULL DEFAULT 'queued',
    stage text NOT NULL DEFAULT 'queued',
    progress numeric(5,4) NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 1),
    parameters jsonb NOT NULL,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE extracted_components (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    paper_id uuid NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
    analysis_job_id uuid NOT NULL REFERENCES analysis_jobs(id) ON DELETE CASCADE,
    parameter varchar(80) NOT NULL,
    ai_value text NOT NULL,
    final_value text,
    status verification_status NOT NULL DEFAULT 'needs_review',
    confidence numeric(5,4) CHECK (confidence BETWEEN 0 AND 1),
    model_name text NOT NULL,
    prompt_version text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE evidence_spans (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    component_id uuid NOT NULL REFERENCES extracted_components(id) ON DELETE CASCADE,
    paper_block_id uuid NOT NULL REFERENCES paper_blocks(id) ON DELETE RESTRICT,
    quote text NOT NULL,
    page_number integer NOT NULL CHECK (page_number > 0),
    section text,
    subsection text,
    bounding_box jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE review_actions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    component_id uuid NOT NULL REFERENCES extracted_components(id) ON DELETE CASCADE,
    reviewer_id uuid NOT NULL,
    action varchar(40) NOT NULL CHECK (action IN ('accept', 'edit', 'reject', 'request_reanalysis')),
    original_ai_value text NOT NULL,
    corrected_value text,
    note text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX papers_project_idx ON papers(project_id);
CREATE INDEX paper_blocks_paper_page_idx ON paper_blocks(paper_id, page_number);
CREATE INDEX analysis_jobs_project_status_idx ON analysis_jobs(project_id, status);
CREATE INDEX extracted_components_paper_status_idx ON extracted_components(paper_id, status);
CREATE INDEX evidence_component_idx ON evidence_spans(component_id);
