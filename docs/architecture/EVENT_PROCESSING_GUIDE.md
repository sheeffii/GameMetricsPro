# Production Event Processing Pipeline Guide

## Overview
Your gaming analytics platform processes events in real-time through a complete pipeline:

```
HTTP POST /api/v1/events 
  ↓
Go Event Ingestion Service (Kafka Producer)
  ↓
Kafka Topics (player.events.raw, player.events.processed, etc.)
  ↓
Python Consumer Services (read from Kafka)
  ↓
PostgreSQL Database (raw events, statistics, leaderboards)
  ↓
Redis Cache (real-time statistics, session data)
```

---

## Part 1: Producer (Go Application)

### Current Status: ✅ IMPLEMENTED

Your Go service at `services/event-ingestion-service/cmd/main.go` already implements the Kafka producer:

```go
// Kafka Writer Configuration
kafkaWriter := &kafka.Writer{
    Addr:         kafka.TCP(brokers...),
    Topic:        "player.events.raw",  // Raw events topic
    Balancer:     &kafka.Hash{},
    RequiredAcks: -1,                  // Wait for all replicas (safest)
    BatchSize:    100,                 // Batch events
    BatchTimeout: 10 * time.Millisecond,
}

// HTTP Endpoint: POST /api/v1/events
func (s *Server) ingestEvent(c *gin.Context) {
    // 1. Parse HTTP request
    var event Event
    if err := c.ShouldBindJSON(&event); err != nil {
        return
    }
    
    // 2. Add metadata (eventID, ingestion timestamp)
    eventWithMetadata := map[string]interface{}{
        "event_id":   uuid.New().String(),
        "event_type": event.EventType,
        "player_id":  event.PlayerID,
        "game_id":    event.GameID,
        "timestamp":  event.Timestamp,
        "data":       event.Data,
        "ingested_at": time.Now(),
    }
    
    // 3. Publish to Kafka topic
    err = s.kafkaWriter.WriteMessages(ctx, kafka.Message{
        Key:   []byte(event.PlayerID),  // Partition by player_id
        Value: eventJSON,                // Message body
        Headers: []kafka.Header{
            {Key: "event_type", Value: []byte(event.EventType)},
            {Key: "event_id", Value: []byte(eventID)},
        },
    })
}
```

### Test the Producer

```bash
# 1. Port-forward to the service
kubectl port-forward -n gamemetrics svc/event-ingestion 8080:8080 &

# 2. Send a test event
curl -X POST http://localhost:8080/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "player_level_up",
    "player_id": "player-123",
    "game_id": "game-456",
    "timestamp": "2024-01-01T12:00:00Z",
    "data": {
      "level": 5,
      "experience": 1000
    }
  }'

# Expected response:
# {"status": "success", "event_id": "550e8400-e29b-41d4-a716-446655440000"}

# 3. Check Kafka UI to see the event in player.events.raw topic
# Access via: kubectl port-forward -n kafka svc/strimzi-kakfa-ui 8081:8081
# Then visit http://localhost:8081 → Messages
```

---

## Part 2: Kafka Topics Configuration

### Existing Topics in Your Cluster

Your infrastructure creates these topics:

| Topic | Purpose | Partitions | Retention |
|-------|---------|-----------|-----------|
| `player.events.raw` | Raw incoming events | 3 | 7 days |
| `player.events.processed` | Events after validation | 3 | 7 days |
| `player.statistics` | Aggregated player stats | 3 | 30 days |
| `game.leaderboards` | Leaderboard updates | 1 | 30 days |
| `system.dlq` | Dead letter queue | 1 | 30 days |

### Event Schema (JSON)

All events follow this structure:

```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_type": "player_level_up",
  "player_id": "player-123",
  "game_id": "game-456",
  "timestamp": "2024-01-01T12:00:00Z",
  "ingested_at": "2024-01-01T12:00:01Z",
  "data": {
    "level": 5,
    "experience": 1000,
    "achievement_id": "first_level_5"
  }
}
```

---

