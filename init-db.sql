CREATE TABLE IF NOT EXISTS events (
    event_id UUID PRIMARY KEY,
    event_type VARCHAR(100),
    player_id VARCHAR(255),
    game_id VARCHAR(255),
    event_timestamp TIMESTAMP,
    ingested_at TIMESTAMP DEFAULT NOW(),
    data JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_event_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_player_id ON events(player_id);
CREATE INDEX IF NOT EXISTS idx_event_timestamp ON events(event_timestamp);
SELECT 'Events table created successfully' as status;
