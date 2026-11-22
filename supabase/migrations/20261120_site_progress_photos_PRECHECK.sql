-- ==============================================================================
-- TSR BUILDERS — PRE-DEPLOYMENT VERIFICATION QUERIES (READ-ONLY)
-- File: supabase/migrations/20261120_site_progress_photos_PRECHECK.sql
-- ==============================================================================
-- PURPOSE:
--   Run these SELECT-only queries BEFORE executing the migration proposal to
--   inspect the current state of the live Supabase project. No data is modified.
--
-- USAGE:
--   Execute in the Supabase SQL Editor (or via psql) while connected to the
--   target project. Review each result set before proceeding.
--
-- DO NOT EXECUTE the main migration until all checks are reviewed and cleared.
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 1: Existing bucket state
-- Expected if first deployment: 0 rows returned.
-- Expected on re-run: 1 row with public=false, file_size_limit=10485760,
--   allowed_mime_types={image/jpeg,image/png,image/webp,image/heic}.
-- ⚠ If public=true exists, review impact before migration (DO UPDATE will flip it to false).
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  id,
  name,
  public                                   AS is_public,
  file_size_limit,
  file_size_limit / 1048576.0             AS file_size_limit_mb,
  allowed_mime_types,
  created_at
FROM storage.buckets
WHERE id = 'site-progress-photos';

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 2: Tables that must NOT yet exist (migration creates them)
-- Expected before migration: all show 'NOT_EXISTS (Ready for migration)'.
-- ⚠ CRITICAL WARNING: If any table already exists, 'CREATE TABLE IF NOT EXISTS'
-- will skip table creation and WILL NOT automatically reconcile missing columns
-- (e.g., claim_token, processing_started_at in storage_cleanup_queue)
-- or missing constraints (e.g., site_progress_updates_id_site_uniq, site_progress_photos_storage_path_uniq).
-- If tables exist, carefully inspect their schema against the migration proposal.
-- ─────────────────────────────────────────────────────────────────────────────
WITH expected_tables (table_name) AS (
  VALUES
    ('storage_cleanup_queue'),
    ('site_progress_updates'),
    ('site_progress_photos')
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
-- CHECK 3: Functions that will be created or replaced by this migration
-- Expected on first deployment: 0 or more rows (some helpers may already exist).
-- Review if any function already exists — CREATE OR REPLACE will overwrite it.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  routine_name,
  routine_type,
  security_type,
  data_type        AS return_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'claim_cleanup_jobs',
    'enforce_progress_update_permissions',
    'validate_progress_photo_fields',
    'enforce_progress_photo_immutability',
    'queue_single_progress_photo_cleanup',
    'can_access_site_progress',
    'can_access_progress_storage_object'
  )
ORDER BY routine_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 4: Existing RLS policies on storage.objects (ALL policies)
-- ⚠ SECURITY WARNING: In PostgreSQL, PERMISSIVE policies combine using logical OR.
-- If any existing PERMISSIVE policy on storage.objects grants broad access (such as
-- allowing authenticated users to SELECT, INSERT, or DELETE without filtering on bucket_id),
-- that policy will broaden access to 'site-progress-photos' objects regardless of the
-- scoped policies defined in this migration proposal.
--
-- Carefully review every policy returned below:
--   - Check 'permissive' column: 'PERMISSIVE' policies combine via logical OR.
--     Only 'RESTRICTIVE' policies combine via logical AND.
--   - Check 'roles': anon or authenticated roles with unconstrained or missing bucket_id filters.
--   - Any pre-existing policy that allows access across all buckets (e.g., bucket_id IS NULL
--     or lacking "bucket_id = '...'") MUST be reviewed and scoped before deploying to production.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd        AS operation,
  qual       AS using_expr,
  with_check AS with_check_expr
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename  = 'objects'
ORDER BY permissive, cmd, policyname;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 5: Confirm required upstream tables and functions exist (migration dependencies)
-- Expected: ALL rows must show status = 'EXISTS'.
-- Any row showing 'MISSING' means the upstream security setup has not been applied.
-- The MISSING status is reliably shown because this uses LEFT JOIN against a known list,
-- not WHERE filtering (which would silently omit absent objects).
-- ─────────────────────────────────────────────────────────────────────────────
WITH required (object_type, object_name) AS (
  VALUES
    ('table',    'sites'),
    ('table',    'user_profiles'),
    ('table',    'site_memberships'),
    ('function', 'is_active_user'),
    ('function', 'is_pm_or_admin'),
    ('function', 'is_admin'),
    ('function', 'has_site_access')
)
SELECT
  r.object_type,
  r.object_name,
  CASE
    WHEN t.table_name   IS NOT NULL THEN 'EXISTS'
    WHEN f.routine_name IS NOT NULL THEN 'EXISTS'
    ELSE 'MISSING'
  END AS status
