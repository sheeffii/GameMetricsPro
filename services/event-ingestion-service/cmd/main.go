package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/segmentio/kafka-go"
	"github.com/segmentio/kafka-go/sasl/scram"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
	"golang.org/x/time/rate"
)

var (
	// Prometheus metrics
	eventsReceived = promauto.NewCounter(prometheus.CounterOpts{
		Name: "events_received_total",
		Help: "Total number of events received",
	})
	eventsPublished = promauto.NewCounter(prometheus.CounterOpts{
		Name: "events_published_total",
		Help: "Total number of events published to Kafka",
	})
	eventsFailed = promauto.NewCounter(prometheus.CounterOpts{
		Name: "events_failed_total",
		Help: "Total number of failed events",
	})
	requestDuration = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "HTTP request duration in seconds",
		Buckets: prometheus.DefBuckets,
	})
)

type Event struct {
	EventType string                 `json:"event_type" binding:"required"`
	PlayerID  string                 `json:"player_id" binding:"required"`
	GameID    string                 `json:"game_id" binding:"required"`
	Timestamp time.Time              `json:"timestamp" binding:"required"`
	Data      map[string]interface{} `json:"data"`
}

type EventResponse struct {
	Status  string `json:"status"`
	EventID string `json:"event_id"`
}

type Server struct {
	router      *gin.Engine
	kafkaWriter *kafka.Writer
	limiter     *rate.Limiter
}

func main() {
	// Initialize OpenTelemetry
	ctx := context.Background()
	tp, err := initTracer(ctx)
	if err != nil {
		log.Fatalf("Failed to initialize tracer: %v", err)
	}
	defer func() {
		if err := tp.Shutdown(ctx); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	// Create server
	server := NewServer()
	defer server.kafkaWriter.Close()

	// Start HTTP server
	srv := &http.Server{
		Addr:    fmt.Sprintf(":%s", getEnv("PORT", "8080")),
		Handler: server.router,
	}

	// Graceful shutdown
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	log.Printf("Event Ingestion Service started on port %s", getEnv("PORT", "8080"))

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}

func NewServer() *Server {
	// Set Gin mode
	if os.Getenv("LOG_LEVEL") != "debug" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.Default()

	// Rate limiter
	rateLimit := getEnvAsInt("RATE_LIMIT_RPS", 10000)
	limiter := rate.NewLimiter(rate.Limit(rateLimit), rateLimit)

	// Kafka writer
	kafkaWriter := createKafkaWriter()

	server := &Server{
		router:      router,
		kafkaWriter: kafkaWriter,
		limiter:     limiter,
	}

	// Routes
	router.POST("/api/v1/events", server.rateLimitMiddleware(), server.ingestEvent)
	router.GET("/health/live", server.livenessProbe)
	router.GET("/health/ready", server.readinessProbe)
	router.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// Swagger UI
	router.GET("/swagger", server.swaggerRedirect)
	router.GET("/api-docs", server.swaggerSpec)
	router.GET("/swagger-ui.html", server.swaggerUI)

	return server
}

func createKafkaWriter() *kafka.Writer {
	brokers := getEnv("KAFKA_BOOTSTRAP_SERVERS", getEnv("KAFKA_BROKERS", "localhost:9092"))
	topic := getEnv("KAFKA_TOPIC_PLAYER_EVENTS", getEnv("KAFKA_TOPIC", "player.events.raw"))
	username := getEnv("KAFKA_USERNAME", "")
	password := getEnv("KAFKA_PASSWORD", "")

	writer := &kafka.Writer{
		Addr:         kafka.TCP(strings.Split(brokers, ",")...),
		Topic:        topic,
		Balancer:     &kafka.Hash{},
		RequiredAcks: -1, // RequireAll
		BatchSize:    100,
		BatchTimeout: 10 * time.Millisecond,
	}

	if username != "" && password != "" {
		mechanism, err := scram.Mechanism(scram.SHA512, username, password)
		if err != nil {
			log.Fatalf("Failed to create SCRAM mechanism: %v", err)
		}

		writer.Transport = &kafka.Transport{
			SASL: mechanism,
		}
	}

	return writer
}

func (s *Server) rateLimitMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !s.limiter.Allow() {
			c.JSON(http.StatusTooManyRequests, gin.H{"error": "rate limit exceeded"})
			c.Abort()
			return
		}
		c.Next()
	}
}

