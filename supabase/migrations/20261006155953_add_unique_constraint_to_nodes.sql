-- Add unique constraint to avoid duplicate nodes per project
ALTER TABLE knowledge_graph_nodes 
    ADD CONSTRAINT knowledge_graph_nodes_project_id_node_type_label_key 
    UNIQUE (project_id, node_type, label);
