-- Database is already created by the MYSQL_DATABASE env var.
-- This script seeds the initial schema and sample data.

CREATE TABLE IF NOT EXISTS users (
    id         INT          AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    email      VARCHAR(150) NOT NULL UNIQUE,
    created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (name, email) VALUES
    ('Alice Martin',  'alice@example.com'),
    ('Bob Johnson',   'bob@example.com'),
    ('Carol White',   'carol@example.com');
