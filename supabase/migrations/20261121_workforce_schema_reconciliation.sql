-- ==============================================================================
-- TSR BUILDERS — WORKFORCE SCHEMA RECONCILIATION MIGRATION
-- File: supabase/migrations/20261121_workforce_schema_reconciliation.sql
-- ==============================================================================
-- PURPOSE:
--   Reconcile existing empty staging tables with the approved workforce
--   architecture without dropping or recreating any existing tables.
--
-- EXISTING STATE (confirmed by precheck):
--   daily_workforce_attendance  — EXISTS, EMPTY. Missing: total_workforce,
--                                 UNIQUE(id, site_id). Reuses/renames existing
--                                 UNIQUE(site_id, attendance_date).
--   supervisor_attendance       — EXISTS, EMPTY. Column is supervisor_user_id
--                                 (not supervisor_id). Unique is
--                                 (site_id, supervisor_user_id, attendance_date).
--                                 Existing supervisor_attendance_recorded_by_fkey
--                                 correctly references user_profiles(id) ON DELETE RESTRICT.
--   daily_workforce_category_counts — NOT EXISTS (created here).
--   daily_workforce_counts          — EXISTS, EMPTY. FK to
--                                     daily_workforce_attendance(id). Preserved.
--
-- TARGETED CORRECTIONS IN THIS VERSION:
--   1. Protects empty-table guard against concurrent writes: immediately locks
--      both daily_workforce_attendance and supervisor_attendance in ACCESS EXCLUSIVE MODE
--      prior to executing the count verification and reconciliation.
--   2. Exact ordered conkey = ARRAY[...] comparisons in B2, B2b, and D3
--      (critical for composite UNIQUE(id, site_id) referenced by category counts FK).
--   3. In D2, drops only the exact obsolete 3-column unique constraint on ordered
--      (site_id, supervisor_id, attendance_date) via exact conkey equality.
--   4. In B3, strictly inspects idx_daily_workforce_attendance_site_date using pg_index:
--      verifies it is exactly a standalone, non-unique, non-partial index on
--      (site_id, attendance_date) with no included columns and no constraint dependency
--      before dropping; preserves the index if any condition is not met.
--   5. Restricts supervisor_attendance column grants:
--        - INSERT: site_id, supervisor_id, attendance_date, status, remarks ONLY
--        - UPDATE: status, remarks ONLY
--        - SELECT, DELETE: table-level
--   6. Trigger immutability enforcement on supervisor_attendance:
--        - id, supervisor_id, site_id, and attendance_date cannot change after INSERT
--        - recorded_by and created_at remain strictly immutable
--        - self-marking and inactive account prohibitions preserved
--   7. Replaces every REVOKE ALL (column) statement: explicitly revokes SELECT,
--      INSERT, UPDATE, and REFERENCES column privileges from anon, authenticated,
--      and PUBLIC (PostgreSQL does not support ALL with a column list).
--   8. In D4, restricts FK selection and replacement strictly to the single-column
--      supervisor_id FK referencing public.user_profiles(id). Verifies both confrelid
--      and confkey. Never drops an unrelated FK. Raises EXCEPTION on unexpected conflicts.
--   9. In D5, applies exact referenced-table and referenced-column validation to
--      recorded_by. Renames supervisor_attendance_recorded_by_fkey to
--      fk_supervisor_attendance_recorded_by if not occupied; preserves unrelated FKs
--      and raises EXCEPTION on unexpected conflicting definitions.
--  10. Fallback recorded_by column is UUID NOT NULL REFERENCES public.user_profiles(id)
--      ON DELETE RESTRICT.
--  11. Section F revokes table- and column-level privileges on daily_workforce_counts
--      from anon, authenticated, and PUBLIC, while fully preserving its table, FK, and data.
--  12. Approved RLS policies (with explicit is_active_user() checks on all branches),
--      category grants, audit triggers, and legacy table preservation are fully preserved.
--
-- SAFETY:
--   • Runs inside a single transaction (BEGIN / COMMIT).
--   • Explicit ACCESS EXCLUSIVE locks prevent race conditions or concurrent writes.
--   • Tables are NEVER dropped; primary keys and unrelated FKs are preserved.
--   • daily_workforce_counts data and structure are untouched.
--   • Run the post-migration verification query after COMMIT.
--
-- STATUS: DO NOT EXECUTE AGAINST PRODUCTION WITHOUT EXPLICIT APPROVAL.
-- ==============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- GUARD: Lock tables against concurrent writes, then confirm tables are empty.
-- ─────────────────────────────────────────────────────────────────────────────
LOCK TABLE
    public.daily_workforce_attendance,
    public.supervisor_attendance
IN ACCESS EXCLUSIVE MODE;

