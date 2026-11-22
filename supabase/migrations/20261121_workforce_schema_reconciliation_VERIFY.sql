-- ==============================================================================
-- TSR BUILDERS — POST-MIGRATION VERIFICATION (READ-ONLY)
-- File: supabase/migrations/20261121_workforce_schema_reconciliation_VERIFY.sql
-- ==============================================================================
-- Run AFTER 20261121_workforce_schema_reconciliation.sql commits successfully.
-- Every statement is strictly SELECT-only. No schema or data is modified.
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 1: Column inventory for all three target tables
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  table_name,
  ordinal_position,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
    'daily_workforce_attendance',
    'daily_workforce_category_counts',
    'supervisor_attendance'
  )
ORDER BY table_name, ordinal_position;
-- Expected columns:
-- daily_workforce_attendance: id, site_id, attendance_date, remarks,
--   total_workforce (NOT NULL DEFAULT 0), created_by, created_at, updated_at.
-- daily_workforce_category_counts: id, attendance_id, site_id, category,
--   count (NOT NULL DEFAULT 0), created_at, updated_at.
-- supervisor_attendance: id, supervisor_id (NOT supervisor_user_id), site_id,
--   attendance_date, status, remarks, recorded_by (NOT NULL), created_at, updated_at.

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 2: Explicit Row-Level Security (RLS) Verification
-- Verifies that RLS is actively enabled on all three tables.
-- Expected: 3 rows, all showing rls_status = 'ENABLED ✓'.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  c.relname AS table_name,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_forced,
  CASE
    WHEN c.relrowsecurity THEN 'ENABLED ✓'
    ELSE 'DISABLED ⚠ (CRITICAL SECURITY FAILURE)'
  END AS rls_status
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
    'daily_workforce_attendance',
    'daily_workforce_category_counts',
    'supervisor_attendance'
  )
