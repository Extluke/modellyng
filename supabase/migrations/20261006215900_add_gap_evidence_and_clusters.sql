-- Migration to add clusters and gap evidence for Knowledge Graph

ALTER TABLE knowledge_graph_nodes ADD COLUMN IF NOT EXISTS method_cluster TEXT;
ALTER TABLE knowledge_graph_nodes ADD COLUMN IF NOT EXISTS object_cluster TEXT;
ALTER TABLE knowledge_graph_nodes ADD COLUMN IF NOT EXISTS validation_status TEXT DEFAULT 'pending';

CREATE TABLE IF NOT EXISTS gap_evidence (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    gap_node_id UUID NOT NULL REFERENCES knowledge_graph_nodes(id) ON DELETE CASCADE,
    paper_id UUID NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
    section TEXT,
    quote TEXT NOT NULL,
    page_number INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE gap_evidence ENABLE ROW LEVEL SECURITY;

-- Policies for gap_evidence
CREATE POLICY "Users can select gap_evidence" ON gap_evidence
    FOR SELECT USING (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );

CREATE POLICY "Users can insert gap_evidence" ON gap_evidence
    FOR INSERT WITH CHECK (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );

CREATE POLICY "Users can update gap_evidence" ON gap_evidence
    FOR UPDATE USING (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );

CREATE POLICY "Users can delete gap_evidence" ON gap_evidence
    FOR DELETE USING (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );
