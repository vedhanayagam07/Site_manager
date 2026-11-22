// ==============================================================================
// TSR BUILDERS — OFFLINE SYNC & OUTBOX DEFINITIONS
// File: src/lib/offline/types.ts
// ==============================================================================

export type OutboxItemType =
  | "workforce_attendance"
  | "supervisor_attendance"
  | "named_attendance";

export type OutboxItemStatus =
  | "pending"
  | "syncing"
  | "failed"
  | "synced"
  | "conflict";

export interface WorkforceCategoryCountItem {
  fullDay: number;
  halfDay: number;
}

export interface WorkforceAttendancePayload {
  siteId: string;
  siteName: string;
  dateStr: string;
  remarks: string;
  categoryCounts: Record<string, number>;
  categoryBreakdowns?: Record<string, WorkforceCategoryCountItem>;
  totalWorkforce: number;
  totalManDays?: number;
}

export interface SupervisorAttendancePayload {
  records: Array<{
    supervisorId: string;
    supervisorName: string;
    siteId: string;
    siteName: string;
    dateStr: string;
    status: "Present" | "Absent" | "Half Day" | "Leave";
    remarks?: string;
  }>;
}

export interface OfflineOutboxItem {
  id: string; // Client idempotency UUID
  type: OutboxItemType;
  siteId: string;
  siteName: string;
  dateStr: string;
  queuedAt: string; // ISO
  status: OutboxItemStatus;
  attempts: number;
  lastAttemptAt?: string;
  errorMessage?: string;
  payload: WorkforceAttendancePayload | SupervisorAttendancePayload;
}

export interface SyncOutcome {
  totalProcessed: number;
  syncedCount: number;
  failedCount: number;
  conflictCount: number;
  errors: string[];
}