ORDER BY c.relname;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 3: Detailed Constraint Verification
-- Validates:
--   - Exact constraint name & type ('u' = UNIQUE, 'f' = FOREIGN KEY)
--   - Exact constrained columns in ordered sequence
--   - Referenced table and referenced columns (for FKs via confrelid and confkey)
--   - Delete behavior ('r' = RESTRICT, 'c' = CASCADE)
--   - Full SQL constraint definition
-- Expected: All rows show status = 'EXISTS ✓' with matching columns and behaviors.
-- ─────────────────────────────────────────────────────────────────────────────
WITH required_constraints (
  table_name,
  constraint_name,
  expected_type,
  expected_columns,
  expected_ref_table,
  expected_ref_columns,
  expected_del_action
) AS (
  VALUES
    (
      'daily_workforce_attendance',
      'daily_workforce_attendance_site_date_uniq',
      'u',
      'site_id, attendance_date',
      NULL,
      NULL,
      NULL
    ),
    (
      'daily_workforce_attendance',
      'daily_workforce_attendance_id_site_uniq',
      'u',
      'id, site_id',
      NULL,
      NULL,
      NULL
    ),
    (
      'daily_workforce_category_counts',
      'fk_workforce_category_counts_header_site',
      'f',
      'attendance_id, site_id',
      'public.daily_workforce_attendance',
      'id, site_id',
      'CASCADE'
    ),
    (
      'daily_workforce_category_counts',
      'daily_workforce_counts_attendance_category_uniq',
      'u',
      'attendance_id, category',
      NULL,
      NULL,
      NULL
    ),
    (
      'supervisor_attendance',
      'supervisor_attendance_supervisor_date_uniq',
      'u',
      'supervisor_id, attendance_date',
      NULL,
      NULL,
      NULL
    ),
    (
      'supervisor_attendance',
      'fk_supervisor_attendance_supervisor',
      'f',
      'supervisor_id',
      'public.user_profiles',
      'id',
      'RESTRICT'
    ),
    (
      'supervisor_attendance',
      'fk_supervisor_attendance_recorded_by',
      'f',
      'recorded_by',
      'public.user_profiles',
      'id',
      'RESTRICT'
    )
),
found_constraints AS (
  SELECT
    cl.relname                                   AS table_name,
    c.conname                                    AS constraint_name,
    c.contype                                    AS type_code,
    pg_get_constraintdef(c.oid)                  AS constraint_definition,
    array_to_string(
      ARRAY(
        SELECT a.attname
        FROM   pg_attribute a
        WHERE  a.attrelid = c.conrelid
          AND  a.attnum   = ANY(c.conkey)
        ORDER  BY array_position(c.conkey, a.attnum)
      ),
      ', '
    )                                            AS constrained_columns,
    CASE c.contype
      WHEN 'f' THEN (
        SELECT nsp.nspname || '.' || rcl.relname
        FROM   pg_class     rcl
        JOIN   pg_namespace nsp ON nsp.oid = rcl.relnamespace
        WHERE  rcl.oid = c.confrelid
      )
      ELSE NULL
    END                                          AS referenced_table,
    CASE c.contype
      WHEN 'f' THEN (
        SELECT array_to_string(
          ARRAY(
            SELECT fa.attname
            FROM   pg_attribute fa
            WHERE  fa.attrelid = c.confrelid
              AND  fa.attnum   = ANY(c.confkey)
            ORDER  BY array_position(c.confkey, fa.attnum)
          ),
          ', '
        )
      )
      ELSE NULL
    END                                          AS referenced_columns,
    CASE c.confdeltype
      WHEN 'r' THEN 'RESTRICT'
      WHEN 'c' THEN 'CASCADE'
      WHEN 'n' THEN 'SET NULL'
      WHEN 'a' THEN 'NO ACTION'
      ELSE c.confdeltype::text
    END                                          AS delete_action
  FROM pg_constraint c
  JOIN pg_class      cl ON cl.oid = c.conrelid
  JOIN pg_namespace  ns ON ns.oid = cl.relnamespace
  WHERE ns.nspname = 'public'
    AND cl.relname IN (
      'daily_workforce_attendance',
      'daily_workforce_category_counts',
      'supervisor_attendance'
    )
)
SELECT
  rc.table_name,
  rc.constraint_name,
  rc.expected_type,
  CASE
    WHEN fc.constraint_name IS NULL                      THEN 'MISSING ⚠'
    WHEN fc.type_code != rc.expected_type::char          THEN 'TYPE MISMATCH ⚠'
    WHEN fc.constrained_columns != rc.expected_columns   THEN 'COLUMN MISMATCH ⚠'
    WHEN rc.expected_ref_table IS NOT NULL
         AND fc.referenced_table != rc.expected_ref_table THEN 'REF TABLE MISMATCH ⚠'
    WHEN rc.expected_ref_columns IS NOT NULL
         AND fc.referenced_columns != rc.expected_ref_columns THEN 'REF COLUMNS MISMATCH ⚠'
    WHEN rc.expected_del_action IS NOT NULL
         AND fc.delete_action != rc.expected_del_action   THEN 'DELETE ACTION MISMATCH ⚠'
    ELSE 'EXISTS ✓'
  END                        AS status,
  fc.type_code               AS actual_type,
  fc.constrained_columns,
  fc.referenced_table,
  fc.referenced_columns,
  fc.delete_action,
  fc.constraint_definition
FROM required_constraints rc
LEFT JOIN found_constraints fc
  ON  fc.table_name       = rc.table_name
  AND fc.constraint_name  = rc.constraint_name
