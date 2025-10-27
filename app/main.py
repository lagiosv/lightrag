import os
from pathlib import Path
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, UploadFile, File
from pydantic import BaseModel
from typing import Optional, List
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

app = FastAPI(
    title="LightRAG with RAG-Anything",
    version="1.0.0",
    description="Multimodal RAG system with Neo4j and Supabase"
)

# Configuration from environment
WORKING_DIR = os.getenv("WORKING_DIR", "./data/rag_storage")
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY")
OPENROUTER_BASE_URL = "https://openrouter.ai/api/v1"
LLM_MODEL = os.getenv("LLM_MODEL", "anthropic/claude-3.5-sonnet")
VISION_MODEL = os.getenv("VISION_MODEL", "openai/gpt-4o")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
EMBEDDING_DIM = int(os.getenv("EMBEDDING_DIM", "1536"))

# Database connections
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USERNAME = os.getenv("NEO4J_USERNAME", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD")
POSTGRES_URI = os.getenv("POSTGRES_URI")

# Global RAG instance
rag_instance = None

# Import LightRAG components
try:
    from lightrag import LightRAG, QueryParam
    from lightrag.llm.openai import openai_complete_if_cache, openai_embed
    from lightrag.utils import EmbeddingFunc
    from raganything import RAGAnything, RAGAnythingConfig
    LIGHTRAG_AVAILABLE = True
    logger.info("✅ LightRAG and RAG-Anything modules loaded")
except ImportError as e:
    LIGHTRAG_AVAILABLE = False
    logger.warning(f"⚠️ LightRAG modules not available: {e}")


# Pydantic models for API
class InsertRequest(BaseModel):
    content: str
    description: Optional[str] = None


class QueryRequest(BaseModel):
    query: str
    mode: Optional[str] = "hybrid"  # naive, local, global, hybrid


class QueryResponse(BaseModel):
    answer: str
    mode: str


def create_llm_func():
    """Create LLM function for text generation"""
    async def llm_func(prompt, **kwargs):
        return await openai_complete_if_cache(
            model=LLM_MODEL,
            prompt=prompt,
            api_key=OPENROUTER_API_KEY,
            base_url=OPENROUTER_BASE_URL,
            **kwargs
        )
    return llm_func


def create_vision_func():
    """Create vision model function for image processing"""
    async def vision_func(prompt, **kwargs):
        return await openai_complete_if_cache(
            model=VISION_MODEL,
            prompt=prompt,
            api_key=OPENROUTER_API_KEY,
            base_url=OPENROUTER_BASE_URL,
            **kwargs
        )
    return vision_func


def create_embedding_func():
    """Create embedding function"""
    return EmbeddingFunc(
        embedding_dim=EMBEDDING_DIM,
        max_token_size=8192,
        func=lambda texts: openai_embed(
            texts,
            model=EMBEDDING_MODEL,
            api_key=OPENROUTER_API_KEY,
            base_url=OPENROUTER_BASE_URL
        )
    )


@app.on_event("startup")
async def startup_event():
    """Initialize RAG system on startup"""
    global rag_instance
    
    logger.info("🚀 Starting LightRAG initialization...")
    
    # Create working directory
    Path(WORKING_DIR).mkdir(parents=True, exist_ok=True)
    logger.info(f"📁 Working directory: {WORKING_DIR}")
    
    # Validate configuration
    if not OPENROUTER_API_KEY:
        logger.error("❌ OPENROUTER_API_KEY not set!")
        return
    
    if not NEO4J_PASSWORD:
        logger.error("❌ NEO4J_PASSWORD not set!")
        return
        
    if not POSTGRES_URI:
        logger.error("❌ POSTGRES_URI not set!")
        return
    
    if not LIGHTRAG_AVAILABLE:
        logger.error("❌ LightRAG modules not available!")
        return
    
    try:
        # Set up database connections in environment
        os.environ.update({
            "NEO4J_URI": NEO4J_URI,
            "NEO4J_USERNAME": NEO4J_USERNAME,
            "NEO4J_PASSWORD": NEO4J_PASSWORD,
            "POSTGRES_URI": POSTGRES_URI
        })
        
        logger.info(f"🔗 Connecting to Neo4j: {NEO4J_URI}")
        logger.info(f"🔗 Connecting to PostgreSQL: {POSTGRES_URI[:50]}...")
        
        # Initialize LightRAG core
        lightrag_core = LightRAG(
            working_dir=WORKING_DIR,
            llm_model_func=create_llm_func(),
            embedding_func=create_embedding_func(),
            graph_storage="Neo4JStorage",
            vector_storage="PGVectorStorage",
            kv_storage="PGKVStorage"
        )
        
        # Initialize storage backends
        await lightrag_core.initialize_storages()
        logger.info("✅ Storage backends initialized")
        
        # Configure RAG-Anything
        config = RAGAnythingConfig(
            working_dir=WORKING_DIR,
            parser="mineru",
            enable_image_processing=True,
            enable_table_processing=True,
            enable_equation_processing=True
        )
        
        # Create RAG instance
        rag_instance = RAGAnything(
            lightrag=lightrag_core,
            vision_model_func=create_vision_func(),
            config=config
        )
        
        logger.info("✅✅✅ RAG system fully initialized!")
        logger.info(f"📊 Graph DB: {NEO4J_URI}")
        logger.info(f"📊 Vector DB: {POSTGRES_URI[:50]}...")
        
    except Exception as e:
        logger.error(f"❌ Failed to initialize RAG system: {e}")
        import traceback
        traceback.print_exc()


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "LightRAG with RAG-Anything",
        "status": "running",
        "docs": "/docs"
    }


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy" if rag_instance else "initializing",
        "rag_initialized": rag_instance is not None,
        "neo4j_uri": NEO4J_URI,
        "lightrag_available": LIGHTRAG_AVAILABLE
    }


