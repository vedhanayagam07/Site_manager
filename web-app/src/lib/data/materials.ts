import { createClient } from "@/lib/supabase/client";
import { logActivity } from "@/lib/data/activity-logs";
import type {
  MaterialRecord,
  MaterialTransactionRecord,
  MaterialTransactionType,
} from "@/types/database";

export async function fetchMaterials(siteId?: string): Promise<MaterialRecord[]> {
  const supabase = createClient();
  let query = supabase
    .from("materials")
    .select("*")
    .order("name", { ascending: true });

  if (siteId) {
    query = query.eq("site_id", siteId);
  }

  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as MaterialRecord[];
}

export async function fetchMaterialById(id: string): Promise<MaterialRecord | null> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("materials")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return (data as MaterialRecord) ?? null;
}

export interface CreateMaterialPayload {
  name: string;
  unit: string;
  supplier: string;
  site_id: string | null;
}

export async function createMaterial(payload: CreateMaterialPayload): Promise<MaterialRecord> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("materials")
    .insert({
      name: payload.name.trim(),
      unit: payload.unit,
      supplier: payload.supplier.trim(),
      site_id: payload.site_id,
      received_qty: 0,
      used_qty: 0,
      balance_qty: 0,
    })
    .select()
    .single();

  if (error) throw error;

  await logActivity({
    action: "Material Created",
    module: "Materials",
    description: `Created material: ${payload.name.trim()} (${payload.unit})`,
  });

  return data as MaterialRecord;
}

export async function updateMaterial(
  id: string,
  payload: { name: string; supplier: string; unit?: string }
): Promise<MaterialRecord> {
  const supabase = createClient();
  const body: Record<string, unknown> = {
    name: payload.name.trim(),
    supplier: payload.supplier.trim(),
  };
  if (payload.unit) body.unit = payload.unit;

  const { data, error } = await supabase
    .from("materials")
    .update(body)
    .eq("id", id)
    .select();

  if (error) throw error;
  const rows = (data ?? []) as MaterialRecord[];
  if (rows.length === 0) {
    throw new Error(
      "Permission denied or material not found. Your account cannot update this material."
    );
  }

  await logActivity({
    action: "Material Updated",
    module: "Materials",
    description: `Updated material: ${payload.name.trim()}`,
  });

  return rows[0];
}

export async function deleteMaterial(id: string, name: string): Promise<void> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("materials")
    .delete()
    .eq("id", id)
    .select("id");

  if (error) throw error;
  if (!data || data.length === 0) {
    throw new Error(
      "Permission denied or material not found. Only authorized Administrators can delete materials."
    );
  }

  await logActivity({
    action: "Material Deleted",
    module: "Materials",
    description: `Deleted material: ${name}`,
  });
}

export async function fetchMaterialTransactions(options?: {
  materialId?: string;
  sinceDate?: string;
  limit?: number;
}): Promise<MaterialTransactionRecord[]> {
  const supabase = createClient();
  let query = supabase
    .from("material_transactions")
    .select("*, materials(name, unit)")
    .order("created_at", { ascending: false });

  if (options?.materialId) {
    query = query.eq("material_id", options.materialId);
  }
  if (options?.sinceDate) {
    query = query.gte("created_at", options.sinceDate);
  }
  if (options?.limit) {
    query = query.limit(options.limit);
  }

  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as MaterialTransactionRecord[];
}

export interface RecordStockMovementPayload {
  materialId: string;
  transactionType: MaterialTransactionType;
  quantity: number;
  siteName: string;
  remarks: string;
}

/**
 * Mirrors Flutter's exact stock movement business logic & validation:
 * - Loads latest material balance from Supabase before mutation
 * - Enforces minimum 0.5 for 'Loads' unit
 * - Requires site selection for USED transactions
 * - Prevents negative balance on USED
 * - Appends immutable record to material_transactions and updates materials counters
 */
export async function recordStockMovement(
  payload: RecordStockMovementPayload
): Promise<MaterialRecord> {
  const supabase = createClient();

  if (payload.quantity <= 0) {
    throw new Error("Quantity must be greater than 0.");
  }

  const { data: latest, error: fetchErr } = await supabase
    .from("materials")
    .select("*")
    .eq("id", payload.materialId)
    .single();

  if (fetchErr || !latest) {
    throw fetchErr ?? new Error("Material not found.");
  }

  const mat = latest as MaterialRecord;
  const unit = (mat.unit ?? "").toLowerCase();
  if (unit === "loads" && payload.quantity < 0.5) {
    throw new Error("Minimum quantity for Loads is 0.5.");
  }

  if (payload.transactionType === "USED" && !payload.siteName.trim()) {
    throw new Error("Selecting an active site is required for stock usage.");
  }

  const currentBalance = Number(mat.balance_qty ?? 0);
  const currentReceived = Number(mat.received_qty ?? 0);
  const currentUsed = Number(mat.used_qty ?? 0);

  if (payload.transactionType === "USED" && payload.quantity > currentBalance) {
    throw new Error(
      `Insufficient stock. Available: ${currentBalance} ${mat.unit}.`
    );
  }

  const isReceive = payload.transactionType === "RECEIVED";
  const newBalance = isReceive
    ? currentBalance + payload.quantity
    : currentBalance - payload.quantity;

  const { error: txnErr } = await supabase.from("material_transactions").insert({
    material_id: payload.materialId,
    transaction_type: payload.transactionType,
    quantity: payload.quantity,
    site_name: payload.siteName.trim(),
    remarks: payload.remarks.trim(),
  });

  if (txnErr) throw txnErr;

  const { data: updatedRows, error: updateErr } = await supabase
    .from("materials")
    .update({
      balance_qty: newBalance,
      received_qty: isReceive ? currentReceived + payload.quantity : currentReceived,
      used_qty: !isReceive ? currentUsed + payload.quantity : currentUsed,
    })
    .eq("id", payload.materialId)
    .select();

  if (updateErr) throw updateErr;
  const rows = (updatedRows ?? []) as MaterialRecord[];
  if (rows.length === 0) {
    throw new Error(
      "Transaction was logged, but updating the material balance was blocked by database policy."
    );
  }

  await logActivity({
    action: "Material Transaction",
    module: "Materials",
    description: `Logged transaction: ${payload.transactionType} ${payload.quantity} ${mat.unit} of ${mat.name}${payload.siteName ? ` (${payload.siteName})` : ""}`,
  });

  return rows[0];
}

export function isLowStock(material: MaterialRecord): boolean {
  const balance = Number(material.balance_qty ?? 0);
  const min = Number(material.minimum_stock ?? 10);
  return balance <= min;
}

