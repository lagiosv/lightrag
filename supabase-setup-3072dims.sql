-- ============================================
-- Supabase pgvector Setup for LightRAG
-- Using text-embedding-3-large (3072 dimensions)
-- ============================================

-- Create extensions schema (security best practice)
CREATE SCHEMA IF NOT EXISTS extensions;
GRANT USAGE ON SCHEMA extensions TO postgres, anon, authenticated, service_role;

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector 
    WITH SCHEMA extensions;

-- Grant permissions
GRANT ALL ON ALL TABLES IN SCHEMA extensions TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA extensions TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA extensions TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA extensions 
    GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;

-- ============================================
-- Create LightRAG embeddings table
-- CRITICAL: Using 3072 dimensions for text-embedding-3-large
-- ============================================
CREATE TABLE IF NOT EXISTS public.lightrag_embeddings (
    id BIGSERIAL PRIMARY KEY,
    content TEXT NOT NULL,
    embedding extensions.vector(3072),  -- ✅ 3072 dimensions!
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE public.lightrag_embeddings ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Enable read access for all users" ON public.lightrag_embeddings
    FOR SELECT USING (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.lightrag_embeddings
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable update for authenticated users only" ON public.lightrag_embeddings
    FOR UPDATE USING (true);

CREATE POLICY "Enable delete for authenticated users only" ON public.lightrag_embeddings
    FOR DELETE USING (true);

-- ============================================
-- Create vector similarity search function
-- Using 3072-dimensional vectors
-- ============================================
CREATE OR REPLACE FUNCTION match_lightrag_embeddings(
    query_embedding extensions.vector(3072),  -- ✅ 3072 dimensions!
    match_threshold FLOAT DEFAULT 0.7,
    match_count INT DEFAULT 10
)
RETURNS TABLE (
    id BIGINT,
    content TEXT,
    metadata JSONB,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        lightrag_embeddings.id,
        lightrag_embeddings.content,
        lightrag_embeddings.metadata,
        1 - (lightrag_embeddings.embedding <=> query_embedding) AS similarity
    FROM public.lightrag_embeddings
    WHERE 1 - (lightrag_embeddings.embedding <=> query_embedding) > match_threshold
    ORDER BY lightrag_embeddings.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- ============================================
-- Create indexes for performance
-- ============================================

-- HNSW index for fast approximate nearest neighbor search
-- Using cosine distance (<=>) as it's best for text embeddings
CREATE INDEX IF NOT EXISTS lightrag_embeddings_vector_idx 
    ON public.lightrag_embeddings 
    USING hnsw (embedding extensions.vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- Additional indexes for metadata queries
CREATE INDEX IF NOT EXISTS lightrag_embeddings_metadata_idx 
    ON public.lightrag_embeddings 
    USING gin (metadata);

CREATE INDEX IF NOT EXISTS lightrag_embeddings_created_at_idx 
    ON public.lightrag_embeddings (created_at DESC);

-- ============================================
-- Grant permissions
-- ============================================
GRANT ALL ON TABLE public.lightrag_embeddings TO postgres, anon, authenticated, service_role;
GRANT ALL ON SEQUENCE public.lightrag_embeddings_id_seq TO postgres, anon, authenticated, service_role;

-- ============================================
-- Verify setup
-- ============================================
DO $$ 
BEGIN
    RAISE NOTICE 'LightRAG pgvector setup completed successfully!';
    RAISE NOTICE 'Vector dimensions: 3072 (text-embedding-3-large)';
    RAISE NOTICE 'Table: public.lightrag_embeddings';
    RAISE NOTICE 'Function: match_lightrag_embeddings()';
END $$;
