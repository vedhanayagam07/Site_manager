-- ==============================================================================
-- TSR Site Manager Pro — Consolidated Security Forward-Fix Migration (Revised)
-- File: supabase/migrations/20261014_consolidated_security_forward_fix.sql
-- ==============================================================================
-- RECONCILED SECURITY & ARCHITECTURAL SPECIFICATION:
-- 1. Eliminates anonymous and PUBLIC inherited access to business data and profiles.
-- 2. Dynamically purges all pre-existing permissive/broad policies across all 8 tables.
-- 3. Differentiates Project Managers and Administrators from Supervisors:
--    - Sites (INSERT/UPDATE) restricted to Project Managers & Admins.
--    - Master Materials Catalog (INSERT) restricted to Project Managers & Admins.
--    - Supervisors retain full operational access to mark attendance, record
--      stock usage transactions, and generate transit loading memos.
-- 4. True Ledger & Audit Trail Immutability:
--    - 'material_transactions' and 'activity_logs' are strictly append-only.
--    - Client DELETE and UPDATE are permanently withheld from ALL roles (including admins).
-- 5. Destructive operations on business entities ('sites', 'workers', 'materials',
--    'site_attendance', 'loading_memos') restricted strictly to active administrators.
-- 6. Profile mutations locked out from client; managed via service-role Edge Function.
-- 7. Defensive index creation: checks column existence in catalog before indexing.
-- ==============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Preflight Checks & Dependent Schema Initialization
-- ─────────────────────────────────────────────────────────────────────────────

-- Ensure loading_memos table exists with required schema
CREATE TABLE IF NOT EXISTS public.loading_memos (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date           DATE NOT NULL DEFAULT CURRENT_DATE,
  vehicle_number TEXT NOT NULL,
  material_id    TEXT,
  material_name  TEXT NOT NULL,
  quantity       NUMERIC NOT NULL,
  unit           TEXT NOT NULL DEFAULT 'Bags',
  remarks        TEXT,
  generated_by   TEXT NOT NULL,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

-- Verify and self-heal columns if table pre-existed with partial definition
ALTER TABLE public.loading_memos ADD COLUMN IF NOT EXISTS date DATE DEFAULT CURRENT_DATE;
ALTER TABLE public.loading_memos ADD COLUMN IF NOT EXISTS vehicle_number TEXT;
ALTER TABLE public.loading_memos ADD COLUMN IF NOT EXISTS material_id TEXT;
ALTER TABLE public.loading_memos ADD COLUMN IF NOT EXISTS material_name TEXT;
ALTER TABLE public.loading_memos ADD COLUMN IF NOT EXISTS quantity NUMERIC;
ALTER TABLE public.loading_memos ADD COLUMN IF NOT EXISTS unit TEXT DEFAULT 'Bags';
ALTER TABLE public.loading_memos ADD COLUMN IF NOT EXISTS remarks TEXT;
ALTER TABLE public.loading_memos ADD COLUMN IF NOT EXISTS generated_by TEXT;
ALTER TABLE public.loading_memos ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- Ensure activity_logs table exists with required schema
CREATE TABLE IF NOT EXISTS public.activity_logs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     TEXT,
  user_name   TEXT,
  role        TEXT,
  action      TEXT NOT NULL,
  module      TEXT NOT NULL,
  old_value   TEXT,
  new_value   TEXT,
  description TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Verify and self-heal columns if table pre-existed with partial definition
ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS user_id TEXT;
ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS user_name TEXT;
ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS role TEXT;
ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS action TEXT;
ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS module TEXT;
ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS old_value TEXT;
ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS new_value TEXT;
ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- Type compatibility: convert user_id to TEXT if pre-existing table defined it as UUID
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'activity_logs'
      AND column_name = 'user_id' AND data_type = 'uuid'
  ) THEN
    ALTER TABLE public.activity_logs ALTER COLUMN user_id TYPE TEXT USING user_id::TEXT;
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Trusted Helper Functions (SECURITY DEFINER with Pinned Search Path)
-- ─────────────────────────────────────────────────────────────────────────────

-- Helper 1: Verify caller is an active administrator
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles
    WHERE id = auth.uid()
      AND role = 'admin'
      AND status = 'active'
  );
$$;

