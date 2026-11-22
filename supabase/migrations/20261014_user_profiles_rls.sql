-- ==============================================================================
-- TSR Site Manager Pro — Database Migration & RLS Security Script
-- File: supabase/migrations/20261014_user_profiles_rls.sql
-- ==============================================================================
-- Instructions: Run this script in the Supabase Dashboard SQL Editor.
-- It establishes trusted server-side authorization, pins search paths, and prevents RLS recursion.
-- ==============================================================================

-- 1. Create a SECURITY DEFINER helper function to safely verify if the caller is an active administrator.
--    This prevents the PostgreSQL "infinite recursion detected in policy" error.
--    Explicitly pins search_path to 'public, auth' to safely resolve public tables and auth functions.
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

-- Revoke execute from unauthenticated public role and anon, grant strictly to authenticated users
REVOKE ALL ON FUNCTION public.is_admin() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- 2. Ensure RLS is enabled on user_profiles
ALTER TABLE IF EXISTS public.user_profiles ENABLE ROW LEVEL SECURITY;

-- 3. Base SQL Privileges (Table-level permissions)
-- RLS filters rows, but the database role must first possess table-level SELECT privilege.
REVOKE ALL ON public.user_profiles FROM anon, public;
GRANT SELECT ON public.user_profiles TO authenticated;

-- 4. Drop existing policies if they conflict
DROP POLICY IF EXISTS "user_profiles_self_read" ON public.user_profiles;
DROP POLICY IF EXISTS "user_profiles_admin_read" ON public.user_profiles;
DROP POLICY IF EXISTS "user_profiles_self_update" ON public.user_profiles;
DROP POLICY IF EXISTS "user_profiles_insert_deny" ON public.user_profiles;
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can read own profile" ON public.user_profiles;

-- 5. Policy: Authenticated users can view their own profile
CREATE POLICY "user_profiles_self_read"
  ON public.user_profiles
  FOR SELECT
  TO authenticated
  USING (id = auth.uid());

-- 6. Policy: Active Administrators can view all user profiles
CREATE POLICY "user_profiles_admin_read"
  ON public.user_profiles
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

-- Note: NO client INSERT, UPDATE, or DELETE policies are granted to 'authenticated'.
-- All user modifications and role assignments MUST be performed via the server-side
-- Edge Function 'admin-manage-user' running with the service_role key.
-- This guarantees users cannot self-promote, alter roles, or bypass status checks.

-- 7. Performance Index for role lookups
CREATE INDEX IF NOT EXISTS idx_user_profiles_role_status
  ON public.user_profiles (role, status);
