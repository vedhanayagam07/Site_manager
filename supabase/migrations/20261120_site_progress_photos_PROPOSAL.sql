-- ==============================================================================
-- TSR BUILDERS — PROPOSED ADDITIVE MIGRATION (PROPOSAL — DO NOT EXECUTE YET)
-- File: supabase/migrations/20261120_site_progress_photos_PROPOSAL.sql
-- ==============================================================================
-- ARCHITECTURAL SPECIFICATION & SECURITY VERIFICATION:
-- 1. Purely Additive & Non-Destructive:
--    - Does NOT modify, alter, or drop any existing tables (sites, workers,
--      materials, material_transactions, site_attendance, loading_memos,
--      activity_logs, user_profiles, site_memberships).
-- 2. Strict Parent-Child Site Matching:
--    - Uses a Composite Foreign Key (progress_id, site_id) on site_progress_photos
--      referencing (id, site_id) on site_progress_updates. A photo's site_id
--      is mathematically guaranteed to match its parent progress update's site_id.
-- 3. Storage Path Validation Against Actual Progress Record:
--    - Storage path convention: sites/{site_id}/{progress_id}/{filename}
--    - Helper can_access_progress_storage_object() verifies that the target
--      progress record actually exists with the exact site_id and progress_id
--      before granting SELECT or INSERT storage access.
--    - Trigger validates storage_path on photo INSERT:
--      a) must match convention sites/{site_id}/{progress_id}/{filename}
--      b) filename segment after the progress_id must be non-empty
--      c) the corresponding storage.objects row MUST already exist (upload before metadata)
-- 4. Photo Metadata Validation & 1:1 Storage Object Uniqueness on INSERT:
--    - Unique Storage Path: storage_path is enforced UNIQUE on site_progress_photos.
--      One Storage object must correspond to exactly one photo metadata record, preventing
--      multiple photo rows from pointing to the same file and triggering premature deletion.
--    - file_size and mime_type are compared against storage.objects.metadata where reliably available,
--      and synchronized with actual storage metadata.
--    - If storage metadata cannot be verified reliably, these database columns are strictly documented
--      as informational records and must NEVER be used as security controls. True size and MIME enforcement
--      is guaranteed at the Storage Bucket perimeter (storage.buckets configuration).
--    - file_size must be a positive integer not exceeding 10 MB (10,485,760 bytes).
--    - mime_type must be one of: image/jpeg, image/png, image/webp, image/heic.
--    - storage_path must contain a non-empty filename after the site_id/progress_id segments.
-- 5. Unconditional Immutability & Audit Foreign Key Protection (ON DELETE RESTRICT):
--    - Audit attribution foreign keys (created_by, feedback_by on site_progress_updates;
--      uploaded_by on site_progress_photos) are configured with ON DELETE RESTRICT referencing
--      public.user_profiles(id). Audit history cannot be orphaned. User accounts should be
--      deactivated (status = 'disabled') rather than physically deleted while audit records reference them.
--    - Trigger enforce_progress_update_permissions() protects id, site_id,
--      created_by, and created_at against client spoofing for ALL roles,
--      including Project Managers and Administrators.
--    - Trigger enforce_progress_photo_immutability() permanently locks photo identity
--      (id), parent progress assignment (progress_id), site assignment (site_id),
--      storage path (storage_path), uploader identity (uploaded_by), and created_at.
--      On UPDATE, file_size and mime_type are strictly preserved; only caption may be updated.
-- 6. Role-Gated Content & Feedback Attribution:
--    - Supervisors may edit their own progress content (category, description, remarks)
--      on sites where they hold active membership.
--    - Non-PM/Admin users are strictly prohibited by BEFORE-trigger from creating,
--      editing, or clearing feedback, feedback_by, or feedback_at fields.
--    - Only Project Managers and Administrators may provide or update management feedback:
--      * If feedback text is unchanged, OLD.feedback_by and OLD.feedback_at are preserved.
--      * If feedback changes to non-empty text, feedback_by = auth.uid() and feedback_at = NOW().
--      * If feedback is cleared, both attribution fields are set to NULL.
-- 7. Reliable Storage Cleanup Queue & Worker Architecture:
--    - Direct authenticated DELETE on storage.objects is REMOVED: authenticated browser users
--      (including PM/Admin) cannot delete storage objects directly.
--    - Deletion is performed by deleting the photo metadata record (or parent progress update).
--    - Database trigger on site_progress_photos BEFORE DELETE stages photo paths into
--      public.storage_cleanup_queue exactly once. Deduplication is enforced by a partial
--      unique index and ON CONFLICT DO NOTHING.
--    - Physical file deletion is performed asynchronously by a trusted server-side worker
--      (Edge Function or cron worker with service_role key) invoking the official Storage API.
--      The service_role key bypasses Storage RLS.
--    - All browser permissions (anon, authenticated) are strictly REVOKED on storage_cleanup_queue.
--    - Minimum permissions (SELECT, UPDATE, INSERT) are granted to service_role only.
--    - Job claiming uses SECURITY DEFINER RPC public.claim_cleanup_jobs() with
--      FOR UPDATE SKIP LOCKED to safely handle concurrent worker invocations.
--    - Stale 'processing' jobs are reclaimed after a configurable lease timeout (default: 10 minutes).
--      Expired leases count as attempts so crashing workers cannot retry indefinitely; jobs reaching
--      max_attempts transition to 'failed' and are not automatically reclaimed.
--    - Strong Lease Ownership: Each claim generates a distinct claim_token UUID. Workers must match
--      id, claim_token, and status='processing' to update jobs, preventing expired workers from modifying
--      reclaimed jobs. claim_token is cleared to NULL upon completion or retry.
-- 8. Private Bucket & Site-Scoped Storage RLS:
--    - Bucket 'site-progress-photos' is private (public = false). Direct public URLs are blocked.
--    - All viewing uses secure, short-lived signed URLs.
--    - Storage RLS enforces active site membership (public.has_site_access) for non-PM/Admin callers.
--    - ON CONFLICT DO UPDATE on storage.buckets: if the bucket already exists its configuration
--      (public flag, file_size_limit, allowed_mime_types) is updated to match this specification.
--      Run pre-deployment verification query to inspect existing bucket state before applying.
-- 9. Cleanup Queue Retention:
--    - 'completed' rows are retained for audit and may be purged after 30 days.
--    - Unresolved 'failed' rows are NEVER purged automatically; they require manual investigation.
--    - Periodic sweep:
--        DELETE FROM public.storage_cleanup_queue
--        WHERE status = 'completed' AND processed_at < NOW() - INTERVAL '30 days';
-- 10. Zero Anon / Public Privileges:
--    - All direct and inherited table permissions from anon & PUBLIC are revoked (42501 expected).
--
-- STATUS: PROPOSAL ONLY. DO NOT EXECUTE AGAINST PRODUCTION WITHOUT EXPLICIT APPROVAL.
-- ==============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Reliable Storage Cleanup Queue Table (public.storage_cleanup_queue)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.storage_cleanup_queue (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id       TEXT        NOT NULL DEFAULT 'site-progress-photos',
  storage_path    TEXT        NOT NULL,
  attempts        INTEGER     NOT NULL DEFAULT 0,
  max_attempts    INTEGER     NOT NULL DEFAULT 5,
  status          TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  last_error      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- processing_started_at: set when a worker claims this job; used to detect crashed workers
  processing_started_at TIMESTAMPTZ,
  -- claim_token: UUID assigned when a worker claims this job; prevents a worker with an expired
  -- lease from modifying a job reclaimed by another worker.
  claim_token     UUID,
  processed_at    TIMESTAMPTZ
);

