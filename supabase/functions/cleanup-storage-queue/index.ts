import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

// ──────────────────────────────────────────────────────────────────────────────
// TSR BUILDERS — Storage Cleanup Worker (Supabase Edge Function)
// File: supabase/functions/cleanup-storage-queue/index.ts
//
// OPERATIONAL STATUS: NOT operational until deployed and scheduled.
//
// Design decisions:
//   - Job claiming uses the SECURITY DEFINER RPC public.claim_cleanup_jobs()
//     instead of raw SQL over PostgREST. This correctly executes FOR UPDATE SKIP
//     LOCKED inside a single atomic server-side transaction, which PostgREST
//     cannot guarantee across separate REST calls.
//   - Stale 'processing' jobs (crashed workers) are automatically reclaimed by
//     claim_cleanup_jobs() via a configurable lease timeout (default: 10 minutes).
//     Expired leases increment the attempt counter; jobs reaching max_attempts transition
//     to 'failed' and are not automatically reclaimed.
//   - Files missing from storage (404 / NoSuchKey) are treated as already deleted
//     and marked 'completed' — not as errors.
//   - Physical Deletion & Storage RLS Bypass: Direct authenticated DELETE on
//     storage.objects is removed. Authenticated users cannot directly delete storage files.
//     Physical file deletion is handled exclusively by this worker using the internal
//     service_role client, which bypasses Storage RLS and removes objects via the official API.
//   - Batch removal is attempted first; on error, falls back to per-file removal
//     so one bad path does not block the whole batch.
//   - Strong Lease Ownership: markCompleted and markRetry strictly require matching
//     id, claim_token, and status='processing'.
//   - Outcome Discrimination: Database errors and lost leases are strictly distinguished.
//     markCompleted and markRetry return "updated" | "lost_lease" | "database_error".
//     Database errors are NEVER counted as lost leases.
//   - Logging: A retry is logged as scheduled ONLY when the database confirms the row
//     was updated to 'pending'.
//   - Metrics & Response: Counters for completed, retried, failed, lostLeases, and
//     databaseErrors are tracked separately. Returns status "partial" if any failures,
//     lost leases, or database errors occurred; "success" otherwise.
//   - Authentication: Strictly requires an exact `Authorization: Bearer <CLEANUP_WORKER_SECRET>`
//     header. SUPABASE_SERVICE_ROLE_KEY is NOT accepted as a fallback for caller auth.
//     SUPABASE_SERVICE_ROLE_KEY is used exclusively for internal Supabase client operations.
//     Requires gateway JWT verification to be disabled for this function (`verify_jwt = false`
//     or `--no-verify-jwt` flag).
//
// Minimum required service_role permissions:
//   - EXECUTE on public.claim_cleanup_jobs(integer, interval)
//   - SELECT, INSERT, UPDATE on public.storage_cleanup_queue
//   - Storage admin on bucket 'site-progress-photos'
// ──────────────────────────────────────────────────────────────────────────────

const BATCH_SIZE = 50;
const LEASE_TIMEOUT = "10 minutes";
// Time Budget: 7.5 minutes (450,000 ms) safety ceiling, well before the 10-minute database lease.
// Guarantees that slow or falling-back per-file operations cannot routinely overrun the lease.
const MAX_EXECUTION_TIME_MS = 7.5 * 60 * 1000;

export type JobUpdateResult = "updated" | "lost_lease" | "database_error";

/** Treat these storage error signals as "file already gone" → mark completed.
 *  Bucket-not-found, auth/permission errors are excluded — these are real errors.
 */
function isMissingOrAlreadyDeleted(msg: string): boolean {
  const lower = msg.toLowerCase();
  // Exclude bucket-not-found, auth/permission errors — these are real errors, not "already deleted"
  if (
    lower.includes("bucket") ||
    lower.includes("unauthorized") ||
    lower.includes("forbidden") ||
    lower.includes("403") ||
    lower.includes("401")
  ) {
    return false;
  }
  return (
    lower.includes("not found") ||
    lower.includes("nosuchkey") ||
    lower.includes("does not exist") ||
    lower.includes("not_found") ||
    lower.includes("404")
  );
}

