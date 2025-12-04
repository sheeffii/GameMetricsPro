# System Architecture & Data Flow Diagrams

## 1. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    REAL-TIME GAMING ANALYTICS                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  INGESTION TIER                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  HTTP API Clients                                              │ │
│  │  (Game Servers, Mobile Apps, Web Clients)                     │ │
│  │          │                                                     │ │
│  │          └──> POST /api/v1/events                            │ │
│  │               (Go Event Ingestion Service)                    │ │
│  │               Rate Limit: 10K req/sec                         │ │
│  │               Metrics: Prometheus                             │ │
│  │               │                                               │ │
│  │               └──> Kafka Producer                             │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                      │                                               │
│                      ▼                                               │
│  MESSAGE BROKER TIER                                                 │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  Kafka Cluster (Strimzi Operator)                             │ │
│  │  - 3 Broker nodes                                             │ │
│  │  - Topic: player.events.raw (3 partitions)                   │ │
│  │  - Replication: 3                                             │ │
│  │  - Retention: 7 days                                          │ │
│  │                                                               │ │
│  │  Partitioning Strategy: hash(player_id) % 3                 │ │
│  │  (Ensures all events for a player go to same partition)      │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                      │                                               │
│     ┌────────────────┼────────────────┐                             │
│     │                │                │                             │
│     ▼                ▼                ▼                             │
│  CONSUMER TIER (3 independent services, parallel consumption)       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │  Logger      │  │  Stats Agg.  │  │  Leaderboard │              │
│  │  (2 replicas)│  │  (2 replicas)│  │  (1 replica) │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
│                                                                      │
│  PERSISTENCE TIER                                                    │
│  ┌────────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │ PostgreSQL     │  │ PostgreSQL   │  │ PostgreSQL   │             │
│  │ events table   │  │ statistics   │  │ leaderboards │             │
│  │ (Raw events)   │  │ (Agg data)   │  │ (Rankings)   │             │
│  └────────────────┘  └──────────────┘  └──────────────┘             │
│                         │                   │                        │
│                         ▼                   ▼                        │
│                    ┌──────────────────┐                              │
│                    │ Redis Cluster    │                              │
│                    │ DB 0: Stats      │                              │
│                    │ DB 1: Leaderboards                              │
│                    └──────────────────┘                              │
│                                                                      │
│  QUERY TIER                                                          │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  API Endpoints (Read-only)                                     │ │
│  │  - GET /player/{id}/stats → Redis                             │ │
│  │  - GET /games/{id}/leaderboard → Redis                        │ │
│  │  - GET /events/{id} → PostgreSQL                              │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Event Flow - Single Event Journey

```
T0: Event Created
   │
   ├─ game_server generates event
   │  └─ event_type: "player_score"
   │     player_id: "player-123"
   │     game_id: "game-456"
   │     data: {score: 1500}
   │
T1: Event Sent (≤1ms)
   │
   ├─ HTTP POST /api/v1/events
   │  └─ event-ingestion-service receives
   │
T2: Validation (≤2ms)
   │
   ├─ JSON validation
   ├─ Rate limit check
   ├─ Generate event_id (UUID)
   └─ Add ingested_at timestamp
   │
T3: Kafka Producer (≤10ms)
   │
   ├─ Serialize to JSON
   ├─ Partition: hash("player-123") % 3 = partition 1
   └─ Write to broker 1 (with replication to brokers 2, 3)
   │
T4: Consumer Assignment (≤50ms)
   │
   ├─ Logger consumer fetches from partition 1
   ├─ Stats aggregator fetches from partition 1
   └─ Leaderboard manager fetches from partition 1
   │
   │ (All 3 consume in parallel from same topic)
   │
T5: Logger Processing (1-5ms after T4)
   │
   ├─ Parse JSON
   ├─ Convert timestamps to datetime
   └─ INSERT into events table
   │     event_id, event_type, player_id, game_id, 
   │     event_timestamp, ingested_at, data
   │
T6: Stats Aggregator Processing (1-5ms after T4)
   │
   ├─ Extract player_id = "player-123"
   ├─ Increment event count in Redis
   ├─ Add to buffer (batch 100 events)
   └─ On buffer flush: UPDATE player_statistics table
   │
T7: Leaderboard Manager Processing (1-5ms after T4)
   │
   ├─ Check if event_type in {player_score, ...}
   ├─ Extract score = 1500
   ├─ ZADD leaderboard:game-456:alltime player-123 +1500
   └─ Periodically: flush top 100 to PostgreSQL
   │
T8+: Event Available for Queries
   │
   ├─ PostgreSQL events table: ready for analytics
   ├─ Redis cache: real-time stats available
   └─ Leaderboards: updated in real-time
   │
TOTAL LATENCY: ~50ms (T0 to T8)
```

