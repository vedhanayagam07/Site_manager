import { createClient } from "@/lib/supabase/client";
import { logActivity } from "@/lib/data/activity-logs";
import type {
  AttendanceStatus,
  DailyWorkforceAttendanceRecord,
  DailyWorkforceCategoryCount,
  DailyWorkforceCountRecord,
  SiteAttendanceRecord,
  SupervisorAttendanceRecord,
  SupervisorAttendanceStatus,
  UserProfile,
} from "@/types/database";

export async function fetchAttendanceByDate(
  dateStr: string,
  siteId?: string
): Promise<SiteAttendanceRecord[]> {
  const supabase = createClient();
  let query = supabase
    .from("site_attendance")
    .select("*, workers(name, role), sites(name)")
    .eq("attendance_date", dateStr)
    .order("created_at", { ascending: false });

  if (siteId) {
    query = query.eq("site_id", siteId);
  }

  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as SiteAttendanceRecord[];
}

export async function fetchAttendanceRange(
  startDate: string,
  endDate?: string,
  options?: { siteId?: string; workerId?: string }
): Promise<SiteAttendanceRecord[]> {
  const supabase = createClient();
  let query = supabase
    .from("site_attendance")
    .select("*, workers(name, role), sites(name)")
    .gte("attendance_date", startDate)
    .order("attendance_date", { ascending: false });

  if (endDate) {
    query = query.lte("attendance_date", endDate);
  }
  if (options?.siteId) {
    query = query.eq("site_id", options.siteId);
  }
  if (options?.workerId) {
    query = query.eq("worker_id", options.workerId);
  }

  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as SiteAttendanceRecord[];
}

export interface UpsertAttendanceRow {
  worker_id: string;
  site_id: string;
  attendance_date: string;
  status: AttendanceStatus;
}

export async function upsertSiteAttendance(
  records: UpsertAttendanceRow[],
  siteName: string,
  dateStr: string
): Promise<void> {
  if (records.length === 0) return;
  const supabase = createClient();
  const { error } = await supabase.from("site_attendance").upsert(records);
  if (error) throw error;

  await logActivity({
    action: "Attendance Saved",
    module: "Attendance",
    description: `Saved attendance for ${siteName} on ${dateStr} (${records.length} staff)`,
  });
}

