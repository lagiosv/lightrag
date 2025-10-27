# LightRAG with RAG-Anything - Deployment

Self-hosted multimodal RAG system with Neo4j knowledge graph and Supabase/pgvector for embeddings.

## 🏗️ Architecture

```
┌─────────────────┐
│   LightRAG      │
│  + RAG-Anything │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼──┐  ┌──▼────┐
│Neo4j │  │Supabase│
│Graph │  │pgvector│
└──────┘  └────────┘
```

**Components:**
- **LightRAG**: Core RAG engine with knowledge graph integration
- **RAG-Anything**: Multimodal document processor (PDF, images, tables)
- **Neo4j**: Knowledge graph database
- **Supabase/PostgreSQL**: Vector embeddings storage with pgvector
- **OpenRouter**: LLM API gateway (Claude, GPT-4, etc.)

---

## 📋 Prerequisites

### 1. Infrastructure Setup
- ✅ Hetzner Private Network configured (`ha-network`)
- ✅ VPS 1 (Supabase) attached to private network: `10.0.0.3`
- ✅ VPS 2 (LightRAG + Neo4j) will be: `10.0.0.4`

### 2. Services Required
- ✅ **Supabase deployed** on VPS 1 via Coolify
- ⏳ **Neo4j** to be deployed on same VPS as LightRAG
- ⏳ **LightRAG** (this application)

### 3. Accounts Needed
- GitHub account (for Git-based deployment)
- OpenRouter account with API key
- Hetzner account with VPS access

---

## 🚀 Deployment via Coolify (Option 1: Git)

### Step 1: Prepare Repository

1. **Create private GitHub repository**: `lightrag-deployment`

2. **Clone and push this code**:
   ```bash
   cd /Users/vasilislagios/Desktop/lightrag-deployment
   
   # Initialize git if not already done
   git init
   git add .
   git commit -m "Initial LightRAG deployment setup"
   
   # Add your GitHub repo as remote
   git remote add origin https://github.com/lagiosv/lightrag.git
   git branch -M main
   git push -u origin main
   ```

3. **Verify files are pushed**:
   - ✅ `Dockerfile`
   - ✅ `docker-compose.yml`
   - ✅ `requirements.txt`
   - ✅ `.env.example`
   - ✅ `app/main.py`
   - ✅ `app/__init__.py`
   - ✅ `README.md`

---

### Step 2: Deploy Neo4j First

**In Coolify UI (VPS 1 or VPS 2):**

1. **Projects** → Select your project (e.g., "supabase-rag")
2. **+ Add New Resource** → **Service** → **Docker Image**

3. **Configuration**:
   ```
   Name: neo4j-lightrag
   Image: neo4j:5.15
   ```

4. **Environment Variables**:
   ```bash
   NEO4J_AUTH=neo4j/YOUR_STRONG_PASSWORD_HERE
   NEO4J_server_memory_heap_initial__size=2G
   NEO4J_server_memory_heap_max__size=2G
   NEO4J_server_memory_pagecache_size=2G
   NEO4J_dbms_security_procedures_unrestricted=apoc.*
   NEO4J_PLUGINS=["apoc"]
   ```

5. **Ports**:
   ```
   7474:7474  # Neo4j Browser (optional, for testing)
   7687:7687  # Bolt protocol
   ```

6. **Volumes**:
   ```
   neo4j-data → /data
   neo4j-logs → /logs
   ```

7. **Network**: Select `coolify` destination

8. **Deploy** → Wait for "Running" status

9. **Test Neo4j**:
   ```bash
   # Via browser: http://YOUR_VPS_IP:7474
   # Login: neo4j / YOUR_PASSWORD
   ```

---

### Step 3: Deploy LightRAG Application

**In Coolify UI:**

1. **Projects** → Select your project
2. **+ Add New Resource** → **Application** → **Public Repository**

3. **Repository Configuration**:
   ```
   Git Repository: https://github.com/lagiosv/lightrag.git
   Branch: main
   Build Pack: Dockerfile
   Port: 9621
   ```

4. **Set Environment Variables** (Critical!):

   Click **Environment Variables** tab and add:

   ```bash
   # Working directory (inside container)
   WORKING_DIR=/app/data/rag_storage
   
   # OpenRouter API
   OPENROUTER_API_KEY=sk-or-v1-YOUR_ACTUAL_KEY_HERE
   LLM_MODEL=anthropic/claude-3.5-sonnet
   VISION_MODEL=openai/gpt-4o
   EMBEDDING_MODEL=text-embedding-3-small
   EMBEDDING_DIM=1536
   
   # Neo4j (use service name if same VPS, or private IP)
   NEO4J_URI=bolt://neo4j-lightrag:7687
   NEO4J_USERNAME=neo4j
   NEO4J_PASSWORD=YOUR_NEO4J_PASSWORD
   
   # PostgreSQL (use private network IP of VPS 1)
   POSTGRES_URI=postgresql://postgres:YOUR_SUPABASE_PASSWORD@10.0.0.3:5432/postgres
   ```

   **Important Notes**:
   - Replace `YOUR_ACTUAL_KEY_HERE` with real OpenRouter API key
   - Replace `YOUR_NEO4J_PASSWORD` with password set in Step 2
   - Replace `YOUR_SUPABASE_PASSWORD` with Supabase PostgreSQL password
   - If deploying on **same VPS as Neo4j**: Use `bolt://neo4j-lightrag:7687`
   - If deploying on **different VPS**: Use `bolt://10.0.0.X:7687` (private IP)

