import * as React from "react";
import { cn } from "@/lib/utils";

export type BadgeVariant =
  | "neutral"
  | "blue"
  | "success"
  | "warning"
  | "danger"
  | "navy";

const variantStyles: Record<BadgeVariant, string> = {
  neutral: "bg-white/5 text-[#A7B0BE] border-white/10",
  blue: "bg-blue-500/15 text-[#4B83F5] border-blue-500/30",
  success: "bg-emerald-500/15 text-[#39B980] border-emerald-500/30",
  warning: "bg-amber-500/15 text-[#E5AD55] border-amber-500/30",
  danger: "bg-red-500/15 text-[#E56B72] border-red-500/30",
  navy: "bg-[#171C24] text-[#F2F4F8] border-[rgba(190,205,225,0.18)]",
};

export function Badge({
  children,
  variant = "neutral",
  className,
}: {
  children: React.ReactNode;
  variant?: BadgeVariant;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-lg border px-2.5 py-0.5 text-xs font-medium leading-4 whitespace-nowrap shadow-xs",
        variantStyles[variant],
        className
      )}
    >
      {children}
    </span>
  );
}

export function StatusBadge({ status }: { status: string | null | undefined }) {
  const value = (status ?? "Unknown").trim();
  const lower = value.toLowerCase();

  let variant: BadgeVariant = "neutral";
  if (["active", "present", "completed", "received", "ok"].includes(lower)) {
    variant = "success";
  } else if (["on hold", "half day", "low stock", "warning"].includes(lower)) {
    variant = "warning";
  } else if (["disabled", "inactive", "absent", "used", "danger"].includes(lower)) {
    variant = lower === "used" ? "blue" : "danger";
  } else if (["admin", "projectmanager"].includes(lower)) {
    variant = "blue";
  }

  return <Badge variant={variant}>{value}</Badge>;
}
