"use client";

import React, { useCallback, useEffect, useState } from "react";
import {
  Activity,
  FileDown,
  FileSpreadsheet,
  RefreshCw,
  Search,
  Shield,
} from "lucide-react";
import { fetchActivityLogs } from "@/lib/data/activity-logs";
import { exportActivityLogPdf } from "@/lib/pdf/generators";
import { downloadCsv } from "@/lib/csv";
import type { ActivityLogRecord } from "@/types/database";
import { formatDisplayDateTime, getErrorMessage } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import {
  EmptyState,
  ErrorBanner,
  LoadingTable,
  PageHeader,
} from "@/components/ui/states";

const MODULES = [
  "All",
  "Attendance",
  "Materials",
  "Workers",
  "Sites",
  "Loading Memo",
  "Reports",
  "Admin",
  "Auth",
];

export default function ActivityLogsPage() {
  const [logs, setLogs] = useState<ActivityLogRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [moduleFilter, setModuleFilter] = useState("All");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await fetchActivityLogs({
        searchQuery: search,
        moduleFilter,
        fromDate: fromDate || undefined,
        toDate: toDate || undefined,
        limit: 150,
      });
      setLogs(data);
    } catch (err) {
      setError(getErrorMessage(err, "Unable to load activity logs."));
    } finally {
      setLoading(false);
    }
  }, [search, moduleFilter, fromDate, toDate]);

  useEffect(() => {
    load();
  }, [load]);

  function handleCsvExport() {
    downloadCsv(
      `tsr_activity_logs_${new Date().toISOString().slice(0, 10)}.csv`,
      ["Timestamp", "Module", "Action", "User", "Old Value", "New Value", "Description"],
      logs.map((l) => [
        l.created_at,
        l.module,
        l.action,
        l.user_name ?? "Unknown",
        l.old_value ?? "",
        l.new_value ?? "",
        l.description ?? "",
      ])
    );
  }

  return (
    <div>
      <PageHeader
        title="Activity Audit Trail"
        description="Tamper-evident operational log. Visibility is enforced by Supabase Row Level Security."
        actions={
          <>
            <Button variant="outline" size="sm" onClick={load} loading={loading}>
              <RefreshCw className="h-3.5 w-3.5" />
              Refresh
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={handleCsvExport}
              disabled={logs.length === 0}
            >
              <FileSpreadsheet className="h-3.5 w-3.5" />
              CSV
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => exportActivityLogPdf(logs)}
              disabled={logs.length === 0}
            >
              <FileDown className="h-3.5 w-3.5" />
              PDF
            </Button>
          </>
        }
      />

      {error && <ErrorBanner message={error} onRetry={load} />}

      <Card>
        <CardHeader>
          <div>
            <CardTitle>Recorded Events ({logs.length})</CardTitle>
            <CardDescription className="inline-flex items-center gap-1">
              <Shield className="h-3 w-3" />
              Append-only ledger — client updates and deletions are disabled at database level.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          {/* Filters */}
          <div className="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div className="relative">
              <Search className="pointer-events-none absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-slate-400" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search action, user, description…"
                className="h-10 w-full rounded-lg border border-slate-300 bg-white pr-3 pl-9 text-sm text-slate-900 placeholder:text-slate-400 focus:border-[#2563EB] focus:outline-none focus:ring-2 focus:ring-[#2563EB]/20"
              />
            </div>
            <Input
              type="date"
              aria-label="From date"
              value={fromDate}
              onChange={(e) => setFromDate(e.target.value)}
            />
            <Input
              type="date"
              aria-label="To date"
              value={toDate}
              onChange={(e) => setToDate(e.target.value)}
            />
          </div>

          <div className="mb-5 flex flex-wrap gap-1.5">
            {MODULES.map((mod) => (
              <button
                key={mod}
                type="button"
                onClick={() => setModuleFilter(mod)}
                className={`rounded-md px-2.5 py-1 text-xs font-medium transition-colors cursor-pointer ${
                  moduleFilter === mod
                    ? "bg-[#0B1628] text-white"
                    : "border border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
                }`}
              >
                {mod}
              </button>
            ))}
          </div>

          {loading ? (
            <LoadingTable rows={6} />
          ) : logs.length === 0 ? (
            <EmptyState
              icon={Activity}
              title="No Accessible Activity Logs"
              description="Either no events match your filters or your database role does not have SELECT permission on activity logs."
            />
          ) : (
            <div className="divide-y divide-slate-100 rounded-xl border border-slate-200">
              {logs.map((log) => (
                <div
                  key={log.id}
                  className="flex flex-col justify-between gap-2 px-4 py-3.5 hover:bg-slate-50/70 sm:flex-row sm:items-center"
                >
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <Badge variant="blue">{log.module}</Badge>
                      <span className="text-sm font-semibold text-slate-900">
                        {log.action}
                      </span>
                    </div>
                    {log.description && (
                      <p className="mt-1 text-xs text-slate-600">
                        {log.description}
                      </p>
                    )}
                    <div className="mt-1 flex flex-wrap items-center gap-2 text-[11px] text-slate-400">
                      <span>{log.user_name || "Unknown"}</span>
                      {log.old_value && log.new_value && (
                        <span className="rounded bg-slate-100 px-1.5 py-0.5 text-slate-600">
                          {log.old_value} → {log.new_value}
                        </span>
                      )}
                    </div>
                  </div>
                  <span className="shrink-0 text-xs text-slate-400">
                    {formatDisplayDateTime(log.created_at)}
                  </span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

