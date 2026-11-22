import { createClient } from "@/lib/supabase/client";
import { logActivity } from "@/lib/data/activity-logs";
import type { AccountStatus, AppRole, UserProfile } from "@/types/database";

/**
 * All user profile mutations MUST flow through the privileged server-side
 * Edge Function 'admin-manage-user' (which verifies JWT + active admin status).
 * Never embed service-role keys in browser code.
 */
async function invokeAdminFunction<T>(body: Record<string, unknown>): Promise<T> {
  const supabase = createClient();
  const { data, error } = await supabase.functions.invoke("admin-manage-user", {
    body,
  });

  if (error) {
    // Surface structured Edge Function error message if present
    const details = (error as { context?: { status?: number; json?: () => Promise<{ error?: string; message?: string }> } }).context;
    if (details?.status === 404 || error.message?.includes("Failed to send a request")) {
      throw new Error(
        "Edge Function 'admin-manage-user' is not deployed or unreachable on this Supabase project. Please deploy it with: supabase functions deploy admin-manage-user"
      );
    }
    if (details && typeof details.json === "function") {
      try {
        const parsed = await details.json();
        if (parsed?.error) throw new Error(parsed.error);
        if (parsed?.message) throw new Error(parsed.message);
      } catch (inner) {
        if (inner instanceof Error && inner.message !== error.message) {
          throw inner;
        }
      }
    }
    throw new Error(error.message || "Admin operation failed.");
  }

  if (data && typeof data === "object" && "error" in data && data.error) {
    throw new Error(String(data.error));
  }

  return data as T;
}

export async function fetchAllUserProfiles(): Promise<UserProfile[]> {
  const supabase = createClient();
  // Primary path: RLS-enforced direct query (active admin sees all profiles)
  const { data, error } = await supabase
    .from("user_profiles")
    .select("*")
    .order("name", { ascending: true });

  if (!error && data && data.length > 0) {
    return data as UserProfile[];
  }

  // Fallback path: authorized Edge Function
  const res = await invokeAdminFunction<{ users?: UserProfile[] }>({
    action: "list_users",
  });
  return res.users ?? [];
}

export interface CreateUserInput {
  email: string;
  password: string;
  name: string;
  role: AppRole;
  status: AccountStatus;
}

export async function adminCreateUser(input: CreateUserInput): Promise<void> {
  await invokeAdminFunction({
    action: "create_user",
    email: input.email.trim().toLowerCase(),
    password: input.password,
    name: input.name.trim(),
    role: input.role,
    status: input.status,
  });

  await logActivity({
    action: "User Created",
    module: "Admin",
    description: `Created: ${input.name.trim()} (${input.email.trim()}) as ${input.role}`,
  });
}

export interface UpdateUserInput {
  userId: string;
  name: string;
  role: AppRole;
  status: AccountStatus;
}

export async function adminUpdateUser(input: UpdateUserInput): Promise<void> {
  await invokeAdminFunction({
    action: "update_user",
    userId: input.userId,
    name: input.name.trim(),
    role: input.role,
    status: input.status,
  });

  await logActivity({
    action: "User Updated",
    module: "Admin",
    description: `Updated: ${input.name.trim()} → role=${input.role}, status=${input.status}`,
  });
}

export async function adminToggleUserStatus(
  user: UserProfile,
  newStatus: AccountStatus
): Promise<void> {
  await invokeAdminFunction({
    action: "toggle_status",
    userId: user.id,
    newStatus,
  });

  await logActivity({
    action: newStatus === "active" ? "User Enabled" : "User Disabled",
    module: "Admin",
    description: `${user.name || user.email} → ${newStatus}`,
    oldValue: user.status,
    newValue: newStatus,
  });
}

export async function adminDeleteUser(user: UserProfile): Promise<void> {
  await invokeAdminFunction({
    action: "delete_user",
    userId: user.id,
  });

  await logActivity({
    action: "User Deleted",
    module: "Admin",
    description: `Deleted user: ${user.name || user.email}`,
  });
}

