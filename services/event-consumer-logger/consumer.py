"""
Raw Event Logger Consumer
- Reads from: player.events.raw Kafka topic
- Writes to: PostgreSQL events table
- Purpose: Store all raw events for audit trail and analysis
"""

import json
import logging
import os
import sys
import uuid
from datetime import datetime
from typing import Dict, Any, Optional

import psycopg2
from psycopg2.extras import Json
from kafka import KafkaConsumer, KafkaAdminClient
from kafka.errors import KafkaError

# Logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def _configure_dependency_logging() -> None:
    """Reduce noisy kafka-python loggers while keeping app logs readable."""
    # kafka-python can emit WARNING spam during broker restarts / topic creation.
    # We still surface real failures at ERROR.
    logging.getLogger('kafka').setLevel(logging.WARNING)
    logging.getLogger('kafka.consumer.fetcher').setLevel(logging.ERROR)
    logging.getLogger('kafka.client').setLevel(logging.ERROR)
    logging.getLogger('kafka.conn').setLevel(logging.ERROR)


def _parse_uuid(value: Any) -> Optional[uuid.UUID]:
    if value is None:
        return None
    try:
        return uuid.UUID(str(value))
    except Exception:
        return None


class RawEventLogger:
    """Consume raw events from Kafka and persist to PostgreSQL"""
    
    def __init__(self):
        """Initialize Kafka consumer and database connection"""
        _configure_dependency_logging()
        self.consumer = self._init_kafka_consumer()
        self.db_params = self._get_db_params()
        self.stats = {
            'processed': 0,
            'failed': 0,
            'last_error': None
        }
    
    def _init_kafka_consumer(self) -> KafkaConsumer:
        """Initialize Kafka consumer with configuration"""
        bootstrap_servers = os.getenv(
            'KAFKA_BOOTSTRAP_SERVERS',
            'localhost:9092'
        ).split(',')

        topic = os.getenv('KAFKA_TOPIC', 'player.events.raw')
        
        consumer_config = {
            'bootstrap_servers': bootstrap_servers,
            'group_id': os.getenv('KAFKA_GROUP_ID', 'event-logger-group'),
            'topic_name': topic,
            'value_deserializer': lambda m: json.loads(m.decode('utf-8')),
            'auto_offset_reset': 'earliest',
            'enable_auto_commit': True,
            'max_poll_records': int(os.getenv('KAFKA_MAX_POLL_RECORDS', '100')),
            'session_timeout_ms': 30000,
        }
        
        # Add SASL/SCRAM auth if configured
        if os.getenv('KAFKA_USERNAME'):
            consumer_config.update({
                'security_protocol': os.getenv('KAFKA_SECURITY_PROTOCOL', 'SASL_PLAINTEXT'),
                'sasl_mechanism': 'SCRAM-SHA-512',
                'sasl_plain_username': os.getenv('KAFKA_USERNAME'),
                'sasl_plain_password': os.getenv('KAFKA_PASSWORD'),
            })
        
        try:
            self._wait_for_topic(bootstrap_servers, topic, consumer_config)

            consumer = KafkaConsumer(
                consumer_config.pop('topic_name'),
                **consumer_config
            )
            logger.info(f"Kafka consumer initialized: {bootstrap_servers}")
            logger.info(f"Kafka topic ready: {topic}")
            return consumer
        except Exception as e:
            logger.error(f"Failed to initialize Kafka consumer: {e}")
            raise

    def _wait_for_topic(self, bootstrap_servers: list[str], topic: str, consumer_config: Dict[str, Any]) -> None:
        """Wait until the Kafka topic exists and is describable.

        Prevents kafka-python from spamming UnknownTopicOrPartition warnings during cluster restarts.
        """
        timeout_seconds = int(os.getenv('KAFKA_WAIT_FOR_TOPIC_SECONDS', '90'))
        poll_seconds = float(os.getenv('KAFKA_WAIT_FOR_TOPIC_POLL_SECONDS', '2'))
        deadline = datetime.utcnow().timestamp() + timeout_seconds

        admin_kwargs: Dict[str, Any] = {
            'bootstrap_servers': bootstrap_servers,
            'client_id': 'event-consumer-logger-admin',
        }
        if os.getenv('KAFKA_USERNAME'):
            admin_kwargs.update({
                'security_protocol': consumer_config.get('security_protocol', 'SASL_PLAINTEXT'),
                'sasl_mechanism': consumer_config.get('sasl_mechanism', 'SCRAM-SHA-512'),
                'sasl_plain_username': consumer_config.get('sasl_plain_username'),
                'sasl_plain_password': consumer_config.get('sasl_plain_password'),
            })

        logger.info(f"Waiting for Kafka topic '{topic}' (timeout {timeout_seconds}s)...")
        while True:
            try:
                admin = KafkaAdminClient(**admin_kwargs)
                topics = admin.list_topics()
                admin.close()

                if topic in topics:
                    return
            except Exception as e:
                logger.warning(f"Kafka not ready yet (waiting for topic): {e}")

            if datetime.utcnow().timestamp() >= deadline:
                raise TimeoutError(f"Kafka topic '{topic}' not ready after {timeout_seconds}s")

            import time
            time.sleep(poll_seconds)
    
    def _get_db_params(self) -> Dict[str, str]:
        """Get database connection parameters from environment"""
        return {
            'host': os.getenv('DB_HOST', 'localhost'),
            'port': os.getenv('DB_PORT', '5432'),
            'database': os.getenv('DB_NAME', 'gamemetrics'),
            'user': os.getenv('DB_USER', 'postgres'),
            'password': os.getenv('DB_PASSWORD', ''),
            'connect_timeout': 5,
        }
    
    def process_event(self, event: Dict[str, Any]) -> bool:
        """
        Write raw event to PostgreSQL
        
        Args:
            event: Kafka message payload (parsed JSON)
            
        Returns:
            True if successful, False otherwise
        """
        try:
            conn = psycopg2.connect(**self.db_params)
            cur = conn.cursor()
            
            # Handle multiple event formats:
            # 1. event-ingestion format: event_id, event_type, player_id, game_id, timestamp, ingested_at, data
            # 2. smoke test format (kcat): smokeTestId, event, ts
            raw_event_id = event.get('event_id') or event.get('smokeTestId')
            parsed_event_uuid = _parse_uuid(raw_event_id)
            event_id = str(parsed_event_uuid or uuid.uuid4())
            event_type = event.get('event_type') or event.get('event') or 'unknown'
            player_id = event.get('player_id') or 'smoke'
            game_id = event.get('game_id') or 'smoke'
            
            # Convert timestamp strings to datetime objects
            try:
                event_ts = datetime.fromisoformat(
                    event.get('timestamp', event.get('ts', '')).replace('Z', '+00:00')
                )
            except (KeyError, ValueError, AttributeError):
                event_ts = datetime.utcnow()
            
            try:
                ingested_ts = datetime.fromisoformat(
                    event.get('ingested_at', '').replace('Z', '+00:00')
                )
            except (KeyError, ValueError, AttributeError):
                ingested_ts = datetime.utcnow()
            
            # Use event data or the whole event as fallback
            data_obj = event.get('data', event)
            if raw_event_id and parsed_event_uuid is None:
                try:
                    if isinstance(data_obj, dict):
                        data_obj = {**data_obj, 'original_event_id': str(raw_event_id)}
                except Exception:
                    pass
            
            # Insert event into database
            cur.execute("""
                INSERT INTO events (
                    event_id, event_type, player_id, game_id,
                    event_timestamp, ingested_at, data, created_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
                ON CONFLICT (event_id) DO NOTHING
            """, (
                event_id,
                event_type,
                player_id,
                game_id,
                event_ts,
                ingested_ts,
                Json(data_obj),
            ))
            
            affected_rows = cur.rowcount
            conn.commit()
            cur.close()
            conn.close()
            
            if affected_rows > 0:
                self.stats['processed'] += 1
                logger.debug(f"Event {event_id} logged to database")
            
            return True
            
        except psycopg2.Error as e:
            self.stats['failed'] += 1
            self.stats['last_error'] = str(e)
            logger.error(f"Database error processing event: {e}")
            return False
        except Exception as e:
            self.stats['failed'] += 1
            self.stats['last_error'] = str(e)
            logger.error(f"Unexpected error processing event: {e}")
            return False
    
    def get_stats(self) -> Dict[str, Any]:
        """Get consumer statistics"""
        return self.stats.copy()
    
    def start(self):
        """Start consuming events"""
        logger.info("Starting Raw Event Logger Consumer...")
        logger.info(f"Consuming from: {os.getenv('KAFKA_TOPIC', 'player.events.raw')}")
        logger.info(f"Consumer group: {os.getenv('KAFKA_GROUP_ID', 'event-logger-group')}")
        
        try:
            for message in self.consumer:
                event = message.value
                self.process_event(event)
                
                # Log stats every 100 events
                if self.stats['processed'] % 100 == 0:
                    logger.info(
                        f"Stats - Processed: {self.stats['processed']}, "
                        f"Failed: {self.stats['failed']}"
                    )
        except KeyboardInterrupt:
            logger.info("Shutting down consumer...")
        except Exception as e:
            logger.error(f"Consumer error: {e}")
            raise
        finally:
            self.consumer.close()
            logger.info("Consumer closed")


def main():
    """Entry point"""
    try:
        consumer = RawEventLogger()
        consumer.start()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