DO $$
DECLARE
  v_count BIGINT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM public.daily_workforce_attendance;
  IF v_count > 0 THEN
    RAISE EXCEPTION
      'GUARD FAILED: daily_workforce_attendance has % row(s). '
      'This reconciliation script is designed for empty tables only. Aborting.',
      v_count;
  END IF;

  SELECT COUNT(*) INTO v_count FROM public.supervisor_attendance;
  IF v_count > 0 THEN
    RAISE EXCEPTION
      'GUARD FAILED: supervisor_attendance has % row(s). '
      'This reconciliation script is designed for empty tables only. Aborting.',
      v_count;
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION A: can_submit_workforce_attendance() Helper Function
--
-- Determines whether the current authenticated user may submit or update a
-- workforce attendance record for a given site.
--   • Active Admin / Project Manager: global access.
--   • Active Supervisor: active site_memberships record (is_active = TRUE) required.
--   • Inactive users or any other role: rejected.
--
-- Search path: pg_catalog first (prevents search-path injection), then public, auth.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_submit_workforce_attendance(p_site_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
STABLE
AS $$
DECLARE
  v_role   TEXT;
  v_status TEXT;
BEGIN
  SELECT role, status INTO v_role, v_status
  FROM public.user_profiles
  WHERE id = auth.uid();

  IF NOT FOUND OR v_status != 'active' THEN
    RETURN FALSE;
  END IF;

  IF v_role IN ('admin', 'projectManager') THEN
    RETURN TRUE;
  END IF;

  IF v_role = 'supervisor' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.site_memberships sm
      WHERE sm.site_id  = p_site_id
        AND sm.user_id  = auth.uid()
        AND sm.is_active = TRUE
    );
  END IF;

  RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.can_submit_workforce_attendance(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.can_submit_workforce_attendance(UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION B: Reconcile public.daily_workforce_attendance
-- ─────────────────────────────────────────────────────────────────────────────

-- B1. Add total_workforce column if it does not already exist.
ALTER TABLE public.daily_workforce_attendance
  ADD COLUMN IF NOT EXISTS total_workforce INTEGER NOT NULL DEFAULT 0
    CHECK (total_workforce >= 0);

-- B2. Ensure UNIQUE(site_id, attendance_date) with canonical name.
--     Validates exact 2-column ordered set (site_id, attendance_date); renames if found,
--     or creates only if missing. Never creates a redundant constraint.
DO $$
DECLARE
  v_existing_name TEXT;
BEGIN
  SELECT c.conname INTO v_existing_name
  FROM pg_constraint c
  JOIN pg_class      cl ON cl.oid = c.conrelid
  JOIN pg_namespace  ns ON ns.oid = cl.relnamespace
  WHERE ns.nspname = 'public'
    AND cl.relname = 'daily_workforce_attendance'
    AND c.contype  = 'u'
    AND c.conkey   = ARRAY[
      (SELECT attnum FROM pg_attribute WHERE attrelid = cl.oid AND attname = 'site_id'),
      (SELECT attnum FROM pg_attribute WHERE attrelid = cl.oid AND attname = 'attendance_date')
    ]::smallint[]
  LIMIT 1;

  IF v_existing_name IS NOT NULL THEN
    IF v_existing_name != 'daily_workforce_attendance_site_date_uniq' THEN
      EXECUTE format(
        'ALTER TABLE public.daily_workforce_attendance '
        'RENAME CONSTRAINT %I TO daily_workforce_attendance_site_date_uniq',
        v_existing_name
      );
    END IF;
  ELSE
    ALTER TABLE public.daily_workforce_attendance
      ADD CONSTRAINT daily_workforce_attendance_site_date_uniq
        UNIQUE (site_id, attendance_date);
  END IF;
END;
$$;

-- B2b. Ensure UNIQUE(id, site_id) as composite FK target for category counts.
--      Validates exact 2-column ordered set (id, site_id); renames if found, or creates if missing.
DO $$
DECLARE
  v_existing_name TEXT;
BEGIN
  SELECT c.conname INTO v_existing_name
  FROM pg_constraint c
  JOIN pg_class      cl ON cl.oid = c.conrelid
  JOIN pg_namespace  ns ON ns.oid = cl.relnamespace
  WHERE ns.nspname = 'public'
    AND cl.relname = 'daily_workforce_attendance'
    AND c.contype  = 'u'
    AND c.conkey   = ARRAY[
      (SELECT attnum FROM pg_attribute WHERE attrelid = cl.oid AND attname = 'id'),
      (SELECT attnum FROM pg_attribute WHERE attrelid = cl.oid AND attname = 'site_id')
    ]::smallint[]
  LIMIT 1;

  IF v_existing_name IS NOT NULL THEN
    IF v_existing_name != 'daily_workforce_attendance_id_site_uniq' THEN
      EXECUTE format(
        'ALTER TABLE public.daily_workforce_attendance '
        'RENAME CONSTRAINT %I TO daily_workforce_attendance_id_site_uniq',
        v_existing_name
      );
    END IF;
  ELSE
    ALTER TABLE public.daily_workforce_attendance
      ADD CONSTRAINT daily_workforce_attendance_id_site_uniq
        UNIQUE (id, site_id);
  END IF;
END;
$$;

-- B3. Conditional index inspection:
-- Before dropping idx_daily_workforce_attendance_site_date, verify using pg_index
-- that it is exactly a standalone, non-unique, non-partial index on
-- (site_id, attendance_date), with no included columns and no constraint dependency,
-- while a unique constraint already covers (site_id, attendance_date).
-- If any condition is not met, preserve the index.
DO $$
DECLARE
  v_table_oid           OID;
  v_site_attnum         SMALLINT;
  v_date_attnum         SMALLINT;
  v_idx_oid             OID;
  v_is_eligible         BOOLEAN := FALSE;
  v_has_covering_unique BOOLEAN := FALSE;
BEGIN
  SELECT oid INTO v_table_oid
  FROM pg_class
  WHERE relnamespace = 'public'::regnamespace
    AND relname = 'daily_workforce_attendance';

  IF v_table_oid IS NULL THEN
    RETURN;
  END IF;

  SELECT attnum INTO v_site_attnum
  FROM pg_attribute
  WHERE attrelid = v_table_oid AND attname = 'site_id';

  SELECT attnum INTO v_date_attnum
  FROM pg_attribute
  WHERE attrelid = v_table_oid AND attname = 'attendance_date';

  -- Inspect pg_index for idx_daily_workforce_attendance_site_date:
  --   1. Attached to daily_workforce_attendance (i.indrelid = v_table_oid)
  --   2. Exactly 2 key columns, 0 included non-key columns (i.indnatts = 2 AND i.indnkeyatts = 2)
  --   3. Exact column sequence (site_id, attendance_date): i.indkey[0] = v_site_attnum AND i.indkey[1] = v_date_attnum
  --   4. Non-unique (NOT i.indisunique)
  --   5. Non-primary (NOT i.indisprimary)
  --   6. Non-partial (i.indpred IS NULL)
  --   7. No constraint dependency / standalone (NOT EXISTS in pg_constraint.conindid)
  SELECT
    c.oid,
    (
      i.indrelid = v_table_oid
      AND i.indnatts = 2
      AND i.indnkeyatts = 2
      AND i.indkey[0] = v_site_attnum
      AND i.indkey[1] = v_date_attnum
      AND NOT i.indisunique
      AND NOT i.indisprimary
      AND i.indpred IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM pg_constraint con WHERE con.conindid = c.oid
      )
    )
  INTO v_idx_oid, v_is_eligible
  FROM pg_class c
  JOIN pg_index i ON i.indexrelid = c.oid
  WHERE c.relnamespace = 'public'::regnamespace
    AND c.relname = 'idx_daily_workforce_attendance_site_date';

  IF v_idx_oid IS NOT NULL AND v_is_eligible THEN
    -- Verify a separate unique constraint covers (site_id, attendance_date)
    SELECT EXISTS (
      SELECT 1
      FROM pg_constraint con
      WHERE con.conrelid = v_table_oid
        AND con.contype  = 'u'
        AND con.conkey   = ARRAY[v_site_attnum, v_date_attnum]::smallint[]
        AND con.conindid IS DISTINCT FROM v_idx_oid
    ) INTO v_has_covering_unique;

    IF v_has_covering_unique THEN
      DROP INDEX public.idx_daily_workforce_attendance_site_date;
    END IF;
  END IF;
END;
$$;

-- B4. Ensure RLS is enabled.
ALTER TABLE public.daily_workforce_attendance ENABLE ROW LEVEL SECURITY;

-- B5. Privilege revocation and column-scoped grants.
--     Table-level REVOKE ALL does not automatically revoke surviving column-level grants.
--     Explicitly revoke SELECT, INSERT, UPDATE, and REFERENCES from anon, authenticated, and PUBLIC.
REVOKE ALL ON public.daily_workforce_attendance FROM anon, PUBLIC;
REVOKE ALL ON public.daily_workforce_attendance FROM authenticated;

DO $$
DECLARE
  v_col TEXT;
BEGIN
  FOR v_col IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'daily_workforce_attendance'
  LOOP
    EXECUTE format(
      'REVOKE SELECT (%I), INSERT (%I), UPDATE (%I), REFERENCES (%I) ON public.daily_workforce_attendance FROM anon, authenticated, PUBLIC',
      v_col, v_col, v_col, v_col
    );
  END LOOP;
END;
$$;

-- Apply approved grants:
--   SELECT / DELETE : table-level
--   INSERT          : site_id, attendance_date, remarks ONLY
--   UPDATE          : remarks ONLY — total_workforce and audit fields are trigger-managed
GRANT SELECT ON public.daily_workforce_attendance TO authenticated;
GRANT INSERT (site_id, attendance_date, remarks) ON public.daily_workforce_attendance TO authenticated;
GRANT UPDATE (remarks) ON public.daily_workforce_attendance TO authenticated;
GRANT DELETE ON public.daily_workforce_attendance TO authenticated;

-- B6. Replace all existing RLS policies with the approved set.
--     Explicit is_active_user() check on ALL branches (PM/Admin, Admin, and site access).
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'daily_workforce_attendance'
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.daily_workforce_attendance',
      r.policyname
    );
  END LOOP;
