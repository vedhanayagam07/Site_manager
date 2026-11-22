-- ==============================================================================
-- TSR Site Manager Pro — Business Tables RLS Security Script
-- File: supabase/migrations/20261014_business_tables_rls.sql
-- ==============================================================================
-- Instructions: Run this script in the Supabase Dashboard SQL Editor.
-- It ensures that anonymous/public internet callers cannot read or manipulate
-- sensitive construction, worker, payroll, material, or audit data.
-- ==============================================================================

-- 1. Helper function: verify caller is an active authenticated user
--    Pinned search_path prevents search path hijacking.
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

REVOKE ALL ON FUNCTION public.is_active_user() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.is_active_user() TO authenticated;

-- Helper function: verify caller is an active Project Manager or Administrator
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

REVOKE ALL ON FUNCTION public.is_pm_or_admin() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.is_pm_or_admin() TO authenticated;

-- Ensure activity_logs table exists before attaching policies
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

-- Ensure loading_memos table exists before attaching policies
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Base SQL Table Grants
-- ─────────────────────────────────────────────────────────────────────────────
-- Revoke all direct and inherited privileges from 'anon' and 'public'
REVOKE ALL ON public.sites, public.workers, public.materials,
  public.material_transactions, public.site_attendance,
  public.loading_memos, public.activity_logs FROM anon, public;

-- Revoke all from authenticated as clean baseline
REVOKE ALL ON public.sites, public.workers, public.materials,
  public.material_transactions, public.site_attendance,
  public.loading_memos, public.activity_logs FROM authenticated;

-- Grant minimal necessary SQL privileges to 'authenticated'
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sites TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.workers TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.materials TO authenticated;
GRANT SELECT, INSERT ON public.material_transactions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.site_attendance TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.loading_memos TO authenticated;
GRANT SELECT, INSERT ON public.activity_logs TO authenticated;

-- Dynamically drop all pre-existing policies on business tables so broad/permissive policies cannot leak
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('sites', 'workers', 'materials', 'material_transactions', 'site_attendance', 'loading_memos', 'activity_logs')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I;', pol.policyname, pol.schemaname, pol.tablename);
  END LOOP;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. SITES TABLE
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.sites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sites_authenticated_select" ON public.sites;
DROP POLICY IF EXISTS "sites_authenticated_insert" ON public.sites;
DROP POLICY IF EXISTS "sites_authenticated_update" ON public.sites;
DROP POLICY IF EXISTS "sites_admin_delete" ON public.sites;

CREATE POLICY "sites_authenticated_select"
  ON public.sites FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "sites_authenticated_insert"
  ON public.sites FOR INSERT TO authenticated
  WITH CHECK (public.is_pm_or_admin());

CREATE POLICY "sites_authenticated_update"
  ON public.sites FOR UPDATE TO authenticated
  USING (public.is_pm_or_admin())
  WITH CHECK (public.is_pm_or_admin());

CREATE POLICY "sites_admin_delete"
  ON public.sites FOR DELETE TO authenticated
  USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. WORKERS TABLE (Contains phone numbers, roles, site assignments)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.workers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "workers_authenticated_select" ON public.workers;
DROP POLICY IF EXISTS "workers_authenticated_insert" ON public.workers;
DROP POLICY IF EXISTS "workers_authenticated_update" ON public.workers;
DROP POLICY IF EXISTS "workers_admin_delete" ON public.workers;

CREATE POLICY "workers_authenticated_select"
  ON public.workers FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "workers_authenticated_insert"
  ON public.workers FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user());

CREATE POLICY "workers_authenticated_update"
  ON public.workers FOR UPDATE TO authenticated
  USING (public.is_active_user())
  WITH CHECK (public.is_active_user());

CREATE POLICY "workers_admin_delete"
  ON public.workers FOR DELETE TO authenticated
  USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. MATERIALS & TRANSACTIONS TABLES
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.material_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "materials_authenticated_all" ON public.materials;
DROP POLICY IF EXISTS "materials_authenticated_select" ON public.materials;
DROP POLICY IF EXISTS "materials_authenticated_insert" ON public.materials;
DROP POLICY IF EXISTS "materials_authenticated_update" ON public.materials;
DROP POLICY IF EXISTS "materials_admin_delete" ON public.materials;

