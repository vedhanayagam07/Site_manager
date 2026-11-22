import React from "react";
import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

interface StatCardProps {
  label: string;
  value: string | number;
  subtitle?: string;
  icon: LucideIcon;
  tone?: "blue" | "slate" | "emerald" | "amber" | "red";
  onClick?: () => void;
}

const toneIconStyles: Record<NonNullable<StatCardProps["tone"]>, string> = {
  blue: "bg-blue-500/15 text-[#4B83F5] border border-blue-500/30 shadow-[0_0_12px_rgba(75,131,245,0.20)]",
  slate: "bg-white/5 text-[#A7B0BE] border border-white/10",
  emerald: "bg-emerald-500/15 text-[#39B980] border border-emerald-500/30 shadow-[0_0_12px_rgba(57,185,128,0.20)]",
  amber: "bg-amber-500/15 text-[#E5AD55] border border-amber-500/30 shadow-[0_0_12px_rgba(229,173,85,0.20)]",
  red: "bg-red-500/15 text-[#E56B72] border border-red-500/30 shadow-[0_0_12px_rgba(229,107,114,0.20)]",
};

export function StatCard({
  label,
  value,
  subtitle,
  icon: Icon,
  tone = "blue",
  onClick,
}: StatCardProps) {
  const Tag = onClick ? "button" : "div";
  return (
    <Tag
      type={onClick ? "button" : undefined}
      onClick={onClick}
      className={cn(
        "flex w-full items-start justify-between rounded-2xl border border-[rgba(220,230,245,0.18)] bg-[rgba(45,53,65,0.68)] backdrop-blur-md p-5 text-left shadow-[0_8px_32px_-2px_rgba(0,0,0,0.40)] transition-all duration-200",
        onClick && "cursor-pointer hover:border-[#4B83F5]/40 hover:bg-[rgba(52,62,75,0.78)] hover:shadow-[0_12px_36px_-2px_rgba(0,0,0,0.55)] active:scale-[0.99]"
      )}
    >
      <div className="min-w-0">
        <p className="text-xs font-medium uppercase tracking-wider text-[#A7B0BE]">
          {label}
        </p>
        <p className="mt-2 text-2xl font-bold tracking-tight text-[#F2F4F8]">
          {value}
        </p>
        {subtitle && (
          <p className="mt-1 truncate text-xs text-[#778292]">{subtitle}</p>
        )}
      </div>
      <div className={cn("rounded-xl p-2.5 shrink-0", toneIconStyles[tone])}>
        <Icon className="h-5 w-5" />
      </div>
    </Tag>
  );
}
