"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  FileDown,
  Users,
  Building2,
  ClipboardCheck,
  Package,
  AlertTriangle,
  RefreshCw,
  HardHat,
  FileSpreadsheet,
} from "lucide-react";
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
} from "recharts";
import { fetchSites } from "@/lib/data/sites";
import { fetchWorkers } from "@/lib/data/workers";
import { fetchAttendanceRange } from "@/lib/data/attendance";
import {
  fetchMaterials,
  fetchMaterialTransactions,
  isLowStock,
} from "@/lib/data/materials";
import { logActivity } from "@/lib/data/activity-logs";
import {
  exportAttendanceReportPdf,
  exportMaterialReportPdf,
  exportSiteReportPdf,
  exportWorkerReportPdf,
} from "@/lib/pdf/generators";
import type {
  MaterialRecord,
  MaterialTransactionRecord,
  SiteAttendanceRecord,
  SiteRecord,
  WorkerRecord,
} from "@/types/database";
import { formatNumber, getErrorMessage } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { StatusBadge } from "@/components/ui/badge";
import { ErrorBanner, LoadingCards, PageHeader } from "@/components/ui/states";
import { useToast } from "@/components/ui/toast";
import { useAuth } from "@/context/auth-context";
import { WorkforceReports } from "@/components/workforce-reports";

