"""
Statistics Aggregator Consumer
- Reads from: player.events.raw Kafka topic
- Writes to: PostgreSQL player_statistics table + Redis cache
- Purpose: Calculate and aggregate player event statistics in real-time
"""

import json
import logging
import os
import sys
from datetime import datetime, timedelta
from typing import Dict, Any
from collections import defaultdict

import psycopg2
import redis
from kafka import KafkaConsumer
from kafka.errors import KafkaError

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class StatisticsAggregator:
    """Aggregate player statistics from raw events"""
    
    def __init__(self):
        """Initialize Kafka consumer, database, and Redis"""
        self.consumer = self._init_kafka_consumer()
        self.db_params = self._get_db_params()
        self.redis_client = self._init_redis()
        
        # Buffer for batching database writes
        self.stats_buffer = defaultdict(dict)
        self.buffer_size = int(os.getenv('BUFFER_SIZE', '100'))
        self.buffer_timeout = timedelta(
            seconds=int(os.getenv('BUFFER_TIMEOUT_SECONDS', '30'))
        )
        self.last_flush = datetime.utcnow()
        
        self.stats = {
            'processed': 0,
            'flushed': 0,
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
            'group_id': os.getenv('KAFKA_GROUP_ID', 'stats-aggregator-group'),
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
                db=int(os.getenv('REDIS_DB', '0')),
                decode_responses=True,
                socket_connect_timeout=5,
            )
            # Test connection
            client.ping()
            logger.info("Redis connection established")
            return client
        except Exception as e:
            logger.warning(f"Redis connection failed (will retry): {e}")
            return None
    
    def process_event(self, event: Dict[str, Any]):
        """
        Update statistics based on event
        
        Updates both in-memory buffer and Redis in real-time
        """
        player_id = event.get('player_id')
        event_type = event.get('event_type')
        
        if not player_id or not event_type:
            logger.warning(f"Event missing player_id or event_type: {event}")
            return
        
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
        if self.redis_client:
            try:
                self.redis_client.hincrby(
                    f"player_stats:{player_id}",
                    'total_events', 1
                )
                self.redis_client.hincrby(
                    f"player_stats:{player_id}",
                    f'event_{event_type}', 1
                )
                self.redis_client.hset(
                    f"player_stats:{player_id}",
                    'last_event',
                    datetime.utcnow().isoformat()
                )
            except Exception as e:
                logger.error(f"Redis update failed: {e}")
        
        self.stats['processed'] += 1
        
        # Flush if buffer is full or timed out
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
            
            buffered_count = len(self.stats_buffer)
            self.stats['flushed'] += buffered_count
            logger.info(
                f"Flushed {buffered_count} player stats to database. "
                f"Total: {self.stats['flushed']}"
            )
            self.stats_buffer.clear()
            self.last_flush = datetime.utcnow()
            
        except psycopg2.Error as e:
            self.stats['failed'] += 1
            logger.error(f"Database error during flush: {e}")
        except Exception as e:
            self.stats['failed'] += 1
            logger.error(f"Unexpected error during flush: {e}")
    
    def start(self):
        """Start consuming and aggregating events"""
        logger.info("Starting Statistics Aggregator Consumer...")
        logger.info(f"Buffer size: {self.buffer_size}, timeout: {self.buffer_timeout.total_seconds()}s")
        
        try:
            for message in self.consumer:
                event = message.value
                self.process_event(event)
                
                # Log stats every 500 events
                if self.stats['processed'] % 500 == 0:
                    logger.info(
                        f"Stats - Processed: {self.stats['processed']}, "
                        f"Flushed: {self.stats['flushed']}, "
                        f"Failed: {self.stats['failed']}"
                    )
        except KeyboardInterrupt:
            logger.info("Shutting down consumer...")
            # Final flush before exit
            self.flush_to_database()
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
        aggregator = StatisticsAggregator()
        aggregator.start()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