interface QueueJob {
  id: string;
  bucket_id: string;
  storage_path: string;
  attempts: number;
  max_attempts: number;
  claim_token: string | null;
}

Deno.serve(async (req) => {
  // ── 1. Authorize the invoking caller ───────────────────────────────────────
  // Strictly require CLEANUP_WORKER_SECRET. SUPABASE_SERVICE_ROLE_KEY is NOT a fallback.
  // Note: Dedicated secret usage requires gateway JWT verification to be disabled
  // for this function (`verify_jwt = false` in config.toml or `--no-verify-jwt`).
  const authHeader = req.headers.get("Authorization") ?? "";
  const workerSecret = Deno.env.get("CLEANUP_WORKER_SECRET") ?? "";

  if (!workerSecret || authHeader !== "Bearer " + workerSecret) {
    return jsonResponse({ error: "Unauthorized worker invocation." }, 401);
  }

  // ── 2. Build service-role Supabase client ──────────────────────────────────
  // SUPABASE_SERVICE_ROLE_KEY is used exclusively for internal database operations.
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ── 3. Atomically claim eligible jobs via SECURITY DEFINER RPC ─────────────
  const { data: claimedJobs, error: claimErr } = await supabase.rpc(
    "claim_cleanup_jobs",
    {
      p_batch_size: BATCH_SIZE,
      p_lease_timeout: LEASE_TIMEOUT,
    }
  );

  if (claimErr) {
    console.error("[CleanupWorker] claim_cleanup_jobs RPC failed:", claimErr);
    return jsonResponse({ error: `Failed to claim jobs: ${claimErr.message}` }, 500);
  }

  const jobs: QueueJob[] = claimedJobs ?? [];

  if (jobs.length === 0) {
    return jsonResponse(
      {
        status: "success",
        message: "No pending cleanup tasks.",
        totalClaimed: 0,
        completed: 0,
        retried: 0,
        failed: 0,
        lostLeases: 0,
        databaseErrors: 0,
      },
      200
    );
  }

  console.log(`[CleanupWorker] Claimed ${jobs.length} job(s).`);

  const startTime = Date.now();
  let timeLimitHit = false;
  const processedJobIds = new Set<string>();

  // ── 4. Group jobs by bucket for batch removal ──────────────────────────────
  const bucketMap = new Map<string, QueueJob[]>();
  for (const job of jobs) {
    const list = bucketMap.get(job.bucket_id) ?? [];
    list.push(job);
    bucketMap.set(job.bucket_id, list);
  }

  let completedCount = 0;
  let retriedCount = 0;
  let failedCount = 0;
  let lostLeasesCount = 0;
  let databaseErrorsCount = 0;

  for (const [bucketId, bucketJobs] of bucketMap.entries()) {
    // Check execution deadline before starting a bucket
    if (Date.now() - startTime > MAX_EXECUTION_TIME_MS) {
      console.warn(
        `[CleanupWorker] Approaching execution deadline (${(Date.now() - startTime) / 1000}s). ` +
          "Halting batch processing early to preserve 10-minute lease ownership."
      );
      timeLimitHit = true;
      break;
    }

    // ── 4a. Attempt batch removal for all paths in this bucket ──────────────
    const paths = bucketJobs.map((j) => j.storage_path);

    let batchSucceeded = false;
    let batchError: string | null = null;

    try {
      const { error: removeErr } = await supabase.storage
        .from(bucketId)
        .remove(paths);

      if (!removeErr) {
        batchSucceeded = true;
      } else {
        batchError = removeErr.message;
      }
    } catch (ex: unknown) {
      batchError = ex instanceof Error ? ex.message : "Unknown batch remove error";
    }

    if (batchSucceeded) {
      // All files in this bucket were removed successfully from storage.
      // Mark each job completed in the database.
      for (const job of bucketJobs) {
        processedJobIds.add(job.id);
        const outcome = await markCompleted(supabase, job);
        if (outcome === "updated") {
          completedCount++;
        } else if (outcome === "lost_lease") {
          lostLeasesCount++;
        } else if (outcome === "database_error") {
          databaseErrorsCount++;
        }
      }
      continue;
    }

    // ── 4b. Batch failed — fall back to per-file removal ────────────────────
    console.warn(
      `[CleanupWorker] Batch remove failed for bucket "${bucketId}": ${batchError}. ` +
        `Falling back to per-file removal for ${bucketJobs.length} job(s).`
    );

    for (const job of bucketJobs) {
      // Check execution deadline before processing individual file
      if (Date.now() - startTime > MAX_EXECUTION_TIME_MS) {
        console.warn(
          `[CleanupWorker] Approaching execution deadline during per-file removal (${(Date.now() - startTime) / 1000}s). ` +
            "Halting batch processing early to preserve 10-minute lease ownership."
        );
        timeLimitHit = true;
        break;
      }

      processedJobIds.add(job.id);
      let fileRemoved = false;
      let fileError: string | null = null;

      try {
        const { error: singleErr } = await supabase.storage
          .from(bucketId)
          .remove([job.storage_path]);

        if (!singleErr) {
          fileRemoved = true;
        } else {
          // Treat 404 / missing as already deleted — not a failure
          if (isMissingOrAlreadyDeleted(singleErr.message)) {
            console.info(
              `[CleanupWorker] File already absent (treating as success): ${job.storage_path}`
            );
            fileRemoved = true;
          } else {
            fileError = singleErr.message;
          }
        }
      } catch (ex: unknown) {
        const msg = ex instanceof Error ? ex.message : "Unknown remove exception";
        if (isMissingOrAlreadyDeleted(msg)) {
          console.info(
            `[CleanupWorker] File already absent (exception, treating as success): ${job.storage_path}`
          );
          fileRemoved = true;
        } else {
          fileError = msg;
        }
      }

      if (fileRemoved) {
        const outcome = await markCompleted(supabase, job);
        if (outcome === "updated") {
          completedCount++;
        } else if (outcome === "lost_lease") {
          lostLeasesCount++;
        } else if (outcome === "database_error") {
          databaseErrorsCount++;
        }
      } else {
        const outcome = await markRetry(supabase, job, fileError ?? "Unknown error");
        if (outcome === "updated") {
          if (job.attempts + 1 >= job.max_attempts) {
            failedCount++;
            console.error(
              `[CleanupWorker] Job permanently failed for "${job.storage_path}" ` +
                `(attempt ${job.attempts + 1}/${job.max_attempts}): ${fileError}`
            );
          } else {
            retriedCount++;
            // Only log retry as scheduled when database confirms row update
            console.info(
              `[CleanupWorker] Retry scheduled for "${job.storage_path}" ` +
                `(attempt ${job.attempts + 1}/${job.max_attempts}): ${fileError}`
            );
          }
        } else if (outcome === "lost_lease") {
          lostLeasesCount++;
        } else if (outcome === "database_error") {
          databaseErrorsCount++;
        }
      }
    }

    if (timeLimitHit) {
      break;
    }
  }

  // Gracefully release any unprocessed jobs back to 'pending' so they are not held until lease expiry
  let releasedEarlyCount = 0;
  if (timeLimitHit) {
    const unprocessedJobs = jobs.filter((j) => !processedJobIds.has(j.id));
    if (unprocessedJobs.length > 0) {
      releasedEarlyCount = await releaseUnprocessedJobs(supabase, unprocessedJobs);
      console.info(
        `[CleanupWorker] Gracefully released ${releasedEarlyCount} unprocessed job(s) back to pending.`
      );
    }
  }

  // Return status "partial" when there are failed jobs, database errors, lost leases, or jobs released early
  const status =
    failedCount > 0 || databaseErrorsCount > 0 || lostLeasesCount > 0 || releasedEarlyCount > 0
      ? "partial"
      : "success";

  const summary = {
    status,
    totalClaimed: jobs.length,
    completed: completedCount,
    retried: retriedCount,
    failed: failedCount,
    lostLeases: lostLeasesCount,
    databaseErrors: databaseErrorsCount,
    releasedEarly: releasedEarlyCount,
  };
  console.log("[CleanupWorker] Run complete:", summary);
  return jsonResponse(summary, 200);
});

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Gracefully release unprocessed jobs back to 'pending' when execution time limit is approached.
 *
 * Safety: Each job is released with a per-job conditional update matching all three of:
 *   - id          = job.id
 *   - claim_token = job.claim_token  (the token this worker holds)
 *   - status      = 'processing'
 *
 * This prevents clearing a claim_token that belongs to a different worker instance
 * (e.g. a job whose lease expired and was reclaimed before this worker could release it).
 * Only rows actually updated by this worker are counted in the return value.
 */