END;
$$;

-- SELECT: Active PM/Admin see all sites; active users see accessible sites
CREATE POLICY "daily_workforce_attendance_select"
  ON public.daily_workforce_attendance FOR SELECT TO authenticated
  USING (
    public.is_active_user()
    AND (
      public.is_pm_or_admin()
      OR public.has_site_access(site_id)
    )
  );

-- INSERT: Active submitters (active PM/Admin global; active supervisors with active membership)
CREATE POLICY "daily_workforce_attendance_insert"
  ON public.daily_workforce_attendance FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_user()
    AND public.can_submit_workforce_attendance(site_id)
  );

-- UPDATE: Active submitters (remarks-only via column grant above)
CREATE POLICY "daily_workforce_attendance_update"
  ON public.daily_workforce_attendance FOR UPDATE TO authenticated
  USING (
    public.is_active_user()
    AND public.can_submit_workforce_attendance(site_id)
  )
  WITH CHECK (
    public.is_active_user()
    AND public.can_submit_workforce_attendance(site_id)
  );

-- DELETE: Strictly active Administrators
CREATE POLICY "daily_workforce_attendance_delete"
  ON public.daily_workforce_attendance FOR DELETE TO authenticated
  USING (
    public.is_active_user()
    AND public.is_admin()
  );

