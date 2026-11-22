-- ==============================================================================
-- TSR BUILDERS — WORKFORCE HALF-DAY ATTENDANCE TRACKING ENHANCEMENT
-- File: supabase/migrations/20261122_workforce_half_day_tracking.sql
-- ==============================================================================
-- PURPOSE:
--   Additively extend public.daily_workforce_category_counts and
--   public.daily_workforce_attendance to track separate full-day and half-day
--   headcounts per trade category, server-computed total workers (headcount),
--   and total equivalent man-days (full_day + 0.5 * half_day).
--
-- GUARANTEES:
--   1. Zero destructive actions: ALTER TABLE ... ADD COLUMN IF NOT EXISTS.
--   2. Backward compatibility: legacy `count` column is preserved and synchronized
--      automatically via trigger (`count = full_day_count + half_day_count`).
--   3. Data backfill: existing non-zero counts become full_day_count with half_day_count = 0.
--   4. Dual calculation triggers:
--        - Total Workers (Headcount) = SUM(full_day_count + half_day_count)
--        - Total Man-Days (Equivalent) = SUM(full_day_count + (half_day_count * 0.5))
--   5. Server-side integrity: client cannot manipulate total_workforce or total_man_days.
--   6. Multi-header move safety: recalculates both OLD and NEW headers on attendance_id shift.
--   7. RLS policies and composite site-bound foreign keys are fully preserved.
-- ==============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 1: Add full_day_count and half_day_count to category counts table
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.daily_workforce_category_counts
  ADD COLUMN IF NOT EXISTS full_day_count INTEGER NOT NULL DEFAULT 0
    CHECK (full_day_count >= 0),
  ADD COLUMN IF NOT EXISTS half_day_count INTEGER NOT NULL DEFAULT 0
    CHECK (half_day_count >= 0);

-- Backfill existing legacy records
UPDATE public.daily_workforce_category_counts
SET    full_day_count = count,
       half_day_count = 0
WHERE  full_day_count = 0
  AND  half_day_count = 0
  AND  count > 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 2: Add total_man_days to parent attendance header
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.daily_workforce_attendance
  ADD COLUMN IF NOT EXISTS total_man_days NUMERIC(7, 1) NOT NULL DEFAULT 0.0
    CHECK (total_man_days >= 0);

-- Backfill parent total_man_days from existing category counts
UPDATE public.daily_workforce_attendance a
SET    total_man_days = COALESCE((
         SELECT SUM(COALESCE(c.full_day_count, 0) + (COALESCE(c.half_day_count, 0) * 0.5))
         FROM   public.daily_workforce_category_counts c
         WHERE  c.attendance_id = a.id
       ), a.total_workforce::numeric);

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 3: Category headcount synchronization trigger (keeps count in sync)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_category_headcount()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  -- Guarantee count is always equal to full_day_count + half_day_count
  NEW.count := COALESCE(NEW.full_day_count, 0) + COALESCE(NEW.half_day_count, 0);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_category_headcount
  ON public.daily_workforce_category_counts;