async function releaseUnprocessedJobs(
  supabase: ReturnType<typeof createClient>,
  jobsToRelease: QueueJob[]
): Promise<number> {
  if (jobsToRelease.length === 0) return 0;
  let releasedCount = 0;
  for (const job of jobsToRelease) {
    if (!job.claim_token) continue; // No token to match — skip safely
    const { data, error } = await supabase
      .from("storage_cleanup_queue")
      .update({
        status: "pending",
        claim_token: null,
        processing_started_at: null,
      })
      .eq("id", job.id)
      .eq("claim_token", job.claim_token)
      .eq("status", "processing")
      .select("id");

    if (error) {
      console.error(
        `[CleanupWorker] Failed to release job ${job.id} (claim_token: ${job.claim_token}):`,
        error.message
      );
      continue;
    }
    if (data && data.length > 0) {
      releasedCount++;
    } else {
      console.warn(
        `[CleanupWorker] WARN: Could not release job ${job.id} — lease may have been claimed by another worker.`
      );
    }
  }
  return releasedCount;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * Mark a single job completed, only if the claim_token still matches
 * (i.e. the lease has not expired and been reclaimed by another worker).
 * Clears claim_token and processing_started_at.
 *
 * Returns:
 *   - "updated": row updated successfully (lease held)
 *   - "lost_lease": update affected 0 rows (lease expired and claimed by another worker)
 *   - "database_error": database query returned an error (NEVER counted as lost lease)
 */
async function markCompleted(
  supabase: ReturnType<typeof createClient>,
  job: QueueJob
): Promise<JobUpdateResult> {
  const { data, error } = await supabase
    .from("storage_cleanup_queue")
    .update({
      status: "completed",
      claim_token: null,
      last_error: null,
      processed_at: new Date().toISOString(),
      processing_started_at: null,
    })
    .eq("id", job.id)
    .eq("claim_token", job.claim_token)
    .eq("status", "processing")
    .select("id");

  if (error) {
    console.error(
      `[CleanupWorker] markCompleted failed (database error) for job ${job.id}:`,
      error.message
    );
    return "database_error";
  }

  if (!data || data.length === 0) {
    console.warn(
      `[CleanupWorker] WARN: Lease lost for job ${job.id} — skipped markCompleted`
    );
    return "lost_lease";
  }

  return "updated";
}

/**
 * Schedule a job for retry (or mark it failed if max_attempts exhausted),
 * only if the claim_token still matches.
 * Clears claim_token and processing_started_at.
 *
 * Returns:
 *   - "updated": row updated successfully (lease held)
 *   - "lost_lease": update affected 0 rows (lease expired and claimed by another worker)
 *   - "database_error": database query returned an error (NEVER counted as lost lease)
 */
async function markRetry(
  supabase: ReturnType<typeof createClient>,
  job: QueueJob,
  errorMsg: string
): Promise<JobUpdateResult> {
  const nextAttempts = job.attempts + 1;
  const newStatus = nextAttempts >= job.max_attempts ? "failed" : "pending";

  const { data, error } = await supabase
    .from("storage_cleanup_queue")
    .update({
      attempts: nextAttempts,
      claim_token: null,
      last_error: errorMsg,
      status: newStatus,
      processed_at: new Date().toISOString(),
      processing_started_at: null,
    })
    .eq("id", job.id)
    .eq("claim_token", job.claim_token)
    .eq("status", "processing")
    .select("id");

  if (error) {
    console.error(
      `[CleanupWorker] markRetry failed (database error) for job ${job.id}:`,
      error.message
    );
    return "database_error";
  }

  if (!data || data.length === 0) {
    console.warn(
      `[CleanupWorker] WARN: Lease lost for job ${job.id} — skipped markRetry`
    );
    return "lost_lease";
  }

  return "updated";
}