## Part 3: Consumer Services (Python)

### Architecture

You need **3 independent consumer services**:

1. **Raw Event Logger** → Writes to PostgreSQL `events` table
2. **Statistics Aggregator** → Calculates player stats, writes to `player_statistics` table
3. **Leaderboard Manager** → Updates Redis leaderboards and PostgreSQL `leaderboards` table

Each runs in its own Kubernetes Pod and reads from specific Kafka topics.

### Service 1: Raw Event Logger Consumer

**File:** `services/event-consumer-logger/consumer.py`

```python
import json
import logging
import os
from datetime import datetime
from typing import Dict, Any

import psycopg2
from psycopg2.extras import Json
from kafka import KafkaConsumer
from kafka.errors import KafkaError

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class RawEventLogger:
    def __init__(self):
        # Kafka configuration
        self.consumer = KafkaConsumer(
            'player.events.raw',  # Topic to consume
            bootstrap_servers=os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092').split(','),
            group_id='event-logger-group',
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            auto_offset_reset='earliest',
            enable_auto_commit=True,
            max_poll_records=100,
            session_timeout_ms=30000,
        )
        
        # Database configuration
        self.db_params = {
            'host': os.getenv('DB_HOST'),
            'port': os.getenv('DB_PORT', '5432'),
            'database': os.getenv('DB_NAME'),
            'user': os.getenv('DB_USER'),
            'password': os.getenv('DB_PASSWORD'),
        }
        
        # Kafka SASL/SCRAM (if enabled)
        if os.getenv('KAFKA_USERNAME'):
            self.consumer = KafkaConsumer(
                'player.events.raw',
                bootstrap_servers=os.getenv('KAFKA_BOOTSTRAP_SERVERS').split(','),
                group_id='event-logger-group',
                value_deserializer=lambda m: json.loads(m.decode('utf-8')),
                security_protocol='SASL_SSL' if os.getenv('KAFKA_SECURITY_PROTOCOL') else 'SASL_PLAINTEXT',
                sasl_mechanism='SCRAM-SHA-512',
                sasl_plain_username=os.getenv('KAFKA_USERNAME'),
                sasl_plain_password=os.getenv('KAFKA_PASSWORD'),
                auto_offset_reset='earliest',
            )
    
    def process_event(self, event: Dict[str, Any]) -> bool:
        """Write raw event to PostgreSQL"""
        try:
            conn = psycopg2.connect(**self.db_params)
            cur = conn.cursor()
            
            # Insert event
            cur.execute("""
                INSERT INTO events (
                    event_id, event_type, player_id, game_id, 
                    event_timestamp, ingested_at, data, created_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
                ON CONFLICT (event_id) DO NOTHING
            """, (
                event['event_id'],
                event['event_type'],
                event['player_id'],
                event['game_id'],
                datetime.fromisoformat(event['timestamp'].replace('Z', '+00:00')),
                datetime.fromisoformat(event['ingested_at'].replace('Z', '+00:00')),
                Json(event.get('data', {})),
            ))
            
            conn.commit()
            cur.close()
            conn.close()
            
            logger.info(f"Event {event['event_id']} logged to database")
            return True
            
        except Exception as e:
            logger.error(f"Failed to process event: {e}")
            # Send to DLQ on error
            self.send_to_dlq(event, str(e))
            return False
    
    def send_to_dlq(self, event: Dict[str, Any], error: str):
        """Send failed events to dead letter queue"""
        try:
            dlq_producer = KafkaProducer(
                bootstrap_servers=os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092').split(','),
                value_serializer=lambda m: json.dumps(m).encode('utf-8'),
            )
            dlq_producer.send('system.dlq', {
                'original_event': event,
                'error': error,
                'timestamp': datetime.utcnow().isoformat(),
                'consumer_service': 'event-logger',
            })
            dlq_producer.close()
        except Exception as e:
            logger.error(f"Failed to send to DLQ: {e}")
    
    def start(self):
        """Start consuming events"""
        logger.info("Starting Raw Event Logger Consumer...")
        for message in self.consumer:
            event = message.value
            self.process_event(event)

if __name__ == '__main__':
    logger = RawEventLogger()
    logger.start()
```

