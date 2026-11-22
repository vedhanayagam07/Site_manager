import { createClient } from "@/lib/supabase/client";
import { logActivity } from "@/lib/data/activity-logs";
import type { LoadingMemoRecord } from "@/types/database";

export async function fetchLoadingMemos(siteId?: string): Promise<LoadingMemoRecord[]> {
  const supabase = createClient();
  let query = supabase
    .from("loading_memos")
    .select("*")
    .order("created_at", { ascending: false });

  if (siteId) {
    query = query.eq("site_id", siteId);
  }

  const { data, error } = await query;

  if (error) throw error;
  return (data ?? []) as LoadingMemoRecord[];
}

export interface CreateLoadingMemoPayload {
  site_id: string;
  date: string; // YYYY-MM-DD
  vehicle_number: string;
  material_id: string | null;
  material_name: string;
  quantity: number;
  unit: string;
  remarks?: string;
}

export async function createLoadingMemo(
  payload: CreateLoadingMemoPayload
): Promise<LoadingMemoRecord> {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const vehicle = payload.vehicle_number.trim().toUpperCase();
  const generatedBy = user?.email ?? "unknown";

  const { data, error } = await supabase
    .from("loading_memos")
    .insert({
      site_id: payload.site_id,
      date: payload.date,
      vehicle_number: vehicle,
      material_id: payload.material_id,
      material_name: payload.material_name.trim(),
      quantity: payload.quantity,
      unit: payload.unit,
      remarks: payload.remarks?.trim() ? payload.remarks.trim() : null,
      generated_by: generatedBy,
    })
    .select()
    .single();

  if (error) throw error;

  await logActivity({
    action: "Loading Memo Generated",
    module: "Loading Memo",
    description: `Memo for ${vehicle} — ${payload.material_name} × ${payload.quantity} ${payload.unit}`,
  });

  return data as LoadingMemoRecord;
}

export async function deleteLoadingMemo(memo: LoadingMemoRecord): Promise<void> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("loading_memos")
    .delete()
    .eq("id", memo.id)
    .select("id");

  if (error) throw error;
  if (!data || data.length === 0) {
    throw new Error(
      "Permission denied or loading memo not found. Only authorized Administrators can delete memos."
    );
  }

  await logActivity({
    action: "Loading Memo Deleted",
    module: "Loading Memo",
    description: `Deleted memo for ${memo.vehicle_number} (${memo.material_name})`,
  });
}

