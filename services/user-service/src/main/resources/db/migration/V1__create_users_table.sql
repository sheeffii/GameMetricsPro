-- Flyway Migration: Create users table
-- Version: 1
-- Description: Initial schema for user service

CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(255) PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NULL;

-- GDPR: Add function to delete user data
CREATE OR REPLACE FUNCTION delete_user_data(user_id VARCHAR)
RETURNS VOID AS $$
BEGIN
    -- Delete from users table
    DELETE FROM users WHERE id = user_id;
    
    -- Note: In production, also delete from related tables:
    -- DELETE FROM player_events WHERE player_id = user_id;
    -- DELETE FROM player_statistics WHERE player_id = user_id;
END;
$$ LANGUAGE plpgsql;