### Service 2: Statistics Aggregator Consumer

**File:** `services/event-consumer-stats/consumer.py`

```python
import json
import logging
import os
import redis
from datetime import datetime, timedelta
from typing import Dict, Any
from collections import defaultdict

import psycopg2
from kafka import KafkaConsumer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class StatisticsAggregator:
    def __init__(self):
        self.consumer = KafkaConsumer(
            'player.events.raw',
            bootstrap_servers=os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092').split(','),
            group_id='stats-aggregator-group',
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            auto_offset_reset='earliest',
        )
        
        # Database
        self.db_params = {
            'host': os.getenv('DB_HOST'),
            'port': os.getenv('DB_PORT', '5432'),
            'database': os.getenv('DB_NAME'),
            'user': os.getenv('DB_USER'),
            'password': os.getenv('DB_PASSWORD'),
        }
        
        # Redis for real-time stats
        self.redis_client = redis.Redis(
            host=os.getenv('REDIS_HOST', 'localhost'),
            port=int(os.getenv('REDIS_PORT', '6379')),
            decode_responses=True,
        )
        
        # In-memory buffers for batching
        self.stats_buffer = defaultdict(dict)
        self.buffer_size = 100
        self.buffer_timeout = timedelta(seconds=30)
        self.last_flush = datetime.utcnow()
    
    def process_event(self, event: Dict[str, Any]):
        """Update statistics based on event"""
        player_id = event['player_id']
        event_type = event['event_type']
        
        # Update in-memory buffer
        if player_id not in self.stats_buffer:
            self.stats_buffer[player_id] = {
                'total_events': 0,
                'event_types': defaultdict(int),
                'last_updated': datetime.utcnow(),
            }
        
        self.stats_buffer[player_id]['total_events'] += 1
        self.stats_buffer[player_id]['event_types'][event_type] += 1
        self.stats_buffer[player_id]['last_updated'] = datetime.utcnow()
        
        # Update Redis in real-time
        self.redis_client.hincrby(f"player_stats:{player_id}", 'total_events', 1)
        self.redis_client.hincrby(f"player_stats:{player_id}", f'event_{event_type}', 1)
        self.redis_client.hset(f"player_stats:{player_id}", 'last_event', 
                               datetime.utcnow().isoformat())
        
        # Flush to database if buffer is full or timed out
        if len(self.stats_buffer) >= self.buffer_size or \
           (datetime.utcnow() - self.last_flush) > self.buffer_timeout:
            self.flush_to_database()
    
    def flush_to_database(self):
        """Persist buffered statistics to PostgreSQL"""
        if not self.stats_buffer:
            return
        
        try:
            conn = psycopg2.connect(**self.db_params)
            cur = conn.cursor()
            
            for player_id, stats in self.stats_buffer.items():
                cur.execute("""
                    INSERT INTO player_statistics (
                        player_id, total_events, event_breakdown, updated_at
                    ) VALUES (%s, %s, %s, NOW())
                    ON CONFLICT (player_id) DO UPDATE SET
                        total_events = EXCLUDED.total_events,
                        event_breakdown = EXCLUDED.event_breakdown,
                        updated_at = NOW()
                """, (
                    player_id,
                    stats['total_events'],
                    json.dumps(dict(stats['event_types'])),
                ))
            
            conn.commit()
            cur.close()
            conn.close()
            
            logger.info(f"Flushed {len(self.stats_buffer)} player stats to database")
            self.stats_buffer.clear()
            self.last_flush = datetime.utcnow()
            
        except Exception as e:
            logger.error(f"Failed to flush statistics: {e}")
    
    def start(self):
        """Start consuming and aggregating events"""
        logger.info("Starting Statistics Aggregator Consumer...")
        for message in self.consumer:
            event = message.value
            self.process_event(event)

if __name__ == '__main__':
    aggregator = StatisticsAggregator()
    aggregator.start()
```

