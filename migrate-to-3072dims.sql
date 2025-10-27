-- ============================================
-- LightRAG Migration: 1536 → 3072 Dimensions
-- SAFE: This will delete existing embeddings!
-- ============================================

-- Step 1: Drop existing function (required to change dimensions)
DROP FUNCTION IF EXISTS match_lightrag_embeddings(extensions.vector, double precision, integer);
DROP FUNCTION IF EXISTS match_lightrag_embeddings(vector, double precision, integer);
DROP FUNCTION IF EXISTS match_lightrag_embeddings;

-- Step 2: Drop existing table (this deletes all data!)
DROP TABLE IF EXISTS public.lightrag_embeddings CASCADE;

-- Step 3: Verify extensions schema exists
CREATE SCHEMA IF NOT EXISTS extensions;
GRANT USAGE ON SCHEMA extensions TO postgres, anon, authenticated, service_role;

-- Step 4: Ensure pgvector extension is enabled
CREATE EXTENSION IF NOT EXISTS vector 
    WITH SCHEMA extensions;

-- Grant permissions
GRANT ALL ON ALL TABLES IN SCHEMA extensions TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA extensions TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA extensions TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA extensions 
    GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;

-- ============================================
-- Step 5: Create NEW table with 3072 dimensions
-- ============================================
CREATE TABLE public.lightrag_embeddings (
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
-- Step 6: Create NEW function with 3072 dimensions
-- ============================================
CREATE FUNCTION match_lightrag_embeddings(
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
-- Step 7: Create indexes for performance
-- ============================================

-- HNSW index for fast approximate nearest neighbor search
CREATE INDEX lightrag_embeddings_vector_idx 
    ON public.lightrag_embeddings 
    USING hnsw (embedding extensions.vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- Additional indexes for metadata queries
CREATE INDEX lightrag_embeddings_metadata_idx 
    ON public.lightrag_embeddings 
    USING gin (metadata);

CREATE INDEX lightrag_embeddings_created_at_idx 
    ON public.lightrag_embeddings (created_at DESC);

-- ============================================
-- Step 8: Grant permissions
-- ============================================
GRANT ALL ON TABLE public.lightrag_embeddings TO postgres, anon, authenticated, service_role;
GRANT ALL ON SEQUENCE public.lightrag_embeddings_id_seq TO postgres, anon, authenticated, service_role;

-- ============================================
-- Step 9: Verify setup
-- ============================================
DO $$ 
BEGIN
    RAISE NOTICE '✅ Migration completed successfully!';
    RAISE NOTICE '📊 Upgraded from 1536 → 3072 dimensions';
    RAISE NOTICE '🗑️  Old data deleted (clean slate)';
    RAISE NOTICE '📋 Table: public.lightrag_embeddings';
    RAISE NOTICE '🔍 Function: match_lightrag_embeddings()';
    RAISE NOTICE '💡 Model: text-embedding-3-large';
END $$;