-- Deduplication index: prevents duplicate active cleanup entries for the same path.
-- Only one active entry per (bucket_id, storage_path) can be in pending or processing state.
CREATE UNIQUE INDEX IF NOT EXISTS idx_storage_cleanup_queue_active_dedup
  ON public.storage_cleanup_queue (bucket_id, storage_path)
  WHERE status IN ('pending', 'processing');

-- Index to accelerate the worker poll query (pending+failed jobs ordered by age)
CREATE INDEX IF NOT EXISTS idx_storage_cleanup_queue_worker_poll
  ON public.storage_cleanup_queue (status, attempts, created_at)
  WHERE status IN ('pending', 'failed');

-- Index to accelerate lease-timeout reclaim (stale processing jobs)
CREATE INDEX IF NOT EXISTS idx_storage_cleanup_queue_stale_processing
  ON public.storage_cleanup_queue (status, processing_started_at)
  WHERE status = 'processing';

ALTER TABLE public.storage_cleanup_queue ENABLE ROW LEVEL SECURITY;

-- Security Fence: Zero permissions for anon, PUBLIC, or standard authenticated browser users.
-- Database triggers use SECURITY DEFINER (running as database owner) for inserts.
-- The trusted cleanup worker connects via service_role for all queue operations.
REVOKE ALL ON public.storage_cleanup_queue FROM anon, PUBLIC;
REVOKE ALL ON public.storage_cleanup_queue FROM authenticated;

