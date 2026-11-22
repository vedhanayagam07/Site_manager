import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
import type { AppRole } from "@/types/database";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatRoleLabel(role: AppRole | string | null | undefined): string {
  switch (role) {
    case "admin":
      return "Administrator";
    case "projectManager":
      return "Project Manager";
    case "supervisor":
      return "Site Supervisor";
    default:
      return "Unassigned";
  }
}

export function todayIsoDate(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function formatDisplayDate(dateStr: string | null | undefined): string {
  if (!dateStr) return "—";
  const parsed = new Date(dateStr);
  if (Number.isNaN(parsed.getTime())) return dateStr;
  return new Intl.DateTimeFormat("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  }).format(parsed);
}

export function formatDisplayDateTime(dateStr: string | null | undefined): string {
  if (!dateStr) return "—";
  const parsed = new Date(dateStr);
  if (Number.isNaN(parsed.getTime())) return dateStr;
  return new Intl.DateTimeFormat("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(parsed);
}

export function formatNumber(val: number | null | undefined, maxDecimals = 1): string {
  const num = Number(val ?? 0);
  if (Number.isNaN(num)) return "0";
  return new Intl.NumberFormat("en-IN", {
    maximumFractionDigits: maxDecimals,
  }).format(num);
}

// ─────────────────────────────────────────────────────────────────────────────
// SAFE CENTRALIZED DIAGNOSTIC ERROR HANDLER (ISSUE 4)
// Distinguishes: Auth, RLS, Column Privilege, Constraint, Trigger,
// Edge Function, Storage, PDF Generation, and Schema errors.
// Never exposes passwords, access tokens, or service-role keys.
// ─────────────────────────────────────────────────────────────────────────────

export type DiagnosticCategory =
  | "AUTH_ERROR"
  | "RLS_VIOLATION"
  | "MISSING_PRIVILEGE"
  | "CONSTRAINT_VIOLATION"
  | "TRIGGER_EXCEPTION"
  | "EDGE_FUNCTION_ERROR"
  | "STORAGE_ERROR"
  | "PDF_GENERATION_ERROR"
  | "SCHEMA_CACHE_ERROR"
  | "UNKNOWN_ERROR";

export interface DiagnosticError {
  category: DiagnosticCategory;
  sqlstate?: string;
  code?: string;
  safeMessage: string;
  operation?: string;
  requestId?: string;
  hint?: string;
}

export function diagnoseError(error: unknown, operation?: string): DiagnosticError {
  if (!error) {
    return {
      category: "UNKNOWN_ERROR",
      safeMessage: "An unexpected error occurred.",
      operation,
    };
  }

  // Extract raw error attributes safely
  let message = "";
  let code = "";
  let details = "";
  let hint = "";
  let requestId = "";

  if (typeof error === "string") {
    message = error;
  } else if (error instanceof Error) {
    message = error.message;
    const anyErr = error as unknown as Record<string, unknown>;
    code = typeof anyErr.code === "string" ? anyErr.code : "";
    details = typeof anyErr.details === "string" ? anyErr.details : "";
    hint = typeof anyErr.hint === "string" ? anyErr.hint : "";
    requestId = typeof anyErr.requestId === "string" ? anyErr.requestId : "";
  } else if (typeof error === "object") {
    const obj = error as Record<string, unknown>;
    message = typeof obj.message === "string" ? obj.message : String(error);
    code = typeof obj.code === "string" ? obj.code : "";
    details = typeof obj.details === "string" ? obj.details : "";
    hint = typeof obj.hint === "string" ? obj.hint : "";
    requestId = typeof obj.requestId === "string" ? obj.requestId : "";
  }

  const lower = message.toLowerCase();
  const lowerDetails = details.toLowerCase();
  const sqlstate = code;

  // 1. Edge Function Failures
  if (
    lower.includes("functionsfetcherror") ||
    lower.includes("failed to send a request to the edge function") ||
    lower.includes("requested function was not found") ||
    lower.includes("functionshttperror") ||
    lower.includes("edge function")
  ) {
    let safeMessage = "Failed to communicate with the server management function.";
    if (lower.includes("not found") || lower.includes("failed to send a request")) {
      safeMessage =
        "The requested Edge Function is not deployed or unreachable. Please verify deployment in Supabase.";
    }
    return {
      category: "EDGE_FUNCTION_ERROR",
      sqlstate,
      code,
      safeMessage,
      operation,
      requestId,
    };
  }

  // 2. Authentication Failures
  if (
    lower.includes("jwt expired") ||
    lower.includes("invalid login credentials") ||
    lower.includes("invalid refresh token") ||
    lower.includes("user not found") ||
    lower.includes("email not confirmed")
  ) {
    let safeMessage = "Authentication failed. Please verify credentials or sign in again.";
    if (lower.includes("jwt expired")) {
      safeMessage = "Your session has expired. Please sign in again.";
    } else if (lower.includes("invalid login credentials")) {
      safeMessage = "Invalid email or password.";
    }
    return {
      category: "AUTH_ERROR",
      sqlstate,
      code,
      safeMessage,
      operation,
      requestId,
    };
  }

  // 3. PostgreSQL SQL Privilege vs RLS Violations (both can be 42501)
  if (sqlstate === "42501" || lower.includes("42501") || lower.includes("permission denied") || lower.includes("row-level security")) {
    if (lower.includes("row-level security") || lower.includes("policy")) {
      return {
        category: "RLS_VIOLATION",
        sqlstate: "42501",
        code: "42501",
        safeMessage:
          "Action restricted by database security policy. Ensure your account is active and assigned to this site.",
        operation,
        hint: hint || undefined,
      };
    }
    // Column or table SQL privilege denied
    return {
      category: "MISSING_PRIVILEGE",
      sqlstate: "42501",
      code: "42501",
      safeMessage:
        "Database operation privilege restricted. Server permissions prevent modifying these fields.",
      operation,
      hint: hint || undefined,
    };
  }

  // 4. Constraint Violations
  // 23505: unique_violation
  if (sqlstate === "23505" || lower.includes("duplicate key") || lower.includes("unique constraint")) {
    return {
      category: "CONSTRAINT_VIOLATION",
      sqlstate: "23505",
      code: "23505",
      safeMessage: "A record with these details already exists for this date and site.",
      operation,
    };
  }
  // 23503: foreign_key_violation
  if (sqlstate === "23503" || lower.includes("foreign key constraint")) {
    return {
      category: "CONSTRAINT_VIOLATION",
      sqlstate: "23503",
      code: "23503",
      safeMessage: "Referenced site, worker, or material record was not found.",
      operation,
    };
  }
  // 23502: not_null_violation
  if (sqlstate === "23502" || lower.includes("null value in column")) {
    return {
      category: "CONSTRAINT_VIOLATION",
      sqlstate: "23502",
      code: "23502",
      safeMessage: "A required field was missing from the submission.",
      operation,
    };
  }
  // 23514: check_violation
  if (sqlstate === "23514" || lower.includes("violates check constraint")) {
    return {
      category: "CONSTRAINT_VIOLATION",
      sqlstate: "23514",
      code: "23514",
      safeMessage: "One or more values did not meet validation rules (e.g. counts must be non-negative).",
      operation,
    };
  }

  // 5. Trigger Exceptions
  if (sqlstate === "P0001" || lower.includes("exception") || lower.includes("trigger")) {
    return {
      category: "TRIGGER_EXCEPTION",
      sqlstate: sqlstate || "P0001",
      code,
      safeMessage: message.replace(/^error:\s*/i, ""),
      operation,
    };
  }

  // 6. Schema Cache / Missing Table or Column
  if (
    sqlstate === "42P01" ||
    sqlstate === "42703" ||
    code === "PGRST204" ||
    code === "PGRST205" ||
    lower.includes("schema cache") ||
    lower.includes("does not exist")
  ) {
    return {
      category: "SCHEMA_CACHE_ERROR",
      sqlstate,
      code,
      safeMessage: "Database schema update required. Please notify your system administrator.",
      operation,
    };
  }

  // 7. Storage Failures
  if (lower.includes("storage") || lower.includes("bucket") || lower.includes("s3")) {
    return {
      category: "STORAGE_ERROR",
      sqlstate,
      code,
      safeMessage: "File upload or storage operation failed.",
      operation,
    };
  }

  // 8. PDF Generation Failures
  if (lower.includes("jspdf") || lower.includes("canvas") || lower.includes("pdf")) {
    return {
      category: "PDF_GENERATION_ERROR",
      sqlstate,
      code,
      safeMessage: "PDF document rendering failed. Please try again.",
      operation,
    };
  }

  return {
    category: "UNKNOWN_ERROR",
    sqlstate,
    code,
    safeMessage: message || "An unexpected error occurred.",
    operation,
  };
}

export function getErrorMessage(error: unknown, fallback = "An unexpected error occurred."): string {
  if (!error) return fallback;
  const diagnosed = diagnoseError(error);
  // Log safe debug diagnostic without leaking sensitive credentials
  if (process.env.NODE_ENV !== "production") {
    console.warn(`[Diagnostic ${diagnosed.category}]`, {
      code: diagnosed.sqlstate || diagnosed.code,
      operation: diagnosed.operation,
      message: diagnosed.safeMessage,
    });
  }
  return diagnosed.safeMessage || fallback;
}
