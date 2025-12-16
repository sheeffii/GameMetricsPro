-- Flyway Migration: Create OAuth2 tables
-- Version: 2
-- Description: OAuth2 authentication tables

CREATE TABLE IF NOT EXISTS oauth_clients (
    client_id VARCHAR(255) PRIMARY KEY,
    client_secret VARCHAR(255) NOT NULL,
    redirect_uris TEXT[],
    scopes TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS oauth_tokens (
    token_id VARCHAR(255) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    client_id VARCHAR(255) NOT NULL,
    access_token TEXT NOT NULL,
    refresh_token TEXT,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (client_id) REFERENCES oauth_clients(client_id) ON DELETE CASCADE
);

CREATE INDEX idx_oauth_tokens_user_id ON oauth_tokens(user_id);
CREATE INDEX idx_oauth_tokens_expires_at ON oauth_tokens(expires_at);