DROP POLICY IF EXISTS "material_transactions_authenticated_all" ON public.material_transactions;
DROP POLICY IF EXISTS "material_transactions_authenticated_select" ON public.material_transactions;
DROP POLICY IF EXISTS "material_transactions_authenticated_insert" ON public.material_transactions;
DROP POLICY IF EXISTS "material_transactions_admin_delete" ON public.material_transactions;

-- Materials: Active users can view and log inventory; only admins can delete material records
CREATE POLICY "materials_authenticated_select"
  ON public.materials FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "materials_authenticated_insert"
  ON public.materials FOR INSERT TO authenticated
  WITH CHECK (public.is_pm_or_admin());

CREATE POLICY "materials_authenticated_update"
  ON public.materials FOR UPDATE TO authenticated
  USING (public.is_active_user())
  WITH CHECK (public.is_active_user());

CREATE POLICY "materials_admin_delete"
  ON public.materials FOR DELETE TO authenticated
  USING (public.is_admin());

-- Material Transactions: Strictly append-only ledger; client updates and deletes are permanently denied
CREATE POLICY "material_transactions_authenticated_select"
  ON public.material_transactions FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "material_transactions_authenticated_insert"
  ON public.material_transactions FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user());

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. SITE ATTENDANCE TABLE
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.site_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "site_attendance_authenticated_all" ON public.site_attendance;
DROP POLICY IF EXISTS "site_attendance_authenticated_select" ON public.site_attendance;
DROP POLICY IF EXISTS "site_attendance_authenticated_insert" ON public.site_attendance;
DROP POLICY IF EXISTS "site_attendance_authenticated_update" ON public.site_attendance;
DROP POLICY IF EXISTS "site_attendance_admin_delete" ON public.site_attendance;

CREATE POLICY "site_attendance_authenticated_select"
  ON public.site_attendance FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "site_attendance_authenticated_insert"
  ON public.site_attendance FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user());

CREATE POLICY "site_attendance_authenticated_update"
  ON public.site_attendance FOR UPDATE TO authenticated
  USING (public.is_active_user())
  WITH CHECK (public.is_active_user());

CREATE POLICY "site_attendance_admin_delete"
  ON public.site_attendance FOR DELETE TO authenticated
  USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. LOADING MEMOS TABLE
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.loading_memos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "loading_memos_authenticated_select" ON public.loading_memos;
DROP POLICY IF EXISTS "loading_memos_authenticated_insert" ON public.loading_memos;
DROP POLICY IF EXISTS "loading_memos_admin_delete" ON public.loading_memos;

CREATE POLICY "loading_memos_authenticated_select"
  ON public.loading_memos FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "loading_memos_authenticated_insert"
  ON public.loading_memos FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user());

-- Destructive deletion of loading memos restricted to active administrators
CREATE POLICY "loading_memos_admin_delete"
  ON public.loading_memos FOR DELETE TO authenticated
  USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. ACTIVITY LOGS TABLE (Tamper-evident Audit Trail)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.activity_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "activity_logs_authenticated_select" ON public.activity_logs;
DROP POLICY IF EXISTS "activity_logs_admin_select" ON public.activity_logs;
DROP POLICY IF EXISTS "activity_logs_authenticated_insert" ON public.activity_logs;
DROP POLICY IF EXISTS "activity_logs_no_update" ON public.activity_logs;
DROP POLICY IF EXISTS "activity_logs_admin_delete" ON public.activity_logs;

-- Audit logs are viewable only by active administrators
CREATE POLICY "activity_logs_admin_select"
  ON public.activity_logs FOR SELECT TO authenticated
  USING (public.is_admin());

-- All active users can append audit logs
CREATE POLICY "activity_logs_authenticated_insert"
  ON public.activity_logs FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user());

-- Tamper-Evident Audit Trail: Updates and deletes are permanently denied for all client roles
