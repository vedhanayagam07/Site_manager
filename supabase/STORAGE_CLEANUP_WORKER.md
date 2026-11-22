# TSR BUILDERS — STORAGE CLEANUP WORKER SPECIFICATION & IMPLEMENTATION
File: `supabase/STORAGE_CLEANUP_WORKER.md`

> [!WARNING]
> **Operational Status:** Physical file deletion is **NOT** operational until the worker is deployed, scheduled, and verified in staging. The cleanup queue stages deletion requests safely; files remain in storage until the worker runs.

---

## 1. Architectural Overview

Physical deletion of files from object storage (S3 / Supabase Storage) must not be executed via synchronous `DELETE FROM storage.objects` inside PostgreSQL triggers. Direct table mutations on internal storage schemas bypass bucket lifecycle adapters, fail silently on network errors, and leave orphaned objects on cloud storage providers.

### Direct Authenticated Storage DELETE Removed
Direct authenticated `DELETE` on `storage.objects` has been **completely removed** (`site_progress_storage_delete` policy dropped). Authenticated browser users (including Project Managers and Administrators) cannot directly delete objects from the storage bucket via the Storage API.

Instead, deletion is orchestrated via database metadata deletion:
1. A Project Manager or Administrator deletes a photo metadata row (`site_progress_photos`) or the parent progress update (`site_progress_updates`).
2. The `BEFORE DELETE` database trigger `trg_queue_single_progress_photo_cleanup` fires and enqueues the `storage_path` into `storage_cleanup_queue`.
3. The trusted server-side cleanup worker connects with `SUPABASE_SERVICE_ROLE_KEY` (which bypasses Storage RLS entirely) and executes physical file deletion via `supabase.storage.from(bucket_id).remove(paths)`.

### Queue & Worker Flow

```
[User Action: Delete progress update or photo]
              │
              ▼ (ON DELETE CASCADE or direct DELETE)
[BEFORE DELETE trigger on public.site_progress_photos]
              │  fires exactly once per photo
              ▼
[INSERT into public.storage_cleanup_queue]  (status = 'pending')
   ON CONFLICT (bucket_id, storage_path)
   WHERE status IN ('pending', 'processing') DO NOTHING
              │
              ▼ (scheduled cron / manual invoke)
[Edge Function: claim_cleanup_jobs() RPC]
   • Resets stale 'processing' jobs (lease expired)
   • Claims batch with FOR UPDATE SKIP LOCKED
   • Returns claimed rows, sets status = 'processing'
              │
              ▼
[Supabase Storage API: storage.from(bucket).remove([paths])]
              │
        ┌─────┴──────────────────────┐
     Success                     Failure
  (or 404/missing)           (transient error)
        │                           │
        ▼                           ▼
[status = 'completed']    [attempts++; status = 'pending']
                          [status = 'failed' if attempts >= max_attempts]
```

---

## 2. Queue Table Schema

```sql
CREATE TABLE IF NOT EXISTS public.storage_cleanup_queue (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id             TEXT        NOT NULL DEFAULT 'site-progress-photos',
  storage_path          TEXT        NOT NULL,
  attempts              INTEGER     NOT NULL DEFAULT 0,
  max_attempts          INTEGER     NOT NULL DEFAULT 5,
  status                TEXT        NOT NULL DEFAULT 'pending'
                                    CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  last_error            TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processing_started_at TIMESTAMPTZ,          -- set when a worker claims a job; used for lease timeout
  claim_token           UUID,                 -- fresh UUID generated on claim; prevents expired-lease updates
  processed_at          TIMESTAMPTZ
);
```

### Indexes

| Index | Purpose |
|---|---|
| `idx_storage_cleanup_queue_active_dedup` | Partial unique index on `(bucket_id, storage_path)` where `status IN ('pending', 'processing')` — prevents duplicate active entries |
| `idx_storage_cleanup_queue_worker_poll` | Accelerates worker poll queries filtering on `(status, attempts, created_at)` |
| `idx_storage_cleanup_queue_stale_processing` | Accelerates lease-timeout reclaim scan on `(status, processing_started_at)` where `status = 'processing'` |

---

## 3. Minimum Required Permissions & Grant vs. RLS Distinction

> [!IMPORTANT]
> **Table-Level Grants vs. RLS Policies:**
> In PostgreSQL and Supabase Storage, permissions operate at two distinct layers:
> 1. **Table-Level Privileges (`GRANT` / `REVOKE`):** Determine if a database role has baseline SQL command capability on the table (`storage.objects`). In standard Supabase configurations, the Storage extension grants table-level commands to `authenticated`.
> 2. **Row-Level Security (RLS) Policies:** Filter and gate which specific rows/objects the role can access.
> 
> Direct authenticated DELETE on `storage.objects` is eliminated at the RLS policy layer by dropping `site_progress_storage_delete`. Browser clients cannot delete progress photo objects because no permissive policy exists for DELETE. Physical deletion is executed exclusively by the trusted worker using the internal `service_role` key, which carries PostgreSQL `BYPASSRLS` attributes and operates via the official Supabase Storage API.