ORDER BY rc.table_name, rc.constraint_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 4: Dedicated Supervisor Foreign Key Target & Deletion Action Check
-- Specifically verifies:
--   1. supervisor_id -> user_profiles(id) ON DELETE RESTRICT
--   2. recorded_by   -> user_profiles(id) ON DELETE RESTRICT
-- Always returns exactly 2 rows; reports MISSING ⚠ if absent or FAIL ⚠ if mismatched.
-- ─────────────────────────────────────────────────────────────────────────────
WITH expected_fks (foreign_key_name, constrained_col, expected_ref_table, expected_ref_col, expected_del_action) AS (
  VALUES
    ('fk_supervisor_attendance_supervisor',  'supervisor_id', 'user_profiles', 'id', 'r'),
    ('fk_supervisor_attendance_recorded_by', 'recorded_by',   'user_profiles', 'id', 'r')
),
actual_fks AS (
  SELECT
    c.conname       AS foreign_key_name,
    a.attname       AS constrained_col,
    cl_ref.relname  AS ref_table,
    ra.attname      AS ref_col,
    c.confdeltype   AS del_type
  FROM pg_constraint c
  JOIN pg_class      cl     ON cl.oid     = c.conrelid
  JOIN pg_namespace  ns     ON ns.oid     = cl.relnamespace
  JOIN pg_class      cl_ref ON cl_ref.oid = c.confrelid
  JOIN pg_attribute  a      ON a.attrelid = cl.oid     AND a.attnum  = c.conkey[1]
  JOIN pg_attribute  ra     ON ra.attrelid = cl_ref.oid AND ra.attnum = c.confkey[1]
  WHERE ns.nspname = 'public'
    AND cl.relname = 'supervisor_attendance'
    AND c.contype  = 'f'
    AND array_length(c.conkey, 1) = 1
    AND array_length(c.confkey, 1) = 1
)
SELECT
  e.foreign_key_name,
  e.constrained_col || ' -> ' || e.expected_ref_table || '(' || e.expected_ref_col || ')' AS expected_fk_target,
  COALESCE(a.constrained_col || ' -> ' || a.ref_table || '(' || a.ref_col || ')', 'NONE') AS actual_fk_target,
  CASE
    WHEN a.foreign_key_name IS NULL THEN 'MISSING ⚠ (FK not installed)'
    WHEN a.ref_table != e.expected_ref_table THEN 'WRONG TARGET TABLE ⚠ (references ' || a.ref_table || ', expected ' || e.expected_ref_table || ')'
    WHEN a.ref_col != e.expected_ref_col THEN 'WRONG TARGET COLUMN ⚠ (references ' || a.ref_col || ', expected ' || e.expected_ref_col || ')'
    WHEN a.del_type = 'r' THEN 'RESTRICT ✓ (correct — cannot delete profile with attendance history)'
    WHEN a.del_type = 'c' THEN 'CASCADE ⚠ (DANGEROUS — will delete attendance history)'
    WHEN a.del_type = 'n' THEN 'SET NULL ⚠ (orphans attendance attribution)'
    ELSE 'ACTION: ' || a.del_type::text
  END AS delete_behavior,
  CASE
    WHEN a.foreign_key_name IS NOT NULL
     AND a.ref_table = e.expected_ref_table
     AND a.ref_col = e.expected_ref_col
     AND a.del_type = e.expected_del_action THEN 'PASS ✓'
    WHEN a.foreign_key_name IS NULL THEN 'MISSING ⚠'
    ELSE 'FAIL ⚠'
  END AS status
FROM expected_fks e
LEFT JOIN actual_fks a
  ON  a.foreign_key_name = e.foreign_key_name
  AND a.constrained_col  = e.constrained_col
ORDER BY e.foreign_key_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 5: Category & Count CHECK Constraint Verification
-- Validates exact seven approved categories and non-negative count rule.
-- Expected: Exactly 2 rows, each showing status = 'EXACT MATCH ✓'.
-- ─────────────────────────────────────────────────────────────────────────────
WITH expected_checks (check_name, expected_rule, canonical_pattern) AS (
  VALUES
    (
      'category_seven_trades',
      'CHECK (category = ANY (ARRAY[''Masons''::text, ''Painters''::text, ''Helpers''::text, ''Carpenters''::text, ''Electricians''::text, ''Plumbers''::text, ''Other''::text]))',
      '^CHECK\s*\(\(?category\s*=\s*ANY\s*\(ARRAY\[''Masons''::text,\s*''Painters''::text,\s*''Helpers''::text,\s*''Carpenters''::text,\s*''Electricians''::text,\s*''Plumbers''::text,\s*''Other''::text\]\)\)?\)$'
    ),
    (
      'count_non_negative',
      'CHECK (count >= 0)',
      '^CHECK\s*\(\(?count\s*>=\s*0\)?\)$'
    )
),
actual_checks AS (
  SELECT
    c.conname                   AS constraint_name,
    pg_get_constraintdef(c.oid) AS check_clause
  FROM pg_constraint c
  JOIN pg_class      cl ON cl.oid = c.conrelid
  JOIN pg_namespace  ns ON ns.oid = cl.relnamespace
  WHERE ns.nspname = 'public'
    AND cl.relname = 'daily_workforce_category_counts'
    AND c.contype  = 'c'
)
SELECT
  e.check_name,
  e.expected_rule,
  COALESCE(a.constraint_name, 'NOT FOUND') AS actual_constraint_name,
  COALESCE(a.check_clause, 'NONE')         AS actual_check_clause,
  CASE
    WHEN a.constraint_name IS NULL THEN 'MISSING ⚠'
    WHEN a.check_clause ~* e.canonical_pattern THEN 'EXACT MATCH ✓'
    ELSE 'RULE MISMATCH ⚠ (Found: ' || a.check_clause || ')'
  END AS status
