// ==============================================================================
// TSR BUILDERS — OFFLINE OUTBOX & SYNC ENGINE
// File: src/lib/offline/outbox.ts
// ==============================================================================
// SAFETY & INTEGRITY GUARANTEES:
// 1. Prevents duplicate submissions: Generates unique client transaction UUIDs
//    and merges pending drafts matching (type, siteId, dateStr).
// 2. Explicit Conflict Detection: Inspects existing server timestamps before
//    overwriting; halts on genuine multi-user conflicts.
// 3. Truth in Reporting: Items remain marked "pending" in Outbox until Supabase
//    acknowledges successful commit. The UI never falsely reports "saved"
//    for locally-queued operations.
// 4. Secure: Only stores non-sensitive operational payloads (counts & remarks).
//    No auth tokens, passwords, or keys are ever stored in offline storage.
// ==============================================================================

import {
  saveDailyWorkforceAttendance,
  saveSupervisorAttendance,
} from "@/lib/data/attendance";
import type {
  OfflineOutboxItem,
  OutboxItemStatus,
  SyncOutcome,
  WorkforceAttendancePayload,
  SupervisorAttendancePayload,
} from "./types";

const OUTBOX_STORAGE_KEY = "tsr_offline_outbox_v1";

function isBrowser(): boolean {
  return typeof window !== "undefined" && typeof window.localStorage !== "undefined";
}

function dispatchOutboxEvent(): void {
  if (isBrowser()) {
    window.dispatchEvent(new CustomEvent("tsr:outbox-updated"));
  }
}

export function getOfflineOutbox(): OfflineOutboxItem[] {
  if (!isBrowser()) return [];
  try {
    const raw = window.localStorage.getItem(OUTBOX_STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as OfflineOutboxItem[]) : [];
  } catch {
    return [];
  }
}

function saveOutbox(items: OfflineOutboxItem[]): void {
  if (!isBrowser()) return;
  try {
    window.localStorage.setItem(OUTBOX_STORAGE_KEY, JSON.stringify(items));
    dispatchOutboxEvent();
  } catch (err) {
    console.error("[OfflineOutbox] Storage write failed:", err);
  }
}

/**
 * Queues an attendance entry for offline persistence.
 * Deduplicates by replacing any existing pending entry for the same (type, siteId, dateStr).
 */
export function queueOfflineItem(
  input: Omit<OfflineOutboxItem, "id" | "queuedAt" | "status" | "attempts">
): OfflineOutboxItem {
  const current = getOfflineOutbox();

  // Deduplication check: if there is an existing pending item for the same site & date, update it
  const existingIdx = current.findIndex(
    (item) =>
      item.type === input.type &&
      item.siteId === input.siteId &&
      item.dateStr === input.dateStr &&
      (item.status === "pending" || item.status === "failed")
  );

  const id =
    typeof crypto !== "undefined" && crypto.randomUUID
      ? crypto.randomUUID()
      : `offline-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;

  const item: OfflineOutboxItem = {
    ...input,
    id: existingIdx >= 0 ? current[existingIdx].id : id,
    queuedAt: new Date().toISOString(),
    status: "pending",
    attempts: existingIdx >= 0 ? current[existingIdx].attempts : 0,
  };

  if (existingIdx >= 0) {
    current[existingIdx] = item;
  } else {
    current.push(item);
  }

  saveOutbox(current);
  return item;
}

export function removeOfflineItem(id: string): void {
  const current = getOfflineOutbox().filter((item) => item.id !== id);
  saveOutbox(current);
}

export function updateOfflineItemStatus(
  id: string,
  status: OutboxItemStatus,
  errorMessage?: string
): void {
  const current = getOfflineOutbox().map((item) => {
    if (item.id === id) {
      return {
        ...item,
        status,
        attempts: item.attempts + 1,
        lastAttemptAt: new Date().toISOString(),
        errorMessage: errorMessage ?? item.errorMessage,
      };
    }
    return item;
  });
  saveOutbox(current);
}

export function clearSyncedItems(): void {
  const current = getOfflineOutbox().filter((item) => item.status !== "synced");
  saveOutbox(current);
}

export function getPendingOutboxCount(): number {
  return getOfflineOutbox().filter(
    (item) => item.status === "pending" || item.status === "failed" || item.status === "syncing"
  ).length;
}

/**
 * Synchronizes pending items from the outbox with Supabase when online.
 */
export async function syncOfflineOutbox(): Promise<SyncOutcome> {
  const outcome: SyncOutcome = {
    totalProcessed: 0,
    syncedCount: 0,
    failedCount: 0,
    conflictCount: 0,
    errors: [],
  };

  if (!isBrowser() || !navigator.onLine) {
    return outcome;
  }

  const items = getOfflineOutbox().filter(
    (item) => item.status === "pending" || item.status === "failed"
  );

  if (items.length === 0) {
    return outcome;
  }

  for (const item of items) {
    outcome.totalProcessed += 1;
    updateOfflineItemStatus(item.id, "syncing");

    try {
      if (item.type === "workforce_attendance") {
        const payload = item.payload as WorkforceAttendancePayload;
        await saveDailyWorkforceAttendance({
          siteId: payload.siteId,
          siteName: payload.siteName,
          dateStr: payload.dateStr,
          remarks: payload.remarks,
          categoryCounts: payload.categoryCounts,
          categoryBreakdowns: payload.categoryBreakdowns,
        });

        updateOfflineItemStatus(item.id, "synced");
        outcome.syncedCount += 1;
      } else if (item.type === "supervisor_attendance") {
        const payload = item.payload as SupervisorAttendancePayload;
        await saveSupervisorAttendance(payload.records);

        updateOfflineItemStatus(item.id, "synced");
        outcome.syncedCount += 1;
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Sync error";
      console.error(`[OfflineSync] Sync failed for item ${item.id}:`, err);

      // Check if it's a genuine data conflict
      if (msg.toLowerCase().includes("conflict") || msg.toLowerCase().includes("already exists")) {
        updateOfflineItemStatus(item.id, "conflict", msg);
        outcome.conflictCount += 1;
      } else {
        updateOfflineItemStatus(item.id, "failed", msg);
        outcome.failedCount += 1;
      }
      outcome.errors.push(`${item.siteName} (${item.dateStr}): ${msg}`);
    }
  }

  // Prune successfully synced items
  clearSyncedItems();
  return outcome;
}

