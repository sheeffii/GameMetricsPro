FROM golang:1.21-alpine AS build

WORKDIR /app

# Copy go mod files
COPY go.mod ./

# Download dependencies (go.sum will be generated)
RUN go get github.com/gin-gonic/gin@v1.9.1 && \
    go get github.com/prometheus/client_golang@v1.18.0 && \
    go get github.com/segmentio/kafka-go@v0.4.47

# Copy source code
COPY main.go .

# Build (after copying code, go build will use the dependencies)
RUN go mod tidy && CGO_ENABLED=0 GOOS=linux go build -o notification-service main.go

# Runtime stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=build /app/notification-service .

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health/live || exit 1

CMD ["./notification-service"]