-- Helper 2: Verify caller is an active Project Manager or Administrator
CREATE OR REPLACE FUNCTION public.is_pm_or_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles
    WHERE id = auth.uid()
      AND role IN ('admin', 'projectManager')
      AND status = 'active'
  );
$$;

-- Helper 3: Verify caller is any active authenticated staff member
CREATE OR REPLACE FUNCTION public.is_active_user()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles
    WHERE id = auth.uid()
      AND status = 'active'
  );
$$;

-- Revoke execute from unauthenticated roles and pseudo-role PUBLIC
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

REVOKE ALL ON FUNCTION public.is_pm_or_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_pm_or_admin() TO authenticated;

REVOKE ALL ON FUNCTION public.is_active_user() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_active_user() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Purge ALL Pre-Existing Policies (Prevents Boolean OR Policy Leaks)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN (
        'user_profiles',
        'sites',
        'workers',
        'materials',
        'material_transactions',
        'site_attendance',
        'loading_memos',
        'activity_logs'
      )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I;', pol.policyname, pol.schemaname, pol.tablename);
  END LOOP;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: Ensure Row Level Security is Enabled on All 8 Tables
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.material_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loading_memos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: Base SQL Table Grants (Direct Grants & Public Revocations)
-- ─────────────────────────────────────────────────────────────────────────────
-- Revoke all direct and inherited privileges from 'anon' and the pseudo-role 'PUBLIC'
REVOKE ALL ON public.user_profiles, public.sites, public.workers,
  public.materials, public.material_transactions, public.site_attendance,
  public.loading_memos, public.activity_logs FROM anon, PUBLIC;

-- Revoke all from authenticated as clean baseline
REVOKE ALL ON public.user_profiles, public.sites, public.workers,
  public.materials, public.material_transactions, public.site_attendance,
  public.loading_memos, public.activity_logs FROM authenticated;

-- Table-specific minimal grants for 'authenticated':
-- 1. user_profiles: Read-only. Mutations strictly via Edge Function (service_role).
GRANT SELECT ON public.user_profiles TO authenticated;

-- 2. sites & workers: Standard operations CRUD.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sites TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.workers TO authenticated;

-- 3. materials: Inventory management.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.materials TO authenticated;

-- 4. material_transactions: Strictly append-only ledger. UPDATE and DELETE withheld from all clients.
GRANT SELECT, INSERT ON public.material_transactions TO authenticated;

-- 5. site_attendance: Daily attendance marking requires SELECT, INSERT, UPDATE (.upsert).
GRANT SELECT, INSERT, UPDATE, DELETE ON public.site_attendance TO authenticated;

-- 6. loading_memos: Transit dispatch memos. UPDATE withheld.
GRANT SELECT, INSERT, DELETE ON public.loading_memos TO authenticated;

-- 7. activity_logs: Tamper-evident audit trail. UPDATE and DELETE withheld from all clients.
GRANT SELECT, INSERT ON public.activity_logs TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 6: Target RLS Policies by Table
-- ─────────────────────────────────────────────────────────────────────────────

-- =============================================================================
-- TABLE 1: user_profiles
-- =============================================================================
CREATE POLICY "user_profiles_self_read"
  ON public.user_profiles FOR SELECT TO authenticated
  USING (id = auth.uid());

CREATE POLICY "user_profiles_admin_read"
  ON public.user_profiles FOR SELECT TO authenticated
  USING (public.is_admin());

-- =============================================================================
-- TABLE 2: sites (Role Differentiated: PM/Admin Manage; Staff View)
-- =============================================================================
CREATE POLICY "sites_active_user_select"
  ON public.sites FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "sites_pm_or_admin_insert"
  ON public.sites FOR INSERT TO authenticated
  WITH CHECK (public.is_pm_or_admin());

CREATE POLICY "sites_pm_or_admin_update"
  ON public.sites FOR UPDATE TO authenticated
  USING (public.is_pm_or_admin())
  WITH CHECK (public.is_pm_or_admin());

CREATE POLICY "sites_admin_delete"
  ON public.sites FOR DELETE TO authenticated
  USING (public.is_admin());

-- =============================================================================
-- TABLE 3: workers
-- =============================================================================
CREATE POLICY "workers_active_user_select"
  ON public.workers FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "workers_active_user_insert"
  ON public.workers FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user());