export async function correctAttendanceStatus(
  recordId: string,
  newStatus: AttendanceStatus,
  workerName: string,
  oldStatus: string
): Promise<void> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("site_attendance")
    .update({ status: newStatus })
    .eq("id", recordId)
    .select("id");

  if (error) throw error;
  if (!data || data.length === 0) {
    throw new Error(
      "Permission denied or record not found. Attendance correction was blocked by database policy."
    );
  }

  await logActivity({
    action: "Attendance Corrected",
    module: "Attendance",
    description: `Corrected attendance of ${workerName} to ${newStatus}`,
    oldValue: oldStatus,
    newValue: newStatus,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Daily Workforce Category Counts (Additive Table: public.daily_workforce_counts)
// Gracefully detects whether the approved migration has been applied.
// ─────────────────────────────────────────────────────────────────────────────

export interface WorkforceCountsResult {
  tableReady: boolean;
  records: DailyWorkforceCountRecord[];
}

export async function fetchDailyWorkforceCounts(
  dateStr: string,
  siteId?: string
): Promise<WorkforceCountsResult> {
  const supabase = createClient();
  let query = supabase
    .from("daily_workforce_counts")
    .select("*, sites(name)")
    .eq("attendance_date", dateStr)
    .order("category", { ascending: true });

  if (siteId) {
    query = query.eq("site_id", siteId);
  }

  const { data, error } = await query;

  if (error) {
    // 42P01 (undefined_table) or PostgREST PGRST205 (table not in schema cache)
    const code = (error as { code?: string }).code ?? "";
    if (
      code === "42P01" ||
      code === "PGRST205" ||
      error.message.toLowerCase().includes("does not exist") ||
      error.message.toLowerCase().includes("schema cache")
    ) {
      return { tableReady: false, records: [] };
    }
    throw error;
  }

  return {
    tableReady: true,
    records: (data ?? []) as DailyWorkforceCountRecord[],
  };
}

export async function upsertDailyWorkforceCounts(
  siteId: string,
  siteName: string,
  dateStr: string,
  entries: Array<{ category: string; count: number; notes?: string }>
): Promise<void> {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const rows = entries.map((e) => ({
    site_id: siteId,
    attendance_date: dateStr,
    category: e.category.trim(),
    count: Math.max(0, Math.floor(e.count)),
    notes: e.notes?.trim() || null,
    recorded_by: user?.id ?? null,
    updated_at: new Date().toISOString(),
  }));

  const { error } = await supabase
    .from("daily_workforce_counts")
    .upsert(rows, { onConflict: "site_id,attendance_date,category" });

  if (error) throw error;

  const totalHeadcount = rows.reduce((sum, r) => sum + r.count, 0);
  await logActivity({
    action: "Workforce Count Saved",
    module: "Attendance",
    description: `Recorded daily workforce for ${siteName} on ${dateStr} (${totalHeadcount} total workers across ${rows.filter((r) => r.count > 0).length} trades)`,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// MODULE A: DAILY WORKFORCE ATTENDANCE (Header & Detail Category Counts)
// ─────────────────────────────────────────────────────────────────────────────

export interface DailyWorkforceAttendanceResult {
  tableReady: boolean;
  record: DailyWorkforceAttendanceRecord | null;
}

export async function fetchDailyWorkforceAttendance(
  dateStr: string,
  siteId: string
): Promise<DailyWorkforceAttendanceResult> {
  if (!siteId) return { tableReady: true, record: null };
  const supabase = createClient();

  // Try fetching from the proposed daily_workforce_attendance table
  const { data, error } = await supabase
    .from("daily_workforce_attendance")
    .select("*, sites(name), category_counts:daily_workforce_category_counts(*)")
    .eq("site_id", siteId)
    .eq("attendance_date", dateStr)
    .maybeSingle();

  if (error) {
    const code = (error as { code?: string }).code ?? "";
    if (
      code === "42P01" ||
      code === "PGRST205" ||
      error.message.toLowerCase().includes("does not exist") ||
      error.message.toLowerCase().includes("schema cache")
    ) {
      // Check fallback table daily_workforce_counts
      const fallback = await fetchDailyWorkforceCounts(dateStr, siteId);
      if (fallback.tableReady && fallback.records.length > 0) {
        const total = fallback.records.reduce((sum, r) => sum + (r.count || 0), 0);
        const reconstructed: DailyWorkforceAttendanceRecord = {
          id: fallback.records[0]?.id || "fallback-id",
          site_id: siteId,
          attendance_date: dateStr,
          remarks: fallback.records.find((r) => r.notes)?.notes ?? null,
          total_workforce: total,
          total_man_days: total,
          created_by: fallback.records[0]?.recorded_by ?? null,
          category_counts: fallback.records.map((r) => ({
            id: r.id,
            attendance_id: r.id,
            site_id: r.site_id,
            category: r.category,
            count: r.count,
            full_day_count: r.count,
            half_day_count: 0,
          })),
        };
        return { tableReady: true, record: reconstructed };
      }
      return { tableReady: fallback.tableReady, record: null };
    }
    throw error;
  }

  return {
    tableReady: true,
    record: data as DailyWorkforceAttendanceRecord | null,
  };
}

export async function fetchDailyWorkforceAttendanceRange(
  startDate: string,
  endDate: string,
  siteId?: string
): Promise<DailyWorkforceAttendanceRecord[]> {
  const supabase = createClient();
  let query = supabase
    .from("daily_workforce_attendance")
    .select("*, sites(name), category_counts:daily_workforce_category_counts(*)")
    .gte("attendance_date", startDate)
    .lte("attendance_date", endDate)
    .order("attendance_date", { ascending: true });

  if (siteId) {
    query = query.eq("site_id", siteId);
  }

  const { data, error } = await query;
  if (error) {
    const code = (error as { code?: string }).code ?? "";
    if (
      code === "42P01" ||
      code === "PGRST205" ||
      error.message.toLowerCase().includes("does not exist") ||
      error.message.toLowerCase().includes("schema cache")
    ) {
      return [];
    }
    throw error;
  }
  return (data ?? []) as DailyWorkforceAttendanceRecord[];
}

export interface SaveDailyWorkforceAttendancePayload {
  siteId: string;
  siteName: string;
  dateStr: string;
  remarks: string;
  categoryCounts?: Record<string, number>;
  categoryBreakdowns?: Record<string, { fullDay: number; halfDay: number }>;
}

export async function saveDailyWorkforceAttendance(
  payload: SaveDailyWorkforceAttendancePayload
): Promise<void> {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Normalize into standardized category breakdown map
  const breakdowns: Record<string, { fullDay: number; halfDay: number }> = {};
  if (payload.categoryBreakdowns) {
    for (const [cat, val] of Object.entries(payload.categoryBreakdowns)) {
      breakdowns[cat] = {
        fullDay: Math.max(0, Math.floor(val.fullDay || 0)),
        halfDay: Math.max(0, Math.floor(val.halfDay || 0)),
      };
    }
  } else if (payload.categoryCounts) {
    for (const [cat, count] of Object.entries(payload.categoryCounts)) {
      breakdowns[cat] = {
        fullDay: Math.max(0, Math.floor(count || 0)),
        halfDay: 0,
      };
    }
  }

  const totalHeadcount = Object.values(breakdowns).reduce(
    (sum, b) => sum + b.fullDay + b.halfDay,
    0
  );
  const totalManDays = Object.values(breakdowns).reduce(
    (sum, b) => sum + b.fullDay + b.halfDay * 0.5,
    0
  );

  // 1. Save daily_workforce_attendance header
  // Note: The database schema grants authenticated clients INSERT on (site_id, attendance_date, remarks)
  // and UPDATE on (remarks) ONLY. Columns site_id and attendance_date are immutable unique business keys.
  // Using PostgREST's .upsert() places non-granted columns in "DO UPDATE SET", triggering Postgres 42501.
  // Therefore, we check if the header row already exists:
  // - If it exists: UPDATE remarks ONLY.
  // - If it does not exist: INSERT (site_id, attendance_date, remarks).
  let attendanceId: string | null = null;
  const remarksValue = payload.remarks.trim() || null;

  const { data: existingHeader, error: findHeaderError } = await supabase
    .from("daily_workforce_attendance")
    .select("id")
    .eq("site_id", payload.siteId)
    .eq("attendance_date", payload.dateStr)
    .maybeSingle();

  if (findHeaderError) {
    const code = (findHeaderError as { code?: string }).code ?? "";
    const msg = findHeaderError.message.toLowerCase();
    if (
      code === "42P01" ||
      code === "PGRST205" ||
      msg.includes("does not exist") ||
      msg.includes("schema cache")
    ) {
      // Fallback: Attempt writing to legacy daily_workforce_counts
      const entries = Object.entries(breakdowns).map(([cat, b]) => ({
        category: cat,
        count: b.fullDay + b.halfDay,
        notes: payload.remarks,
      }));
      await upsertDailyWorkforceCounts(
        payload.siteId,
        payload.siteName,
        payload.dateStr,
        entries
      );
      return;
    }
    throw findHeaderError;
  }

  if (existingHeader?.id) {
    attendanceId = existingHeader.id;
    // Update remarks only (the only column granted for UPDATE)
    const { error: updateHeaderError } = await supabase
      .from("daily_workforce_attendance")
      .update({ remarks: remarksValue })
      .eq("id", attendanceId);
    if (updateHeaderError) throw updateHeaderError;
  } else {
    // Insert new header (granted: site_id, attendance_date, remarks)
    const { data: insertedHeader, error: insertHeaderError } = await supabase
      .from("daily_workforce_attendance")
      .insert({
        site_id: payload.siteId,
        attendance_date: payload.dateStr,
        remarks: remarksValue,
      })
      .select("id")
      .single();

    if (insertHeaderError) {
      const code = (insertHeaderError as { code?: string }).code ?? "";
      const msg = insertHeaderError.message.toLowerCase();
      if (
        code === "42P01" ||
        code === "PGRST205" ||
        msg.includes("does not exist") ||
        msg.includes("schema cache")
      ) {
        const entries = Object.entries(breakdowns).map(([cat, b]) => ({
          category: cat,
          count: b.fullDay + b.halfDay,
          notes: payload.remarks,
        }));
        await upsertDailyWorkforceCounts(
          payload.siteId,
          payload.siteName,
          payload.dateStr,
          entries
        );
        return;
      }
      throw insertHeaderError;
    }
    attendanceId = insertedHeader?.id ?? null;
  }

  if (!attendanceId) {
    throw new Error("Failed to retrieve attendance header ID after save.");
  }

  // 2. Save category counts (with dual full_day_count & half_day_count support)
  // Note: The database grants INSERT on (attendance_id, site_id, category, count, full_day_count, half_day_count)
  // and UPDATE on (category, count, full_day_count, half_day_count) ONLY.
  // attendance_id and site_id are immutable foreign keys and must NEVER appear in an UPDATE statement.
  // We inspect existing category rows for this header, then update existing and insert new rows.
  const { data: existingCategories, error: fetchCatError } = await supabase
    .from("daily_workforce_category_counts")
    .select("id, category")
    .eq("attendance_id", attendanceId);

  if (fetchCatError) throw fetchCatError;

  const existingCatMap = new Map(
    (existingCategories || []).map((c) => [c.category, c.id])
  );

  for (const [cat, b] of Object.entries(breakdowns)) {
    const headcount = b.fullDay + b.halfDay;
    const existingCatId = existingCatMap.get(cat);

    if (existingCatId) {
      // UPDATE ONLY granted columns: count, full_day_count, half_day_count
      const { error: updCatErr } = await supabase
        .from("daily_workforce_category_counts")
        .update({
          count: headcount,
          full_day_count: b.fullDay,
          half_day_count: b.halfDay,
        })
        .eq("id", existingCatId);

      if (updCatErr) {
        // Fallback for legacy database schema before 20261122 migration
        const catCode = (updCatErr as { code?: string }).code ?? "";
        if (catCode === "42703" || updCatErr.message.toLowerCase().includes("full_day_count")) {
          const { error: legacyUpdErr } = await supabase
            .from("daily_workforce_category_counts")
            .update({ count: headcount })
            .eq("id", existingCatId);
          if (legacyUpdErr) throw legacyUpdErr;
        } else {
          throw updCatErr;
        }
      }
    } else {
      // INSERT new category row with granted columns
      const { error: insCatErr } = await supabase
        .from("daily_workforce_category_counts")
        .insert({
          attendance_id: attendanceId,
          site_id: payload.siteId,
          category: cat,
          count: headcount,
          full_day_count: b.fullDay,
          half_day_count: b.halfDay,
        });

      if (insCatErr) {
        // Fallback for legacy database schema before 20261122 migration
        const catCode = (insCatErr as { code?: string }).code ?? "";
        if (catCode === "42703" || insCatErr.message.toLowerCase().includes("full_day_count")) {
          const { error: legacyInsErr } = await supabase
            .from("daily_workforce_category_counts")
            .insert({
              attendance_id: attendanceId,
              site_id: payload.siteId,
              category: cat,
              count: headcount,
            });
          if (legacyInsErr) throw legacyInsErr;
        } else {
          throw insCatErr;
        }
      }
    }
  }

  await logActivity({
    action: "Daily Workforce Attendance Saved",
    module: "Attendance",
    description: `Submitted workforce attendance for ${payload.siteName} on ${payload.dateStr} (${totalHeadcount} workers, ${totalManDays.toFixed(1)} man-days across ${Object.values(breakdowns).filter((b) => b.fullDay + b.halfDay > 0).length} trades)`,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// MODULE B: SUPERVISOR PERSONAL ATTENDANCE
// ─────────────────────────────────────────────────────────────────────────────

export interface SupervisorAttendanceResult {
  tableReady: boolean;
  records: SupervisorAttendanceRecord[];
}

export async function fetchSupervisorAttendance(
  dateStr: string,
  siteId?: string
): Promise<SupervisorAttendanceResult> {
  const supabase = createClient();
  let query = supabase
    .from("supervisor_attendance")
    .select("*, sites(name)")
    .eq("attendance_date", dateStr)
    .order("created_at", { ascending: false });

  if (siteId) {
    query = query.eq("site_id", siteId);
  }

  const { data, error } = await query;

  if (error) {
    const code = (error as { code?: string }).code ?? "";
    if (
      code === "42P01" ||
      code === "PGRST205" ||
      error.message.toLowerCase().includes("does not exist") ||
      error.message.toLowerCase().includes("schema cache")
    ) {
      return { tableReady: false, records: [] };
    }
    throw error;
  }

  // Also attach supervisor user profile information if available
  const records = (data ?? []) as SupervisorAttendanceRecord[];
  if (records.length > 0) {
    const supervisorIds = Array.from(new Set(records.map((r) => r.supervisor_id)));
    const { data: profiles } = await supabase
      .from("user_profiles")
      .select("id, name, email, role, status")
      .in("id", supervisorIds);

    const profileMap = new Map((profiles ?? []).map((p) => [p.id, p as UserProfile]));
    for (const r of records) {
      r.supervisor = profileMap.get(r.supervisor_id) ?? null;
    }
  }

  return { tableReady: true, records };
}

export interface SupervisorSiteCandidate {
  id: string; // user profile id
  name: string;
  email: string;
  isAssignedToSite: boolean;
}

export async function fetchSupervisorsForSite(
  siteId: string
): Promise<{ tableReady: boolean; supervisors: SupervisorSiteCandidate[] }> {
  const supabase = createClient();

  // 1. Fetch all active supervisors from user_profiles
  const { data: profiles, error: profileErr } = await supabase
    .from("user_profiles")
    .select("id, name, email, role, status")
    .eq("role", "supervisor")
    .eq("status", "active")
    .order("name", { ascending: true });

  if (profileErr) throw profileErr;
  const activeSupervisors = (profiles ?? []) as UserProfile[];

  // 2. Query live site_memberships junction table for this site
  let assignedSet = new Set<string>();
  let tableReady = true;

  const { data: siteMembers, error: junctionErr } = await supabase
    .from("site_memberships")
    .select("user_id")
    .eq("site_id", siteId);

  if (junctionErr) {
    // If site_memberships query is unconfigured or not directly readable, check site_supervisors fallback
    const { data: fallbackSupervisors } = await supabase
      .from("site_supervisors")
      .select("user_id")
      .eq("site_id", siteId);

    if (fallbackSupervisors && fallbackSupervisors.length > 0) {
      assignedSet = new Set(fallbackSupervisors.map((s) => s.user_id));
    } else {
      tableReady = false;
      // When junction table is not yet migrated, candidate supervisors are active supervisors
      assignedSet = new Set(activeSupervisors.map((s) => s.id));
    }
  } else if (siteMembers && siteMembers.length > 0) {
    assignedSet = new Set(siteMembers.map((s) => s.user_id));
  } else {
    // If table exists but no supervisor is assigned yet to this site, allow PM to select from active supervisors
    assignedSet = new Set(activeSupervisors.map((s) => s.id));
  }

  const candidates: SupervisorSiteCandidate[] = activeSupervisors.map((p) => ({
    id: p.id,
    name: p.name || p.email.split("@")[0],
    email: p.email,
    isAssignedToSite: assignedSet.has(p.id),
  }));

  return { tableReady, supervisors: candidates };
}

export interface SaveSupervisorAttendanceInput {
  supervisorId: string;
  supervisorName: string;
  siteId: string;
  siteName: string;
  dateStr: string;
  status: SupervisorAttendanceStatus;
  remarks?: string;
}

export async function saveSupervisorAttendance(
  records: SaveSupervisorAttendanceInput[]
): Promise<void> {
  if (records.length === 0) return;
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Strict guardrail: Prevent supervisors from marking their own attendance
  for (const r of records) {
    if (user && user.id === r.supervisorId) {
      throw new Error(
        "Supervisors cannot record or edit their own attendance. Personal attendance must be marked by a Project Manager or Administrator."
      );
    }
  }

  // Note: Database schema grants authenticated clients INSERT on (site_id, supervisor_id, attendance_date, status, remarks)
  // and UPDATE on (status, remarks) ONLY. supervisor_id, site_id, and attendance_date are immutable after insert.
  // Using PostgREST's .upsert() puts non-granted columns in "DO UPDATE SET", triggering Postgres 42501.
  // We query existing records for (supervisor_id, attendance_date) and cleanly update status/remarks or insert new rows.
  for (const r of records) {
    const { data: existing, error: findErr } = await supabase
      .from("supervisor_attendance")
      .select("id")
      .eq("supervisor_id", r.supervisorId)
      .eq("attendance_date", r.dateStr)
      .maybeSingle();

    if (findErr) {
      const code = (findErr as { code?: string }).code ?? "";
      if (
        code === "42P01" ||
        code === "PGRST205" ||
        findErr.message.toLowerCase().includes("does not exist")
      ) {
        throw new Error(
          "The supervisor_attendance table (20261120_workforce_and_supervisor_attendance_PROPOSAL.sql) is not yet applied to the database. Please request an administrator to run the migration."
        );
      }
      throw findErr;
    }

    if (existing?.id) {
      // UPDATE ONLY granted columns: status, remarks
      const { error: updErr } = await supabase
        .from("supervisor_attendance")
        .update({
          status: r.status,
          remarks: r.remarks?.trim() || null,
        })
        .eq("id", existing.id);
      if (updErr) throw updErr;
    } else {
      // INSERT granted columns: site_id, supervisor_id, attendance_date, status, remarks
      const { error: insErr } = await supabase
        .from("supervisor_attendance")
        .insert({
          supervisor_id: r.supervisorId,
          site_id: r.siteId,
          attendance_date: r.dateStr,
          status: r.status,
          remarks: r.remarks?.trim() || null,
        });
      if (insErr) throw insErr;
    }
  }

  await logActivity({
    action: "Supervisor Attendance Recorded",
    module: "Attendance",
    description: `Recorded personal attendance for ${records.length} supervisor(s) on ${records[0].dateStr}`,
  });
}

export async function fetchSupervisorAttendanceHistory(
  supervisorId: string,
  startDate: string,
  endDate?: string
): Promise<SupervisorAttendanceRecord[]> {
  const supabase = createClient();
  let query = supabase
    .from("supervisor_attendance")
    .select("*, sites(name)")
    .eq("supervisor_id", supervisorId)
    .gte("attendance_date", startDate)
    .order("attendance_date", { ascending: false });

  if (endDate) {
    query = query.lte("attendance_date", endDate);
  }

  const { data, error } = await query;
  if (error) {
    const code = (error as { code?: string }).code ?? "";
    if (
      code === "42P01" ||
      code === "PGRST205" ||
      error.message.toLowerCase().includes("does not exist")
    ) {
      return [];
    }
    throw error;
  }

  return (data ?? []) as SupervisorAttendanceRecord[];
}

