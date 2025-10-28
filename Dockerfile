FROM python:3.12-slim

RUN apt-get update && \
    apt-get install -y \
    build-essential \
    curl \
    poppler-utils \
    tesseract-ocr \
    tesseract-ocr-eng \
    libmagic1 \
    libmagickwand-dev \
    ffmpeg \
    fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

RUN mkdir -p /app/data/{rag_storage,inputs,outputs,logs,cache,uploads} && \
    chmod -R 755 /app/data

EXPOSE 9621

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s \
  CMD curl -f http://localhost:9621/health || exit 1

CMD ["python", "-m", "app.main"]