-- Minimum required grants for service_role:
--   SELECT: to poll eligible jobs in claim_cleanup_jobs()
--   INSERT: required for triggers running under SECURITY DEFINER (owner privileges suffice,
--           but explicit grant documents intent)
--   UPDATE: to mark jobs as processing, completed, or failed
GRANT SELECT, INSERT, UPDATE ON public.storage_cleanup_queue TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Atomic Job Claim RPC (public.claim_cleanup_jobs)
-- ─────────────────────────────────────────────────────────────────────────────
-- SECURITY DEFINER function callable only by service_role.
-- Atomically:
--   1. Resets stale 'processing' jobs whose lease has expired (default: 10 minutes) back to 'pending'.
--   2. Claims up to p_batch_size eligible jobs (pending + failed with attempts < max_attempts)
--      using FOR UPDATE SKIP LOCKED to safely handle concurrent worker invocations.
--   3. Sets status = 'processing' and records processing_started_at = NOW() on claimed rows.
--   4. Returns the claimed rows as a result set.
--
-- Usage: SELECT * FROM public.claim_cleanup_jobs();
--        SELECT * FROM public.claim_cleanup_jobs(100, '15 minutes'::INTERVAL);
CREATE OR REPLACE FUNCTION public.claim_cleanup_jobs(
  p_batch_size    INTEGER  DEFAULT 50,
  p_lease_timeout INTERVAL DEFAULT '10 minutes'::INTERVAL
)
RETURNS SETOF public.storage_cleanup_queue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validate input parameters
  IF p_batch_size IS NULL OR p_batch_size <= 0 THEN
    RAISE EXCEPTION 'p_batch_size must be a positive integer (got %)', p_batch_size;
  END IF;
  IF p_batch_size > 500 THEN
    RAISE EXCEPTION 'p_batch_size cannot exceed 500 (got %)', p_batch_size;
  END IF;
  IF p_lease_timeout IS NULL OR p_lease_timeout < INTERVAL '1 minute' THEN
    RAISE EXCEPTION 'p_lease_timeout must be at least 1 minute (got %)', p_lease_timeout;
  END IF;
  IF p_lease_timeout > INTERVAL '24 hours' THEN
    RAISE EXCEPTION 'p_lease_timeout cannot exceed 24 hours (got %)', p_lease_timeout;
  END IF;

  -- Step 1: Reclaim stale 'processing' jobs whose lease has expired.
  -- These are jobs that were claimed by a worker that crashed or timed out.
  -- Expired leases count as an attempt so crashing workers cannot retry indefinitely.
  -- Jobs that reach max_attempts transition to 'failed' and are not automatically reclaimed.
  UPDATE public.storage_cleanup_queue
  SET
    attempts              = attempts + 1,
    status                = CASE
                              WHEN attempts + 1 >= max_attempts THEN 'failed'
                              ELSE 'pending'
                            END,
    last_error            = CASE
                              WHEN attempts + 1 >= max_attempts THEN 'Worker lease expired; maximum retry attempts reached.'
                              ELSE 'Worker lease expired; returned to pending queue for retry.'
                            END,
    processing_started_at = NULL,
    claim_token           = NULL,
    processed_at          = NOW()
  WHERE
    status = 'processing'
    AND processing_started_at IS NOT NULL
    AND processing_started_at < NOW() - p_lease_timeout;

  -- Step 2: Atomically claim eligible jobs.
  -- FOR UPDATE SKIP LOCKED ensures that if two worker instances run concurrently,
  -- they cannot claim the same row. Each worker gets a distinct, non-overlapping
  -- batch of jobs.
  RETURN QUERY
    UPDATE public.storage_cleanup_queue q
    SET
      status                = 'processing',
      processing_started_at = NOW(),
      claim_token           = gen_random_uuid()
    FROM (
      SELECT id
      FROM   public.storage_cleanup_queue
      WHERE  status IN ('pending', 'failed')
        AND  attempts < max_attempts
      ORDER  BY created_at ASC
      LIMIT  p_batch_size
      FOR UPDATE SKIP LOCKED
    ) AS eligible
    WHERE q.id = eligible.id
    RETURNING q.*;
END;
$$;

-- Restrict execution strictly to service_role.
-- Browser users (anon, authenticated) cannot call this function.
REVOKE ALL ON FUNCTION public.claim_cleanup_jobs(INTEGER, INTERVAL) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_cleanup_jobs(INTEGER, INTERVAL) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Site Progress Updates Table (public.site_progress_updates)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.site_progress_updates (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  site_id      UUID        NOT NULL REFERENCES public.sites(id) ON DELETE CASCADE,
  work_date    DATE        NOT NULL DEFAULT CURRENT_DATE,
  category     TEXT        NOT NULL,
  description  TEXT        NOT NULL,
  remarks      TEXT,
  feedback     TEXT,
  feedback_by  UUID        REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
  feedback_at  TIMESTAMPTZ,
  created_by   UUID        REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Composite unique target for child photo composite foreign key enforcement
  CONSTRAINT site_progress_updates_id_site_uniq UNIQUE (id, site_id)
);

CREATE INDEX IF NOT EXISTS idx_site_progress_updates_site_date
  ON public.site_progress_updates (site_id, work_date DESC);

CREATE INDEX IF NOT EXISTS idx_site_progress_updates_category
  ON public.site_progress_updates (category);

CREATE INDEX IF NOT EXISTS idx_site_progress_updates_created_at
  ON public.site_progress_updates (created_at DESC);

