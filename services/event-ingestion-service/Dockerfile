# Build stage
FROM golang:1.22-alpine3.20 AS builder

WORKDIR /app

# Install dependencies with security updates
RUN apk upgrade --no-cache && \
    apk add --no-cache git ca-certificates

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o event-ingestion-service ./cmd/main.go

# Final stage - use distroless for minimal attack surface
FROM gcr.io/distroless/static-debian12:nonroot

# Copy CA certificates from builder
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/event-ingestion-service /app/event-ingestion-service

# Use nonroot user (UID 65532) - already set in distroless
# No shell, minimal packages, minimal attack surface

# Expose port
EXPOSE 8080

# Run binary
ENTRYPOINT ["/app/event-ingestion-service"]
