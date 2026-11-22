import { createClient } from "@/lib/supabase/client";
import { logActivity } from "@/lib/data/activity-logs";
import type { WorkerRecord } from "@/types/database";

export async function fetchWorkers(siteId?: string): Promise<WorkerRecord[]> {
  const supabase = createClient();
  let query = supabase
    .from("workers")
    .select("*")
    .order("created_at", { ascending: false });

  if (siteId) {
    query = query.eq("site_id", siteId);
  }

  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as WorkerRecord[];
}

export async function fetchUnassignedWorkers(): Promise<WorkerRecord[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("workers")
    .select("*")
    .is("site_id", null)
    .order("name", { ascending: true });

  if (error) throw error;
  return (data ?? []) as WorkerRecord[];
}

export async function fetchWorkerById(id: string): Promise<WorkerRecord | null> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("workers")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return (data as WorkerRecord) ?? null;
}

export interface WorkerFormPayload {
  name: string;
  phone: string;
  role: string;
  skill: string;
  status: string;
  site_id: string | null;
  assigned_site: string | null;
}

export async function createWorker(payload: WorkerFormPayload): Promise<WorkerRecord> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("workers")
    .insert({
      name: payload.name.trim(),
      phone: payload.phone.trim(),
      role: payload.role,
      skill: payload.skill,
      status: payload.status,
      site_id: payload.site_id,
      assigned_site: payload.assigned_site,
    })
    .select()
    .single();

  if (error) throw error;

  await logActivity({
    action: "Worker Created",
    module: "Workers",
    description: `Created worker: ${payload.name.trim()} (${payload.role})`,
  });

  return data as WorkerRecord;
}

export async function updateWorker(
  id: string,
  payload: Partial<WorkerFormPayload>
): Promise<WorkerRecord> {
  const supabase = createClient();
  const updateBody: Record<string, unknown> = {};
  if (payload.name !== undefined) updateBody.name = payload.name.trim();
  if (payload.phone !== undefined) updateBody.phone = payload.phone.trim();
  if (payload.role !== undefined) updateBody.role = payload.role;
  if (payload.skill !== undefined) updateBody.skill = payload.skill;
  if (payload.status !== undefined) updateBody.status = payload.status;
  if (payload.site_id !== undefined) updateBody.site_id = payload.site_id;
  if (payload.assigned_site !== undefined) updateBody.assigned_site = payload.assigned_site;

  const { data, error } = await supabase
    .from("workers")
    .update(updateBody)
    .eq("id", id)
    .select();

  if (error) throw error;
  const rows = (data ?? []) as WorkerRecord[];
  if (rows.length === 0) {
    throw new Error(
      "Permission denied or worker not found. Your account cannot update this worker."
    );
  }

  await logActivity({
    action: "Worker Updated",
    module: "Workers",
    description: `Updated worker: ${rows[0].name}`,
  });

  return rows[0];
}

export async function assignWorkerToSite(
  worker: WorkerRecord,
  siteId: string | null,
  siteName: string | null
): Promise<void> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("workers")
    .update({ site_id: siteId, assigned_site: siteName })
    .eq("id", worker.id)
    .select("id");

  if (error) throw error;
  if (!data || data.length === 0) {
    throw new Error(
      "Permission denied or worker not accessible. Site assignment was blocked by database policy."
    );
  }

  await logActivity({
    action: siteId ? "Worker Assigned" : "Worker Unassigned",
    module: "Sites",
    description: siteId
      ? `Assigned worker ${worker.name} to site ${siteName ?? siteId}`
      : `Unassigned worker ${worker.name}`,
  });
}

export async function deleteWorker(id: string, workerName: string): Promise<void> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("workers")
    .delete()
    .eq("id", id)
    .select("id");

  if (error) throw error;
  if (!data || data.length === 0) {
    throw new Error(
      "Permission denied or worker not found. Only authorized Administrators can delete workers."
    );
  }

  await logActivity({
    action: "Worker Deleted",
    module: "Workers",
    description: `Deleted worker: ${workerName}`,
  });
}