---

## 3. Consumer Processing - Detailed View

### Logger Consumer

```
Kafka Topic: player.events.raw
              │
              ▼
┌─────────────────────────────────────┐
│  Event: {                           │
│    event_id: "abc123...",          │
│    event_type: "player_level_up",  │
│    player_id: "player-001",        │
│    game_id: "game-001",            │
│    timestamp: "2024-01-15...",     │
│    ingested_at: "2024-01-15...",   │
│    data: {level: 5, xp: 500}       │
│  }                                 │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  Logger Consumer (Python)           │
│  - Deserialize JSON                │
│  - Validate required fields        │
│  - Convert timestamps              │
│  - Handle errors (→ DLQ)           │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  PostgreSQL Insert                 │
│  INSERT INTO events (               │
│    event_id: "abc123...",          │
│    event_type: "player_level_up",  │
│    player_id: "player-001",        │
│    game_id: "game-001",            │
│    event_timestamp: ...,           │
│    ingested_at: ...,               │
│    data: {"level": 5, "xp": 500},  │
│    created_at: NOW()               │
│  );                                │
└─────────────────────────────────────┘
              │
              ▼
PostgreSQL events table
(Audit trail, analytics, data lake)
```

### Stats Aggregator Consumer

```
Kafka Topic: player.events.raw
              │
              ▼ (All events from partition)
┌─────────────────────────────────────┐
│  Event 1: player_level_up           │
│  Event 2: player_score (+100 pts)   │
│  Event 3: quest_completed           │
│  Event 4: achievement_unlocked      │
│  Event 5: player_score (+500 pts)   │
│  ... (repeat 95 more)               │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  Stats Aggregator (Python)          │
│                                     │
│  In-Memory Buffer (100 events):     │
│  - player-001: 5 total events       │
│    {                                │
│      player_level_up: 1,           │
│      player_score: 2,               │
│      quest_completed: 1,            │
│      achievement_unlocked: 1        │
│    }                                │
│  - player-002: 3 total events       │
│  - ... (etc)                        │
│                                     │
│  Every 30 seconds OR 100 events:    │
│  Flush buffer to database           │
└─────────────────────────────────────┘
              │
         ┌────┴────┐
         │          │
         ▼          ▼
   PostgreSQL    Redis
   (Persistent)  (Cache)
   
   UPDATE player_statistics
   SET
     total_events = 5,
     event_breakdown = {
       "player_level_up": 1,
       "player_score": 2,
       "quest_completed": 1,
       "achievement_unlocked": 1
     },
     updated_at = NOW()
   WHERE player_id = 'player-001';
   
   HSET player_stats:player-001
     total_events 5
     last_event "2024-01-15..."
     event_player_score 2
     event_player_level_up 1
```

### Leaderboard Manager Consumer

```
Kafka Topic: player.events.raw
              │
              ▼ (Filter: only scoring events)
┌─────────────────────────────────────┐
│  FILTERING                          │
│  Score Events Only:                │
│  - player_score                    │
│  - quest_completed                 │
│  - achievement_unlocked            │
│  - boss_defeated                   │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  Event: player_score                │
│  Data: {score: 1500}                │
│  Player: player-001                 │
│  Game: game-001                     │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  Leaderboard Manager (Python)       │
│                                     │
│  1. Extract score = 1500            │
│  2. ZADD Redis sorted set           │
│     leaderboard:game-001:daily      │
│     leaderboard:game-001:weekly     │
│     leaderboard:game-001:alltime    │
│  3. Update ranks (real-time)        │
│  4. Every 50 events: flush top 100  │
│     to PostgreSQL                   │
└─────────────────────────────────────┘
              │
         ┌────┴────┐
         │          │
         ▼          ▼
   PostgreSQL    Redis
   (Top 100)     (Real-time)
   
   INSERT INTO leaderboards
   (game_id, player_id, rank, score,
    period, updated_at)
   VALUES
   (game-001, player-001, 1, 1500, alltime, NOW())
   
   ON CONFLICT... DO UPDATE;
   
   ZADD leaderboard:game-001:alltime
     1500 player-001
   
   (Rankings update as new scores arrive)
```