ALTER TABLE public.site_progress_updates ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.site_progress_updates FROM anon, PUBLIC;
REVOKE ALL ON public.site_progress_updates FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.site_progress_updates TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Trigger: enforce_progress_update_permissions
-- Enforces: creation audit attribution, record immutability, and feedback boundaries.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_progress_update_permissions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Server-enforce created_by and created_at unconditionally for all callers
    NEW.created_by := auth.uid();
    NEW.created_at := NOW();

    -- Restrict initial feedback: non-PM/Admin cannot seed feedback fields
    IF NOT public.is_pm_or_admin() THEN
      NEW.feedback    := NULL;
      NEW.feedback_by := NULL;
      NEW.feedback_at := NULL;
    ELSE
      IF NEW.feedback IS NOT NULL AND TRIM(NEW.feedback) != '' THEN
        NEW.feedback    := TRIM(NEW.feedback);
        NEW.feedback_by := auth.uid();
        NEW.feedback_at := NOW();
      ELSE
        NEW.feedback    := NULL;
        NEW.feedback_by := NULL;
        NEW.feedback_at := NULL;
      END IF;
    END IF;

  ELSIF TG_OP = 'UPDATE' THEN
    -- Absolute immutability: id, site_id, created_by, and created_at cannot be spoofed by ANY caller
    IF NEW.id IS DISTINCT FROM OLD.id THEN
      RAISE EXCEPTION 'Progress update record ID is immutable.';
    END IF;
    IF NEW.site_id IS DISTINCT FROM OLD.site_id THEN
      RAISE EXCEPTION 'Cannot reassign progress update to a different construction site.';
    END IF;

    NEW.created_by := OLD.created_by;
    NEW.created_at := OLD.created_at;

    IF NOT public.is_pm_or_admin() THEN
      -- 1. Must be the original creator
      IF OLD.created_by IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'You are only authorized to edit your own progress updates.';
      END IF;

      -- 2. Must still possess active site membership
      IF NOT public.has_site_access(OLD.site_id) THEN
        RAISE EXCEPTION 'You do not have active site membership for this construction site.';
      END IF;

      -- 3. Strictly prohibit supervisors / non-PM/Admin from altering feedback fields
      IF NEW.feedback IS DISTINCT FROM OLD.feedback
         OR NEW.feedback_by IS DISTINCT FROM OLD.feedback_by
         OR NEW.feedback_at IS DISTINCT FROM OLD.feedback_at THEN
        RAISE EXCEPTION 'Only Project Managers and Administrators are permitted to provide or modify feedback.';
      END IF;

      -- Silently preserve existing feedback fields for non-PM/Admin regardless of what client sent
      NEW.feedback    := OLD.feedback;
      NEW.feedback_by := OLD.feedback_by;
      NEW.feedback_at := OLD.feedback_at;
    ELSE
      -- PM/Admin feedback attribution rules:
      -- 1. If feedback text is unchanged → preserve OLD.feedback_by and OLD.feedback_at
      IF NEW.feedback IS NOT DISTINCT FROM OLD.feedback THEN
        NEW.feedback_by := OLD.feedback_by;
        NEW.feedback_at := OLD.feedback_at;
      -- 2. If feedback changes to non-empty text → attribute to current PM/Admin
      ELSIF NEW.feedback IS NOT NULL AND TRIM(NEW.feedback) != '' THEN
        NEW.feedback    := TRIM(NEW.feedback);
        NEW.feedback_by := auth.uid();
        NEW.feedback_at := NOW();
      -- 3. If feedback is cleared → set both attribution fields to NULL
      ELSE
        NEW.feedback    := NULL;
        NEW.feedback_by := NULL;
        NEW.feedback_at := NULL;
      END IF;
    END IF;
  END IF;

  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_progress_update_permissions ON public.site_progress_updates;