-- B7. Audit + immutability trigger for daily_workforce_attendance.
CREATE OR REPLACE FUNCTION public.set_workforce_attendance_audit_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by      := auth.uid();
    NEW.created_at      := now();
    NEW.total_workforce := 0;

  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
      RAISE EXCEPTION 'Attendance record ID is immutable.';
    END IF;
    IF NEW.site_id IS DISTINCT FROM OLD.site_id THEN
      RAISE EXCEPTION 'Cannot reassign attendance record to a different construction site.';
    END IF;
    IF NEW.attendance_date IS DISTINCT FROM OLD.attendance_date THEN
      RAISE EXCEPTION 'Attendance date is immutable after insert.';
    END IF;

    NEW.created_by := OLD.created_by;
    NEW.created_at := OLD.created_at;

    IF NEW.total_workforce IS DISTINCT FROM OLD.total_workforce THEN
      IF pg_trigger_depth() >= 2
         AND nullif(current_setting('tsr.workforce_sync_token', true), '') IS NOT NULL
      THEN
        PERFORM set_config('tsr.workforce_sync_token', '', true);
      ELSE
        NEW.total_workforce := OLD.total_workforce;
      END IF;
    ELSE
      NEW.total_workforce := OLD.total_workforce;
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_workforce_attendance_audit_fields
  ON public.daily_workforce_attendance;
CREATE TRIGGER trg_set_workforce_attendance_audit_fields
  BEFORE INSERT OR UPDATE ON public.daily_workforce_attendance
  FOR EACH ROW
  EXECUTE FUNCTION public.set_workforce_attendance_audit_fields();

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION C: Create public.daily_workforce_category_counts
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.daily_workforce_category_counts (
  id            UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_id UUID    NOT NULL,
  site_id       UUID    NOT NULL,
  category      TEXT    NOT NULL
                  CHECK (category IN (
                    'Masons',
                    'Painters',
                    'Helpers',
                    'Carpenters',
                    'Electricians',
                    'Plumbers',
                    'Other'
                  )),
  count         INTEGER NOT NULL DEFAULT 0 CHECK (count >= 0),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Composite FK: prevents cross-site category rows
  CONSTRAINT fk_workforce_category_counts_header_site
    FOREIGN KEY (attendance_id, site_id)
    REFERENCES public.daily_workforce_attendance(id, site_id)
    ON DELETE CASCADE,

  -- One count per trade category per attendance submission
  CONSTRAINT daily_workforce_counts_attendance_category_uniq
    UNIQUE (attendance_id, category)
);

CREATE INDEX IF NOT EXISTS idx_daily_workforce_cat_attendance
  ON public.daily_workforce_category_counts (attendance_id);

CREATE INDEX IF NOT EXISTS idx_daily_workforce_cat_site
  ON public.daily_workforce_category_counts (site_id);

ALTER TABLE public.daily_workforce_category_counts ENABLE ROW LEVEL SECURITY;

-- Privilege revocation: explicitly clear table- and column-level privileges from anon, authenticated, PUBLIC
REVOKE ALL ON public.daily_workforce_category_counts FROM anon, PUBLIC;
REVOKE ALL ON public.daily_workforce_category_counts FROM authenticated;

DO $$
DECLARE
  v_col TEXT;
BEGIN
  FOR v_col IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'daily_workforce_category_counts'
  LOOP
    EXECUTE format(
      'REVOKE SELECT (%I), INSERT (%I), UPDATE (%I), REFERENCES (%I) ON public.daily_workforce_category_counts FROM anon, authenticated, PUBLIC',
      v_col, v_col, v_col, v_col
    );
  END LOOP;
END;
$$;

-- Apply approved grants on category counts:
--   SELECT, DELETE : table-level
--   INSERT          : attendance_id, site_id, category, count (editable business fields)
--   UPDATE          : category, count ONLY
--   id, created_at, updated_at are strictly server-controlled
GRANT SELECT, DELETE ON public.daily_workforce_category_counts TO authenticated;
GRANT INSERT (attendance_id, site_id, category, count) ON public.daily_workforce_category_counts TO authenticated;
GRANT UPDATE (category, count) ON public.daily_workforce_category_counts TO authenticated;

-- Policies on category counts with explicit is_active_user() checks on all branches:
CREATE POLICY "daily_workforce_category_counts_select"
  ON public.daily_workforce_category_counts FOR SELECT TO authenticated
  USING (
    public.is_active_user()
    AND (
      public.is_pm_or_admin()
      OR public.has_site_access(site_id)
    )
  );

CREATE POLICY "daily_workforce_category_counts_insert"
  ON public.daily_workforce_category_counts FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_user()
    AND public.can_submit_workforce_attendance(site_id)
  );

CREATE POLICY "daily_workforce_category_counts_update"
  ON public.daily_workforce_category_counts FOR UPDATE TO authenticated
  USING (
    public.is_active_user()
    AND public.can_submit_workforce_attendance(site_id)
  )
  WITH CHECK (
    public.is_active_user()
    AND public.can_submit_workforce_attendance(site_id)
  );

CREATE POLICY "daily_workforce_category_counts_delete"
  ON public.daily_workforce_category_counts FOR DELETE TO authenticated
  USING (
    public.is_active_user()
    AND public.is_admin()
  );

