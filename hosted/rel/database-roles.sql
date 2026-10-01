-- WI-081 (ASSESS-001 FND-13): the two database roles of a hosted deployment, made once by the database's
-- administrator (a superuser), before the first migration. Run with psql, choosing the passwords:
--
--   psql -v owner_password='...' -v runtime_password='...' -v database=findependence -f rel/database-roles.sql
--
-- findependence_owner owns the database and its schema and runs migrations (MIGRATION_DATABASE_URL);
-- findependence_app is what the server connects as (DATABASE_URL, DATABASE_RUNTIME_ROLE=findependence_app):
-- after each migration, FindependenceHosted.Release.migrate grants it row access on every table, add-only on
-- audit_events, and nothing on schema_migrations. Neither role is a superuser or can make roles or databases.

CREATE ROLE findependence_owner LOGIN PASSWORD :'owner_password'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE ROLE findependence_app LOGIN PASSWORD :'runtime_password'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;

CREATE DATABASE :"database" OWNER findependence_owner;
\connect :"database"

-- only the owner creates objects; nobody else gets anything by default
REVOKE ALL ON DATABASE :"database" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"database" TO findependence_app;
ALTER SCHEMA public OWNER TO findependence_owner;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
