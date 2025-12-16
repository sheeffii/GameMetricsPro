package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/segmentio/kafka-go"
)

var (
	notificationsSent = promauto.NewCounter(prometheus.CounterOpts{
		Name: "notifications_sent_total",
		Help: "Total number of notifications sent",
	})
	notificationsFailed = promauto.NewCounter(prometheus.CounterOpts{
		Name: "notifications_failed_total",
		Help: "Total number of failed notifications",
	})
	dlqMessages = promauto.NewCounter(prometheus.CounterOpts{
		Name: "dlq_messages_total",
		Help: "Total number of messages sent to DLQ",
	})
)

type Notification struct {
	ID        string                 `json:"id"`
	UserID    string                 `json:"user_id"`
	Type      string                 `json:"type"`
	Channel   string                 `json:"channel"`
	Title     string                 `json:"title"`
	Message   string                 `json:"message"`
	Data      map[string]interface{} `json:"data"`
	CreatedAt time.Time              `json:"created_at"`
}

type NotificationService struct {
	kafkaReader *kafka.Reader
	kafkaWriter *kafka.Writer
	dlqWriter   *kafka.Writer
}

func NewNotificationService() *NotificationService {
	bootstrapServers := getEnv("KAFKA_BOOTSTRAP_SERVERS", "gamemetrics-kafka-bootstrap.kafka.svc.cluster.local:9092")
	
	// Consumer for notifications topic
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:  []string{bootstrapServers},
		Topic:    getEnv("KAFKA_TOPIC_NOTIFICATIONS", "notifications"),
		GroupID:  "notification-service-group",
		MinBytes: 10e3,
		MaxBytes: 10e6,
	})
	
	// Producer for DLQ
	dlqWriter := &kafka.Writer{
		Addr:     kafka.TCP(bootstrapServers),
		Topic:    "system.dlq",
		Balancer: &kafka.Hash{},
	}
	
	return &NotificationService{
		kafkaReader: reader,
		dlqWriter:   dlqWriter,
	}
}

func (ns *NotificationService) sendNotification(ctx context.Context, notification Notification) error {
	// Mock implementation - in production would integrate with:
	// - Email service (SendGrid, SES)
	// - SMS service (Twilio)
	// - Push notification service (FCM, APNS)
	// - WebSocket for in-app notifications
	
	log.Printf("Sending notification: %s to user %s via %s", notification.Type, notification.UserID, notification.Channel)
	
	// Simulate sending delay
	time.Sleep(50 * time.Millisecond)
	
	notificationsSent.Inc()
	return nil
}

func (ns *NotificationService) processNotification(ctx context.Context, notification Notification) error {
	maxRetries := 3
	retryCount := 0
	
	for retryCount < maxRetries {
		err := ns.sendNotification(ctx, notification)
		if err == nil {
			return nil
		}
		
		retryCount++
		log.Printf("Notification send failed (attempt %d/%d): %v", retryCount, maxRetries, err)
		
		if retryCount < maxRetries {
			time.Sleep(time.Duration(retryCount) * time.Second)
		}
	}
	
	// Send to DLQ after max retries
	notificationsFailed.Inc()
	dlqMessages.Inc()
	
	dlqMessage, _ := json.Marshal(notification)
	return ns.dlqWriter.WriteMessages(ctx, kafka.Message{
		Key:   []byte(notification.UserID),
		Value: dlqMessage,
		Headers: []kafka.Header{
			{Key: "original_topic", Value: []byte("notifications")},
			{Key: "failure_reason", Value: []byte("max_retries_exceeded")},
		},
	})
}

func (ns *NotificationService) startConsumer() {
	log.Println("Starting notification consumer...")
	
	ctx := context.Background()
	
	for {
		msg, err := ns.kafkaReader.ReadMessage(ctx)
		if err != nil {
			log.Printf("Error reading message: %v", err)
			continue
		}
		
		var notification Notification
		if err := json.Unmarshal(msg.Value, &notification); err != nil {
			log.Printf("Error unmarshaling notification: %v", err)
			continue
		}
		
		if err := ns.processNotification(ctx, notification); err != nil {
			log.Printf("Error processing notification: %v", err)
		}
	}
}

func main() {
	// Create service
	service := NewNotificationService()
	defer service.kafkaReader.Close()
	defer service.dlqWriter.Close()
	
	// Start consumer in goroutine
	go service.startConsumer()
	
	// HTTP server for health checks
	router := gin.Default()
	router.GET("/health/live", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "alive"})
	})
	router.GET("/health/ready", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ready"})
	})
	router.GET("/metrics", gin.WrapH(promhttp.Handler()))
	
	port := getEnv("PORT", "8080")
	srv := &http.Server{
		Addr:    fmt.Sprintf(":%s", port),
		Handler: router,
	}
	
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()
	
	log.Printf("Notification Service started on port %s", port)
	
	// Graceful shutdown
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

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}