-- C1. AFTER trigger: sync parent total_workforce on category INSERT/UPDATE/DELETE
CREATE OR REPLACE FUNCTION public.sync_workforce_total()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_sync_token TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_sync_token := gen_random_uuid()::text;
    PERFORM set_config('tsr.workforce_sync_token', v_sync_token, true);
    UPDATE public.daily_workforce_attendance
    SET    total_workforce = COALESCE((
             SELECT SUM(count)
             FROM   public.daily_workforce_category_counts
             WHERE  attendance_id = OLD.attendance_id
           ), 0),
           updated_at = now()
    WHERE  id = OLD.attendance_id;
    PERFORM set_config('tsr.workforce_sync_token', '', true);

  ELSIF TG_OP = 'INSERT' THEN
    v_sync_token := gen_random_uuid()::text;
    PERFORM set_config('tsr.workforce_sync_token', v_sync_token, true);
    UPDATE public.daily_workforce_attendance
    SET    total_workforce = COALESCE((
             SELECT SUM(count)
             FROM   public.daily_workforce_category_counts
             WHERE  attendance_id = NEW.attendance_id
           ), 0),
           updated_at = now()
    WHERE  id = NEW.attendance_id;
    PERFORM set_config('tsr.workforce_sync_token', '', true);

  ELSIF TG_OP = 'UPDATE' THEN
    -- Recalculate destination (NEW) header
    v_sync_token := gen_random_uuid()::text;
    PERFORM set_config('tsr.workforce_sync_token', v_sync_token, true);
    UPDATE public.daily_workforce_attendance
    SET    total_workforce = COALESCE((
             SELECT SUM(count)
             FROM   public.daily_workforce_category_counts
             WHERE  attendance_id = NEW.attendance_id
           ), 0),
           updated_at = now()
    WHERE  id = NEW.attendance_id;
    PERFORM set_config('tsr.workforce_sync_token', '', true);

    IF OLD.attendance_id IS DISTINCT FROM NEW.attendance_id THEN
      v_sync_token := gen_random_uuid()::text;
      PERFORM set_config('tsr.workforce_sync_token', v_sync_token, true);
      UPDATE public.daily_workforce_attendance
      SET    total_workforce = COALESCE((
               SELECT SUM(count)
               FROM   public.daily_workforce_category_counts
               WHERE  attendance_id = OLD.attendance_id
             ), 0),
             updated_at = now()
      WHERE  id = OLD.attendance_id;
      PERFORM set_config('tsr.workforce_sync_token', '', true);
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_workforce_total ON public.daily_workforce_category_counts;
CREATE TRIGGER trg_sync_workforce_total
  AFTER INSERT OR UPDATE OR DELETE ON public.daily_workforce_category_counts
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_workforce_total();

-- C2. BEFORE UPDATE trigger: reliable updated_at stamp on category count edits
CREATE OR REPLACE FUNCTION public.set_category_counts_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_category_counts_updated_at ON public.daily_workforce_category_counts;
CREATE TRIGGER trg_set_category_counts_updated_at
  BEFORE UPDATE ON public.daily_workforce_category_counts
  FOR EACH ROW
  EXECUTE FUNCTION public.set_category_counts_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION D: Reconcile public.supervisor_attendance
-- ─────────────────────────────────────────────────────────────────────────────

-- D1. Rename supervisor_user_id → supervisor_id (guarded)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE  table_schema = 'public'
      AND  table_name   = 'supervisor_attendance'
      AND  column_name  = 'supervisor_user_id'
  ) THEN
    ALTER TABLE public.supervisor_attendance
      RENAME COLUMN supervisor_user_id TO supervisor_id;
  END IF;
END;
$$;

-- D2. Drop ONLY the obsolete 3-column unique constraint on
--     exact ordered (site_id, supervisor_id, attendance_date).
DO $$
DECLARE
  v_conname TEXT;
BEGIN
  SELECT c.conname INTO v_conname
  FROM pg_constraint c
  JOIN pg_class      cl ON cl.oid = c.conrelid
  JOIN pg_namespace  ns ON ns.oid = cl.relnamespace
  WHERE ns.nspname = 'public'
    AND cl.relname = 'supervisor_attendance'
    AND c.contype  = 'u'
    AND c.conkey   = ARRAY[
      (SELECT attnum FROM pg_attribute WHERE attrelid = cl.oid AND attname = 'site_id'),
      (SELECT attnum FROM pg_attribute WHERE attrelid = cl.oid AND attname = 'supervisor_id'),
      (SELECT attnum FROM pg_attribute WHERE attrelid = cl.oid AND attname = 'attendance_date')
    ]::smallint[]
    AND c.conname != 'supervisor_attendance_supervisor_date_uniq'
  LIMIT 1;

  IF v_conname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.supervisor_attendance DROP CONSTRAINT %I', v_conname);
  END IF;
END;
$$;

-- D3. Add approved unique constraint: exactly (supervisor_id, attendance_date)
--     Validates exact 2-column ordered set (supervisor_id, attendance_date); renames or creates.
DO $$
DECLARE
  v_existing_name TEXT;