FROM expected_checks e
LEFT JOIN actual_checks a
  ON a.check_clause ~* e.canonical_pattern
  OR (e.check_name = 'category_seven_trades' AND a.check_clause LIKE '%category%')
  OR (e.check_name = 'count_non_negative' AND a.check_clause LIKE '%count%')
ORDER BY e.check_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 6: RLS Policies & Explicit is_active_user() Enforcement
-- Enumerates all 12 expected policies and validates:
--   - Policy presence (no missing policies)
--   - Absence of unexpected extra policies (extra policies produce a FAIL result)
--   - Each policy is PERMISSIVE and applies strictly to role 'authenticated'
--   - Command matches expected command (SELECT, INSERT, UPDATE, DELETE)
--   - USING and WITH CHECK expressions independently enforce is_active_user()
-- Expected: Exactly 12 rows, all showing status = 'PASS ✓'.
-- ─────────────────────────────────────────────────────────────────────────────
WITH expected_policies (
  table_name,
  policy_name,
  expected_cmd,
  expects_using,
  expects_with_check
) AS (
  VALUES
    -- daily_workforce_attendance (4 policies)
    ('daily_workforce_attendance', 'daily_workforce_attendance_select', 'SELECT', TRUE,  FALSE),
    ('daily_workforce_attendance', 'daily_workforce_attendance_insert', 'INSERT', FALSE, TRUE),
    ('daily_workforce_attendance', 'daily_workforce_attendance_update', 'UPDATE', TRUE,  TRUE),
    ('daily_workforce_attendance', 'daily_workforce_attendance_delete', 'DELETE', TRUE,  FALSE),

    -- daily_workforce_category_counts (4 policies)
    ('daily_workforce_category_counts', 'daily_workforce_category_counts_select', 'SELECT', TRUE,  FALSE),
    ('daily_workforce_category_counts', 'daily_workforce_category_counts_insert', 'INSERT', FALSE, TRUE),
    ('daily_workforce_category_counts', 'daily_workforce_category_counts_update', 'UPDATE', TRUE,  TRUE),
    ('daily_workforce_category_counts', 'daily_workforce_category_counts_delete', 'DELETE', TRUE,  FALSE),

    -- supervisor_attendance (4 policies)
    ('supervisor_attendance', 'supervisor_attendance_active_select',    'SELECT', TRUE,  FALSE),
    ('supervisor_attendance', 'supervisor_attendance_pm_admin_insert', 'INSERT', FALSE, TRUE),
    ('supervisor_attendance', 'supervisor_attendance_pm_admin_update', 'UPDATE', TRUE,  TRUE),
    ('supervisor_attendance', 'supervisor_attendance_admin_delete',    'DELETE', TRUE,  FALSE)
),
actual_policies AS (
  SELECT
    schemaname,
    tablename,
    policyname,
    cmd,
    roles,
    permissive,
    qual,
    with_check
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename IN (
      'daily_workforce_attendance',
      'daily_workforce_category_counts',
      'supervisor_attendance'
    )
)
SELECT
  COALESCE(e.table_name, a.tablename)   AS table_name,
  COALESCE(e.policy_name, a.policyname) AS policy_name,
  e.expected_cmd,
  a.cmd                                 AS actual_cmd,
  CASE
    WHEN e.policy_name IS NULL   THEN 'UNEXPECTED EXTRA POLICY ⚠ (CRITICAL SECURITY FAILURE)'
    WHEN a.policyname IS NULL    THEN 'MISSING POLICY ⚠'
    WHEN a.cmd != e.expected_cmd THEN 'COMMAND MISMATCH ⚠ (Expected ' || e.expected_cmd || ', got ' || a.cmd || ')'
    ELSE 'INSTALLED ✓'
  END AS policy_status,
  CASE
    WHEN a.policyname IS NULL THEN 'N/A (MISSING)'
    WHEN a.permissive = 'PERMISSIVE' THEN 'PERMISSIVE ✓'
    ELSE 'NON-PERMISSIVE ⚠ (' || a.permissive || ')'
  END AS permissive_check,
  CASE
    WHEN a.policyname IS NULL THEN 'N/A (MISSING)'
    WHEN a.roles = ARRAY['authenticated']::name[] THEN 'AUTHENTICATED ONLY ✓'
    ELSE 'ROLE MISMATCH ⚠ (roles: ' || array_to_string(a.roles, ', ') || ', expected exactly {authenticated})'
  END AS roles_check,
  CASE
    WHEN e.policy_name IS NULL  THEN 'EXTRA'
    WHEN a.policyname IS NULL   THEN 'N/A (MISSING)'
    WHEN NOT e.expects_using    THEN 'NOT APPLICABLE (INSERT)'
    WHEN a.qual IS NULL         THEN 'MISSING USING CLAUSE ⚠'
    WHEN a.qual LIKE '%is_active_user%' THEN 'ENFORCED ✓'
    ELSE 'MISSING is_active_user() in USING ⚠'
  END AS using_active_user,
  CASE
    WHEN e.policy_name IS NULL      THEN 'EXTRA'
    WHEN a.policyname IS NULL       THEN 'N/A (MISSING)'
    WHEN NOT e.expects_with_check   THEN 'NOT APPLICABLE'
    WHEN a.with_check IS NULL       THEN 'MISSING WITH CHECK CLAUSE ⚠'
    WHEN a.with_check LIKE '%is_active_user%' THEN 'ENFORCED ✓'
    ELSE 'MISSING is_active_user() in WITH CHECK ⚠'
  END AS with_check_active_user,
  CASE
    WHEN e.policy_name IS NULL  THEN 'FAIL ⚠ (UNEXPECTED EXTRA POLICY)'
    WHEN a.policyname IS NULL   THEN 'FAIL ⚠ (MISSING POLICY)'
    WHEN a.cmd != e.expected_cmd THEN 'FAIL ⚠ (CMD MISMATCH)'
    WHEN a.permissive != 'PERMISSIVE' THEN 'FAIL ⚠ (NOT PERMISSIVE)'
    WHEN NOT (a.roles = ARRAY['authenticated']::name[]) THEN 'FAIL ⚠ (ROLES NOT EXACTLY {authenticated})'
    WHEN e.expects_using AND (a.qual IS NULL OR a.qual NOT LIKE '%is_active_user%') THEN 'FAIL ⚠ (USING INSECURE)'
    WHEN e.expects_with_check AND (a.with_check IS NULL OR a.with_check NOT LIKE '%is_active_user%') THEN 'FAIL ⚠ (WITH CHECK INSECURE)'
    ELSE 'PASS ✓'
  END AS status,
  a.qual       AS actual_using_expression,
  a.with_check AS actual_with_check_expression