FROM required r
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
-- CHECK 6: Effective table privileges on storage_cleanup_queue
-- Uses has_table_privilege() to test TRUE effective permissions (including
-- direct grants, inherited roles, and PUBLIC privileges).
--
-- Expected before migration: all rows show 'TABLE_NOT_YET_CREATED'.
-- Expected after migration:
--   - anon:          all DENIED
--   - authenticated: all DENIED
--   - service_role:  SELECT=GRANTED, INSERT=GRANTED, UPDATE=GRANTED, DELETE=DENIED
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  r.rolname AS role_name,
  CASE
    WHEN to_regclass('public.storage_cleanup_queue') IS NULL THEN 'TABLE_NOT_YET_CREATED'
    WHEN has_table_privilege(r.rolname, 'public.storage_cleanup_queue', 'SELECT') THEN 'GRANTED'
    ELSE 'DENIED'
  END AS effective_select,
  CASE
    WHEN to_regclass('public.storage_cleanup_queue') IS NULL THEN 'TABLE_NOT_YET_CREATED'
    WHEN has_table_privilege(r.rolname, 'public.storage_cleanup_queue', 'INSERT') THEN 'GRANTED'
    ELSE 'DENIED'
  END AS effective_insert,
  CASE
    WHEN to_regclass('public.storage_cleanup_queue') IS NULL THEN 'TABLE_NOT_YET_CREATED'
    WHEN has_table_privilege(r.rolname, 'public.storage_cleanup_queue', 'UPDATE') THEN 'GRANTED'
    ELSE 'DENIED'
  END AS effective_update,
  CASE
    WHEN to_regclass('public.storage_cleanup_queue') IS NULL THEN 'TABLE_NOT_YET_CREATED'
    WHEN has_table_privilege(r.rolname, 'public.storage_cleanup_queue', 'DELETE') THEN 'GRANTED'
    ELSE 'DENIED'
  END AS effective_delete
FROM pg_roles r
WHERE r.rolname IN ('anon', 'authenticated', 'service_role')
ORDER BY r.rolname;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 7: Existing objects in bucket (if bucket already exists)
-- Expected on first deployment: 0 rows.
-- If files already exist, they are unaffected by the migration but will be
-- subject to the new storage RLS policies once applied.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  COUNT(*)                                            AS object_count,
  MIN(created_at)                                     AS oldest_object,
  MAX(created_at)                                     AS newest_object,
  SUM(
    CASE
      WHEN metadata->>'size' ~ '^\d+$'
      THEN (metadata->>'size')::BIGINT
      ELSE 0
    END
  )                                                   AS total_bytes
FROM storage.objects
WHERE bucket_id = 'site-progress-photos';

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 8: Unique constraints required for referential integrity & 1:1 photo storage mapping
-- Expected before migration: both show 'MISSING' (they will be created by the migration).
-- Expected after migration: both show 'EXISTS'.
--
-- 1. site_progress_updates_id_site_uniq:
--    Composite unique constraint UNIQUE (id, site_id) on site_progress_updates.
--    Required as the target for child composite foreign key fk_site_progress_photos_parent_site.
-- 2. site_progress_photos_storage_path_uniq:
--    Unique constraint UNIQUE (storage_path) on site_progress_photos.
--    Guarantees exactly one photo metadata record per Storage object, preventing multiple
--    records from pointing to the same file and triggering premature physical deletion on delete.
-- ─────────────────────────────────────────────────────────────────────────────
WITH required_constraints (table_name, constraint_name, constraint_description) AS (
  VALUES
    (
      'site_progress_updates',
      'site_progress_updates_id_site_uniq',
      'Composite unique (id, site_id) required for child composite foreign key'
    ),
    (
      'site_progress_photos',
      'site_progress_photos_storage_path_uniq',
      'Unique storage_path ensuring 1:1 mapping between storage objects and photo records'
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
-- CHECK 9: Inspect columns of storage_cleanup_queue (if table exists)
-- Confirms claim_token UUID and processing_started_at columns exist for lease safety.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'storage_cleanup_queue'
ORDER BY ordinal_position;

-- ==============================================================================
-- END OF PRE-DEPLOYMENT VERIFICATION
-- Review all result sets before executing the migration proposal.
-- ==============================================================================
