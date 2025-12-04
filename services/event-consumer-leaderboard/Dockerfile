FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY consumer.py .

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ps aux | grep "consumer.py" | grep -v grep || exit 1

ENV LOG_LEVEL=INFO
ENV PYTHONUNBUFFERED=1

CMD ["python", "-u", "consumer.py"]
