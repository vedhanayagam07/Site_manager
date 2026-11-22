import React from "react";
import type { LucideIcon } from "lucide-react";
import { AlertCircle, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: string;
  actions?: React.ReactNode;
}) {
  return (
    <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 className="text-xl font-bold tracking-tight text-[#F2F4F8] sm:text-2xl">
          {title}
        </h1>
        {description && (
          <p className="mt-0.5 text-sm text-[#A7B0BE]">{description}</p>
        )}
      </div>
      {actions && (
        <div className="flex flex-wrap items-center gap-2">{actions}</div>
      )}
    </div>
  );
}

export function EmptyState({
  icon: Icon,
  title,
  description,
  action,
}: {
  icon: LucideIcon;
  title: string;
  description: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center rounded-2xl border border-dashed border-[rgba(190,205,225,0.20)] bg-[rgba(35,42,53,0.35)] backdrop-blur-sm px-6 py-12 text-center">
      <div className="rounded-2xl border border-[rgba(190,205,225,0.15)] bg-white/5 p-3.5 text-[#A7B0BE]">
        <Icon className="h-6 w-6" />
      </div>
      <h3 className="mt-4 text-sm font-semibold text-[#F2F4F8]">{title}</h3>
      <p className="mt-1 max-w-sm text-xs text-[#A7B0BE]">{description}</p>
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}

export function ErrorBanner({
  message,
  onRetry,
}: {
  message: string;
  onRetry?: () => void;
}) {
  return (
    <div className="mb-4 flex flex-col items-start justify-between gap-3 rounded-2xl border border-red-500/30 bg-red-950/40 backdrop-blur-md px-4 py-3 text-sm text-red-200 sm:flex-row sm:items-center">
      <div className="flex items-start gap-2.5">
        <AlertCircle className="mt-0.5 h-4 w-4 shrink-0 text-[#E56B72]" />
        <span className="text-xs sm:text-sm">{message}</span>
      </div>
      {onRetry && (
        <Button variant="outline" size="sm" onClick={onRetry}>
          <RefreshCw className="h-3.5 w-3.5" />
          Retry
        </Button>
      )}
    </div>
  );
}

export function LoadingCards({ count = 4 }: { count?: number }) {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {Array.from({ length: count }).map((_, idx) => (
        <div
          key={idx}
          className="h-28 animate-pulse rounded-2xl border border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.50)] p-5"
        >
          <div className="h-3 w-24 rounded-md bg-white/10" />
          <div className="mt-4 h-7 w-16 rounded-md bg-white/10" />
          <div className="mt-2 h-2.5 w-32 rounded-md bg-white/5" />
        </div>
      ))}
    </div>
  );
}

export function LoadingTable({ rows = 5 }: { rows?: number }) {
  return (
    <div className="rounded-2xl border border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.50)] p-5">
      <div className="space-y-3">
        {Array.from({ length: rows }).map((_, i) => (
          <div
            key={i}
            className="flex items-center justify-between border-b border-[rgba(190,205,225,0.08)] pb-3 last:border-0"
          >
            <div className="h-4 w-48 rounded-md bg-white/10" />
            <div className="h-4 w-20 rounded-md bg-white/5" />
          </div>
        ))}
      </div>
    </div>
  );
}