| Role / Actor | Resource / Table Access | Operations | Mechanism |
|---|---|---|---|
| `anon` | `storage_cleanup_queue`<br>`storage.objects` | **REVOKED** | `REVOKE ALL` + RLS |
| `authenticated` (browsers) | `storage_cleanup_queue` | **REVOKED** | `REVOKE ALL` + RLS |
| `authenticated` (browsers) | `storage.objects` (DELETE) | **NO POLICY** | Direct storage DELETE RLS policy removed (`DROP POLICY`) |
| DB triggers (`queue_single_progress_photo_cleanup`) | `storage_cleanup_queue` (INSERT) | Stages cleanup tasks | `SECURITY DEFINER` running as DB owner |
| **Service-role cleanup worker** | `storage_cleanup_queue`: SELECT, INSERT, UPDATE<br>`storage.objects`: Full bypass | Poll queue; claim jobs; mark completed/failed; delete files | `GRANT SELECT, INSERT, UPDATE … TO service_role`; Service role key bypasses Storage RLS |
| `claim_cleanup_jobs()` RPC | EXECUTE | Atomic job claim with `FOR UPDATE SKIP LOCKED` | `GRANT EXECUTE … TO service_role`; `REVOKE … FROM authenticated, anon` |

```sql
-- Grants applied by migration:
GRANT SELECT, INSERT, UPDATE ON public.storage_cleanup_queue TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_cleanup_jobs(INTEGER, INTERVAL) TO service_role;
REVOKE ALL ON FUNCTION public.claim_cleanup_jobs(INTEGER, INTERVAL) FROM PUBLIC, anon, authenticated;
```

---

## 4. Atomic Job Claiming: `public.claim_cleanup_jobs()`

### Why an RPC instead of raw PostgREST queries?

PostgREST cannot issue `SELECT ... FOR UPDATE SKIP LOCKED` through its standard REST interface. If the worker attempts locking through separate REST calls (fetch → update), there is an unavoidable race window where two concurrent workers claim the same rows. The `claim_cleanup_jobs()` SECURITY DEFINER function closes this window by executing the full claim inside a single server-side transaction.

### Function signature

```sql
CREATE OR REPLACE FUNCTION public.claim_cleanup_jobs(
  p_batch_size    INTEGER  DEFAULT 50,
  p_lease_timeout INTERVAL DEFAULT '10 minutes'::INTERVAL
)
RETURNS SETOF public.storage_cleanup_queue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
```

### What it does atomically

1. **Parameter validation:** Validates `p_batch_size` (1–500) and `p_lease_timeout` (1 minute–24 hours).
2. **Reclaim stale jobs:** Any row in `'processing'` status whose `processing_started_at` is older than `p_lease_timeout` has its `attempts` incremented by 1. If `attempts >= max_attempts`, its status becomes `'failed'`; otherwise, it returns to `'pending'`. `claim_token` is set to `NULL` and `processing_started_at` is reset to `NULL`. This prevents crashing workers from retrying indefinitely.
3. **Claim eligible jobs:** Selects up to `p_batch_size` rows where `status IN ('pending', 'failed')` and `attempts < max_attempts`, ordered by `created_at ASC`, using `FOR UPDATE SKIP LOCKED`. Sets `status = 'processing'`, `processing_started_at = NOW()`, and `claim_token = gen_random_uuid()`.
4. **Returns claimed rows** — the worker processes exactly these rows, retaining the `claim_token`.

### Edge Function usage & Lease Protection

```typescript
const { data: claimedJobs, error } = await supabase.rpc("claim_cleanup_jobs", {
  p_batch_size: 50,
  p_lease_timeout: "10 minutes",
});
```

When marking a job completed or retrying, the worker discriminates between three distinct outcomes:
1. `"updated"`: Database row was modified successfully while holding the lease.
2. `"lost_lease"`: Update affected 0 rows because the lease expired and another worker reclaimed the job.
3. `"database_error"`: PostgREST/network error occurred. **Database errors are NEVER counted as lost leases.**

```typescript
// markCompleted / markRetry return JobUpdateResult: "updated" | "lost_lease" | "database_error"
const outcome = await markCompleted(supabase, job);
if (outcome === "updated") {
  completedCount++;
} else if (outcome === "lost_lease") {
  lostLeasesCount++;
} else if (outcome === "database_error") {
  databaseErrorsCount++;
}
```

A retry is logged as scheduled ONLY when the database confirms the row was updated to `'pending'`.
If any failed jobs, lost leases, or database errors occur, the response returns `status: "partial"`. Otherwise, it returns `status: "success"`.

