-- ==============================================================================
-- TSR BUILDERS — PRE-DEPLOYMENT VERIFICATION QUERIES (READ-ONLY)
-- File: supabase/migrations/20261120_workforce_and_supervisor_attendance_PRECHECK.sql
-- ==============================================================================
-- PURPOSE:
--   Run these SELECT-only queries BEFORE executing the workforce & supervisor
--   attendance migration proposal (20261120_workforce_and_supervisor_attendance_PROPOSAL.sql)
--   to inspect the current database state. No data or schemas are modified.
--
-- USAGE:
--   Execute in the Supabase SQL Editor (or via psql) while connected to the
--   target project. Review each result set before proceeding with migration.
--
-- DO NOT EXECUTE the main migration until all checks are reviewed and cleared.
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 1: Target tables that must NOT yet exist
-- Expected before migration: all show 'NOT_EXISTS (Ready for migration)'.
-- ⚠ CRITICAL WARNING: If any table already exists, 'CREATE TABLE IF NOT EXISTS'
-- will skip table creation and WILL NOT automatically reconcile missing columns
-- (e.g. total_workforce) or constraints (e.g. category CHECK, composite FKs,
-- ON DELETE RESTRICT). If tables exist, review column/constraint checks below.
-- ─────────────────────────────────────────────────────────────────────────────
WITH expected_tables (table_name) AS (
  VALUES
    ('daily_workforce_attendance'),
    ('daily_workforce_category_counts'),
    ('supervisor_attendance')
)
SELECT
  e.table_name,
  CASE
    WHEN t.table_name IS NOT NULL THEN 'EXISTS (WARNING: CREATE TABLE IF NOT EXISTS will not reconcile missing columns/constraints)'
    ELSE 'NOT_EXISTS (Ready for migration)'
  END AS table_status
FROM expected_tables e
LEFT JOIN information_schema.tables t
  ON  t.table_schema = 'public'
  AND t.table_name   = e.table_name
ORDER BY e.table_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 2: Confirm required upstream tables and security functions exist
-- Expected: ALL rows must show status = 'EXISTS'.
-- Any row showing 'MISSING' means upstream schema or RLS helpers have not been applied.
-- Uses LEFT JOIN against known list so missing dependencies are explicitly displayed.
-- ─────────────────────────────────────────────────────────────────────────────
WITH required_objects (object_type, object_name) AS (
  VALUES
    ('table',    'sites'),
    ('table',    'user_profiles'),
    ('table',    'site_memberships'),
    ('function', 'is_active_user'),
    ('function', 'is_pm_or_admin'),
    ('function', 'is_admin'),
    ('function', 'has_site_access'),
    ('function', 'can_manage_site')
)
SELECT
  r.object_type,
  r.object_name,
  CASE
    WHEN t.table_name   IS NOT NULL THEN 'EXISTS'
    WHEN f.routine_name IS NOT NULL THEN 'EXISTS'
    ELSE 'MISSING'
  END AS status
FROM required_objects r
LEFT JOIN information_schema.tables t
  ON  r.object_type = 'table'
  AND t.table_schema = 'public'
  AND t.table_name   = r.object_name
LEFT JOIN information_schema.routines f
  ON  r.object_type   = 'function'
  AND f.routine_schema = 'public'
  AND f.routine_name   = r.object_name
ORDER BY r.object_type, r.object_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 3: Unique and Referential Constraints Required by Architecture
-- Expected before migration: all show 'MISSING' (will be created by migration).
-- Expected after migration: all show 'EXISTS'.
--
-- 1. daily_workforce_attendance_site_date_uniq: exactly one workforce record per site/date
-- 2. daily_workforce_attendance_id_site_uniq: composite unique target for detail composite FK
-- 3. fk_workforce_category_counts_header_site: composite FK ensuring detail matches parent site
-- 4. daily_workforce_counts_attendance_category_uniq: one count per category per attendance
-- 5. supervisor_attendance_supervisor_date_uniq: one attendance per supervisor per calendar date
-- ─────────────────────────────────────────────────────────────────────────────
WITH required_constraints (table_name, constraint_name, constraint_description) AS (
  VALUES
    (
      'daily_workforce_attendance',
      'daily_workforce_attendance_site_date_uniq',
      'Unique (site_id, attendance_date): one submission per site per date'
    ),
    (
      'daily_workforce_attendance',
      'daily_workforce_attendance_id_site_uniq',
      'Composite unique (id, site_id) required for child composite foreign key'
    ),
    (
      'daily_workforce_category_counts',
      'fk_workforce_category_counts_header_site',
      'Composite foreign key (attendance_id, site_id) preventing cross-site references'
    ),
    (
      'daily_workforce_category_counts',
      'daily_workforce_counts_attendance_category_uniq',
      'Unique (attendance_id, category): exactly one count per category per submission'
    ),
    (
      'supervisor_attendance',
      'supervisor_attendance_supervisor_date_uniq',
      'Unique (supervisor_id, attendance_date): one record per supervisor per calendar date'
    )
)
SELECT
  rc.table_name,
  rc.constraint_name,
  rc.constraint_description,
  CASE
    WHEN c.conname IS NOT NULL THEN 'EXISTS'
    ELSE 'MISSING'
  END AS status