BEGIN
  SELECT c.conname INTO v_existing_name
  FROM pg_constraint c
  JOIN pg_class      cl ON cl.oid = c.conrelid
  JOIN pg_namespace  ns ON ns.oid = cl.relnamespace
  WHERE ns.nspname = 'public'
    AND cl.relname = 'supervisor_attendance'
    AND c.contype  = 'u'
    AND c.conkey   = ARRAY[
      (SELECT attnum FROM pg_attribute WHERE attrelid = cl.oid AND attname = 'supervisor_id'),
      (SELECT attnum FROM pg_attribute WHERE attrelid = cl.oid AND attname = 'attendance_date')
    ]::smallint[]
  LIMIT 1;

  IF v_existing_name IS NOT NULL THEN
    IF v_existing_name != 'supervisor_attendance_supervisor_date_uniq' THEN
      EXECUTE format(
        'ALTER TABLE public.supervisor_attendance RENAME CONSTRAINT %I TO supervisor_attendance_supervisor_date_uniq',
        v_existing_name
      );
    END IF;
  ELSE
    ALTER TABLE public.supervisor_attendance
      ADD CONSTRAINT supervisor_attendance_supervisor_date_uniq
        UNIQUE (supervisor_id, attendance_date);
  END IF;
END;
$$;

-- D4. Re-wire supervisor identity FK as ON DELETE RESTRICT.
--     Strictly checks single-column FK on supervisor_id.
--     Verifies both confrelid (user_profiles) and confkey (user_profiles.id).
--     Never drops unrelated FKs. Raises EXCEPTION on unexpected conflicts.
DO $$
DECLARE
  v_rec            RECORD;
  v_found_approved BOOLEAN := FALSE;
  v_sup_attnum     SMALLINT;
  v_up_id_attnum   SMALLINT;
BEGIN
  SELECT attnum INTO v_sup_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.supervisor_attendance'::regclass
    AND attname = 'supervisor_id';

  SELECT attnum INTO v_up_id_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.user_profiles'::regclass
    AND attname = 'id';

  FOR v_rec IN
    SELECT
      c.conname,
      c.conkey,
      c.confrelid,
      c.confkey,
      c.confdeltype
    FROM pg_constraint c
    WHERE c.conrelid = 'public.supervisor_attendance'::regclass
      AND c.contype = 'f'
      AND v_sup_attnum = ANY(c.conkey)
  LOOP
    IF v_rec.conkey != ARRAY[v_sup_attnum] THEN
      RAISE EXCEPTION
        'Unexpected composite foreign key "%" on supervisor_attendance involves supervisor_id. Cannot safely reconcile.',
        v_rec.conname;
    END IF;

    IF v_rec.confrelid != 'public.user_profiles'::regclass THEN
      RAISE EXCEPTION
        'Foreign key "%" on supervisor_attendance(supervisor_id) references unexpected table (oid: %). Expected public.user_profiles. Aborting.',
        v_rec.conname, v_rec.confrelid;
    END IF;

    IF v_rec.confkey != ARRAY[v_up_id_attnum] THEN
      RAISE EXCEPTION
        'Foreign key "%" on supervisor_attendance(supervisor_id) references unexpected column(s) on user_profiles. Expected user_profiles(id). Aborting.',
        v_rec.conname;
    END IF;

    IF v_rec.confdeltype = 'r' THEN
      IF v_rec.conname = 'fk_supervisor_attendance_supervisor' THEN
        v_found_approved := TRUE;
      ELSE
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conrelid = 'public.supervisor_attendance'::regclass
            AND conname = 'fk_supervisor_attendance_supervisor'
        ) THEN
          EXECUTE format(
            'ALTER TABLE public.supervisor_attendance RENAME CONSTRAINT %I TO fk_supervisor_attendance_supervisor',
            v_rec.conname
          );
          v_found_approved := TRUE;
        ELSE
          RAISE EXCEPTION
            'Cannot rename FK "%" to "fk_supervisor_attendance_supervisor" because constraint name already exists.',
            v_rec.conname;
        END IF;
      END IF;
    ELSE
      EXECUTE format(
        'ALTER TABLE public.supervisor_attendance DROP CONSTRAINT %I',
        v_rec.conname
      );
    END IF;
  END LOOP;

  IF NOT v_found_approved AND NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.supervisor_attendance'::regclass
      AND conname = 'fk_supervisor_attendance_supervisor'
  ) THEN
    ALTER TABLE public.supervisor_attendance
      ADD CONSTRAINT fk_supervisor_attendance_supervisor
        FOREIGN KEY (supervisor_id)
        REFERENCES public.user_profiles(id)
        ON DELETE RESTRICT;
  END IF;
END;
$$;

-- D5. Ensure recorded_by column exists as UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT.
--     Applies exact referenced-column validation to recorded_by. Preserves unrelated FKs,
--     renames supervisor_attendance_recorded_by_fkey to canonical name, and fails clearly on conflicts.
DO $$
DECLARE
  v_rec            RECORD;
  v_found_approved BOOLEAN := FALSE;
  v_rec_by_attnum  SMALLINT;
  v_up_id_attnum   SMALLINT;
  v_auto_fk        TEXT;
