"""
Database Migration Script - Event Processing Schema
Initializes tables for raw events, statistics, leaderboards, and DLQ
"""

import os
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database connection parameters from environment
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME', 'gamemetrics')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASSWORD = os.getenv('DB_PASSWORD', '')

# SQL migrations
MIGRATIONS = [
    # 001: Create events table
    """
    CREATE TABLE IF NOT EXISTS events (
        event_id UUID PRIMARY KEY,
        event_type VARCHAR(100) NOT NULL,
        player_id VARCHAR(100) NOT NULL,
        game_id VARCHAR(100) NOT NULL,
        event_timestamp TIMESTAMP NOT NULL,
        ingested_at TIMESTAMP NOT NULL,
        data JSONB DEFAULT '{}',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE INDEX IF NOT EXISTS idx_events_player_id ON events(player_id);
    CREATE INDEX IF NOT EXISTS idx_events_game_id ON events(game_id);
    CREATE INDEX IF NOT EXISTS idx_events_event_type ON events(event_type);
    CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(event_timestamp DESC);
    """,
    
    # 002: Create player_statistics table
    """
    CREATE TABLE IF NOT EXISTS player_statistics (
        player_id VARCHAR(100) PRIMARY KEY,
        total_events INTEGER DEFAULT 0,
        event_breakdown JSONB DEFAULT '{}',
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE INDEX IF NOT EXISTS idx_player_stats_updated ON player_statistics(updated_at DESC);
    """,
    
    # 003: Create leaderboards table
    """
    CREATE TABLE IF NOT EXISTS leaderboards (
        game_id VARCHAR(100) NOT NULL,
        player_id VARCHAR(100) NOT NULL,
        rank INTEGER NOT NULL,
        score BIGINT NOT NULL,
        period VARCHAR(50) NOT NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (game_id, player_id, period)
    );
    
    CREATE INDEX IF NOT EXISTS idx_leaderboards_game_period ON leaderboards(game_id, period, rank);
    CREATE INDEX IF NOT EXISTS idx_leaderboards_score ON leaderboards(score DESC);
    """,
    
    # 004: Create dlq_events table
    """
    CREATE TABLE IF NOT EXISTS dlq_events (
        id SERIAL PRIMARY KEY,
        original_event JSONB NOT NULL,
        error_message TEXT,
        consumer_service VARCHAR(100),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE INDEX IF NOT EXISTS idx_dlq_service ON dlq_events(consumer_service);
    CREATE INDEX IF NOT EXISTS idx_dlq_created ON dlq_events(created_at DESC);
    """,
]


def connect_db():
    """Create database connection"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=5,
        )
        return conn
    except psycopg2.OperationalError as e:
        logger.error(f"Failed to connect to database: {e}")
        raise


def run_migrations():
    """Execute all database migrations"""
    try:
        conn = connect_db()
        conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
        cur = conn.cursor()
        
        for i, migration in enumerate(MIGRATIONS, 1):
            try:
                logger.info(f"Running migration {i}...")
                cur.execute(migration)
                logger.info(f"Migration {i} completed successfully")
            except psycopg2.Error as e:
                logger.error(f"Migration {i} failed: {e}")
                raise
        
        cur.close()
        conn.close()
        
        logger.info("✓ All migrations completed successfully!")
        return True
        
    except Exception as e:
        logger.error(f"Migration process failed: {e}")
        return False


def verify_schema():
    """Verify schema was created correctly"""
    try:
        conn = connect_db()
        cur = conn.cursor()
        
        tables_to_check = ['events', 'player_statistics', 'leaderboards', 'dlq_events']
        
        for table in tables_to_check:
            cur.execute(f"""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_name = '{table}'
                );
            """)
            exists = cur.fetchone()[0]
            status = "✓" if exists else "✗"
            print(f"{status} Table '{table}': {'exists' if exists else 'missing'}")
        
        cur.close()
        conn.close()
        
    except Exception as e:
        logger.error(f"Verification failed: {e}")


if __name__ == '__main__':
    logger.info(f"Connecting to {DB_HOST}:{DB_PORT}/{DB_NAME}")
    
    if run_migrations():
        logger.info("Running schema verification...")
        verify_schema()
        sys.exit(0)
    else:
        sys.exit(1)