5. **Destination**: Select `coolify` network

6. **Ports**: 
   ```
   Port: 9621
   Publicly accessible: ✅ (check if you want external access)
   ```

7. **Deploy** → Coolify will:
   - Clone your GitHub repository
   - Build Docker image from Dockerfile
   - Start container with environment variables
   - Attach to coolify network

---

### Step 4: Verify Deployment

#### 4.1 Check Logs

In Coolify → Your Application → **Logs** tab

Look for these success indicators:
```
✅ LightRAG and RAG-Anything modules loaded
🔗 Connecting to Neo4j: bolt://neo4j-lightrag:7687
🔗 Connecting to PostgreSQL: postgresql://...
✅ Storage backends initialized
✅✅✅ RAG system fully initialized!
```

#### 4.2 Health Check

```bash
curl http://YOUR_VPS_IP:9621/health | jq
```

**Expected response**:
```json
{
  "status": "healthy",
  "rag_initialized": true,
  "neo4j_uri": "bolt://neo4j-lightrag:7687",
  "lightrag_available": true
}
```

#### 4.3 Test Insert

```bash
curl -X POST http://YOUR_VPS_IP:9621/api/insert \
  -H "Content-Type: application/json" \
  -d '{
    "content": "LightRAG is a powerful retrieval-augmented generation system that combines knowledge graphs with vector embeddings for enhanced information retrieval and reasoning."
  }' | jq
```

**Expected response**:
```json
{
  "status": "success",
  "message": "Content indexed successfully",
  "content_length": 187
}
```

#### 4.4 Test Query

```bash
curl -X POST http://YOUR_VPS_IP:9621/api/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is LightRAG?",
    "mode": "hybrid"
  }' | jq
```

Should return relevant answer based on inserted content.

#### 4.5 Verify Data Storage

**Neo4j Browser** (`http://YOUR_VPS_IP:7474`):
```cypher
MATCH (n) RETURN n LIMIT 25
```
Should show nodes created by LightRAG.

**Supabase Studio** (via Coolify):
```sql
SELECT COUNT(*) FROM lightrag_embeddings;
```
Should show vector embeddings.

---

## 🔧 Configuration Options

### LLM Models (via OpenRouter)

```bash
# Claude models
LLM_MODEL=anthropic/claude-3.5-sonnet
LLM_MODEL=anthropic/claude-opus-4

# OpenAI models
LLM_MODEL=openai/gpt-4o
LLM_MODEL=openai/gpt-4-turbo

# Vision models
VISION_MODEL=openai/gpt-4o
VISION_MODEL=anthropic/claude-3.5-sonnet
```

### Embedding Models

```bash
# OpenAI embeddings (recommended)
EMBEDDING_MODEL=text-embedding-3-small
EMBEDDING_DIM=1536

EMBEDDING_MODEL=text-embedding-3-large
EMBEDDING_DIM=3072
```

### Query Modes

- `naive`: Simple retrieval
- `local`: Local graph context
- `global`: Global graph context  
- `hybrid`: Combines all approaches (recommended)

---

## 📊 API Endpoints

### GET /health
Health check endpoint.

### POST /api/insert
Insert text content into RAG system.

**Request**:
```json
{
  "content": "Your text content here",
  "description": "Optional description"
}
```

### POST /api/query
Query the RAG system.

**Request**:
```json
{
  "query": "Your question here",
  "mode": "hybrid"
}
```

**Response**:
```json
{
  "answer": "Generated answer",
  "mode": "hybrid"
}
```

### POST /api/upload
Upload and process files (PDF, images, etc.).

**Request**: Multipart form data with file

---

## 🔐 Security Notes

### Private Network (Recommended)
- ✅ PostgreSQL on private network only (10.0.0.3:5432)
- ✅ No public database exposure
- ✅ Neo4j can also be private (remove port 7474 mapping)

### Public Access
- LightRAG API (9621) can be public or private
- Neo4j Browser (7474) should be private in production
- Use Coolify's built-in authentication for added security

### Secrets Management
- Store API keys in Coolify's Environment Variables
- Never commit `.env` file to Git
- Use strong passwords (32+ characters)

---

## 🐛 Troubleshooting

### "RAG system not initialized"
- Check logs for initialization errors
- Verify environment variables are set correctly
- Ensure Neo4j and PostgreSQL are accessible

### "Connection refused" to Neo4j
- Verify Neo4j container is running
- Check NEO4J_URI matches service name or IP
- Ensure both containers are on `coolify` network

### "Connection refused" to PostgreSQL
- Verify Supabase is running on VPS 1
- Check private network IPs (`ip addr show`)
- Ensure POSTGRES_URI uses correct IP (10.0.0.3)

### Build fails in Coolify
- Check Dockerfile syntax
- Verify requirements.txt dependencies
- Review build logs for specific errors

---

## 📚 Resources

- [LightRAG GitHub](https://github.com/HKUDS/LightRAG)
- [RAG-Anything GitHub](https://github.com/HKUDS/RAG-Anything)
- [Coolify Documentation](https://coolify.io/docs)
- [OpenRouter API](https://openrouter.ai)
- [Neo4j Documentation](https://neo4j.com/docs/)
- [Supabase Documentation](https://supabase.com/docs)

---

## 📝 License

This deployment configuration is provided as-is. Check individual component licenses:
- LightRAG: Check upstream repository
- RAG-Anything: Check upstream repository
