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
-- Database names are each bot's config default, matched verbatim
-- (some intentionally carry dev suffixes — e.g. bot_army_skills_dev,
-- ergon_synapse_dev — that's what the bots actually connect to).

CREATE EXTENSION IF NOT EXISTS vector;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ergon_gtd') THEN
        CREATE DATABASE ergon_gtd;
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ergon_llm') THEN
        CREATE DATABASE ergon_llm;
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'bot_army_dispatcher') THEN
        CREATE DATABASE bot_army_dispatcher;
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'bot_army_skills_dev') THEN
        CREATE DATABASE bot_army_skills_dev;
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ergon_synapse_dev') THEN
        CREATE DATABASE ergon_synapse_dev;
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ergon_job_scheduler') THEN
        CREATE DATABASE ergon_job_scheduler;
    END IF;
END
$$;