### Service 3: Leaderboard Manager Consumer

**File:** `services/event-consumer-leaderboard/consumer.py`

```python
import json
import logging
import os
import redis
from datetime import datetime
from typing import Dict, Any

import psycopg2
from kafka import KafkaConsumer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class LeaderboardManager:
    def __init__(self):
        self.consumer = KafkaConsumer(
            'player.events.raw',
            bootstrap_servers=os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092').split(','),
            group_id='leaderboard-manager-group',
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            auto_offset_reset='earliest',
        )
        
        # Database
        self.db_params = {
            'host': os.getenv('DB_HOST'),
            'port': os.getenv('DB_PORT', '5432'),
            'database': os.getenv('DB_NAME'),
            'user': os.getenv('DB_USER'),
            'password': os.getenv('DB_PASSWORD'),
        }
        
        # Redis for leaderboards
        self.redis_client = redis.Redis(
            host=os.getenv('REDIS_HOST', 'localhost'),
            port=int(os.getenv('REDIS_PORT', '6379')),
            decode_responses=True,
        )
    
    def process_event(self, event: Dict[str, Any]):
        """Update leaderboards based on specific events"""
        event_type = event['event_type']
        player_id = event['player_id']
        game_id = event['game_id']
        data = event.get('data', {})
        
        # Only process scoring events
        if event_type == 'player_score':
            score = data.get('score', 0)
            
            # Update Redis leaderboard (sorted set, descending)
            self.redis_client.zadd(
                f"leaderboard:{game_id}:daily",
                {player_id: score},
                incr=True  # Add to existing score
            )
            
            # Also update weekly/monthly
            self.redis_client.zadd(f"leaderboard:{game_id}:weekly", {player_id: score}, incr=True)
            self.redis_client.zadd(f"leaderboard:{game_id}:alltime", {player_id: score}, incr=True)
            
            # Persist top 100 to database daily
            self.update_leaderboard_database(game_id)
            
            logger.info(f"Updated leaderboard for {player_id} with score {score}")
    
    def update_leaderboard_database(self, game_id: str):
        """Save top 100 players to database"""
        try:
            # Get top 100 from Redis
            top_100 = self.redis_client.zrange(
                f"leaderboard:{game_id}:alltime",
                0, 99,
                withscores=True,
                byscore=False,
                rev=True
            )
            
            conn = psycopg2.connect(**self.db_params)
            cur = conn.cursor()
            
            for rank, (player_id, score) in enumerate(top_100, 1):
                cur.execute("""
                    INSERT INTO leaderboards (
                        game_id, player_id, rank, score, period, updated_at
                    ) VALUES (%s, %s, %s, %s, 'alltime', NOW())
                    ON CONFLICT (game_id, player_id, period) DO UPDATE SET
                        rank = EXCLUDED.rank,
                        score = EXCLUDED.score,
                        updated_at = NOW()
                """, (game_id, player_id, rank, int(score)))
            
            conn.commit()
            cur.close()
            conn.close()
            
        except Exception as e:
            logger.error(f"Failed to update leaderboard database: {e}")
    
    def start(self):
        """Start consuming events"""
        logger.info("Starting Leaderboard Manager Consumer...")
        for message in self.consumer:
            event = message.value
            self.process_event(event)

if __name__ == '__main__':
    manager = LeaderboardManager()
    manager.start()
```

---

## Part 4: Database Schema

**File:** `terraform/database/schema.sql`

