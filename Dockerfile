# Stage 1: Build LightRAG WebUI Frontend
FROM oven/bun:1-alpine AS frontend-builder

RUN apk add --no-cache git

WORKDIR /frontend

RUN git clone --depth=1 https://github.com/HKUDS/LightRAG.git /tmp/lightrag && \
    cp -r /tmp/lightrag/lightrag_webui . && \
    rm -rf /tmp/lightrag

WORKDIR /frontend/lightrag_webui

RUN bun install --frozen-lockfile && \
    bun run build --emptyOutDir

RUN if [ ! -f "./dist/index.html" ]; then \
    echo "❌ ERROR: Frontend build failed"; \
    exit 1; \
    fi && \
    echo "✅ Frontend build successful"


# Stage 2: Build Python Application
FROM python:3.12-slim

# Install ONLY essential system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements
COPY requirements.txt .

# Install Python dependencies with timeout and retries
RUN pip install --no-cache-dir --timeout=300 -r requirements.txt

# Copy application code
COPY app/ ./app/

# Create data directories
RUN mkdir -p /app/data/{rag_storage,inputs,outputs,logs}

# Copy built frontend files from builder stage
COPY --from=frontend-builder /frontend/lightrag_webui/dist /app/lightrag/api/webui

# Verify frontend files
RUN if [ ! -f "/app/lightrag/api/webui/index.html" ]; then \
    echo "❌ ERROR: Frontend files not copied"; \
    exit 1; \
    fi && \
    echo "✅ Deployment ready"

# Expose API port
EXPOSE 9621

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s \
  CMD curl -f http://localhost:9621/health || exit 1

# Run the application
CMD ["python", "-m", "app.main"]