func (s *Server) ingestEvent(c *gin.Context) {
	start := time.Now()
	defer func() {
		requestDuration.Observe(time.Since(start).Seconds())
	}()

	eventsReceived.Inc()

	var event Event
	if err := c.ShouldBindJSON(&event); err != nil {
		eventsFailed.Inc()
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Generate event ID
	eventID := uuid.New().String()

	// Add metadata
	eventWithMetadata := map[string]interface{}{
		"event_id":    eventID,
		"event_type":  event.EventType,
		"player_id":   event.PlayerID,
		"game_id":     event.GameID,
		"timestamp":   event.Timestamp,
		"data":        event.Data,
		"ingested_at": time.Now(),
	}

	// Serialize to JSON
	eventJSON, err := json.Marshal(eventWithMetadata)
	if err != nil {
		eventsFailed.Inc()
		c.JSON(http.StatusInternalServerError, gin.H{"error":"failed to serialize event"})
		return
	}

	// Publish to Kafka
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	err = s.kafkaWriter.WriteMessages(ctx, kafka.Message{
		Key:   []byte(event.PlayerID),
		Value: eventJSON,
		Headers: []kafka.Header{
			{Key: "event_type", Value: []byte(event.EventType)},
			{Key: "event_id", Value: []byte(eventID)},
		},
	})

	if err != nil {
		eventsFailed.Inc()
		log.Printf("Failed to publish event: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to publish event"})
		return
	}

	eventsPublished.Inc()

	c.JSON(http.StatusOK, EventResponse{
		Status:  "success",
		EventID: eventID,
	})
}

func (s *Server) livenessProbe(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "alive"})
}

func (s *Server) readinessProbe(c *gin.Context) {
	// Check if Kafka writer is initialized
	if s.kafkaWriter == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"status": "not ready", "error": "kafka writer not initialized"})
		return
	}

	// Simple readiness without Kafka health check to avoid blocking
	c.JSON(http.StatusOK, gin.H{"status": "ready"})
}

func initTracer(ctx context.Context) (*sdktrace.TracerProvider, error) {
	endpoint := getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
	if endpoint == "" {
		return sdktrace.NewTracerProvider(), nil
	}

	exporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(endpoint),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	serviceName := getEnv("OTEL_SERVICE_NAME", "event-ingestion-service")
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceNameKey.String(serviceName),
		)),
	)

	otel.SetTracerProvider(tp)
	return tp, nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvAsInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		var intValue int
		if _, err := fmt.Sscanf(value, "%d", &intValue); err == nil {
			return intValue
		}
	}
	return defaultValue
}

// Swagger handlers
func (s *Server) swaggerRedirect(c *gin.Context) {
	c.Redirect(http.StatusMovedPermanently, "/swagger-ui.html")
}

func (s *Server) swaggerSpec(c *gin.Context) {
	// Serve OpenAPI spec inline (no file dependency)
	spec := map[string]interface{}{
		"openapi": "3.0.3",
		"info": map[string]interface{}{
			"title":       "GameMetrics Event Ingestion API",
			"description": "Real-time event ingestion service for gaming analytics",
			"version":     "1.0.0",
		},
		"servers": []map[string]string{
			{"url": "http://localhost:8080", "description": "Local"},
		},
		"paths": map[string]interface{}{
			"/api/v1/events": map[string]interface{}{
				"post": map[string]interface{}{
					"summary": "Ingest Player Event",
					"tags":    []string{"Events"},
					"requestBody": map[string]interface{}{
						"required": true,
						"content": map[string]interface{}{
							"application/json": map[string]interface{}{
								"schema": map[string]interface{}{
									"$ref": "#/components/schemas/Event",
								},
							},
						},
					},
					"responses": map[string]interface{}{
						"200": map[string]interface{}{
							"description": "Event successfully ingested",
						},
					},
				},
			},
			"/health/live": map[string]interface{}{
				"get": map[string]interface{}{
					"summary": "Liveness Probe",
					"tags":    []string{"Health"},
				},
			},
			"/health/ready": map[string]interface{}{
				"get": map[string]interface{}{
					"summary": "Readiness Probe",
					"tags":    []string{"Health"},
				},
			},
		},
		"components": map[string]interface{}{
			"schemas": map[string]interface{}{
				"Event": map[string]interface{}{
					"type":     "object",
					"required": []string{"player_id", "game_id", "event_type", "timestamp"},
					"properties": map[string]interface{}{
						"player_id":  map[string]string{"type": "string"},
						"game_id":    map[string]string{"type": "string"},
						"event_type": map[string]string{"type": "string"},
						"timestamp":  map[string]string{"type": "string", "format": "date-time"},
						"data":       map[string]string{"type": "object"},
					},
				},
			},
		},
	}
	c.JSON(http.StatusOK, spec)
}

func (s *Server) swaggerUI(c *gin.Context) {
	html := `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GameMetrics Event Ingestion API</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui.css" />
  <style>
    body {
      margin: 0;
      padding: 0;
    }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-bundle.js"></script>
  <script src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-standalone-preset.js"></script>
  <script>
    window.onload = function() {
      window.ui = SwaggerUIBundle({
        url: '/api-docs',
        dom_id: '#swagger-ui',
        deepLinking: true,
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIStandalonePreset
        ],
        layout: "StandaloneLayout",
        tryItOutEnabled: true
      })
    }
  </script>
</body>
</html>
	`
	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(html))
}
