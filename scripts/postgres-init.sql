-- Bot Army Starter — PostgreSQL initialization
-- Mounted by quickstart-default.sh into /docker-entrypoint-initdb.d/ so it
-- runs automatically the FIRST time the pgdata volume is initialized.
--
-- P8 (2026-09-06, vagrant-test fresh-user reproduction): bot entrypoints
-- cannot create their own databases — the public bot repos implement only
-- Release.migrate() (shared MigrationRunner), no create_databases(), and
-- mix releases don't ship source, so the entrypoint's Release-module
-- detection found nothing. Bots then looped forever on
-- `database "..." does not exist` while compose showed them Up.
-- Fix: create every core-bot database Postgres-side, idempotently.
--
-- NOTE on style: CREATE DATABASE cannot run inside a transaction block, so
-- DO $$ ... $$ wrappers FAIL here ("cannot be executed from a function").
-- The \gexec meta-command runs each SELECT's returned row as a standalone
-- SQL statement — no transaction — and emits nothing when the DB exists.
-- (The old monorepo's init_postgres.sql used the broken DO-block form.)
--
-- Database names are each bot's config default, matched verbatim
-- (some intentionally carry dev suffixes — e.g. bot_army_skills_dev,
-- ergon_synapse_dev — that's what the bots actually connect to).

CREATE EXTENSION IF NOT EXISTS vector;

SELECT 'CREATE DATABASE ergon_gtd'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ergon_gtd')\gexec

SELECT 'CREATE DATABASE ergon_llm'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ergon_llm')\gexec

SELECT 'CREATE DATABASE bot_army_dispatcher'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'bot_army_dispatcher')\gexec

SELECT 'CREATE DATABASE bot_army_skills_dev'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'bot_army_skills_dev')\gexec

SELECT 'CREATE DATABASE ergon_synapse_dev'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ergon_synapse_dev')\gexec

SELECT 'CREATE DATABASE ergon_job_scheduler'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ergon_job_scheduler')\gexec