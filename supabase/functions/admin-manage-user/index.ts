// ==============================================================================
// TSR Site Manager Pro — Supabase Edge Function: admin-manage-user
// File: supabase/functions/admin-manage-user/index.ts
// ==============================================================================
// This function handles privileged user management operations strictly on the server:
// - Verifies caller JWT against Supabase Auth
// - Confirms caller is an active 'admin' in user_profiles
// - Performs auth.admin actions using SUPABASE_SERVICE_ROLE_KEY
// - Validates input format (UUIDs, email regex, string lengths, role/status allowlists)
// - Prevents administrator self-lockout (demote, disable, delete)
// - Handles non-atomic deletion failure with profile rollback
// - Never exposes internal service keys or credentials to the client
// ==============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ALLOWED_ROLES = ["admin", "projectManager", "supervisor"];
const ALLOWED_STATUSES = ["active", "disabled"];

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL_REGEX = /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/;

function jsonResponse(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function sanitizeAuthError(message: string): string {
  const lower = message.toLowerCase();
  if (lower.includes("already registered") || lower.includes("already exists") || lower.includes("unique")) {
    return "A user with this email address already exists.";
  }
  if (lower.includes("password")) {
    return "Password does not meet security requirements (8-72 characters).";
  }
  if (lower.includes("invalid email")) {
    return "The provided email address is invalid.";
  }
  return "Operation failed. Please verify the input and try again.";
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed. Use POST." }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return jsonResponse({ error: "Unauthorized: Missing or invalid Authorization header." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
      console.error("[admin-manage-user] Server configuration error: Missing environment variables.");
      return jsonResponse({ error: "Server misconfiguration. Please contact support." }, 500);
    }

    // 1. Authenticate caller using caller's JWT
    const callerClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const { data: { user: callerUser }, error: userError } = await callerClient.auth.getUser();
    if (userError || !callerUser) {
      return jsonResponse({ error: "Unauthorized: Invalid or expired session." }, 401);
    }

    // 2. Initialize privileged client with service role key for database verification & admin tasks
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
      auth: { persistSession: false },
    });

    // 3. Verify caller is an active administrator in public.user_profiles
    const { data: callerProfile, error: profileError } = await adminClient
      .from("user_profiles")
      .select("role, status")
      .eq("id", callerUser.id)
      .maybeSingle();

    if (profileError) {
      console.error("[admin-manage-user] Error verifying caller profile:", profileError);
      return jsonResponse({ error: "Authorization check failed." }, 500);
    }

    if (!callerProfile || callerProfile.role !== "admin" || callerProfile.status !== "active") {
      return jsonResponse({ error: "Forbidden: Active administrator privileges required." }, 403);
    }

    // Parse request body
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body." }, 400);
    }

    const action = String(body.action || "").trim();

    // ─────────────────────────────────────────────────────────────────────────
    // ACTION: list_users
    // ─────────────────────────────────────────────────────────────────────────
    if (action === "list_users") {
      const { data: users, error: listError } = await adminClient
        .from("user_profiles")
        .select("*")
        .order("name", { ascending: true });

      if (listError) {
        console.error("[admin-manage-user] list_users error:", listError);
        return jsonResponse({ error: "Failed to fetch users." }, 500);
      }

      return jsonResponse({ success: true, users: users ?? [] });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ACTION: create_user
    // ─────────────────────────────────────────────────────────────────────────
    if (action === "create_user") {
      const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
      const password = typeof body.password === "string" ? body.password : "";
      const name = typeof body.name === "string" ? body.name.trim() : "";
      const role = typeof body.role === "string" ? body.role.trim() : "supervisor";
      const status = typeof body.status === "string" ? body.status.trim() : "active";

      // Input validation
      if (!email || email.length > 255 || !EMAIL_REGEX.test(email)) {
        return jsonResponse({ error: "A valid email address (maximum 255 characters) is required." }, 400);
      }
      if (!password || password.length < 8 || password.length > 72) {
        return jsonResponse({ error: "Password must be between 8 and 72 characters long." }, 400);
      }
      if (!name || name.length < 2 || name.length > 100) {
        return jsonResponse({ error: "User full name must be between 2 and 100 characters long." }, 400);
      }
      if (!ALLOWED_ROLES.includes(role)) {
        return jsonResponse({ error: `Invalid role. Allowed values: ${ALLOWED_ROLES.join(", ")}` }, 400);
      }
      if (!ALLOWED_STATUSES.includes(status)) {
        return jsonResponse({ error: `Invalid status. Allowed values: ${ALLOWED_STATUSES.join(", ")}` }, 400);
      }

      // Step A: Create user in Supabase Auth
      const { data: authResult, error: authCreateError } = await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { name },
      });

      if (authCreateError || !authResult.user) {
        const errorMsg = authCreateError ? sanitizeAuthError(authCreateError.message) : "Failed to create authentication user.";
        return jsonResponse({ error: errorMsg }, 400);
      }

      const newUserId = authResult.user.id;

      // Step B: Upsert into public.user_profiles
      const { error: profileUpsertError } = await adminClient.from("user_profiles").upsert({
        id: newUserId,
        email,
        name,
        role,
        status,
      });

      if (profileUpsertError) {
        console.error("[admin-manage-user] Failed to write profile after auth creation. Rolling back auth user:", newUserId);
        // Rollback: delete orphaned auth user
        try {
          await adminClient.auth.admin.deleteUser(newUserId);
        } catch (rollbackErr) {
          console.error("[admin-manage-user] Rollback failed:", rollbackErr);
        }
        return jsonResponse({ error: "Failed to persist user profile. Operation rolled back." }, 500);
      }

      return jsonResponse({
        success: true,
        userId: newUserId,
        message: "User created successfully.",
      });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ACTION: update_user
    // ─────────────────────────────────────────────────────────────────────────
    if (action === "update_user") {
      const userId = typeof body.userId === "string" ? body.userId.trim() : "";
      const name = typeof body.name === "string" ? body.name.trim() : "";
      const role = typeof body.role === "string" ? body.role.trim() : "";
      const status = typeof body.status === "string" ? body.status.trim() : "";

      if (!userId || !UUID_REGEX.test(userId)) {
        return jsonResponse({ error: "A valid user UUID is required." }, 400);
      }
      if (!name || name.length < 2 || name.length > 100) {
        return jsonResponse({ error: "Full name must be between 2 and 100 characters long." }, 400);
      }
      if (!ALLOWED_ROLES.includes(role)) {
        return jsonResponse({ error: `Invalid role: ${role}.` }, 400);
      }
      if (!ALLOWED_STATUSES.includes(status)) {
        return jsonResponse({ error: `Invalid status: ${status}.` }, 400);
      }

      // Safeguard: Prevent admin from disabling or demoting their own active session
      if (callerUser.id === userId) {
        if (status === "disabled") {
          return jsonResponse({ error: "Administrators cannot disable their own account." }, 400);
        }
        if (role !== "admin") {
          return jsonResponse({ error: "Administrators cannot demote their own role." }, 400);
        }
      }

      const { error: updateError } = await adminClient
        .from("user_profiles")
        .update({ name, role, status })
        .eq("id", userId);

      if (updateError) {
        console.error("[admin-manage-user] update_user error:", updateError);
        return jsonResponse({ error: "Failed to update user profile." }, 500);
      }

      return jsonResponse({ success: true, message: "User updated successfully." });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ACTION: toggle_status
    // ─────────────────────────────────────────────────────────────────────────
    if (action === "toggle_status") {
      const userId = typeof body.userId === "string" ? body.userId.trim() : "";
      const newStatus = typeof body.newStatus === "string" ? body.newStatus.trim() : "";

      if (!userId || !UUID_REGEX.test(userId)) {
        return jsonResponse({ error: "A valid user UUID is required." }, 400);
      }
      if (!ALLOWED_STATUSES.includes(newStatus)) {
        return jsonResponse({ error: `Invalid status: ${newStatus}. Allowed values: ${ALLOWED_STATUSES.join(", ")}` }, 400);
      }

      // Safeguard: Prevent admin from disabling themselves
      if (callerUser.id === userId && newStatus === "disabled") {
        return jsonResponse({ error: "Administrators cannot disable their own account." }, 400);
      }

      const { error: statusError } = await adminClient
        .from("user_profiles")
        .update({ status: newStatus })
        .eq("id", userId);

      if (statusError) {
        console.error("[admin-manage-user] toggle_status error:", statusError);
        return jsonResponse({ error: "Failed to update user status." }, 500);
      }

      return jsonResponse({ success: true, status: newStatus });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ACTION: delete_user
    // ─────────────────────────────────────────────────────────────────────────
    if (action === "delete_user") {
      const userId = typeof body.userId === "string" ? body.userId.trim() : "";

      if (!userId || !UUID_REGEX.test(userId)) {
        return jsonResponse({ error: "A valid user UUID is required." }, 400);
      }

      // Safeguard: Prevent admin from deleting their own account
      if (callerUser.id === userId) {
        return jsonResponse({ error: "Administrators cannot delete their own account." }, 400);
      }

      // Step 1: Fetch existing profile to verify existence and capture baseline state
      const { data: targetProfile, error: fetchError } = await adminClient
        .from("user_profiles")
        .select("*")
        .eq("id", userId)
        .maybeSingle();

      if (fetchError) {
        console.error("[admin-manage-user] delete_user profile fetch error:", fetchError);
        return jsonResponse({ error: "Failed to verify target user profile." }, 500);
      }

      if (!targetProfile) {
        return jsonResponse({ error: "User profile not found." }, 404);
      }

      // Step 2: Optimistic lock & pre-disable.
      // Set status to 'disabled' before attempting auth deletion.
      // This immediately revokes all permissions via is_active_user() and avoids deleting the row prematurely.
      // If Auth deletion fails, the row was never dropped, eliminating data loss from failed re-inserts.
      const { error: lockError } = await adminClient
        .from("user_profiles")
        .update({ status: "disabled" })
        .eq("id", userId)
        .eq("status", targetProfile.status);

      if (lockError) {
        console.error("[admin-manage-user] delete_user concurrency lock failed:", lockError);
        return jsonResponse({ error: "Failed to lock profile for deletion. Please retry." }, 409);
      }

      // Step 3: Delete from auth.users (GoTrue Auth API)
      // Note: This operation is non-atomic with PostgreSQL. If this step fails,
      // we safely revert the profile status back to its original value.
      const { error: deleteAuthError } = await adminClient.auth.admin.deleteUser(userId);

      if (deleteAuthError) {
        console.error("[admin-manage-user] delete_user auth error; reverting status lock:", deleteAuthError);
        try {
          await adminClient
            .from("user_profiles")
            .update({ status: targetProfile.status })
            .eq("id", userId);
        } catch (revertErr) {
          console.error("[admin-manage-user] CRITICAL: Failed to revert profile status:", revertErr);
        }
        return jsonResponse({
          error: "Failed to delete authentication account. The user profile has been preserved."
        }, 500);
      }

      // Step 4: Delete the profile row from public.user_profiles
      // If user_profiles has ON DELETE CASCADE from auth.users, this row may already be removed.
      const { error: deleteProfileError } = await adminClient
        .from("user_profiles")
        .delete()
        .eq("id", userId);

      if (deleteProfileError) {
        // Auth user is already permanently removed, so the user can never authenticate.
        // Log a warning if the orphaned profile row couldn't be deleted due to FK constraints.
        console.warn("[admin-manage-user] Note: Profile row could not be removed after auth user deletion (may have already cascaded or FK blocked):", deleteProfileError);
      }

      return jsonResponse({ success: true, message: "User deleted successfully." });
    }

    return jsonResponse({ error: `Unsupported action: '${action}'.` }, 400);
  } catch (error) {
    console.error("[admin-manage-user] Unhandled exception:", error);
    return jsonResponse({ error: "An unexpected internal server error occurred." }, 500);
  }
});