BEGIN
  -- 1. If column is absent, add with full required definition
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'supervisor_attendance'
      AND column_name  = 'recorded_by'
  ) THEN
    ALTER TABLE public.supervisor_attendance
      ADD COLUMN recorded_by UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT;

    SELECT c.conname INTO v_auto_fk
    FROM pg_constraint c
    WHERE c.conrelid = 'public.supervisor_attendance'::regclass
      AND c.contype = 'f'
      AND c.conkey = ARRAY[
        (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.supervisor_attendance'::regclass AND attname = 'recorded_by')
      ]
    LIMIT 1;

    IF v_auto_fk IS NOT NULL AND v_auto_fk != 'fk_supervisor_attendance_recorded_by' THEN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.supervisor_attendance'::regclass
          AND conname = 'fk_supervisor_attendance_recorded_by'
      ) THEN
        EXECUTE format(
          'ALTER TABLE public.supervisor_attendance RENAME CONSTRAINT %I TO fk_supervisor_attendance_recorded_by',
          v_auto_fk
        );
      END IF;
    END IF;
    RETURN;
  END IF;

  -- 2. Column exists: ensure NOT NULL (safe since table confirmed empty)
  ALTER TABLE public.supervisor_attendance
    ALTER COLUMN recorded_by SET NOT NULL;

  -- 3. Validate FK constraints strictly on recorded_by
  SELECT attnum INTO v_rec_by_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.supervisor_attendance'::regclass
    AND attname = 'recorded_by';

  SELECT attnum INTO v_up_id_attnum
  FROM pg_attribute
  WHERE attrelid = 'public.user_profiles'::regclass
    AND attname = 'id';

  FOR v_rec IN
    SELECT
      c.conname,
      c.conkey,
      c.confrelid,
      c.confkey,
      c.confdeltype
    FROM pg_constraint c
    WHERE c.conrelid = 'public.supervisor_attendance'::regclass
      AND c.contype = 'f'
      AND v_rec_by_attnum = ANY(c.conkey)
  LOOP
    IF v_rec.conkey != ARRAY[v_rec_by_attnum] THEN
      RAISE EXCEPTION
        'Unexpected composite foreign key "%" on supervisor_attendance involves recorded_by. Cannot safely reconcile.',
        v_rec.conname;
    END IF;

    IF v_rec.confrelid != 'public.user_profiles'::regclass THEN
      RAISE EXCEPTION
        'Foreign key "%" on supervisor_attendance(recorded_by) references unexpected table (oid: %). Expected public.user_profiles. Aborting.',
        v_rec.conname, v_rec.confrelid;
    END IF;

    IF v_rec.confkey != ARRAY[v_up_id_attnum] THEN
      RAISE EXCEPTION
        'Foreign key "%" on supervisor_attendance(recorded_by) references unexpected column(s) on user_profiles. Expected user_profiles(id). Aborting.',
        v_rec.conname;
    END IF;

    IF v_rec.confdeltype = 'r' THEN
      IF v_rec.conname = 'fk_supervisor_attendance_recorded_by' THEN
        v_found_approved := TRUE;
      ELSE
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conrelid = 'public.supervisor_attendance'::regclass
            AND conname = 'fk_supervisor_attendance_recorded_by'
        ) THEN
          EXECUTE format(
            'ALTER TABLE public.supervisor_attendance RENAME CONSTRAINT %I TO fk_supervisor_attendance_recorded_by',
            v_rec.conname
          );
          v_found_approved := TRUE;
        ELSE
          RAISE EXCEPTION
            'Cannot rename FK "%" to "fk_supervisor_attendance_recorded_by" because constraint name already exists.',
            v_rec.conname;
        END IF;
      END IF;
    ELSE
      EXECUTE format(
        'ALTER TABLE public.supervisor_attendance DROP CONSTRAINT %I',
        v_rec.conname
      );
    END IF;
  END LOOP;

  IF NOT v_found_approved AND NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.supervisor_attendance'::regclass
      AND conname = 'fk_supervisor_attendance_recorded_by'
  ) THEN
    ALTER TABLE public.supervisor_attendance
      ADD CONSTRAINT fk_supervisor_attendance_recorded_by
        FOREIGN KEY (recorded_by)
        REFERENCES public.user_profiles(id)
        ON DELETE RESTRICT;
  END IF;
END;
$$;

-- D6. Ensure RLS is enabled.
ALTER TABLE public.supervisor_attendance ENABLE ROW LEVEL SECURITY;

-- D7. Remove ALL existing RLS policies and install approved set.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'supervisor_attendance'
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.supervisor_attendance',
      r.policyname
    );
  END LOOP;
END;
$$;

REVOKE ALL ON public.supervisor_attendance FROM anon, PUBLIC;
REVOKE ALL ON public.supervisor_attendance FROM authenticated;

-- Clear any surviving column-level privileges from anon, authenticated, PUBLIC
DO $$
DECLARE
  v_col TEXT;
BEGIN
  FOR v_col IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'supervisor_attendance'
  LOOP
    EXECUTE format(
      'REVOKE SELECT (%I), INSERT (%I), UPDATE (%I), REFERENCES (%I) ON public.supervisor_attendance FROM anon, authenticated, PUBLIC',
      v_col, v_col, v_col, v_col
    );
  END LOOP;
END;
$$;

-- Apply restricted grants on supervisor_attendance:
--   SELECT, DELETE : table-level
--   INSERT          : site_id, supervisor_id, attendance_date, status, remarks ONLY
--   UPDATE          : status, remarks ONLY
--   id, recorded_by, created_at, updated_at are strictly server-managed
GRANT SELECT, DELETE ON public.supervisor_attendance TO authenticated;
GRANT INSERT (site_id, supervisor_id, attendance_date, status, remarks) ON public.supervisor_attendance TO authenticated;
GRANT UPDATE (status, remarks) ON public.supervisor_attendance TO authenticated;