```sql
-- Raw events table
CREATE TABLE IF NOT EXISTS events (
    event_id UUID PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL,
    player_id VARCHAR(100) NOT NULL,
    game_id VARCHAR(100) NOT NULL,
    event_timestamp TIMESTAMP NOT NULL,
    ingested_at TIMESTAMP NOT NULL,
    data JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_player_id (player_id),
    INDEX idx_game_id (game_id),
    INDEX idx_event_type (event_type),
    INDEX idx_timestamp (event_timestamp)
);

-- Player statistics
CREATE TABLE IF NOT EXISTS player_statistics (
    player_id VARCHAR(100) PRIMARY KEY,
    total_events INTEGER DEFAULT 0,
    event_breakdown JSONB DEFAULT '{}',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Leaderboards
CREATE TABLE IF NOT EXISTS leaderboards (
    game_id VARCHAR(100) NOT NULL,
    player_id VARCHAR(100) NOT NULL,
    rank INTEGER NOT NULL,
    score BIGINT NOT NULL,
    period VARCHAR(50) NOT NULL, -- 'daily', 'weekly', 'alltime'
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (game_id, player_id, period),
    INDEX idx_game_period (game_id, period),
    INDEX idx_rank (rank)
);

-- Dead letter queue for failed events
CREATE TABLE IF NOT EXISTS dlq_events (
    id SERIAL PRIMARY KEY,
    original_event JSONB NOT NULL,
    error_message TEXT,
    consumer_service VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_service (consumer_service)
);
```

---

## Part 5: Complete Event Flow Example

### Test Scenario: Player levels up

**Step 1: Send event from HTTP**
```bash
curl -X POST http://localhost:8080/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "player_level_up",
    "player_id": "player-123",
    "game_id": "game-456",
    "timestamp": "2024-01-01T12:00:00Z",
    "data": {
      "new_level": 5,
      "experience_gained": 500,
      "achievement_unlocked": "first_level_5"
    }
  }'
```

**Response:**
```json
{
  "status": "success",
  "event_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Step 2: Event goes to Kafka**
- Topic: `player.events.raw`
- Partition: `hash("player-123") % 3` (consistent partitioning)
- Message:
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_type": "player_level_up",
  "player_id": "player-123",
  "game_id": "game-456",
  "timestamp": "2024-01-01T12:00:00Z",
  "ingested_at": "2024-01-01T12:00:01Z",
  "data": {
    "new_level": 5,
    "experience_gained": 500,
    "achievement_unlocked": "first_level_5"
  }
}
```

**Step 3: Parallel consumption**

| Consumer | Action | Database Table |
|----------|--------|------------------|
| **Raw Logger** | Inserts raw event | `events` |
| **Stats Aggregator** | Increments `player_statistics.total_events` | `player_statistics` |
| **Leaderboard Manager** | (No action - not a scoring event) | - |

**Step 4: Verify in database**
```sql
-- Check event was logged
SELECT * FROM events WHERE player_id = 'player-123';

-- Check statistics were updated
SELECT * FROM player_statistics WHERE player_id = 'player-123';

-- Check Redis real-time stats
redis-cli HGETALL player_stats:player-123
```

---

## Deployment Commands (Next Steps)

### 1. Deploy Python Consumer Services
```bash
# Create Python consumer deployments
kubectl apply -f k8s/services/event-consumer-logger/deployment.yaml
kubectl apply -f k8s/services/event-consumer-stats/deployment.yaml
kubectl apply -f k8s/services/event-consumer-leaderboard/deployment.yaml

# Check they're running
kubectl get pods -n gamemetrics -l component=consumer
```

### 2. Send Bulk Test Events
```bash
# Run load test
python scripts/load_test_events.py --count 1000 --rate 100
```

### 3. Monitor Pipeline
```bash
# Terminal 1: Watch Kafka topics
kubectl logs -n gamemetrics deployment/event-consumer-logger -f

# Terminal 2: Check database
psql $DB_URL -c "SELECT COUNT(*) FROM events;"

# Terminal 3: Check Redis
redis-cli --stat
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Events not appearing in Kafka | Check `KAFKA_BOOTSTRAP_SERVERS` environment variable, verify Kafka brokers are running |
| Consumer not processing events | Check consumer group offsets: `kafka-consumer-groups --bootstrap-server localhost:9092 --group event-logger-group --describe` |
| Database inserts failing | Verify DB credentials in secrets, check schema exists |
| Redis not updating | Check Redis connection string, verify Redis pod is running |