---

## 5. Crashed Worker Recovery & Lease Ownership

If a worker invocation crashes, is killed, or times out after claiming jobs but before marking them `completed`, those jobs remain in `'processing'` status until the lease expires.

**Recovery mechanism:** `claim_cleanup_jobs()` resets stale `'processing'` jobs at the start of every invocation:
- Increments `attempts = attempts + 1`.
- If `attempts >= max_attempts`, sets `status = 'failed'` so it is NOT automatically retried.
- If `attempts < max_attempts`, sets `status = 'pending'` for future claiming.
- Clears `claim_token = NULL` and `processing_started_at = NULL`.

**Lease Ownership Guarantee:** Even if a slow worker resumes after its lease has expired and been reclaimed by another worker, any subsequent `UPDATE` by the slow worker will fail to match the new `claim_token` (or `status = 'processing'`). This eliminates race conditions and ensures only the current lease holder can update the queue status. Database updates affecting zero rows are detected and reported as lost leases rather than successful completions, while database query errors are tracked separately under `databaseErrors`.

**Batch Execution Budget & Lease Overrun Prevention:**
To ensure batch processing cannot routinely exceed the 10-minute database lease:
- The Edge Function enforces an execution time ceiling of **7.5 minutes (450,000 ms)** (`MAX_EXECUTION_TIME_MS`).
- Before processing each bucket and before each individual file in fallback mode, the worker checks elapsed execution time.
- If the 7.5-minute mark is reached, processing halts immediately.
- Any claimed jobs that were not yet processed are **gracefully released** back to `'pending'` (`releaseUnprocessedJobs`) with `claim_token = null` and `processing_started_at = null`. This avoids holding jobs until the 10-minute lease expires and avoids burning a failure attempt.
- The invocation returns `status: "partial"` with `releasedEarly` reporting the count of deferred jobs.

---

## 6. Missing / Already-Deleted File Handling

The Supabase Storage API's `remove()` method does not reliably raise an error when a file is already absent (the behaviour varies by underlying storage provider). The worker applies this rule:

> If the error message contains any of `not found`, `nosuchkey`, `does not exist`, `not_found`, or `404` **AND** does NOT contain `bucket`, `unauthorized`, `forbidden`, `401`, or `403` → treat the job as **completed**. The file is physically gone; there is nothing left to delete.

Bucket-not-found, authentication failures, and permission errors are treated as genuine system errors and trigger retries or alerting, not silent completion.

---

## 7. Deduplication Guarantee & 1:1 Storage Object Uniqueness

### 1:1 Mapping Guarantee
`site_progress_photos` enforces `CONSTRAINT site_progress_photos_storage_path_uniq UNIQUE (storage_path)`.
One Storage object must correspond to exactly one photo metadata record. This eliminates duplicate references to the same storage path and prevents premature file deletion if one metadata row is deleted while another still references it.

### Queue Deduplication
When a progress update is deleted:

1. `ON DELETE CASCADE` deletes all child `site_progress_photos` rows.
2. `BEFORE DELETE` trigger `trg_queue_single_progress_photo_cleanup` fires **exactly once** per deleted photo row.
3. The parent trigger on `site_progress_updates` is **deliberately absent** to prevent double-queueing.
4. Even with concurrent deletions, the partial unique index ensures only one active queue entry per path:

```sql
CREATE UNIQUE INDEX idx_storage_cleanup_queue_active_dedup
  ON public.storage_cleanup_queue (bucket_id, storage_path)
  WHERE status IN ('pending', 'processing');
```

Combined with `ON CONFLICT … DO NOTHING`, each physical file is queued at most once per active lifecycle.

---

## 8. Audit Attribution Preservation (ON DELETE RESTRICT)

Audit attribution foreign keys in the schema:
- `site_progress_updates.created_by` → `REFERENCES public.user_profiles(id) ON DELETE RESTRICT`
- `site_progress_updates.feedback_by` → `REFERENCES public.user_profiles(id) ON DELETE RESTRICT`
- `site_progress_photos.uploaded_by` → `REFERENCES public.user_profiles(id) ON DELETE RESTRICT`

Audit history can never be silently nulled out or orphaned. If a user leaves the organization or is offboarded, their user account should be **deactivated** (`status = 'disabled'` in `user_profiles`) rather than physically deleted while audit records reference them.

---

## 9. Queue Retention Policy

| Status | Retention | Rationale |
|---|---|---|
| `pending` | Indefinite until processed | Active work item |
| `processing` | Until completed, failed, or lease expires | Active claim |
| `completed` | 30 days (recommended) | Audit trail of deleted files; safe to purge |
| `failed` | **Indefinite (manual review)** | **Do NOT automatically purge.** Requires investigation or explicit resolution |