-- Policies on supervisor_attendance with explicit is_active_user() on all branches:
CREATE POLICY "supervisor_attendance_active_select"
  ON public.supervisor_attendance FOR SELECT TO authenticated
  USING (
    public.is_active_user()
    AND (
      public.is_pm_or_admin()
      OR supervisor_id = auth.uid()
    )
  );

-- INSERT: Active PM/Admin only; self-marking prohibited
CREATE POLICY "supervisor_attendance_pm_admin_insert"
  ON public.supervisor_attendance FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_user()
    AND public.is_pm_or_admin()
    AND (auth.uid() IS NULL OR auth.uid() != supervisor_id)
  );

-- UPDATE: Active PM/Admin only; self-marking prohibited (status, remarks via column grant)
CREATE POLICY "supervisor_attendance_pm_admin_update"
  ON public.supervisor_attendance FOR UPDATE TO authenticated
  USING (
    public.is_active_user()
    AND public.is_pm_or_admin()
    AND (auth.uid() IS NULL OR auth.uid() != supervisor_id)
  )
  WITH CHECK (
    public.is_active_user()
    AND public.is_pm_or_admin()
    AND (auth.uid() IS NULL OR auth.uid() != supervisor_id)
  );

-- DELETE: Strictly active Administrators
CREATE POLICY "supervisor_attendance_admin_delete"
  ON public.supervisor_attendance FOR DELETE TO authenticated
  USING (
    public.is_active_user()
    AND public.is_admin()
  );

-- D8. Server-enforced audit, validation, and immutability trigger for supervisor_attendance
CREATE OR REPLACE FUNCTION public.validate_and_audit_supervisor_attendance()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_role   TEXT;
  v_status TEXT;
BEGIN
  -- 1. Immutability & audit field preservation
  IF TG_OP = 'INSERT' THEN
    NEW.recorded_by := auth.uid();
    NEW.created_at  := now();
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
      RAISE EXCEPTION 'Supervisor attendance ID is immutable.';
    END IF;
    IF NEW.supervisor_id IS DISTINCT FROM OLD.supervisor_id THEN
      RAISE EXCEPTION 'Supervisor ID is immutable after insert.';
    END IF;
    IF NEW.site_id IS DISTINCT FROM OLD.site_id THEN
      RAISE EXCEPTION 'Site ID is immutable after insert.';
    END IF;
    IF NEW.attendance_date IS DISTINCT FROM OLD.attendance_date THEN
      RAISE EXCEPTION 'Attendance date is immutable after insert.';
    END IF;

    NEW.recorded_by := OLD.recorded_by;
    NEW.created_at  := OLD.created_at;
  END IF;

  -- 2. Self-marking prohibition
  IF auth.uid() IS NOT NULL AND auth.uid() = NEW.supervisor_id THEN
    RAISE EXCEPTION
      'Supervisors are prohibited from recording or editing their own personal attendance.';
  END IF;

  -- 3. Verify target supervisor: must exist, be active, have role "supervisor"
  SELECT role, status INTO v_role, v_status
  FROM   public.user_profiles
  WHERE  id = NEW.supervisor_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Target supervisor ID % does not exist in user_profiles.', NEW.supervisor_id;
  END IF;

  IF v_status != 'active' THEN
    RAISE EXCEPTION 'Cannot record attendance for a disabled user account.';
  END IF;

  IF v_role != 'supervisor' THEN
    RAISE EXCEPTION
      'Target user must have role "supervisor". Current role: %', v_role;
  END IF;

  -- 4. Mandatory active site membership (never skipped)
  IF NOT EXISTS (
    SELECT 1 FROM public.site_memberships sm
    WHERE  sm.site_id  = NEW.site_id
      AND  sm.user_id  = NEW.supervisor_id
      AND  sm.is_active = TRUE
  ) THEN
    RAISE EXCEPTION
      'Supervisor % is not an active assigned member (is_active = TRUE) of site % in site_memberships.',
      NEW.supervisor_id, NEW.site_id;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_and_audit_supervisor_attendance
  ON public.supervisor_attendance;
CREATE TRIGGER trg_validate_and_audit_supervisor_attendance
  BEFORE INSERT OR UPDATE ON public.supervisor_attendance
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_and_audit_supervisor_attendance();

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION E: Performance indexes on supervisor_attendance
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_supervisor_attendance_site_date
  ON public.supervisor_attendance (site_id, attendance_date);

CREATE INDEX IF NOT EXISTS idx_supervisor_attendance_supervisor_date
  ON public.supervisor_attendance (supervisor_id, attendance_date);

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION F: Protect legacy table from unauthorized access while preserving data.
-- daily_workforce_counts structure, foreign keys, and existing rows are 100% preserved.
-- Revoke all table-level and column-level privileges from anon, authenticated, and PUBLIC.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_col TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'daily_workforce_counts'
  ) THEN
    REVOKE ALL ON public.daily_workforce_counts FROM anon, authenticated, PUBLIC;

    FOR v_col IN
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name   = 'daily_workforce_counts'
    LOOP
      EXECUTE format(
        'REVOKE SELECT (%I), INSERT (%I), UPDATE (%I), REFERENCES (%I) ON public.daily_workforce_counts FROM anon, authenticated, PUBLIC',
        v_col, v_col, v_col, v_col
      );
    END LOOP;
  END IF;
END;
$$;

COMMIT;
