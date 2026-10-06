-- Migration for Knowledge Graph Epic

CREATE TABLE IF NOT EXISTS knowledge_graph_nodes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    node_type TEXT NOT NULL,
    label TEXT NOT NULL,
    detail TEXT,
    parent_id UUID REFERENCES knowledge_graph_nodes(id) ON DELETE CASCADE,
    gap_typology TEXT,
    saturation_status TEXT,
    confidence_score NUMERIC(5,2),
    zone_category TEXT,
    x NUMERIC(10,4),
    y NUMERIC(10,4),
    evidence JSONB DEFAULT '[]'::jsonb,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS knowledge_graph_edges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    source_id UUID NOT NULL REFERENCES knowledge_graph_nodes(id) ON DELETE CASCADE,
    target_id UUID NOT NULL REFERENCES knowledge_graph_nodes(id) ON DELETE CASCADE,
    relation TEXT NOT NULL,
    detail TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE knowledge_graph_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_graph_edges ENABLE ROW LEVEL SECURITY;

-- Policies for nodes
CREATE POLICY "Users can select project nodes" ON knowledge_graph_nodes
    FOR SELECT USING (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );

CREATE POLICY "Users can insert project nodes" ON knowledge_graph_nodes
    FOR INSERT WITH CHECK (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );

CREATE POLICY "Users can update project nodes" ON knowledge_graph_nodes
    FOR UPDATE USING (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );

CREATE POLICY "Users can delete project nodes" ON knowledge_graph_nodes
    FOR DELETE USING (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );

-- Policies for edges
CREATE POLICY "Users can select project edges" ON knowledge_graph_edges
    FOR SELECT USING (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );

CREATE POLICY "Users can insert project edges" ON knowledge_graph_edges
    FOR INSERT WITH CHECK (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );

CREATE POLICY "Users can update project edges" ON knowledge_graph_edges
    FOR UPDATE USING (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );

CREATE POLICY "Users can delete project edges" ON knowledge_graph_edges
    FOR DELETE USING (
        project_id IN (SELECT id FROM projects WHERE owner_id = auth.uid())
    );