CREATE POLICY "workers_active_user_update"
  ON public.workers FOR UPDATE TO authenticated
  USING (public.is_active_user())
  WITH CHECK (public.is_active_user());

CREATE POLICY "workers_admin_delete"
  ON public.workers FOR DELETE TO authenticated
  USING (public.is_admin());

-- =============================================================================
-- TABLE 4: materials (Role Differentiated: Catalog Addition vs Stock Sync)
-- =============================================================================
CREATE POLICY "materials_active_user_select"
  ON public.materials FOR SELECT TO authenticated
  USING (public.is_active_user());

-- Adding a new master product catalog item is restricted to PM and Admin
CREATE POLICY "materials_pm_or_admin_insert"
  ON public.materials FOR INSERT TO authenticated
  WITH CHECK (public.is_pm_or_admin());

-- Updating material balances (e.g. usage sync) is permitted for active operational staff
CREATE POLICY "materials_active_user_update"
  ON public.materials FOR UPDATE TO authenticated
  USING (public.is_active_user())
  WITH CHECK (public.is_active_user());

CREATE POLICY "materials_admin_delete"
  ON public.materials FOR DELETE TO authenticated
  USING (public.is_admin());

-- =============================================================================
-- TABLE 5: material_transactions (Strictly Append-Only Ledger)
-- =============================================================================
CREATE POLICY "material_transactions_active_user_select"
  ON public.material_transactions FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "material_transactions_active_user_insert"
  ON public.material_transactions FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user());

-- Reconciled Ledger Immutability:
-- NO client UPDATE policy.
-- NO client DELETE policy (even for administrators).
-- Accounting records cannot be altered or removed once logged.

-- =============================================================================
-- TABLE 6: site_attendance
-- =============================================================================
CREATE POLICY "site_attendance_active_user_select"
  ON public.site_attendance FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "site_attendance_active_user_insert"
  ON public.site_attendance FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user());

CREATE POLICY "site_attendance_active_user_update"
  ON public.site_attendance FOR UPDATE TO authenticated
  USING (public.is_active_user())
  WITH CHECK (public.is_active_user());

CREATE POLICY "site_attendance_admin_delete"
  ON public.site_attendance FOR DELETE TO authenticated
  USING (public.is_admin());

-- =============================================================================
-- TABLE 7: loading_memos
-- =============================================================================
CREATE POLICY "loading_memos_active_user_select"
  ON public.loading_memos FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "loading_memos_active_user_insert"
  ON public.loading_memos FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user());

-- Dispatch Immutability: NO UPDATE policy.

CREATE POLICY "loading_memos_admin_delete"
  ON public.loading_memos FOR DELETE TO authenticated
  USING (public.is_admin());

-- =============================================================================
-- TABLE 8: activity_logs (Strictly Append-Only Audit Trail)
-- =============================================================================
-- Only administrators may view audit logs
CREATE POLICY "activity_logs_admin_select"
  ON public.activity_logs FOR SELECT TO authenticated
  USING (public.is_admin());

-- All active staff members write audit log entries
CREATE POLICY "activity_logs_active_user_insert"
  ON public.activity_logs FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user());

-- Reconciled Tamper-Evident Integrity:
-- NO client UPDATE policy.
-- NO client DELETE policy (even for administrators).
-- Audit logs cannot be pruned or modified by any client session.

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 7: Defensive Performance Indexes (Guarded Against Missing Columns)
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  -- 1. Index on user_profiles (role, status)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'role'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'status'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_user_profiles_role_status
      ON public.user_profiles (role, status);
  END IF;

  -- 2. Index on site_attendance (site_id, attendance_date)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'site_attendance' AND column_name = 'site_id'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'site_attendance' AND column_name = 'attendance_date'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_site_attendance_site_date
      ON public.site_attendance (site_id, attendance_date);
  END IF;

  -- 3. Index on material_transactions (material_id)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'material_transactions' AND column_name = 'material_id'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_material_transactions_mat_id
      ON public.material_transactions (material_id);
  END IF;

  -- 4. Index on loading_memos (date)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'loading_memos' AND column_name = 'date'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_loading_memos_date
      ON public.loading_memos (date);
  END IF;
END;
$$;

COMMIT;
