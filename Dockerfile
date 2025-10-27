# Stage 1: Build LightRAG WebUI Frontend
FROM oven/bun:1-alpine AS frontend-builder

# Install git in the builder stage
RUN apk add --no-cache git

WORKDIR /frontend

# Clone LightRAG repository to get the webui source
RUN git clone --depth=1 https://github.com/HKUDS/LightRAG.git /tmp/lightrag && \
    cp -r /tmp/lightrag/lightrag_webui . && \
    rm -rf /tmp/lightrag

# Install dependencies and build with bun
RUN cd /frontend && \
    bun install --frozen-lockfile && \
    bun run build --emptyOutDir

# Verify build succeeded
RUN if [ ! -f "/frontend/dist/index.html" ]; then \
    echo "❌ ERROR: Frontend build failed - index.html not found"; \
    ls -la /frontend/dist/ || echo "dist/ directory not found"; \
    exit 1; \
    fi && \
    echo "✅ Frontend build successful" && \
    ls -lh /frontend/dist/ | head -20


# Stage 2: Build Python Application
FROM python:3.12-slim

# Install system dependencies
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements first (for better caching)
COPY requirements.txt .

# Install Python dependencies
# Including raganything for multimodal document processing
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir raganything

# Copy application code
COPY app/ ./app/

# Create data directories
RUN mkdir -p /app/data/{rag_storage,inputs,outputs,logs}

# Copy built frontend files from builder stage
COPY --from=frontend-builder /frontend/dist /app/lightrag/api/webui

# Verify frontend files were copied
RUN if [ ! -f "/app/lightrag/api/webui/index.html" ]; then \
    echo "❌ ERROR: Frontend files not copied to /app/lightrag/api/webui/"; \
    exit 1; \
    fi && \
    echo "✅ Frontend files verified in container" && \
    ls -lh /app/lightrag/api/webui/ | head -20

# Expose API port
EXPOSE 9621

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s \
  CMD curl -f http://localhost:9621/health || exit 1

# Run the application
CMD ["python", "-m", "app.main"]
