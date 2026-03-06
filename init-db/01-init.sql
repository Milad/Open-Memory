CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS memory_nodes (
    id SERIAL PRIMARY KEY,
    content TEXT NOT NULL,
    metadata JSONB,
    -- Keep this in sync with PGAI_VECTORIZER_DIMS (default 1024 for voyage-3)
    embedding vector(1024),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- HNSW index for lightning-fast retrieval as your memory grows
CREATE INDEX IF NOT EXISTS memory_nodes_embedding_hnsw_idx
    ON memory_nodes USING hnsw (embedding vector_cosine_ops);
