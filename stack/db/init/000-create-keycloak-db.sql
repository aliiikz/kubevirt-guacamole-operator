--
-- Create Keycloak database
-- This script creates a separate database for Keycloak within the same PostgreSQL instance
--

-- Create the keycloak database if it doesn't already exist
SELECT 'CREATE DATABASE keycloak'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'keycloak')\gexec

-- Note: Keycloak will automatically create its own tables when it first connects
-- to the database, so no additional schema setup is needed here.