FROM expected_policies e
FULL OUTER JOIN actual_policies a
  ON  a.tablename  = e.table_name
  AND a.policyname = e.policy_name
ORDER BY
  COALESCE(e.table_name, a.tablename),
  COALESCE(e.expected_cmd, a.cmd),
  COALESCE(e.policy_name, a.policyname);

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 7: Trigger Objects (Distinct trigger entities via pg_trigger)
-- Expected: Exactly 4 rows (one per trigger object).
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  cl.relname AS table_name,
  t.tgname   AS trigger_name,
  CASE t.tgtype & 2  WHEN 2 THEN 'BEFORE' ELSE 'AFTER'  END        AS timing,
  CASE t.tgtype & 1  WHEN 1 THEN 'ROW'    ELSE 'STATEMENT' END     AS orientation,
  array_to_string(
    ARRAY[
      CASE WHEN (t.tgtype & 4)  != 0 THEN 'INSERT' END,
      CASE WHEN (t.tgtype & 8)  != 0 THEN 'DELETE' END,
      CASE WHEN (t.tgtype & 16) != 0 THEN 'UPDATE' END
    ],
    ', '
  ) AS events
FROM pg_trigger    t
JOIN pg_class      cl ON cl.oid = t.tgrelid
JOIN pg_namespace  ns ON ns.oid = cl.relnamespace
WHERE ns.nspname = 'public'
  AND cl.relname IN (
    'daily_workforce_attendance',
    'daily_workforce_category_counts',
    'supervisor_attendance'
  )
  AND NOT t.tgisinternal
