import { createClient } from "@/lib/supabase/client";
import type { ActivityLogRecord } from "@/types/database";

export interface LogActivityParams {
  action: string;
  module: string;
  description?: string;
  oldValue?: string;
  newValue?: string;
}

/**
 * Append an entry to public.activity_logs.
 * Mirrors Flutter's ActivityLogService: never throws so caller workflows remain resilient.
 */
export async function logActivity({
  action,
  module,
  description,
  oldValue,
  newValue,
}: LogActivityParams): Promise<void> {
  try {
    const supabase = createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) return;

    let userName: string = user.email ?? "Unknown";
    let role: string | null = null;

    try {
      const { data: profile } = await supabase
        .from("user_profiles")
        .select("name, role")
        .eq("id", user.id)
        .maybeSingle();

      if (profile) {
        if (profile.name && String(profile.name).trim().length > 0) {
          userName = String(profile.name);
        }
        role = profile.role ?? null;
      }
    } catch {
      // Fallback to auth email if profile lookup fails
    }

    await supabase.from("activity_logs").insert({
      user_id: user.id,
      user_name: userName,
      role,
      action,
      module,
      old_value: oldValue ?? null,
      new_value: newValue ?? null,
      description: description ?? null,
    });
  } catch (err) {
    console.warn("[ActivityLog] Failed to write log:", err);
  }
}

export interface FetchActivityLogsFilter {
  searchQuery?: string;
  moduleFilter?: string;
  fromDate?: string; // YYYY-MM-DD
  toDate?: string; // YYYY-MM-DD
  limit?: number;
  offset?: number;
}

export async function fetchActivityLogs(
  filters: FetchActivityLogsFilter = {}
): Promise<ActivityLogRecord[]> {
  const supabase = createClient();
  const limit = filters.limit ?? 50;
  const offset = filters.offset ?? 0;

  let query = supabase
    .from("activity_logs")
    .select("*")
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (filters.moduleFilter && filters.moduleFilter !== "All") {
    query = query.eq("module", filters.moduleFilter);
  }
  if (filters.fromDate) {
    query = query.gte("created_at", `${filters.fromDate}T00:00:00.000Z`);
  }
  if (filters.toDate) {
    query = query.lte("created_at", `${filters.toDate}T23:59:59.999Z`);
  }

  const { data, error } = await query;
  if (error) throw error;

  let logs = (data ?? []) as ActivityLogRecord[];
  if (filters.searchQuery && filters.searchQuery.trim().length > 0) {
    const q = filters.searchQuery.trim().toLowerCase();
    logs = logs.filter(
      (log) =>
        (log.action ?? "").toLowerCase().includes(q) ||
        (log.user_name ?? "").toLowerCase().includes(q) ||
        (log.description ?? "").toLowerCase().includes(q) ||
        (log.module ?? "").toLowerCase().includes(q)
    );
  }

  return logs;
}

