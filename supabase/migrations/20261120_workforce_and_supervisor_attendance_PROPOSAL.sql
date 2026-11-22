-- ==============================================================================
-- TSR BUILDERS — PROPOSED ADDITIVE MIGRATION (PROPOSAL — DO NOT EXECUTE YET)
-- File: supabase/migrations/20261120_workforce_and_supervisor_attendance_PROPOSAL.sql
-- ==============================================================================
-- ARCHITECTURAL SPECIFICATION & SECURITY VERIFICATION:
-- 1. Purely Additive: Does NOT drop, alter, or modify public.site_attendance,
--    public.workers, public.sites, or public.user_profiles. Historical records
--    and existing workflows remain 100% intact.
-- 2. Strict Site Membership Enforcement (sm.is_active = TRUE):
--    - In validate_and_audit_supervisor_attendance(), an active public.site_memberships
--      record (sm.is_active = TRUE) is strictly required for the supervisor on that site.
--      Membership validation is NEVER skipped regardless of table state.
--    - Eliminates duplicate assignment sources (no redundant site_supervisors table).
--    - Reuses live security functions: public.has_site_access(site_id) and public.can_manage_site(site_id).
-- 3. Complete can_submit_workforce_attendance(p_site_id UUID):
--    - Defined fully in SQL with pinned search_path.
--    - Allows Admin and Project Manager globally across all sites.
--    - Allows supervisors only on sites where they have active membership (sm.is_active = TRUE).
--    - Strictly rejects inactive users and unauthorized roles.
-- 4. Supervisor Personal Attendance & Foreign Key Deletion Protection (ON DELETE RESTRICT):
--    - supervisor_attendance.supervisor_id REFERENCES public.user_profiles(id) ON DELETE RESTRICT.
--      Supervisor profiles cannot be deleted while historical attendance records exist; accounts must be
--      deactivated (status = 'disabled') instead.
--    - Business Rule: A supervisor can have exactly ONE personal attendance record per
--      calendar date across the entire enterprise (UNIQUE (supervisor_id, attendance_date)).
--      A supervisor cannot be recorded as simultaneously Present, Absent, or on Leave
--      at multiple separate sites on the same calendar date.
-- 5. Seven Agreed Trade Categories & Reliable Category updated_at:
--    - daily_workforce_category_counts.category has a strict CHECK constraint for the seven agreed
--      categories: ('Masons', 'Painters', 'Helpers', 'Carpenters', 'Electricians', 'Plumbers', 'Other').
--    - BEFORE UPDATE trigger trg_set_category_counts_updated_at ensures updated_at is reliably refreshed
--      on category count edits, while sync_workforce_total updates the parent header updated_at.
-- 6. Cross-Site Reference Prevention:
--    - Uses a Composite Foreign Key (attendance_id, site_id) on detail category counts
--      referencing (id, site_id) on the attendance header. Workforce category rows
--      cannot reference an attendance header from a different site.
-- 7. Server-Enforced Audit Attribution & Field Immutability:
--    - In daily_workforce_attendance: created_by, site_id, and attendance_date are immutable after insert.
--      Authenticated users are granted UPDATE on remarks ONLY. Client cannot modify site_id or date.
--    - In supervisor_attendance: recorded_by represents the original recorder who logged the attendance
--      and is strictly immutable on UPDATE (preserving original recorder audit trail).
-- 8. Self-Marking Prohibition:
--    - Supervisors are barred by RLS policies and BEFORE-triggers from marking or
--      editing their own personal attendance (auth.uid() != supervisor_id).
--    - Only Project Managers and Administrators can record or edit supervisor personal attendance.
-- 9. Scoped Supervisor Attendance Visibility:
--    - In supervisor_attendance_active_select: PM/Admin can read all supervisor attendance records;
--      supervisors can read only their own records (supervisor_id = auth.uid()).
-- 10. Workforce Total Protection & Header Recalculation:
--    - Direct client tampering with total_workforce and created_by is strictly blocked via column-level grants
--      (authenticated role has no column grant for total_workforce or created_by).
--    - On header INSERT, total_workforce is initialized to zero (client-provided value ignored).
--    - On header UPDATE, client attempts to modify total_workforce directly are blocked by column grants (42501).
--    - Recalculation is delegated solely to the SECURITY DEFINER category trigger (sync_workforce_total).
--    - Narrow Scoped Internal Authorization: sync_workforce_total generates a fresh random token
--      (tsr.workforce_sync_token) per UPDATE statement and restores it immediately.
--    - The audit trigger requires BOTH pg_trigger_depth() >= 2 AND the active token, ensuring ordinary
--      authenticated client requests cannot activate the internal bypass.
--    - inserting, updating, reparenting, and deleting category rows correctly recalculates target and old headers.
-- 11. Zero Anon / Public Privileges:
--    - All direct and inherited table permissions from anon & PUBLIC are revoked (42501 expected).
--
-- STATUS: PROPOSAL ONLY. DO NOT EXECUTE AGAINST PRODUCTION WITHOUT EXPLICIT APPROVAL.
-- ==============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Complete can_submit_workforce_attendance() Helper Function
-- ─────────────────────────────────────────────────────────────────────────────
-- Validates that the caller is an active authenticated user with permitted role:
-- - 'admin' and 'projectManager' have global access across all sites.
-- - 'supervisor' has access only if an active site_memberships record (is_active = TRUE) exists.
-- - Inactive users and other roles are strictly rejected.
CREATE OR REPLACE FUNCTION public.can_submit_workforce_attendance(p_site_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
STABLE
AS $$
DECLARE
  v_role TEXT;
  v_status TEXT;
BEGIN
  -- 1. Fetch caller role and account status
  SELECT role, status INTO v_role, v_status
  FROM public.user_profiles
  WHERE id = auth.uid();

  -- Reject unauthenticated or disabled accounts
  IF NOT FOUND OR v_status != 'active' THEN
    RETURN FALSE;
  END IF;

  -- 2. Admin and Project Manager have global submission privileges across all sites
  IF v_role IN ('admin', 'projectManager') THEN
    RETURN TRUE;
  END IF;

  -- 3. Supervisors can submit only for sites where they hold active membership
  IF v_role = 'supervisor' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.site_memberships sm
      WHERE sm.site_id = p_site_id
        AND sm.user_id = auth.uid()
        AND sm.is_active = TRUE
    );
  END IF;

  -- 4. All other roles (e.g. workers, subcontractors, external viewers) are rejected
  RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.can_submit_workforce_attendance(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_submit_workforce_attendance(UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Module A — Daily Workforce Attendance Header (public.daily_workforce_attendance)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.daily_workforce_attendance (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id         UUID NOT NULL REFERENCES public.sites(id) ON DELETE CASCADE,
  attendance_date DATE NOT NULL DEFAULT CURRENT_DATE,
  remarks         TEXT,
  total_workforce INTEGER NOT NULL DEFAULT 0 CHECK (total_workforce >= 0),
  created_by      UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Exactly one workforce submission per site per date
  CONSTRAINT daily_workforce_attendance_site_date_uniq UNIQUE (site_id, attendance_date),
  -- Composite unique target for detail-table composite foreign key enforcement
  CONSTRAINT daily_workforce_attendance_id_site_uniq UNIQUE (id, site_id)
);

CREATE INDEX IF NOT EXISTS idx_daily_workforce_attendance_site_date
  ON public.daily_workforce_attendance (site_id, attendance_date);

ALTER TABLE public.daily_workforce_attendance ENABLE ROW LEVEL SECURITY;

-- Zero anon / public privileges
REVOKE ALL ON public.daily_workforce_attendance FROM anon, PUBLIC;
REVOKE ALL ON public.daily_workforce_attendance FROM authenticated;
-- Column-level grants: authenticated clients may NOT set total_workforce or created_by.
-- Furthermore, site_id and attendance_date are immutable after insert.
-- Authenticated users are granted UPDATE on remarks ONLY.
-- These columns are managed exclusively by SECURITY DEFINER triggers.
-- Any INSERT or UPDATE that includes total_workforce or created_by will raise 42501.
GRANT SELECT ON public.daily_workforce_attendance TO authenticated;
GRANT INSERT (site_id, attendance_date, remarks) ON public.daily_workforce_attendance TO authenticated;
GRANT UPDATE (remarks) ON public.daily_workforce_attendance TO authenticated;
GRANT DELETE ON public.daily_workforce_attendance TO authenticated;

-- Verification (run after migration to confirm column-level restriction):
-- SET ROLE authenticated;
-- UPDATE public.daily_workforce_attendance SET total_workforce = 999 WHERE false;
-- Expected result: ERROR 42501 permission denied for column total_workforce
-- UPDATE public.daily_workforce_attendance SET site_id = gen_random_uuid() WHERE false;
-- Expected result: ERROR 42501 permission denied for column site_id

-- Server-enforced audit trigger: sets created_by from auth.uid() on INSERT; protects on UPDATE.
-- Enforces immutability of site_id and attendance_date, and protects total_workforce:
-- - On header INSERT: initializes total_workforce to zero (client-provided value is strictly ignored).
-- - On header UPDATE: validates site_id and attendance_date are unchanged; preserves total_workforce.
-- - The category-count trigger (sync_workforce_total) remains solely responsible for recalculating the total.
CREATE OR REPLACE FUNCTION public.set_workforce_attendance_audit_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := auth.uid();
    NEW.created_at := NOW();
    -- Directly initialize total_workforce to zero on insert; client values are ignored
    NEW.total_workforce := 0;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Immutability: Record identity, site_id, and attendance_date cannot be modified after insert
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

    -- Verify total_workforce modification authorization:
    -- Authenticated clients cannot set total_workforce directly (prevented by column-level grants).
    -- When recalculation occurs via the trusted sync_workforce_total trigger:
    -- 1. pg_trigger_depth() >= 2: must be called from within another trigger context
    -- 2. tsr.workforce_sync_token must contain an active one-time token
    IF NEW.total_workforce IS DISTINCT FROM OLD.total_workforce THEN
      IF pg_trigger_depth() >= 2 AND NULLIF(current_setting('tsr.workforce_sync_token', true), '') IS NOT NULL THEN
        -- Authorized trigger recalculation: consume token immediately to close bypass window
        PERFORM set_config('tsr.workforce_sync_token', '', true);
      ELSE
        -- Unauthorized client tampering: preserve database-managed total_workforce
        NEW.total_workforce := OLD.total_workforce;
      END IF;
    ELSE
      NEW.total_workforce := OLD.total_workforce;
    END IF;
  END IF;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_workforce_attendance_audit_fields ON public.daily_workforce_attendance;
CREATE TRIGGER trg_set_workforce_attendance_audit_fields
  BEFORE INSERT OR UPDATE ON public.daily_workforce_attendance
  FOR EACH ROW
  EXECUTE FUNCTION public.set_workforce_attendance_audit_fields();

-- Header Table RLS Policies:
-- SELECT: PM/Admin see all sites; active users see sites where they have access
DROP POLICY IF EXISTS "daily_workforce_attendance_select" ON public.daily_workforce_attendance;
CREATE POLICY "daily_workforce_attendance_select"
  ON public.daily_workforce_attendance FOR SELECT TO authenticated
  USING (
    public.is_pm_or_admin()
    OR (public.is_active_user() AND public.has_site_access(site_id))
  );

-- INSERT: Authorized users (PM/Admin for all sites; supervisors with active membership on target site)
DROP POLICY IF EXISTS "daily_workforce_attendance_insert" ON public.daily_workforce_attendance;
CREATE POLICY "daily_workforce_attendance_insert"
  ON public.daily_workforce_attendance FOR INSERT TO authenticated
  WITH CHECK (public.can_submit_workforce_attendance(site_id));

-- UPDATE: Authorized users (PM/Admin for all sites; supervisors with active membership on target site)
DROP POLICY IF EXISTS "daily_workforce_attendance_update" ON public.daily_workforce_attendance;
CREATE POLICY "daily_workforce_attendance_update"
  ON public.daily_workforce_attendance FOR UPDATE TO authenticated
  USING (public.can_submit_workforce_attendance(site_id))
  WITH CHECK (public.can_submit_workforce_attendance(site_id));

-- DELETE: Strictly Administrator
DROP POLICY IF EXISTS "daily_workforce_attendance_delete" ON public.daily_workforce_attendance;
CREATE POLICY "daily_workforce_attendance_delete"
  ON public.daily_workforce_attendance FOR DELETE TO authenticated
  USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Module A — Category Breakdown (public.daily_workforce_category_counts)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.daily_workforce_category_counts (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_id UUID NOT NULL,
  site_id       UUID NOT NULL,
  category      TEXT NOT NULL
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
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Composite Foreign Key strictly guarantees detail rows cannot reference a header from a different site
  CONSTRAINT fk_workforce_category_counts_header_site
    FOREIGN KEY (attendance_id, site_id)
    REFERENCES public.daily_workforce_attendance(id, site_id)
    ON DELETE CASCADE,
  -- Exactly one count per trade category per attendance submission
  CONSTRAINT daily_workforce_counts_attendance_category_uniq UNIQUE (attendance_id, category)
);

CREATE INDEX IF NOT EXISTS idx_daily_workforce_cat_attendance
  ON public.daily_workforce_category_counts (attendance_id);

CREATE INDEX IF NOT EXISTS idx_daily_workforce_cat_site
  ON public.daily_workforce_category_counts (site_id);

ALTER TABLE public.daily_workforce_category_counts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.daily_workforce_category_counts FROM anon, PUBLIC;
REVOKE ALL ON public.daily_workforce_category_counts FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.daily_workforce_category_counts TO authenticated;

DROP POLICY IF EXISTS "daily_workforce_category_counts_select" ON public.daily_workforce_category_counts;
CREATE POLICY "daily_workforce_category_counts_select"
  ON public.daily_workforce_category_counts FOR SELECT TO authenticated
  USING (
    public.is_pm_or_admin()
    OR (public.is_active_user() AND public.has_site_access(site_id))
  );

DROP POLICY IF EXISTS "daily_workforce_category_counts_insert" ON public.daily_workforce_category_counts;
CREATE POLICY "daily_workforce_category_counts_insert"
  ON public.daily_workforce_category_counts FOR INSERT TO authenticated
  WITH CHECK (public.can_submit_workforce_attendance(site_id));

DROP POLICY IF EXISTS "daily_workforce_category_counts_update" ON public.daily_workforce_category_counts;
CREATE POLICY "daily_workforce_category_counts_update"
  ON public.daily_workforce_category_counts FOR UPDATE TO authenticated
  USING (public.can_submit_workforce_attendance(site_id))
  WITH CHECK (public.can_submit_workforce_attendance(site_id));

DROP POLICY IF EXISTS "daily_workforce_category_counts_delete" ON public.daily_workforce_category_counts;
CREATE POLICY "daily_workforce_category_counts_delete"
  ON public.daily_workforce_category_counts FOR DELETE TO authenticated
  USING (public.is_admin());

-- Automated total calculation on daily_workforce_attendance header.
-- Recalculates both OLD and NEW attendance headers if attendance_id changes on UPDATE.
-- Uses narrowly scoped one-time token (tsr.workforce_sync_token) restored immediately per statement.
CREATE OR REPLACE FUNCTION public.sync_workforce_total()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_sync_token TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_sync_token := gen_random_uuid()::text;
    PERFORM set_config('tsr.workforce_sync_token', v_sync_token, true);

    UPDATE public.daily_workforce_attendance
    SET total_workforce = COALESCE((
      SELECT SUM(count) FROM public.daily_workforce_category_counts
      WHERE attendance_id = OLD.attendance_id
    ), 0),
    updated_at = NOW()
    WHERE id = OLD.attendance_id;

    -- Immediately restore/clear token
    PERFORM set_config('tsr.workforce_sync_token', '', true);

  ELSIF TG_OP = 'INSERT' THEN
    v_sync_token := gen_random_uuid()::text;
    PERFORM set_config('tsr.workforce_sync_token', v_sync_token, true);

    UPDATE public.daily_workforce_attendance
    SET total_workforce = COALESCE((
      SELECT SUM(count) FROM public.daily_workforce_category_counts
      WHERE attendance_id = NEW.attendance_id
    ), 0),
    updated_at = NOW()
    WHERE id = NEW.attendance_id;

    -- Immediately restore/clear token
    PERFORM set_config('tsr.workforce_sync_token', '', true);

  ELSIF TG_OP = 'UPDATE' THEN
    -- Recalculate target (NEW) attendance header
    v_sync_token := gen_random_uuid()::text;
    PERFORM set_config('tsr.workforce_sync_token', v_sync_token, true);

    UPDATE public.daily_workforce_attendance
    SET total_workforce = COALESCE((
      SELECT SUM(count) FROM public.daily_workforce_category_counts
      WHERE attendance_id = NEW.attendance_id
    ), 0),
    updated_at = NOW()
    WHERE id = NEW.attendance_id;

    -- Immediately restore/clear token
    PERFORM set_config('tsr.workforce_sync_token', '', true);

    -- If attendance_id was modified, also recalculate previous (OLD) attendance header
    IF OLD.attendance_id IS DISTINCT FROM NEW.attendance_id THEN
      v_sync_token := gen_random_uuid()::text;
      PERFORM set_config('tsr.workforce_sync_token', v_sync_token, true);

      UPDATE public.daily_workforce_attendance
      SET total_workforce = COALESCE((
        SELECT SUM(count) FROM public.daily_workforce_category_counts
        WHERE attendance_id = OLD.attendance_id
      ), 0),
      updated_at = NOW()
      WHERE id = OLD.attendance_id;

      -- Immediately restore/clear token
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

-- Reliable updated_at handling for category count updates
CREATE OR REPLACE FUNCTION public.set_category_counts_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_category_counts_updated_at ON public.daily_workforce_category_counts;
CREATE TRIGGER trg_set_category_counts_updated_at
  BEFORE UPDATE ON public.daily_workforce_category_counts
  FOR EACH ROW
  EXECUTE FUNCTION public.set_category_counts_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: Module B — Supervisor Personal Attendance (public.supervisor_attendance)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.supervisor_attendance (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supervisor_id   UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
  site_id         UUID NOT NULL REFERENCES public.sites(id) ON DELETE CASCADE,
  attendance_date DATE NOT NULL DEFAULT CURRENT_DATE,
  status          TEXT NOT NULL CHECK (status IN ('Present', 'Absent', 'Half Day', 'Leave')),
  remarks         TEXT,
  -- recorded_by: represents the original recorder who initially created and logged
  -- this attendance submission. Immutable on update.
  recorded_by     UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Exactly one personal attendance record per supervisor per calendar date across all sites
  CONSTRAINT supervisor_attendance_supervisor_date_uniq UNIQUE (supervisor_id, attendance_date)
);

CREATE INDEX IF NOT EXISTS idx_supervisor_attendance_site_date
  ON public.supervisor_attendance (site_id, attendance_date);

CREATE INDEX IF NOT EXISTS idx_supervisor_attendance_supervisor_date
  ON public.supervisor_attendance (supervisor_id, attendance_date);

ALTER TABLE public.supervisor_attendance ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.supervisor_attendance FROM anon, PUBLIC;
REVOKE ALL ON public.supervisor_attendance FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.supervisor_attendance TO authenticated;

-- Policies for supervisor_attendance:
-- 1. SELECT: PM/Admin can read all records; supervisors can read ONLY their own records
DROP POLICY IF EXISTS "supervisor_attendance_active_select" ON public.supervisor_attendance;
CREATE POLICY "supervisor_attendance_active_select"
  ON public.supervisor_attendance FOR SELECT TO authenticated
  USING (
    public.is_pm_or_admin()
    OR (
      public.is_active_user()
      AND supervisor_id = auth.uid()
    )
  );

-- 2. INSERT: Only PM or Admin; strictly prohibited from self-marking
DROP POLICY IF EXISTS "supervisor_attendance_pm_admin_insert" ON public.supervisor_attendance;
CREATE POLICY "supervisor_attendance_pm_admin_insert"
  ON public.supervisor_attendance FOR INSERT TO authenticated
  WITH CHECK (
    public.is_pm_or_admin()
    AND (auth.uid() IS NULL OR auth.uid() != supervisor_id)
  );

-- 3. UPDATE: Only PM or Admin; strictly prohibited from self-marking
DROP POLICY IF EXISTS "supervisor_attendance_pm_admin_update" ON public.supervisor_attendance;
CREATE POLICY "supervisor_attendance_pm_admin_update"
  ON public.supervisor_attendance FOR UPDATE TO authenticated
  USING (
    public.is_pm_or_admin()
    AND (auth.uid() IS NULL OR auth.uid() != supervisor_id)
  )
  WITH CHECK (
    public.is_pm_or_admin()
    AND (auth.uid() IS NULL OR auth.uid() != supervisor_id)
  );

-- 4. DELETE: Strictly Administrator
DROP POLICY IF EXISTS "supervisor_attendance_admin_delete" ON public.supervisor_attendance;
CREATE POLICY "supervisor_attendance_admin_delete"
  ON public.supervisor_attendance FOR DELETE TO authenticated
  USING (public.is_admin());

-- Server-enforced audit & validation trigger for supervisor_attendance:
-- - Sets recorded_by from auth.uid() on INSERT (original recorder, immutable on UPDATE)
-- - Blocks self-marking
-- - Strictly verifies target user is an active supervisor
-- - Strictly verifies an active site_memberships record (sm.is_active = TRUE) exists for the site
CREATE OR REPLACE FUNCTION public.validate_and_audit_supervisor_attendance()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_role TEXT;
  v_status TEXT;
BEGIN
  -- 1. Server-enforce recorded_by: represents the original recorder who initially
  -- logged the supervisor attendance record. It is immutable once created.
  IF TG_OP = 'INSERT' THEN
    NEW.recorded_by := auth.uid();
    NEW.created_at  := NOW();
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.recorded_by := OLD.recorded_by;
    NEW.created_at  := OLD.created_at;
  END IF;

  -- 2. Prevent self-marking: Supervisors are barred from recording or editing their own attendance
  IF auth.uid() IS NOT NULL AND auth.uid() = NEW.supervisor_id THEN
    RAISE EXCEPTION 'Supervisors are prohibited from recording or editing their own personal attendance.';
  END IF;

  -- 3. Verify target user exists, is active, and has role "supervisor"
  SELECT role, status INTO v_role, v_status
  FROM public.user_profiles
  WHERE id = NEW.supervisor_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target supervisor ID % does not exist in user_profiles.', NEW.supervisor_id;
  END IF;

  IF v_status != 'active' THEN
    RAISE EXCEPTION 'Cannot record attendance for a disabled user account.';
  END IF;

  IF v_role != 'supervisor' THEN
    RAISE EXCEPTION 'Target user must have role "supervisor". Current role: %', v_role;
  END IF;

  -- 4. Mandatory Active Site Membership: Require sm.is_active = TRUE in site_memberships.
  -- Validation is NEVER skipped.
  IF NOT EXISTS (
    SELECT 1 FROM public.site_memberships sm
    WHERE sm.site_id = NEW.site_id
      AND sm.user_id = NEW.supervisor_id
      AND sm.is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Supervisor % is not an active assigned member (sm.is_active = TRUE) of site % in site_memberships.',
      NEW.supervisor_id, NEW.site_id;
  END IF;

  NEW.updated_at := NOW();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_and_audit_supervisor_attendance ON public.supervisor_attendance;
CREATE TRIGGER trg_validate_and_audit_supervisor_attendance
  BEFORE INSERT OR UPDATE ON public.supervisor_attendance
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_and_audit_supervisor_attendance();

COMMIT;
