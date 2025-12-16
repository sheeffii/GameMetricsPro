/**
 * Analytics API Service
 * - Node.js/GraphQL API for analytics dashboard
 * - WebSocket for real-time updates
 * - Multi-tenant isolation
 */

const express = require('express');
const { createServer } = require('http');
const { WebSocketServer } = require('ws');
const { ApolloServer, gql } = require('apollo-server-express');
const { Kafka } = require('kafkajs');
const { Pool } = require('pg');
const Redis = require('ioredis');

const app = express();
const httpServer = createServer(app);

// Configuration
const PORT = process.env.PORT || 8080;
const KAFKA_BROKERS = process.env.KAFKA_BOOTSTRAP_SERVERS?.split(',') || 
  ['gamemetrics-kafka-bootstrap.kafka.svc.cluster.local:9092'];
const DB_CONFIG = {
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME || 'gamemetrics',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || '',
};

// Initialize clients
const dbPool = new Pool(DB_CONFIG);
const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  db: parseInt(process.env.REDIS_DB || '0'),
});

// Kafka consumer for real-time updates
const kafka = new Kafka({
  brokers: KAFKA_BROKERS,
  clientId: 'analytics-api',
});

const consumer = kafka.consumer({ groupId: 'analytics-api-group' });

// GraphQL Schema
const typeDefs = gql`
  type Query {
    playerStats(playerId: String!): PlayerStats
    gameStats(gameId: String!): GameStats
    leaderboard(gameId: String!, limit: Int): [LeaderboardEntry]
    events(playerId: String, gameId: String, limit: Int): [Event]
  }

  type PlayerStats {
    playerId: String!
    totalEvents: Int!
    totalGames: Int!
    lastActive: String!
    eventBreakdown: [EventCount]
  }

  type EventCount {
    eventType: String!
    count: Int!
  }

  type GameStats {
    gameId: String!
    totalPlayers: Int!
    totalEvents: Int!
    averageSessionDuration: Float!
  }

  type LeaderboardEntry {
    playerId: String!
    score: Int!
    rank: Int!
  }

  type Event {
    eventId: String!
    eventType: String!
    playerId: String!
    gameId: String!
    timestamp: String!
    data: String
  }
`;

// GraphQL Resolvers
const resolvers = {
  Query: {
    async playerStats(_, { playerId }) {
      try {
        const result = await dbPool.query(
          'SELECT * FROM player_statistics WHERE player_id = $1',
          [playerId]
        );
        
        if (result.rows.length === 0) {
          return null;
        }
        
        const stats = result.rows[0];
        return {
          playerId: stats.player_id,
          totalEvents: stats.total_events || 0,
          totalGames: 0, // Would calculate from events
          lastActive: stats.updated_at?.toISOString() || new Date().toISOString(),
          eventBreakdown: JSON.parse(stats.event_breakdown || '{}'),
        };
      } catch (error) {
        console.error('Error fetching player stats:', error);
        throw error;
      }
    },

    async gameStats(_, { gameId }) {
      try {
        const result = await dbPool.query(
          `SELECT COUNT(DISTINCT player_id) as total_players,
                  COUNT(*) as total_events
           FROM player_events
           WHERE game_id = $1`,
          [gameId]
        );
        
        return {
          gameId,
          totalPlayers: parseInt(result.rows[0].total_players) || 0,
          totalEvents: parseInt(result.rows[0].total_events) || 0,
          averageSessionDuration: 0, // Would calculate from events
        };
      } catch (error) {
        console.error('Error fetching game stats:', error);
        throw error;
      }
    },

    async leaderboard(_, { gameId, limit = 10 }) {
      try {
        const result = await dbPool.query(
          `SELECT player_id, MAX(CAST(data->>'score' AS INTEGER)) as score
           FROM player_events
           WHERE game_id = $1 AND data->>'score' IS NOT NULL
           GROUP BY player_id
           ORDER BY score DESC
           LIMIT $2`,
          [gameId, limit]
        );
        
        return result.rows.map((row, index) => ({
          playerId: row.player_id,
          score: parseInt(row.score) || 0,
          rank: index + 1,
        }));
      } catch (error) {
        console.error('Error fetching leaderboard:', error);
        throw error;
      }
    },

    async events(_, { playerId, gameId, limit = 100 }) {
      try {
        let query = 'SELECT * FROM player_events WHERE 1=1';
        const params = [];
        let paramIndex = 1;
        
        if (playerId) {
          query += ` AND player_id = $${paramIndex++}`;
          params.push(playerId);
        }
        
        if (gameId) {
          query += ` AND game_id = $${paramIndex++}`;
          params.push(gameId);
        }
        
        query += ` ORDER BY timestamp DESC LIMIT $${paramIndex++}`;
        params.push(limit);
        
        const result = await dbPool.query(query, params);
        
        return result.rows.map(row => ({
          eventId: row.event_id,
          eventType: row.event_type,
          playerId: row.player_id,
          gameId: row.game_id,
          timestamp: row.timestamp.toISOString(),
          data: JSON.stringify(row.data),
        }));
      } catch (error) {
        console.error('Error fetching events:', error);
        throw error;
      }
    },
  },
};

// Apollo Server
const apolloServer = new ApolloServer({
  typeDefs,
  resolvers,
  introspection: true,
  playground: true,
});

// WebSocket Server for real-time updates
const wss = new WebSocketServer({ server: httpServer, path: '/ws' });
const clients = new Set();

wss.on('connection', (ws) => {
  clients.add(ws);
  console.log('WebSocket client connected');
  
  ws.on('close', () => {
    clients.delete(ws);
    console.log('WebSocket client disconnected');
  });
  
  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
  });
});

// Broadcast updates to WebSocket clients
async function broadcastUpdate(data) {
  const message = JSON.stringify(data);
  clients.forEach((client) => {
    if (client.readyState === 1) { // OPEN
      client.send(message);
    }
  });
}

// Kafka consumer for real-time events
async function startKafkaConsumer() {
  await consumer.connect();
  await consumer.subscribe({ topic: 'player.events.processed', fromBeginning: false });
  
  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      try {
        const event = JSON.parse(message.value.toString());
        
        // Broadcast to WebSocket clients
        await broadcastUpdate({
          type: 'event',
          data: event,
        });
      } catch (error) {
        console.error('Error processing Kafka message:', error);
      }
    },
  });
}

// Health endpoints
app.get('/health/live', (req, res) => {
  res.json({ status: 'alive' });
});

app.get('/health/ready', async (req, res) => {
  try {
    await dbPool.query('SELECT 1');
    res.json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not ready', error: error.message });
  }
});

app.get('/metrics', (req, res) => {
  res.json({
    requests_total: 0,
    websocket_connections: clients.size,
  });
});

// Start server
async function start() {
  await apolloServer.start();
  apolloServer.applyMiddleware({ app });
  
  // Start Kafka consumer
  startKafkaConsumer().catch(console.error);
  
  httpServer.listen(PORT, () => {
    console.log(`Analytics API server running on port ${PORT}`);
    console.log(`GraphQL endpoint: http://localhost:${PORT}${apolloServer.graphqlPath}`);
    console.log(`WebSocket endpoint: ws://localhost:${PORT}/ws`);
  });
}

start().catch(console.error);