CREATE TRIGGER trg_enforce_progress_update_permissions
  BEFORE INSERT OR UPDATE ON public.site_progress_updates
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_progress_update_permissions();

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: Site Progress Photos Table (public.site_progress_photos)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.site_progress_photos (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  progress_id  UUID        NOT NULL,
  site_id      UUID        NOT NULL,
  storage_path TEXT        NOT NULL,
  caption      TEXT,
  -- file_size: bytes; must be 1–10,485,760 (10 MB). Validated by insert trigger.
  file_size    INTEGER,
  -- mime_type: validated by insert trigger against allowed set.
  mime_type    TEXT        DEFAULT 'image/jpeg',
  uploaded_by  UUID        REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Storage path uniqueness: one Storage object corresponds to exactly one photo record
  CONSTRAINT site_progress_photos_storage_path_uniq UNIQUE (storage_path),
  -- Composite Foreign Key: a photo's site_id MUST match its parent progress update's site_id.
  CONSTRAINT fk_site_progress_photos_parent_site
    FOREIGN KEY (progress_id, site_id)
    REFERENCES public.site_progress_updates(id, site_id)
    ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_site_progress_photos_progress_id
  ON public.site_progress_photos (progress_id);

CREATE INDEX IF NOT EXISTS idx_site_progress_photos_site_id
  ON public.site_progress_photos (site_id);

ALTER TABLE public.site_progress_photos ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.site_progress_photos FROM anon, PUBLIC;
REVOKE ALL ON public.site_progress_photos FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.site_progress_photos TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Trigger: validate_progress_photo_fields (INSERT only)
-- Validates and enforces on INSERT:
--   1. storage_path follows convention: sites/{site_id}/{progress_id}/{filename}
--      where {filename} is non-empty.
--   2. file_size is a positive integer not exceeding 10 MB.
--   3. mime_type is one of: image/jpeg, image/png, image/webp, image/heic.
--   4. The corresponding storage.objects row MUST already exist (upload-first discipline).
--      This prevents orphaned metadata rows and confirms the file is physically present.
--   5. Sets uploaded_by = auth.uid() and enforces created_at = NOW().
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.validate_progress_photo_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, storage
AS $$
DECLARE
  v_expected_prefix  TEXT;
  v_filename         TEXT;
  v_parts            TEXT[];
  v_storage_size_raw TEXT;
  v_storage_mimetype TEXT;
  v_storage_size     BIGINT;
BEGIN
  -- ── 1. storage_path convention & non-empty filename ──────────────────────
  v_expected_prefix := 'sites/' || NEW.site_id::text || '/' || NEW.progress_id::text || '/';

  IF NOT (NEW.storage_path LIKE (v_expected_prefix || '%')) THEN
    RAISE EXCEPTION
      'Photo storage_path "%" does not match required convention "sites/{site_id}/{progress_id}/{filename}".',
      NEW.storage_path;
  END IF;

  -- Extract filename: everything after the prefix
  v_filename := substring(NEW.storage_path FROM length(v_expected_prefix) + 1);
  IF v_filename IS NULL OR TRIM(v_filename) = '' THEN
    RAISE EXCEPTION
      'Photo storage_path "%" must contain a non-empty filename after the site and progress ID segments.',
      NEW.storage_path;
  END IF;

  -- ── 2. Verify corresponding storage.objects row exists & compare metadata ──
  -- The frontend uploads the binary first, then inserts this metadata row.
  -- If the storage object is absent, the metadata row would be orphaned.
  --
  -- SECURITY & METADATA ARCHITECTURE NOTE:
  -- True enforcement of maximum file size and allowable content types occurs at the
  -- Storage Bucket perimeter via storage.buckets configuration:
  --   (file_size_limit = 10485760, allowed_mime_types = ['image/jpeg', 'image/png', ...])
  -- In this trigger, file_size and mime_type are compared against storage.objects.metadata
  -- where reliable, and reconciled with actual storage metadata.
  -- If storage.objects.metadata fields cannot be verified reliably (e.g. missing or unparseable),
  -- the table fields are documented as purely informational and MUST NEVER be relied upon
  -- as independent security controls.
  SELECT
    so.metadata->>'size',
    so.metadata->>'mimetype'
  INTO
    v_storage_size_raw,
    v_storage_mimetype
  FROM storage.objects so
  WHERE so.bucket_id = 'site-progress-photos'
    AND so.name      = NEW.storage_path;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Storage object "%" does not exist in bucket "site-progress-photos". '
      'Upload the file before inserting photo metadata.',
      NEW.storage_path;
  END IF;

  -- Reconcile file_size with storage.objects metadata when reliably available
  IF v_storage_size_raw IS NOT NULL AND v_storage_size_raw ~ '^\d+$' THEN
    v_storage_size := v_storage_size_raw::BIGINT;
    IF v_storage_size <= 0 THEN
      RAISE EXCEPTION 'Storage object size must be greater than 0 bytes (got %)', v_storage_size;
    END IF;
    IF v_storage_size > 10485760 THEN
      RAISE EXCEPTION 'Actual storage file size (% bytes) exceeds the 10 MB limit (10,485,760 bytes).', v_storage_size;
    END IF;
    -- Synchronize with actual verified physical storage size
    NEW.file_size := v_storage_size::INTEGER;
  ELSE
    -- If storage metadata cannot be parsed reliably, validate within bounds; documented as informational
    IF NEW.file_size IS NULL OR NEW.file_size <= 0 THEN
      RAISE EXCEPTION 'file_size must be a positive integer (got %). Ensure client reports byte size.', NEW.file_size;
    END IF;
    IF NEW.file_size > 10485760 THEN
      RAISE EXCEPTION 'file_size % exceeds the 10 MB limit (10,485,760 bytes).', NEW.file_size;
    END IF;
  END IF;

  -- Reconcile mime_type with storage.objects metadata when reliably available
  IF v_storage_mimetype IS NOT NULL AND TRIM(v_storage_mimetype) != '' THEN
    IF LOWER(v_storage_mimetype) NOT IN ('image/jpeg', 'image/png', 'image/webp', 'image/heic') THEN
      RAISE EXCEPTION 'Storage object MIME type "%" is not permitted. Allowed: image/jpeg, image/png, image/webp, image/heic.',
        v_storage_mimetype;
    END IF;
    NEW.mime_type := LOWER(v_storage_mimetype);
  ELSE
    -- If storage metadata cannot be parsed reliably, validate within permitted set; documented as informational
    IF NEW.mime_type IS NULL OR LOWER(NEW.mime_type) NOT IN ('image/jpeg', 'image/png', 'image/webp', 'image/heic') THEN
      RAISE EXCEPTION 'mime_type "%" is not permitted. Allowed: image/jpeg, image/png, image/webp, image/heic.',
        NEW.mime_type;
    END IF;
    NEW.mime_type := LOWER(NEW.mime_type);
  END IF;

  -- ── 3. Audit attribution ──────────────────────────────────────────────────
  NEW.uploaded_by := auth.uid();
  NEW.created_at  := NOW();
  NEW.updated_at  := NOW();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_progress_photo_fields ON public.site_progress_photos;
CREATE TRIGGER trg_validate_progress_photo_fields
  BEFORE INSERT ON public.site_progress_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_progress_photo_fields();

-- ─────────────────────────────────────────────────────────────────────────────
-- Trigger: enforce_progress_photo_immutability (UPDATE only)
-- Locks on UPDATE: id, progress_id, site_id, storage_path, uploaded_by, created_at,
--                  file_size, mime_type (all immutable after INSERT).
-- Only caption may be changed. Non-PM/Admin must own the photo and hold active site access.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_progress_photo_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- Permanent lock: immutable fields
  IF NEW.id IS DISTINCT FROM OLD.id THEN
    RAISE EXCEPTION 'Photo record ID is immutable.';
  END IF;
  IF NEW.progress_id IS DISTINCT FROM OLD.progress_id THEN
    RAISE EXCEPTION 'Cannot reassign a photo to a different progress update.';
  END IF;
  IF NEW.site_id IS DISTINCT FROM OLD.site_id THEN
    RAISE EXCEPTION 'Cannot reassign a photo to a different construction site.';
  END IF;
  IF NEW.storage_path IS DISTINCT FROM OLD.storage_path THEN
    RAISE EXCEPTION 'Photo storage path is immutable once uploaded.';
  END IF;
  IF NEW.uploaded_by IS DISTINCT FROM OLD.uploaded_by THEN
    RAISE EXCEPTION 'Photo uploader attribution is immutable.';
  END IF;

  -- Silently preserve immutable metadata (never raise on these; just restore OLD)
  NEW.created_at := OLD.created_at;
  NEW.file_size  := OLD.file_size;
  NEW.mime_type  := OLD.mime_type;

  -- Authorization: non-PM/Admin must be the original uploader with active site access
  IF NOT public.is_pm_or_admin() THEN
    IF OLD.uploaded_by IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'You are only authorized to edit captions on photos you uploaded.';
    END IF;
    IF NOT public.has_site_access(OLD.site_id) THEN
      RAISE EXCEPTION 'You no longer possess active site membership for this construction site.';
    END IF;
  END IF;

  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_progress_photo_immutability ON public.site_progress_photos;
CREATE TRIGGER trg_enforce_progress_photo_immutability
  BEFORE UPDATE ON public.site_progress_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_progress_photo_immutability();

-- ─────────────────────────────────────────────────────────────────────────────
-- Trigger: queue_single_progress_photo_cleanup (BEFORE DELETE)
-- When a photo row is deleted (directly or via parent CASCADE), stages its
-- storage path into storage_cleanup_queue exactly once.
-- Deduplication: ON CONFLICT DO NOTHING against the partial unique index.
-- Parent trigger is intentionally absent to prevent double-queueing on cascade.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.queue_single_progress_photo_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.storage_path IS NOT NULL AND TRIM(OLD.storage_path) != '' THEN
    INSERT INTO public.storage_cleanup_queue (bucket_id, storage_path)
    VALUES ('site-progress-photos', OLD.storage_path)
    ON CONFLICT (bucket_id, storage_path) WHERE status IN ('pending', 'processing') DO NOTHING;
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_queue_single_progress_photo_cleanup ON public.site_progress_photos;
CREATE TRIGGER trg_queue_single_progress_photo_cleanup
  BEFORE DELETE ON public.site_progress_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_single_progress_photo_cleanup();

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: Site Access Helper Function for Progress Records
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_access_site_progress(p_site_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
STABLE
AS $$
  SELECT public.is_pm_or_admin() OR (
    public.is_active_user() AND public.has_site_access(p_site_id)
  );
$$;

REVOKE ALL ON FUNCTION public.can_access_site_progress(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_site_progress(UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 6: Table RLS Policies
-- ─────────────────────────────────────────────────────────────────────────────

-- Table 1: site_progress_updates Policies
DROP POLICY IF EXISTS "site_progress_updates_select" ON public.site_progress_updates;
CREATE POLICY "site_progress_updates_select"
  ON public.site_progress_updates FOR SELECT TO authenticated
  USING (public.can_access_site_progress(site_id));

DROP POLICY IF EXISTS "site_progress_updates_insert" ON public.site_progress_updates;
CREATE POLICY "site_progress_updates_insert"
  ON public.site_progress_updates FOR INSERT TO authenticated
  WITH CHECK (public.can_access_site_progress(site_id));

DROP POLICY IF EXISTS "site_progress_updates_update" ON public.site_progress_updates;
CREATE POLICY "site_progress_updates_update"
  ON public.site_progress_updates FOR UPDATE TO authenticated
  USING (
    public.is_pm_or_admin()
    OR (
      created_by = auth.uid()
      AND public.can_access_site_progress(site_id)
    )
  )
  WITH CHECK (
    public.is_pm_or_admin()
    OR (
      created_by = auth.uid()
      AND public.can_access_site_progress(site_id)
    )
  );

DROP POLICY IF EXISTS "site_progress_updates_delete" ON public.site_progress_updates;
CREATE POLICY "site_progress_updates_delete"
  ON public.site_progress_updates FOR DELETE TO authenticated
  USING (public.is_pm_or_admin());

-- Table 2: site_progress_photos Policies
DROP POLICY IF EXISTS "site_progress_photos_select" ON public.site_progress_photos;
CREATE POLICY "site_progress_photos_select"
  ON public.site_progress_photos FOR SELECT TO authenticated
  USING (public.can_access_site_progress(site_id));

DROP POLICY IF EXISTS "site_progress_photos_insert" ON public.site_progress_photos;
CREATE POLICY "site_progress_photos_insert"
  ON public.site_progress_photos FOR INSERT TO authenticated
  WITH CHECK (public.can_access_site_progress(site_id));

DROP POLICY IF EXISTS "site_progress_photos_update" ON public.site_progress_photos;
CREATE POLICY "site_progress_photos_update"
  ON public.site_progress_photos FOR UPDATE TO authenticated
  USING (
    public.is_pm_or_admin()
    OR (
      uploaded_by = auth.uid()
      AND public.can_access_site_progress(site_id)
    )
  )
  WITH CHECK (
    public.is_pm_or_admin()
    OR (
      uploaded_by = auth.uid()
      AND public.can_access_site_progress(site_id)
    )
  );

DROP POLICY IF EXISTS "site_progress_photos_delete" ON public.site_progress_photos;
CREATE POLICY "site_progress_photos_delete"
  ON public.site_progress_photos FOR DELETE TO authenticated
  USING (public.is_pm_or_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 7: Private Supabase Storage Bucket & Storage Object RLS Policies
-- ─────────────────────────────────────────────────────────────────────────────

-- Bucket creation / idempotent reconfiguration.
--
-- ON CONFLICT (id) DO UPDATE behavior:
--   If the bucket 'site-progress-photos' already exists (from a previous migration attempt
--   or manual creation), this statement updates its configuration to match the specification:
--     - Enforces public = false (private bucket, no direct public URL access).
--     - Sets the 10 MB per-file size limit.
--     - Restricts accepted MIME types to the approved image set.
--
-- ⚠ PRE-DEPLOYMENT VERIFICATION REQUIREMENT:
--   Before executing this migration, run the read-only verification query in
--   supabase/migrations/20261120_site_progress_photos_PRECHECK.sql to inspect the
--   current bucket state. If the bucket exists with public = true or different
--   size limits, review the impact before proceeding.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'site-progress-photos',
  'site-progress-photos',
  false,
  10485760,   -- 10 MB limit per image file
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
ON CONFLICT (id) DO UPDATE SET
  public             = false,
  file_size_limit    = 10485760,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic'];

-- Storage Path Security Helper:
-- Validates storage path against actual existing site_progress_updates record
-- and confirms caller's verified site membership.
CREATE OR REPLACE FUNCTION public.can_access_progress_storage_object(object_path TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, storage
STABLE
AS $$
DECLARE
  v_parts       TEXT[];
  v_site_id     UUID;
  v_progress_id UUID;
  v_filename    TEXT;
BEGIN
  IF NOT public.is_active_user() THEN
    RETURN FALSE;
  END IF;

  -- Expected path convention: sites/{site_id}/{progress_id}/{filename}
  -- Minimum 4 segments; parts[1]='sites', parts[2]=site_id, parts[3]=progress_id, parts[4]=filename
  v_parts := string_to_array(object_path, '/');
  IF array_length(v_parts, 1) < 4 OR v_parts[1] != 'sites' THEN
    RETURN FALSE;
  END IF;

  -- Filename (4th segment onward) must be non-empty
  v_filename := array_to_string(v_parts[4:array_length(v_parts, 1)], '/');
  IF v_filename IS NULL OR TRIM(v_filename) = '' THEN
    RETURN FALSE;
  END IF;

  BEGIN
    v_site_id     := v_parts[2]::uuid;
    v_progress_id := v_parts[3]::uuid;
  EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
  END;

  -- Validate storage path against actual progress record:
  -- The parent progress update MUST exist with this site_id and progress_id
  IF NOT EXISTS (
    SELECT 1 FROM public.site_progress_updates
    WHERE id = v_progress_id AND site_id = v_site_id
  ) THEN
    RETURN FALSE;
  END IF;

  -- PM and Admin have global access across all sites.
  -- VERIFICATION CONFIRMED: public.is_pm_or_admin() explicitly queries user_profiles for
  -- `role IN ('admin', 'projectManager') AND status = 'active'`. Disabled users are strictly rejected.
  -- In addition, the initial guard `IF NOT public.is_active_user()` rejects inactive callers upfront.
  IF public.is_pm_or_admin() THEN
    RETURN TRUE;
  END IF;

  -- Non-PM/Admin callers must have active membership on this site
  RETURN public.has_site_access(v_site_id);
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_progress_storage_object(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_progress_storage_object(TEXT) TO authenticated;

-- Storage Object RLS Policies (storage.objects)

-- SELECT: Authenticated users with verified site access can read/create signed photo URLs
DROP POLICY IF EXISTS "site_progress_storage_select" ON storage.objects;
CREATE POLICY "site_progress_storage_select"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'site-progress-photos'
    AND public.can_access_progress_storage_object(name)
  );

-- INSERT: Authenticated users with verified site access can upload photos to existing progress records
DROP POLICY IF EXISTS "site_progress_storage_insert" ON storage.objects;
CREATE POLICY "site_progress_storage_insert"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'site-progress-photos'
    AND public.can_access_progress_storage_object(name)
  );

-- ⚠ Direct authenticated DELETE on storage.objects is strictly REMOVED:
-- Authenticated users (including PM and Admin) CANNOT delete storage objects directly via Storage API.
-- Photo deletion is executed by deleting the site_progress_photos record (or cascading from site_progress_updates).
-- The BEFORE DELETE trigger queues the storage path into storage_cleanup_queue, and the trusted
-- service-role worker executes physical deletion via the official Storage API, bypassing Storage RLS.
DROP POLICY IF EXISTS "site_progress_storage_delete" ON storage.objects;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 8: Cleanup Queue Retention Guidance
-- ─────────────────────────────────────────────────────────────────────────────
-- 'completed' rows are intentionally retained for audit purposes (confirms which files
-- were physically deleted and when). They may be safely purged after 30 days.
--
-- ⚠ 'failed' rows are NEVER purged automatically. Failed jobs indicate systematic
-- errors, bucket configuration issues, or persistent failures that require manual review.
--
-- Recommended retention: 30 days for completed tasks only. Run periodically via pg_cron:
--
--   DELETE FROM public.storage_cleanup_queue
--   WHERE  status = 'completed'
--     AND  processed_at < NOW() - INTERVAL '30 days';
--
-- Optional pg_cron schedule (requires pg_cron extension):
--
--   SELECT cron.schedule(
--     'purge-completed-cleanup-queue-rows',
--     '0 3 * * *',   -- daily at 03:00
--     $$
--     DELETE FROM public.storage_cleanup_queue
--     WHERE  status = 'completed'
--       AND  processed_at < NOW() - INTERVAL '30 days';
--     $$
--   );
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 9: Cleanup Worker Contract Summary
-- ─────────────────────────────────────────────────────────────────────────────
-- Full specification: supabase/STORAGE_CLEANUP_WORKER.md
-- Edge Function:      supabase/functions/cleanup-storage-queue/index.ts
--
-- Workflow:
--   1. Worker calls: SELECT * FROM public.claim_cleanup_jobs(50, '10 minutes'::INTERVAL);
--      This atomically:
--        a) Resets stale 'processing' jobs (lease > 10 min old), increments attempts,
--           sets status to 'failed' if max_attempts reached, otherwise 'pending', and clears claim_token.
--        b) Claims up to 50 eligible (pending/failed, attempts < max_attempts) jobs
--           using FOR UPDATE SKIP LOCKED.
--        c) Sets a fresh random claim_token UUID and returns the claimed rows with status = 'processing'.
--
--   2. Worker calls Storage API per bucket group:
--        await supabase.storage.from(bucket_id).remove([...paths]);
--
--   3. On success → UPDATE storage_cleanup_queue SET status = 'completed', claim_token = NULL, processed_at = NOW()
--      WHERE id = job.id AND claim_token = job.claim_token AND status = 'processing'
--   4. On missing/404 error → treat as success (file already gone); mark 'completed'
--   5. On real transient error → increment attempts; set status = 'pending' or 'failed', and clear claim_token
--
-- Operational requirement: Physical deletion is NOT active until the worker is deployed
-- and scheduled. Browser clients have zero direct access to the queue table or the
-- claim function.
-- ─────────────────────────────────────────────────────────────────────────────

COMMIT;