CREATE TRIGGER trg_sync_category_headcount
  BEFORE INSERT OR UPDATE ON public.daily_workforce_category_counts
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_category_headcount();

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 4: Update header audit guard to protect both total_workforce and total_man_days
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_workforce_attendance_audit_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := auth.uid();
    NEW.created_at := now();
    -- Totals are initially 0; populated by after trigger
    NEW.total_workforce := 0;
    NEW.total_man_days  := 0.0;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Immutable audit fields
    NEW.created_by := OLD.created_by;
    NEW.created_at := OLD.created_at;

    -- Protect total_workforce and total_man_days from direct client mutation
    IF (NEW.total_workforce IS DISTINCT FROM OLD.total_workforce)
       OR (NEW.total_man_days IS DISTINCT FROM OLD.total_man_days) THEN
      IF pg_trigger_depth() >= 2
         AND nullif(current_setting('tsr.workforce_sync_token', true), '') IS NOT NULL
      THEN
        PERFORM set_config('tsr.workforce_sync_token', '', true);
      ELSE
        NEW.total_workforce := OLD.total_workforce;
        NEW.total_man_days  := OLD.total_man_days;
      END IF;
    ELSE
      NEW.total_workforce := OLD.total_workforce;
      NEW.total_man_days  := OLD.total_man_days;
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 5: Update sync_workforce_total() trigger to compute headcount & man-days
-- ─────────────────────────────────────────────────────────────────────────────
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
             SELECT SUM(COALESCE(full_day_count, 0) + COALESCE(half_day_count, 0))
             FROM   public.daily_workforce_category_counts
             WHERE  attendance_id = OLD.attendance_id
           ), 0),
           total_man_days = COALESCE((
             SELECT SUM(COALESCE(full_day_count, 0) + (COALESCE(half_day_count, 0) * 0.5))
             FROM   public.daily_workforce_category_counts
             WHERE  attendance_id = OLD.attendance_id
           ), 0.0),
           updated_at = now()
    WHERE  id = OLD.attendance_id;
    PERFORM set_config('tsr.workforce_sync_token', '', true);

  ELSIF TG_OP = 'INSERT' THEN
    v_sync_token := gen_random_uuid()::text;
    PERFORM set_config('tsr.workforce_sync_token', v_sync_token, true);
    UPDATE public.daily_workforce_attendance
    SET    total_workforce = COALESCE((
             SELECT SUM(COALESCE(full_day_count, 0) + COALESCE(half_day_count, 0))
             FROM   public.daily_workforce_category_counts
             WHERE  attendance_id = NEW.attendance_id
           ), 0),
           total_man_days = COALESCE((
             SELECT SUM(COALESCE(full_day_count, 0) + (COALESCE(half_day_count, 0) * 0.5))
             FROM   public.daily_workforce_category_counts
             WHERE  attendance_id = NEW.attendance_id
           ), 0.0),
           updated_at = now()
    WHERE  id = NEW.attendance_id;
    PERFORM set_config('tsr.workforce_sync_token', '', true);

  ELSIF TG_OP = 'UPDATE' THEN
    -- Recalculate destination (NEW) header
    v_sync_token := gen_random_uuid()::text;
    PERFORM set_config('tsr.workforce_sync_token', v_sync_token, true);
    UPDATE public.daily_workforce_attendance
    SET    total_workforce = COALESCE((
             SELECT SUM(COALESCE(full_day_count, 0) + COALESCE(half_day_count, 0))
             FROM   public.daily_workforce_category_counts
             WHERE  attendance_id = NEW.attendance_id
           ), 0),
           total_man_days = COALESCE((
             SELECT SUM(COALESCE(full_day_count, 0) + (COALESCE(half_day_count, 0) * 0.5))
             FROM   public.daily_workforce_category_counts
             WHERE  attendance_id = NEW.attendance_id
           ), 0.0),
           updated_at = now()
    WHERE  id = NEW.attendance_id;
    PERFORM set_config('tsr.workforce_sync_token', '', true);

    -- If category row shifted between headers, also update source (OLD) header
    IF OLD.attendance_id IS DISTINCT FROM NEW.attendance_id THEN
      v_sync_token := gen_random_uuid()::text;
      PERFORM set_config('tsr.workforce_sync_token', v_sync_token, true);
      UPDATE public.daily_workforce_attendance
      SET    total_workforce = COALESCE((
               SELECT SUM(COALESCE(full_day_count, 0) + COALESCE(half_day_count, 0))
               FROM   public.daily_workforce_category_counts
               WHERE  attendance_id = OLD.attendance_id
             ), 0),
             total_man_days = COALESCE((
               SELECT SUM(COALESCE(full_day_count, 0) + (COALESCE(half_day_count, 0) * 0.5))
               FROM   public.daily_workforce_category_counts
               WHERE  attendance_id = OLD.attendance_id
             ), 0.0),
             updated_at = now()
      WHERE  id = OLD.attendance_id;
      PERFORM set_config('tsr.workforce_sync_token', '', true);
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 6: Explicit column privileges for authenticated role
-- ─────────────────────────────────────────────────────────────────────────────
GRANT INSERT (attendance_id, site_id, category, count, full_day_count, half_day_count)
  ON public.daily_workforce_category_counts TO authenticated;

GRANT UPDATE (category, count, full_day_count, half_day_count)
  ON public.daily_workforce_category_counts TO authenticated;

COMMIT;