**Recommended retention sweep (run via pg_cron or manually):**

```sql
DELETE FROM public.storage_cleanup_queue
WHERE  status = 'completed'
  AND  processed_at < NOW() - INTERVAL '30 days';
```

**Optional pg_cron schedule:**

```sql
SELECT cron.schedule(
  'purge-completed-cleanup-queue-rows',
  '0 3 * * *',   -- daily at 03:00 UTC
  $$
  DELETE FROM public.storage_cleanup_queue
  WHERE  status = 'completed'
    AND  processed_at < NOW() - INTERVAL '30 days';
  $$
);
```

---

## 10. Bucket ON CONFLICT Behavior

The migration uses:

```sql
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('site-progress-photos', 'site-progress-photos', false, 10485760,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic'])
ON CONFLICT (id) DO UPDATE SET
  public             = false,
  file_size_limit    = 10485760,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic'];
```

**Effect if bucket already exists:** The `DO UPDATE SET` clause enforces the specification:
- Ensures `public = false` even if the bucket was manually created as public.
- Resets `file_size_limit` to exactly 10 MB.
- Resets `allowed_mime_types` to the approved set.

**Risk:** If the bucket was previously configured with a larger size limit or additional MIME types that existing uploads depend on, applying this migration narrows those limits. Run the pre-deployment verification query before execution.

**MIME Type & Header Validation Disclaimer:**
`storage.buckets.allowed_mime_types` validates the client-supplied HTTP `Content-Type` request header and matching file extension during file upload. **It does NOT perform server-side binary magic-number validation, deep image decoding, or file-content byte inspection.** Database triggers compare `file_size` and `mime_type` against storage metadata for inventory consistency where available, but neither the storage bucket configuration nor database metadata triggers constitute byte-level binary validation.

---

## 11. Deployment Checklist

> [!IMPORTANT]
> Complete every step below **in staging** before applying to production.

1. **Apply database migration:**
   ```
   supabase db push
   ```
   or execute `20261120_site_progress_photos_PROPOSAL.sql` in the Supabase SQL Editor.

2. **Run pre-deployment verification** (read-only, see `20261120_site_progress_photos_PRECHECK.sql`):
   - Confirm the bucket exists or does not exist and what its current settings are.
   - Confirm `claim_cleanup_jobs` is present and callable from service_role.
   - Confirm `storage_cleanup_queue` grants are correct.

3. **Deploy the Edge Function & Configure Secrets:**
   ```bash
   # Set dedicated worker invocation secret (distinct from service_role key)
   supabase secrets set CLEANUP_WORKER_SECRET=your-random-32-character-secret

   # Deploy edge function with gateway JWT verification disabled:
   supabase functions deploy cleanup-storage-queue --no-verify-jwt
   ```
   *Note on Gateway Auth:* Because the scheduled cron caller provides a dedicated custom worker secret (`CLEANUP_WORKER_SECRET`) rather than an end-user Supabase JWT, Supabase's API gateway JWT verification must be disabled for this function (`verify_jwt = false` in `supabase/config.toml` or `--no-verify-jwt` CLI flag). The function enforces exact Bearer-token validation internally:
   `authHeader !== "Bearer " + workerSecret`
   Requests without this exact header are rejected with 401. `SUPABASE_SERVICE_ROLE_KEY` is strictly prohibited as a caller authentication fallback and is used exclusively for internal database operations.

4. **Configure the cron trigger** (pg_cron, every 15 minutes, using Supabase Vault):
   ```sql
   -- Store the worker secret in Supabase Vault (protected secret store):
   SELECT vault.create_secret(
     'your-random-32-character-secret',
     'cleanup_worker_secret',
     'Bearer token for cleanup-storage-queue Edge Function'
   );

   -- Schedule cron job reading directly from vault.decrypted_secrets:
   SELECT cron.schedule(
     'purge-orphaned-progress-photos',
     '*/15 * * * *',
     $$
     SELECT net.http_post(
       url     := 'https://yrgsgjiqijccunisqzqz.supabase.co/functions/v1/cleanup-storage-queue',
       headers := jsonb_build_object(
         'Content-Type',  'application/json',
         'Authorization', 'Bearer ' || (
           SELECT decrypted_secret
           FROM vault.decrypted_secrets
           WHERE name = 'cleanup_worker_secret'
           LIMIT 1
         )
       )
     );
     $$
   );
   ```

5. **Stage a test deletion:** Upload a photo, delete the progress update, then manually trigger the worker and verify:
   - Queue row transitions: `pending` → `processing` → `completed`
   - Response payload reports: `{ status: "success", totalClaimed: 1, completed: 1, retried: 0, failed: 0, lostLeases: 0, databaseErrors: 0 }`
   - File is physically absent from the bucket afterward.

6. **Only after step 5 passes:** Declare physical deletion operational.