@app.post("/api/insert")
async def insert_content(request: InsertRequest):
    """Insert text content into RAG system"""
    if not rag_instance:
        raise HTTPException(status_code=503, detail="RAG system not initialized")
    
    try:
        # Insert content using LightRAG
        await rag_instance.lightrag.ainsert(request.content)
        
        logger.info(f"✅ Inserted content: {request.content[:100]}...")
        return {
            "status": "success",
            "message": "Content indexed successfully",
            "content_length": len(request.content)
        }
    except Exception as e:
        logger.error(f"❌ Insert failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/query", response_model=QueryResponse)
async def query_content(request: QueryRequest):
    """Query the RAG system"""
    if not rag_instance:
        raise HTTPException(status_code=503, detail="RAG system not initialized")
    
    try:
        # Query using LightRAG
        result = await rag_instance.lightrag.aquery(
            request.query,
            param=QueryParam(mode=request.mode)
        )
        
        logger.info(f"✅ Query successful: {request.query[:100]}...")
        return QueryResponse(
            answer=result,
            mode=request.mode
        )
    except Exception as e:
        logger.error(f"❌ Query failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    """Upload and process a file using RAG-Anything"""
    if not rag_instance:
        raise HTTPException(status_code=503, detail="RAG system not initialized")
    
    try:
        # Save uploaded file temporarily
        upload_dir = Path(WORKING_DIR) / "uploads"
        upload_dir.mkdir(parents=True, exist_ok=True)
        
        file_path = upload_dir / file.filename
        with open(file_path, "wb") as f:
            content = await file.read()
            f.write(content)
        
        logger.info(f"📁 Processing file: {file.filename}")
        
        # Process file with RAG-Anything
        result = await rag_instance.process_file(str(file_path))
        
        logger.info(f"✅ File processed: {file.filename}")
        return {
            "status": "success",
            "message": f"File {file.filename} processed successfully",
            "filename": file.filename,
            "size": len(content)
        }
    except Exception as e:
        logger.error(f"❌ File upload failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=9621)
