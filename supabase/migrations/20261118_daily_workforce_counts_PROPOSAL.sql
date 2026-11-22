-- ==============================================================================
-- TSR BUILDERS — PROPOSED ADDITIVE MIGRATION (ON HOLD — DO NOT EXECUTE YET)
-- File: supabase/migrations/20261118_daily_workforce_counts_PROPOSAL.sql
-- ==============================================================================
-- STATUS: HOLD FOR SECURITY RECONCILIATION
-- Before executing, verify whether the live database enforces site-scoped helpers
-- (e.g., public.has_site_access(site_id) / public.can_manage_site(site_id)).
-- If site-scoped helpers exist in production, replace public.is_active_user()
-- below with public.has_site_access(site_id) so this table never weakens site
-- isolation!
-- ==============================================================================
-- PURPOSE:
-- Supports daily temporary labourer attendance by trade category headcount
-- (e.g., Masons: 3, Helpers: 5, Carpenters: 2, Electricians: 1) without requiring
-- permanent named records in public.workers.
--
-- SAFETY GUARANTEES:
-- 1. Purely additive: does NOT alter public.site_attendance, public.workers, or
--    any existing table, column, policy, or historical record.
-- 2. Preserves existing named-worker and supervisor attendance in site_attendance.
-- 3. Mirrors the exact security model established in
--    20261014_consolidated_security_forward_fix.sql:
--    - RLS enabled
--    - Zero anon or PUBLIC privileges
--    - Active authenticated staff can SELECT, INSERT, UPDATE
--    - Only active administrators can DELETE
--
-- DO NOT RUN ON PRODUCTION WITHOUT REVIEW AND STAGING VERIFICATION.
-- ==============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.daily_workforce_counts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id         UUID NOT NULL REFERENCES public.sites(id) ON DELETE CASCADE,
  attendance_date DATE NOT NULL DEFAULT CURRENT_DATE,
  category        TEXT NOT NULL,
  count           INTEGER NOT NULL CHECK (count >= 0),
  notes           TEXT,
  recorded_by     UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT daily_workforce_counts_site_date_category_uniq
    UNIQUE (site_id, attendance_date, category)
);

CREATE INDEX IF NOT EXISTS idx_daily_workforce_counts_site_date
  ON public.daily_workforce_counts (site_id, attendance_date);

ALTER TABLE public.daily_workforce_counts ENABLE ROW LEVEL SECURITY;

-- Revoke all direct and inherited privileges from anon and PUBLIC
REVOKE ALL ON public.daily_workforce_counts FROM anon, PUBLIC;
REVOKE ALL ON public.daily_workforce_counts FROM authenticated;

-- Grant minimal client privileges to authenticated
GRANT SELECT, INSERT, UPDATE, DELETE ON public.daily_workforce_counts TO authenticated;

-- Clean slate policies
DROP POLICY IF EXISTS "daily_workforce_counts_active_user_select" ON public.daily_workforce_counts;
DROP POLICY IF EXISTS "daily_workforce_counts_active_user_insert" ON public.daily_workforce_counts;
DROP POLICY IF EXISTS "daily_workforce_counts_active_user_update" ON public.daily_workforce_counts;
DROP POLICY IF EXISTS "daily_workforce_counts_admin_delete" ON public.daily_workforce_counts;

CREATE POLICY "daily_workforce_counts_active_user_select"
  ON public.daily_workforce_counts FOR SELECT TO authenticated
  USING (public.is_active_user());

CREATE POLICY "daily_workforce_counts_active_user_insert"
  ON public.daily_workforce_counts FOR INSERT TO authenticated
  WITH CHECK (public.is_active_user());

CREATE POLICY "daily_workforce_counts_active_user_update"
  ON public.daily_workforce_counts FOR UPDATE TO authenticated
  USING (public.is_active_user())
  WITH CHECK (public.is_active_user());

CREATE POLICY "daily_workforce_counts_admin_delete"
  ON public.daily_workforce_counts FOR DELETE TO authenticated
  USING (public.is_admin());

COMMIT;