---

## 4. Data Model - Database Schema

```
┌─────────────────────────────────────────┐
│          RAW EVENTS TABLE              │
├─────────────────────────────────────────┤
│ PK: event_id (UUID)                    │
├─────────────────────────────────────────┤
│ event_type (VARCHAR 100)               │ Index: event_type
│ player_id (VARCHAR 100)                │ Index: player_id
│ game_id (VARCHAR 100)                  │ Index: game_id
│ event_timestamp (TIMESTAMP)            │ Index: timestamp DESC
│ ingested_at (TIMESTAMP)                │ (for ordering)
│ data (JSONB)                           │
│ created_at (TIMESTAMP)                 │
├─────────────────────────────────────────┤
│ Example Row:                           │
│ {                                      │
│   event_id: uuid,                      │
│   event_type: "player_level_up",      │
│   player_id: "player-001",             │
│   game_id: "game-001",                 │
│   event_timestamp: 2024-01-15 10:00,   │
│   ingested_at: 2024-01-15 10:00:01,    │
│   data: {                              │
│     level: 5,                          │
│     experience: 500,                   │
│     achievement: "first_level_5"       │
│   },                                   │
│   created_at: 2024-01-15 10:00:01      │
│ }                                      │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│     PLAYER STATISTICS TABLE            │
├─────────────────────────────────────────┤
│ PK: player_id (VARCHAR 100)            │
├─────────────────────────────────────────┤
│ total_events (INTEGER)                 │
│ event_breakdown (JSONB)                │
│ updated_at (TIMESTAMP)                 │
│ created_at (TIMESTAMP)                 │
├─────────────────────────────────────────┤
│ Example Row:                           │
│ {                                      │
│   player_id: "player-001",             │
│   total_events: 47,                    │
│   event_breakdown: {                   │
│     "player_score": 15,                │
│     "player_level_up": 5,              │
│     "quest_completed": 12,             │
│     "achievement_unlocked": 8,         │
│     "boss_defeated": 7                 │
│   },                                   │
│   updated_at: 2024-01-15 10:30,        │
│   created_at: 2024-01-10 08:00         │
│ }                                      │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│      LEADERBOARDS TABLE                │
├─────────────────────────────────────────┤
│ PK: (game_id, player_id, period)       │
├─────────────────────────────────────────┤
│ rank (INTEGER)                         │ Index: rank
│ score (BIGINT)                         │ Index: score DESC
│ period (VARCHAR 50)                    │ Values: daily/weekly/alltime
│ updated_at (TIMESTAMP)                 │
│ created_at (TIMESTAMP)                 │
├─────────────────────────────────────────┤
│ Example Rows:                          │
│ {                                      │
│   game_id: "game-001",                 │
│   player_id: "player-001",             │
│   rank: 1,                             │
│   score: 150000,                       │
│   period: "alltime",                   │
│   updated_at: 2024-01-15 10:30         │
│ },                                     │
│ {                                      │
│   game_id: "game-001",                 │
│   player_id: "player-002",             │
│   rank: 2,                             │
│   score: 145000,                       │
│   period: "alltime",                   │
│   updated_at: 2024-01-15 10:30         │
│ }                                      │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│      DLQ (DEAD LETTER QUEUE)            │
├─────────────────────────────────────────┤
│ PK: id (SERIAL)                        │
├─────────────────────────────────────────┤
│ original_event (JSONB)                 │
│ error_message (TEXT)                   │
│ consumer_service (VARCHAR 100)         │
│ created_at (TIMESTAMP)                 │
├─────────────────────────────────────────┤
│ Example Row:                           │
│ {                                      │
│   id: 1,                               │
│   original_event: {...},               │
│   error_message: "DB connection timeout", │
│   consumer_service: "event-logger",    │
│   created_at: 2024-01-15 10:05         │
│ }                                      │
└─────────────────────────────────────────┘
```

---

## 5. Deployment Architecture