export default function ReportsPage() {
  const { selectedSiteId } = useAuth();
  const toast = useToast();

  const [activeTab, setActiveTab] = useState<"workforce" | "executive">("workforce");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sites, setSites] = useState<SiteRecord[]>([]);
  const [workers, setWorkers] = useState<WorkerRecord[]>([]);
  const [materials, setMaterials] = useState<MaterialRecord[]>([]);
  const [transactions, setTransactions] = useState<MaterialTransactionRecord[]>([]);
  const [monthAttendance, setMonthAttendance] = useState<SiteAttendanceRecord[]>([]);

  const monthStartIso = useMemo(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), 1)
      .toISOString()
      .slice(0, 10);
  }, []);

  const monthLabel = useMemo(
    () =>
      new Intl.DateTimeFormat("en-IN", {
        month: "long",
        year: "numeric",
      }).format(new Date()),
    []
  );

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [sitesData, workersData, matsData, txnsData, attData] =
        await Promise.all([
          fetchSites(),
          fetchWorkers(selectedSiteId || undefined),
          fetchMaterials(selectedSiteId || undefined),
          fetchMaterialTransactions({ sinceDate: monthStartIso }),
          fetchAttendanceRange(monthStartIso, undefined, {
            siteId: selectedSiteId || undefined,
          }),
        ]);
      const scopedSites = selectedSiteId
        ? sitesData.filter((s) => s.id === selectedSiteId)
        : sitesData;
      const activeSiteName = scopedSites[0]?.name?.toLowerCase();
      const scopedTxns =
        selectedSiteId && activeSiteName
          ? txnsData.filter(
              (t) => (t.site_name ?? "").toLowerCase() === activeSiteName
            )
          : txnsData;

      setSites(scopedSites);
      setWorkers(workersData);
      setMaterials(matsData);
      setTransactions(scopedTxns);
      setMonthAttendance(attData);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load report data."));
    } finally {
      setLoading(false);
    }
  }, [monthStartIso, selectedSiteId]);

  useEffect(() => {
    load();
  }, [load]);

  const lowStockItems = useMemo(
    () => materials.filter((m) => isLowStock(m)),
    [materials]
  );

  // Site-wise material usage chart for this month
  const siteUsageChart = useMemo(() => {
    const map = new Map<string, number>();
    for (const t of transactions) {
      if (t.transaction_type !== "USED") continue;
      const key = t.site_name?.trim() || "Central Stock";
      map.set(key, (map.get(key) ?? 0) + Number(t.quantity ?? 0));
    }
    return Array.from(map.entries())
      .map(([site, qty]) => ({ site, qty }))
      .sort((a, b) => b.qty - a.qty)
      .slice(0, 6);
  }, [transactions]);

  async function runExport(kind: "worker" | "attendance" | "material" | "site") {
    try {
      if (kind === "worker") {
        exportWorkerReportPdf(workers);
        await logActivity({
          action: "Report Generated",
          module: "Reports",
          description: `Worker Report exported (${workers.length} workers)`,
        });
      } else if (kind === "attendance") {
        exportAttendanceReportPdf(monthAttendance, monthLabel);
        await logActivity({
          action: "Report Generated",
          module: "Reports",
          description: `Attendance Report exported (${monthLabel}, ${monthAttendance.length} records)`,
        });
      } else if (kind === "material") {
        exportMaterialReportPdf(materials, transactions);
        await logActivity({
          action: "Report Generated",
          module: "Reports",
          description: `Material Inventory Report exported (${materials.length} materials)`,
        });
      } else {
        exportSiteReportPdf(sites);
        await logActivity({
          action: "Report Generated",
          module: "Reports",
          description: `Site Report exported (${sites.length} sites)`,
        });
      }
      toast.success("PDF report downloaded.");
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to export report PDF."));
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reports & Analytics"
        description="Comprehensive workforce deployment intelligence, executive PDF reports, and inventory consumption."
        actions={
          <Button variant="outline" size="sm" onClick={load} loading={loading}>
            <RefreshCw className="h-3.5 w-3.5" />
            Refresh Data
          </Button>
        }
      />

      {error && <ErrorBanner message={error} onRetry={load} />}

      {/* Main Tab Navigation */}
      <div className="flex flex-wrap gap-2 border-b border-[rgba(190,205,225,0.12)] pb-3">
        <button
          type="button"
          onClick={() => setActiveTab("workforce")}
          className={`flex items-center gap-2 rounded-xl px-4 py-2.5 text-xs font-semibold transition-all cursor-pointer ${
            activeTab === "workforce"
              ? "bg-[#4B83F5] text-white shadow-[0_0_16px_rgba(75,131,245,0.35)]"
              : "border border-[rgba(190,205,225,0.18)] bg-[rgba(23,28,36,0.6)] text-[#A7B0BE] hover:bg-white/5 hover:text-[#F2F4F8]"
          }`}
        >
          <HardHat className="h-4 w-4" />
          Workforce Deployment Reports
        </button>

        <button
          type="button"
          onClick={() => setActiveTab("executive")}
          className={`flex items-center gap-2 rounded-xl px-4 py-2.5 text-xs font-semibold transition-all cursor-pointer ${
            activeTab === "executive"
              ? "bg-[#4B83F5] text-white shadow-[0_0_16px_rgba(75,131,245,0.35)]"
              : "border border-[rgba(190,205,225,0.18)] bg-[rgba(23,28,36,0.6)] text-[#A7B0BE] hover:bg-white/5 hover:text-[#F2F4F8]"
          }`}
        >
          <FileDown className="h-4 w-4" />
          Executive PDF Exports &amp; Stock
        </button>
      </div>

      {/* TAB 1: WORKFORCE DEPLOYMENT REPORTS (Day-Wise & Week-Wise) */}
      {activeTab === "workforce" && <WorkforceReports />}

      {/* TAB 2: EXECUTIVE PDF EXPORTS & MATERIAL CONSUMPTION */}
      {activeTab === "executive" && (
        loading ? (
          <LoadingCards count={4} />
        ) : (
          <div className="space-y-6">
            {/* PDF Export Cards */}
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <Card className="border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.60)]">
                <CardContent className="flex h-full flex-col justify-between p-5">
                  <div>
                    <div className="mb-3 inline-flex rounded-xl bg-blue-500/15 border border-blue-500/30 p-2.5 text-[#4B83F5]">
                      <Users className="h-5 w-5" />
                    </div>
                    <h3 className="text-sm font-semibold text-[#F2F4F8]">
                      Worker Directory Report
                    </h3>
                    <p className="mt-1 text-xs text-[#A7B0BE]">
                      {workers.length} workers with roles, skills, sites &amp; status.
                    </p>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    className="mt-4 w-full"
                    onClick={() => runExport("worker")}
                  >
                    <FileDown className="h-3.5 w-3.5" />
                    Export PDF
                  </Button>
                </CardContent>
              </Card>

              <Card className="border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.60)]">
                <CardContent className="flex h-full flex-col justify-between p-5">
                  <div>
                    <div className="mb-3 inline-flex rounded-xl bg-emerald-500/15 border border-emerald-500/30 p-2.5 text-[#39B980]">
                      <ClipboardCheck className="h-5 w-5" />
                    </div>
                    <h3 className="text-sm font-semibold text-[#F2F4F8]">
                      Attendance Summary Report
                    </h3>
                    <p className="mt-1 text-xs text-[#A7B0BE]">
                      {monthAttendance.length} records logged in {monthLabel}.
                    </p>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    className="mt-4 w-full"
                    onClick={() => runExport("attendance")}
                  >
                    <FileDown className="h-3.5 w-3.5" />
                    Export PDF
                  </Button>
                </CardContent>
              </Card>

              <Card className="border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.60)]">
                <CardContent className="flex h-full flex-col justify-between p-5">
                  <div>
                    <div className="mb-3 inline-flex rounded-xl bg-amber-500/15 border border-amber-500/30 p-2.5 text-[#E5AD55]">
                      <Package className="h-5 w-5" />
                    </div>
                    <h3 className="text-sm font-semibold text-[#F2F4F8]">
                      Material Inventory Report
                    </h3>
                    <p className="mt-1 text-xs text-[#A7B0BE]">
                      {materials.length} items, {lowStockItems.length} low stock alerts &amp; transactions.
                    </p>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    className="mt-4 w-full"
                    onClick={() => runExport("material")}
                  >
                    <FileDown className="h-3.5 w-3.5" />
                    Export PDF
                  </Button>
                </CardContent>
              </Card>

              <Card className="border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.60)]">
                <CardContent className="flex h-full flex-col justify-between p-5">
                  <div>
                    <div className="mb-3 inline-flex rounded-xl bg-purple-500/15 border border-purple-500/30 p-2.5 text-purple-400">
                      <Building2 className="h-5 w-5" />
                    </div>
                    <h3 className="text-sm font-semibold text-[#F2F4F8]">
                      Site Portfolio Report
                    </h3>
                    <p className="mt-1 text-xs text-[#A7B0BE]">
                      {sites.length} sites with locations, managers &amp; progress.
                    </p>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    className="mt-4 w-full"
                    onClick={() => runExport("site")}
                  >
                    <FileDown className="h-3.5 w-3.5" />
                    Export PDF
                  </Button>
                </CardContent>
              </Card>
            </div>

            {/* Analytics Visuals */}
            <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
              <Card>
                <CardHeader>
                  <div>
                    <CardTitle>Material Consumption by Site ({monthLabel})</CardTitle>
                    <CardDescription>Total USED quantities logged this month</CardDescription>
                  </div>
                </CardHeader>
                <CardContent>
                  {siteUsageChart.length === 0 ? (
                    <p className="py-12 text-center text-xs text-[#A7B0BE]">
                      No material usage transactions recorded this month.
                    </p>
                  ) : (
                    <div className="h-64 w-full">
                      <ResponsiveContainer width="100%" height="100%">
                        <BarChart
                          data={siteUsageChart}
                          margin={{ top: 8, right: 8, left: -16, bottom: 0 }}
                        >
                          <CartesianGrid strokeDasharray="3 3" stroke="rgba(190,205,225,0.10)" vertical={false} />
                          <XAxis dataKey="site" tick={{ fontSize: 11, fill: "#A7B0BE" }} />
                          <YAxis tick={{ fontSize: 11, fill: "#A7B0BE" }} />
                          <Tooltip
                            contentStyle={{
                              backgroundColor: "#171C24",
                              borderColor: "rgba(190,205,225,0.20)",
                              borderRadius: "12px",
                              color: "#F2F4F8",
                            }}
                          />
                          <Bar dataKey="qty" name="Units Used" fill="#4B83F5" radius={[6, 6, 0, 0]} maxBarSize={36} />
                        </BarChart>
                      </ResponsiveContainer>
                    </div>
                  )}
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <div className="flex items-center gap-2">
                    <AlertTriangle className="h-4 w-4 text-[#E5AD55]" />
                    <div>
                      <CardTitle>Low Stock Watchlist ({lowStockItems.length})</CardTitle>
                      <CardDescription>Items at or below minimum required balance</CardDescription>
                    </div>
                  </div>
                </CardHeader>
                <CardContent className="p-0">
                  {lowStockItems.length === 0 ? (
                    <p className="p-8 text-center text-xs text-[#A7B0BE]">
                      No materials are currently below minimum stock threshold.
                    </p>
                  ) : (
                    <div className="divide-y divide-[rgba(190,205,225,0.08)]">
                      {lowStockItems.map((m) => (
                        <div
                          key={m.id}
                          className="flex items-center justify-between px-5 py-3.5 hover:bg-white/[0.03] transition-colors"
                        >
                          <div>
                            <p className="text-sm font-semibold text-[#F2F4F8]">{m.name}</p>
                            <p className="text-xs text-[#A7B0BE]">
                              Balance: {formatNumber(m.balance_qty)} {m.unit} · Min:{" "}
                              {formatNumber(m.minimum_stock ?? 10)}
                            </p>
                          </div>
                          <StatusBadge status="Low Stock" />
                        </div>
                      ))}
                    </div>
                  )}
                </CardContent>
              </Card>
            </div>
          </div>
        )
      )}
    </div>
  );
}