ORDER BY cl.relname, t.tgname;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 8: Functions Installed by Migration
-- Expected: Exactly 5 rows, security_type = 'DEFINER' for all.
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
-- CHECK 9a: Table-Level Grants for Authenticated, Anon, and PUBLIC
-- Expected:
--   daily_workforce_attendance: SELECT, DELETE to authenticated; none to anon/PUBLIC.
--   daily_workforce_category_counts: SELECT, DELETE to authenticated; none to anon/PUBLIC.
--   supervisor_attendance: SELECT, DELETE to authenticated; none to anon/PUBLIC.
--   daily_workforce_counts (legacy preserved): ZERO grants to authenticated, anon, PUBLIC.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  table_name,
  privilege_type,
  grantee
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN (
    'daily_workforce_attendance',
    'daily_workforce_category_counts',
    'supervisor_attendance',
    'daily_workforce_counts'
  )
  AND grantee IN ('authenticated', 'anon', 'PUBLIC')
ORDER BY table_name, grantee, privilege_type;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 9b: Column-Level Privilege Verification
-- Expected:
--   daily_workforce_attendance (authenticated):
--     INSERT: site_id, attendance_date, remarks ONLY
--     UPDATE: remarks ONLY
--     (total_workforce, created_by, created_at, updated_at MUST NOT APPEAR)
--   daily_workforce_category_counts (authenticated):
--     INSERT: attendance_id, site_id, category, count ONLY
--     UPDATE: category, count ONLY
--     (id, created_at, updated_at MUST NOT APPEAR)
--   supervisor_attendance (authenticated):
--     INSERT: site_id, supervisor_id, attendance_date, status, remarks ONLY
--     UPDATE: status, remarks ONLY
--     (id, recorded_by, created_at, updated_at MUST NOT APPEAR)
--   daily_workforce_counts (legacy preserved table):
--     ZERO column privileges across anon, authenticated, PUBLIC (all revoked in Section F).
--   anon & PUBLIC:
--     ZERO rows across all four tables.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  table_name,
  column_name,
  privilege_type,
  grantee
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name IN (
    'daily_workforce_attendance',
    'daily_workforce_category_counts',
    'supervisor_attendance',
    'daily_workforce_counts'
  )
  AND grantee IN ('authenticated', 'anon', 'PUBLIC')
ORDER BY table_name, column_name, privilege_type;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 10: Empty Row Counts (Tables must remain empty post-migration)
-- Expected: All zeros.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 'daily_workforce_attendance'      AS table_name, COUNT(*) AS row_count FROM public.daily_workforce_attendance
UNION ALL
SELECT 'daily_workforce_category_counts' AS table_name, COUNT(*) AS row_count FROM public.daily_workforce_category_counts
UNION ALL
SELECT 'supervisor_attendance'           AS table_name, COUNT(*) AS row_count FROM public.supervisor_attendance
UNION ALL
SELECT 'daily_workforce_counts'          AS table_name, COUNT(*) AS row_count FROM public.daily_workforce_counts;

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 11: Confirm supervisor_user_id is Completely Absent
-- Expected: 0 rows.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'supervisor_attendance'
  AND column_name  = 'supervisor_user_id';

-- ==============================================================================
-- END OF POST-MIGRATION VERIFICATION
-- ==============================================================================
