FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY consumer.py .

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ps aux | grep "consumer.py" | grep -v grep || exit 1

# Set environment variables
ENV LOG_LEVEL=INFO
ENV PYTHONUNBUFFERED=1

# Run the consumer
CMD ["python", "-u", "consumer.py"]
