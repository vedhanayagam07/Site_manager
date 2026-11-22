import { createClient } from "@/lib/supabase/client";
import { logActivity } from "@/lib/data/activity-logs";
import type { SiteRecord } from "@/types/database";

const PROGRESS_STORAGE_PREFIX = "tsr_site_progress_";

export function getLocalSiteProgress(siteId: string): number {
  if (typeof window === "undefined") return 0;
  const raw = window.localStorage.getItem(`${PROGRESS_STORAGE_PREFIX}${siteId}`);
  const parsed = raw ? parseInt(raw, 10) : 0;
  return Number.isNaN(parsed) ? 0 : Math.min(100, Math.max(0, parsed));
}

export function setLocalSiteProgress(siteId: string, progress: number): void {
  if (typeof window === "undefined") return;
  const clamped = Math.min(100, Math.max(0, Math.round(progress)));
  window.localStorage.setItem(`${PROGRESS_STORAGE_PREFIX}${siteId}`, String(clamped));
}

export async function fetchSites(): Promise<SiteRecord[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("sites")
    .select("*")
    .order("created_at", { ascending: false });

  if (error) throw error;
  return ((data ?? []) as SiteRecord[]).map((site) => ({
    ...site,
    progress: site.progress ?? getLocalSiteProgress(site.id),
  }));
}

export async function fetchActiveSites(): Promise<SiteRecord[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("sites")
    .select("*")
    .not("status", "ilike", "archived")
    .order("name", { ascending: true });

  if (error) throw error;
  return ((data ?? []) as SiteRecord[]).map((site) => ({
    ...site,
    progress: site.progress ?? getLocalSiteProgress(site.id),
  }));
}

export async function fetchSiteById(id: string): Promise<SiteRecord | null> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("sites")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;
  const site = data as SiteRecord;
  return {
    ...site,
    progress: site.progress ?? getLocalSiteProgress(site.id),
  };
}

export interface SiteFormPayload {
  name: string;
  location: string;
  project_manager: string;
  status: string;
  progress: number;
}

export async function createSite(payload: SiteFormPayload): Promise<SiteRecord> {
  const supabase = createClient();
  // Match Flutter's exact DB columns (progress is stored locally to avoid referencing an unverified DB column)
  const dbPayload = {
    name: payload.name.trim(),
    location: payload.location.trim(),
    project_manager: payload.project_manager.trim(),
    status: payload.status,
  };

  const { data, error } = await supabase
    .from("sites")
    .insert(dbPayload)
    .select()
    .single();

  if (error) throw error;
  const created = data as SiteRecord;
  setLocalSiteProgress(created.id, payload.progress);

  await logActivity({
    action: "Site Created",
    module: "Sites",
    description: `Created site: ${dbPayload.name}`,
  });

  return { ...created, progress: payload.progress };
}

export async function updateSite(id: string, payload: SiteFormPayload): Promise<SiteRecord> {
  const supabase = createClient();
  const dbPayload = {
    name: payload.name.trim(),
    location: payload.location.trim(),
    project_manager: payload.project_manager.trim(),
    status: payload.status,
  };

  const { data, error } = await supabase
    .from("sites")
    .update(dbPayload)
    .eq("id", id)
    .select();

  if (error) throw error;
  const rows = (data ?? []) as SiteRecord[];
  if (rows.length === 0) {
    throw new Error(
      "Permission denied or site not found. Your database role cannot update this site."
    );
  }
  setLocalSiteProgress(id, payload.progress);

  await logActivity({
    action: "Site Updated",
    module: "Sites",
    description: `Updated site: ${dbPayload.name} (${payload.status}, ${payload.progress}%)`,
  });

  return { ...rows[0], progress: payload.progress };
}

export async function toggleSiteCompletion(site: SiteRecord): Promise<SiteRecord> {
  const isCompleted = site.status === "Completed";
  const newStatus = isCompleted ? "Active" : "Completed";
  const newProgress = isCompleted ? (site.progress ?? 0) : 100;

  return updateSite(site.id, {
    name: site.name,
    location: site.location ?? "",
    project_manager: site.project_manager ?? "",
    status: newStatus,
    progress: newProgress,
  });
}

export async function deleteSite(id: string, siteName: string): Promise<void> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("sites")
    .delete()
    .eq("id", id)
    .select("id");

  if (error) throw error;
  if (!data || data.length === 0) {
    throw new Error(
      "Permission denied or site not found. Only authorized Administrators can delete sites."
    );
  }

  await logActivity({
    action: "Site Deleted",
    module: "Sites",
    description: `Deleted site: ${siteName}`,
  });
}

