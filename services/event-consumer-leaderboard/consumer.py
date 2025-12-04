"""
Leaderboard Manager Consumer
- Reads from: player.events.raw Kafka topic (filtered for scoring events)
- Writes to: PostgreSQL leaderboards table + Redis sorted sets
- Purpose: Maintain real-time leaderboards and scoreboard rankings
"""

import json
import logging
import os
import sys
from datetime import datetime
from typing import Dict, Any, List, Tuple

import psycopg2
import redis
from kafka import KafkaConsumer

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class LeaderboardManager:
    """Manage leaderboards from event stream"""
    
    # Event types that contribute to scores
    SCORING_EVENTS = {'player_score', 'quest_completed', 'achievement_unlocked', 'boss_defeated'}
    
    def __init__(self):
        """Initialize Kafka consumer, database, and Redis"""
        self.consumer = self._init_kafka_consumer()
        self.db_params = self._get_db_params()
        self.redis_client = self._init_redis()
        self.top_n = int(os.getenv('LEADERBOARD_TOP_N', '100'))
        
        self.stats = {
            'processed': 0,
            'updated_redis': 0,
            'updated_db': 0,
            'failed': 0,
        }
    
    def _init_kafka_consumer(self) -> KafkaConsumer:
        """Initialize Kafka consumer"""
        bootstrap_servers = os.getenv(
            'KAFKA_BOOTSTRAP_SERVERS',
            'localhost:9092'
        ).split(',')
        
        config = {
            'bootstrap_servers': bootstrap_servers,
            'group_id': os.getenv('KAFKA_GROUP_ID', 'leaderboard-manager-group'),
            'topic_name': os.getenv('KAFKA_TOPIC', 'player.events.raw'),
            'value_deserializer': lambda m: json.loads(m.decode('utf-8')),
            'auto_offset_reset': 'earliest',
            'enable_auto_commit': True,
            'max_poll_records': int(os.getenv('KAFKA_MAX_POLL_RECORDS', '100')),
        }
        
        if os.getenv('KAFKA_USERNAME'):
            config.update({
                'security_protocol': os.getenv('KAFKA_SECURITY_PROTOCOL', 'SASL_PLAINTEXT'),
                'sasl_mechanism': 'SCRAM-SHA-512',
                'sasl_plain_username': os.getenv('KAFKA_USERNAME'),
                'sasl_plain_password': os.getenv('KAFKA_PASSWORD'),
            })
        
        topic = config.pop('topic_name')
        consumer = KafkaConsumer(topic, **config)
        logger.info(f"Kafka consumer initialized for topic: {topic}")
        return consumer
    
    def _get_db_params(self) -> Dict[str, str]:
        """Get database parameters"""
        return {
            'host': os.getenv('DB_HOST', 'localhost'),
            'port': os.getenv('DB_PORT', '5432'),
            'database': os.getenv('DB_NAME', 'gamemetrics'),
            'user': os.getenv('DB_USER', 'postgres'),
            'password': os.getenv('DB_PASSWORD', ''),
            'connect_timeout': 5,
        }
    
    def _init_redis(self) -> redis.Redis:
        """Initialize Redis connection"""
        try:
            client = redis.Redis(
                host=os.getenv('REDIS_HOST', 'localhost'),
                port=int(os.getenv('REDIS_PORT', '6379')),
                db=int(os.getenv('REDIS_DB', '1')),  # Use DB 1 for leaderboards
                decode_responses=True,
                socket_connect_timeout=5,
            )
            client.ping()
            logger.info("Redis connection established for leaderboards")
            return client
        except Exception as e:
            logger.warning(f"Redis connection failed: {e}")
            return None
    
    def get_score_from_event(self, event_type: str, data: Dict[str, Any]) -> int:
        """Extract score value from event data"""
        if event_type == 'player_score':
            return int(data.get('score', 0))
        elif event_type == 'quest_completed':
            return int(data.get('reward_points', 10))
        elif event_type == 'achievement_unlocked':
            return int(data.get('points', 5))
        elif event_type == 'boss_defeated':
            return int(data.get('difficulty_score', 50))
        return 0
    
    def process_event(self, event: Dict[str, Any]):
        """Update leaderboards based on scoring events"""
        event_type = event.get('event_type')
        
        # Only process scoring events
        if event_type not in self.SCORING_EVENTS:
            return
        
        player_id = event.get('player_id')
        game_id = event.get('game_id')
        data = event.get('data', {})
        
        if not player_id or not game_id:
            logger.warning(f"Event missing player_id or game_id: {event}")
            return
        
        score = self.get_score_from_event(event_type, data)
        
        if score <= 0:
            return
        
        # Update Redis leaderboards (sorted sets)
        if self.redis_client:
            try:
                self.redis_client.zadd(
                    f"leaderboard:{game_id}:daily",
                    {player_id: score},
                    incr=True
                )
                self.redis_client.zadd(
                    f"leaderboard:{game_id}:weekly",
                    {player_id: score},
                    incr=True
                )
                self.redis_client.zadd(
                    f"leaderboard:{game_id}:alltime",
                    {player_id: score},
                    incr=True
                )
                self.stats['updated_redis'] += 1
                logger.debug(
                    f"Updated Redis leaderboard for {player_id} "
                    f"({event_type}): +{score} points"
                )
            except Exception as e:
                logger.error(f"Redis update failed: {e}")
        
        # Periodically flush top 100 to database
        if self.stats['updated_redis'] % 50 == 0:
            self.update_leaderboard_database(game_id)
        
        self.stats['processed'] += 1
    
    def update_leaderboard_database(self, game_id: str):
        """Persist top N players to database"""
        if not self.redis_client:
            return
        
        try:
            # Get top N from Redis sorted set (descending score)
            top_players: List[Tuple[str, float]] = self.redis_client.zrange(
                f"leaderboard:{game_id}:alltime",
                0, self.top_n - 1,
                withscores=True,
                byscore=False,
                rev=True
            )
            
            if not top_players:
                return
            
            conn = psycopg2.connect(**self.db_params)
            cur = conn.cursor()
            
            for rank, (player_id, score) in enumerate(top_players, 1):
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
            
            self.stats['updated_db'] += 1
            logger.info(
                f"Updated database leaderboard for {game_id}: "
                f"persisted top {len(top_players)} players"
            )
            
        except psycopg2.Error as e:
            self.stats['failed'] += 1
            logger.error(f"Database error updating leaderboard: {e}")
        except Exception as e:
            self.stats['failed'] += 1
            logger.error(f"Unexpected error updating leaderboard: {e}")
    
    def start(self):
        """Start consuming events"""
        logger.info("Starting Leaderboard Manager Consumer...")
        logger.info(f"Scoring events tracked: {self.SCORING_EVENTS}")
        logger.info(f"Top N players persisted: {self.top_n}")
        
        try:
            for message in self.consumer:
                event = message.value
                self.process_event(event)
                
                # Log stats every 1000 events
                if self.stats['processed'] % 1000 == 0:
                    logger.info(
                        f"Stats - Processed: {self.stats['processed']}, "
                        f"Redis updates: {self.stats['updated_redis']}, "
                        f"DB updates: {self.stats['updated_db']}, "
                        f"Failed: {self.stats['failed']}"
                    )
        except KeyboardInterrupt:
            logger.info("Shutting down consumer...")
        except Exception as e:
            logger.error(f"Consumer error: {e}")
            raise
        finally:
            self.consumer.close()
            if self.redis_client:
                self.redis_client.close()
            logger.info("Consumer closed")


def main():
    """Entry point"""
    try:
        manager = LeaderboardManager()
        manager.start()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
