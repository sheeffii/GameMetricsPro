# Event Ingestion Service

Go-based high-performance REST API for receiving player events and publishing to Kafka.

## Features

- REST API for event ingestion
- Rate limiting (10k req/sec)
- Kafka producer with retries
- Health checks
- Prometheus metrics
- OpenTelemetry tracing
- Graceful shutdown

## API Endpoints

### POST /api/v1/events
Ingest player events

**Request Body:**
```json
{
  "event_type": "gameplay",
  "player_id": "player123",
  "game_id": "game456",
  "timestamp": "2024-12-01T12:00:00Z",
  "data": {
    "score": 1000,
    "level": 5
  }
}
```

**Response:**
```json
{
  "status": "success",
  "event_id": "evt_123456"
}
```

### GET /health/live
Liveness probe - returns 200 if service is running

### GET /health/ready
Readiness probe - returns 200 if service is ready to accept traffic

### GET /metrics
Prometheus metrics endpoint

## Environment Variables

- `PORT`: HTTP server port (default: 8080)
- `KAFKA_BROKERS`: Kafka broker addresses
- `KAFKA_TOPIC`: Kafka topic name
- `KAFKA_USERNAME`: Kafka SASL username
- `KAFKA_PASSWORD`: Kafka SASL password
- `RATE_LIMIT_RPS`: Rate limit requests per second
- `LOG_LEVEL`: Logging level (debug, info, warn, error)
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OpenTelemetry collector endpoint
- `OTEL_SERVICE_NAME`: Service name for tracing

## Building

```bash
docker build -t event-ingestion-service:latest .
```

## Running Locally

```bash
go run cmd/main.go
```

## Testing

```bash
go test ./...
```

## Performance

- Handles 10,000+ requests/second
- P99 latency < 50ms
- Memory usage ~100MB under load