```
┌────────────────────────────────────────────────────────┐
│           AWS EKS Cluster                             │
│  (Kubernetes)                                         │
├────────────────────────────────────────────────────────┤
│                                                        │
│  ┌─────────────────────────────────────────────────┐ │
│  │  gamemetrics Namespace                          │ │
│  ├─────────────────────────────────────────────────┤ │
│  │                                                 │ │
│  │  Service: event-ingestion (Port 8080)          │ │
│  │  └─ Deployment: event-ingestion (2 replicas)  │ │
│  │     └─ Pod: event-ingestion-xxx                │ │
│  │     └─ Pod: event-ingestion-yyy                │ │
│  │                                                 │ │
│  │  Deployment: event-consumer-logger (2 rep)    │ │
│  │  └─ Pod: event-consumer-logger-aaa             │ │
│  │  └─ Pod: event-consumer-logger-bbb             │ │
│  │                                                 │ │
│  │  Deployment: event-consumer-stats (2 rep)     │ │
│  │  └─ Pod: event-consumer-stats-ccc              │ │
│  │  └─ Pod: event-consumer-stats-ddd              │ │
│  │                                                 │ │
│  │  Deployment: event-consumer-leaderboard (1)   │ │
│  │  └─ Pod: event-consumer-leaderboard-eee        │ │
│  │                                                 │ │
│  │  ConfigMap: event-consumer-config              │ │
│  │  Secret: kafka-credentials                     │ │
│  │  Secret: db-credentials                        │ │
│  │  Secret: redis-credentials                     │ │
│  │                                                 │ │
│  └─────────────────────────────────────────────────┘ │
│                                                        │
│  ┌─────────────────────────────────────────────────┐ │
│  │  kafka Namespace (Strimzi)                      │ │
│  ├─────────────────────────────────────────────────┤ │
│  │                                                 │ │
│  │  Kafka Cluster: gamemetrics-kafka              │ │
│  │  ├─ Broker 0 (Pod)                             │ │
│  │  ├─ Broker 1 (Pod)                             │ │
│  │  └─ Broker 2 (Pod)                             │ │
│  │                                                 │ │
│  │  Kafka UI Service                              │ │
│  │                                                 │ │
│  └─────────────────────────────────────────────────┘ │
│                                                        │
└────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
    ┌─────────────┐   ┌──────────────┐   ┌───────────────┐
    │ AWS RDS     │   │ ElastiCache  │   │ S3 Bucket     │
    │ PostgreSQL  │   │ Redis        │   │ (for configs) │
    │ gamemetrics │   │ 6 nodes      │   │               │
    │ Prod DB     │   │              │   │               │
    └─────────────┘   └──────────────┘   └───────────────┘
```

---

## 6. Request/Response Flow

```
CLIENT REQUEST
│
├─ POST /api/v1/events
│  Content-Type: application/json
│  Body: {
│    "event_type": "player_score",
│    "player_id": "player-001",
│    "game_id": "game-001",
│    "timestamp": "2024-01-15T10:30:00Z",
│    "data": {"score": 1500}
│  }
│
▼
event-ingestion-service (Go)
│
├─ Rate limiter: Allow? (10K req/sec)
├─ JSON validation
├─ Generate event_id: "550e8400-e29b-41d4-a716-446655440000"
├─ Add ingested_at: "2024-01-15T10:30:01Z"
├─ Kafka Producer: WriteMessages()
│  └─ Partition key: SHA256(player-001) % 3 = partition 1
│  └─ Message headers: event_type, event_id
│  └─ Message value: JSON serialized event
│
▼
Kafka Broker
│
├─ Receive from producer
├─ Replicate to 2 other brokers (sync)
├─ Commit offset
├─ Emit to subscribers
│
▼
Three Consumer Groups (in parallel)
│
├─ Group 1: event-logger-group
│  └─ Consumer 1-A fetches and processes
│  └─ Consumer 1-B fetches and processes
│
├─ Group 2: stats-aggregator-group
│  └─ Consumer 2-A fetches and processes
│  └─ Consumer 2-B fetches and processes
│
└─ Group 3: leaderboard-manager-group
   └─ Consumer 3-A fetches and processes
│
▼
HTTP RESPONSE (immediate, after Kafka confirms)
│
└─ Status: 200 OK
   Content-Type: application/json
   Body: {
     "status": "success",
     "event_id": "550e8400-e29b-41d4-a716-446655440000"
   }

(Meanwhile, consumers process in background)

EVENT EVENTUALLY REACHES:
├─ PostgreSQL events table (2-5ms)
├─ PostgreSQL player_statistics (batched)
├─ Redis cache (real-time)
└─ PostgreSQL leaderboards (periodic flush)

TOTAL LATENCY: <50ms to database, <10ms HTTP response
```

---

This visual documentation helps you understand:
- How data flows from HTTP request to database
- Why there are 3 independent consumers
- How Kafka partitioning works
- Database schema relationships
- Kubernetes deployment structure