FROM required_constraints rc
LEFT JOIN (
  pg_constraint c
  JOIN pg_class cl ON cl.oid = c.conrelid
  JOIN pg_namespace ns ON ns.oid = cl.relnamespace AND ns.nspname = 'public'
) ON rc.constraint_name = c.conname AND rc.table_name = cl.relname
ORDER BY rc.table_name, rc.constraint_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 4: Category CHECK constraint on daily_workforce_category_counts
-- Expected before migration: TABLE_NOT_YET_CREATED.
-- Expected after migration: 1 row showing the 7 agreed categories:
--   ('Masons', 'Painters', 'Helpers', 'Carpenters', 'Electricians', 'Plumbers', 'Other')
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  c.conname AS constraint_name,
  pg_get_constraintdef(c.oid) AS check_clause
FROM pg_constraint c
JOIN pg_class cl ON cl.oid = c.conrelid
JOIN pg_namespace ns ON ns.oid = cl.relnamespace
WHERE ns.nspname = 'public'
  AND cl.relname = 'daily_workforce_category_counts'
  AND c.contype  = 'c';

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 5: Supervisor foreign key deletion action (ON DELETE RESTRICT)
-- Expected before migration: 0 rows.
-- Expected after migration: 1 row showing confdeltype = 'r' (RESTRICT).
-- (confdeltype: 'r' = RESTRICT, 'c' = CASCADE, 'n' = SET NULL, 'a' = NO ACTION)
-- Prohibits deleting supervisor user profiles while attendance records exist.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  c.conname AS foreign_key_name,
  cl.relname AS table_name,
  c.confdeltype,
  CASE c.confdeltype
    WHEN 'r' THEN 'RESTRICT (Correct — profile cannot be deleted with attendance history)'
    WHEN 'c' THEN 'CASCADE (DANGEROUS — deleting profile will delete attendance history)'
    WHEN 'n' THEN 'SET NULL (Incorrect — will orphan attendance attribution)'
    ELSE c.confdeltype::text
  END AS delete_behavior
FROM pg_constraint c
JOIN pg_class cl ON cl.oid = c.conrelid
JOIN pg_namespace ns ON ns.oid = cl.relnamespace
WHERE ns.nspname = 'public'
  AND cl.relname = 'supervisor_attendance'
  AND c.contype  = 'f'
  AND c.confrelid = 'public.user_profiles'::regclass;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 6: Column-level privileges on daily_workforce_attendance
-- Verifies that authenticated users are restricted to:
--   - INSERT: (site_id, attendance_date, remarks)
--   - UPDATE: (remarks) ONLY
-- Direct modifications to total_workforce, site_id, attendance_date, created_by
-- must be DENIED (raising 42501).
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  column_name,
  privilege_type,
  grantee
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name   = 'daily_workforce_attendance'
  AND grantee      = 'authenticated'
ORDER BY column_name, privilege_type;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 7: Functions to be created or replaced by this migration
-- Expected on first deployment: 0 rows.
-- Expected after migration: 5 rows.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  routine_name,
  routine_type,
  security_type,
  data_type AS return_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'can_submit_workforce_attendance',
    'set_workforce_attendance_audit_fields',
    'sync_workforce_total',
    'set_category_counts_updated_at',
    'validate_and_audit_supervisor_attendance'
  )
ORDER BY routine_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 8: Legacy / Conflicting Workforce Table Detection
-- Checks if legacy public.daily_workforce_counts exists from earlier draft proposal.
-- If it exists with data, review whether historical temporary data needs migration.
--
-- Always returns exactly 1 row:
--   NOT_PRESENT              → safe to proceed (expected before first migration)
--   LEGACY_TABLE_PRESENT     → legacy table found; review data before dropping
-- ─────────────────────────────────────────────────────────────────────────────
WITH legacy_check (target_table) AS (
  VALUES ('daily_workforce_counts')
)
SELECT
  lc.target_table AS table_name,
  CASE
    WHEN t.table_name IS NOT NULL THEN 'LEGACY_TABLE_PRESENT (Review before dropping)'
    ELSE 'NOT_PRESENT'
  END AS legacy_status
FROM legacy_check lc
LEFT JOIN information_schema.tables t
  ON  t.table_schema = 'public'
  AND t.table_name   = lc.target_table;

-- ==============================================================================
-- END OF WORKFORCE PRE-DEPLOYMENT VERIFICATION
-- Review all result sets before executing the migration proposal.
-- ==============================================================================

