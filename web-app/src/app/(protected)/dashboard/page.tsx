"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  Building2,
  Users,
  Package,
  AlertTriangle,
  ClipboardCheck,
  FileText,
  RefreshCw,
  ArrowRight,
  ArrowDownLeft,
  ArrowUpRight,
  Activity,
  HardHat,
  Camera,
  Sparkles,
  LayoutDashboard,
} from "lucide-react";
import GlassyDashboard from "@/components/ui/glassy-dashboard";
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
} from "recharts";
import { useAuth } from "@/context/auth-context";
import { fetchSites } from "@/lib/data/sites";
import { fetchWorkers } from "@/lib/data/workers";
import { fetchAttendanceRange } from "@/lib/data/attendance";
import {
  fetchMaterials,
  fetchMaterialTransactions,
  isLowStock,
} from "@/lib/data/materials";
import { fetchActivityLogs } from "@/lib/data/activity-logs";
import { fetchSiteProgressUpdates } from "@/lib/data/site-progress";
import type {
  ActivityLogRecord,
  MaterialRecord,
  MaterialTransactionRecord,
  SiteAttendanceRecord,
  SiteProgressUpdateRecord,
  SiteRecord,
  WorkerRecord,
} from "@/types/database";
import {
  formatDisplayDateTime,
  formatNumber,
  formatRoleLabel,
  getErrorMessage,
  todayIsoDate,
} from "@/lib/utils";
import { StatCard } from "@/components/ui/stat-card";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusBadge, Badge } from "@/components/ui/badge";
import {
  EmptyState,
  ErrorBanner,
  LoadingCards,
  PageHeader,
} from "@/components/ui/states";

export default function DashboardPage() {
  const router = useRouter();
  const { profile, isAdmin, isPmOrAdmin, isSupervisor, selectedSiteId } = useAuth();

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [sites, setSites] = useState<SiteRecord[]>([]);
  const [workers, setWorkers] = useState<WorkerRecord[]>([]);
  const [materials, setMaterials] = useState<MaterialRecord[]>([]);
  const [transactions, setTransactions] = useState<MaterialTransactionRecord[]>([]);
  const [attendance, setAttendance] = useState<SiteAttendanceRecord[]>([]);
  const [adminLogs, setAdminLogs] = useState<ActivityLogRecord[]>([]);
  const [recentProgress, setRecentProgress] = useState<SiteProgressUpdateRecord[]>([]);

  const [viewMode, setViewMode] = useState<"classic" | "glassy">(() => {
    if (typeof window !== "undefined") {
      return (localStorage.getItem("tsr_dashboard_view_mode") as "classic" | "glassy") || "classic";
    }
    return "classic";
  });

  const handleSetViewMode = (mode: "classic" | "glassy") => {
    setViewMode(mode);
    if (typeof window !== "undefined") {
      localStorage.setItem("tsr_dashboard_view_mode", mode);
    }
  };

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const today = todayIsoDate();
      const sevenDaysAgoDate = new Date();
      sevenDaysAgoDate.setDate(sevenDaysAgoDate.getDate() - 6);
      const sevenDaysAgo = sevenDaysAgoDate.toISOString().slice(0, 10);

      const [sitesData, workersData, materialsData, txnsData, attData, progressRes] =
        await Promise.all([
          fetchSites(),
          fetchWorkers(selectedSiteId || undefined),
          fetchMaterials(selectedSiteId || undefined),
          fetchMaterialTransactions({ limit: 30 }),
          fetchAttendanceRange(sevenDaysAgo, today, {
            siteId: selectedSiteId || undefined,
          }),
          fetchSiteProgressUpdates({
            siteId: selectedSiteId || undefined,
          }).catch(() => ({ tableReady: false, records: [] })),
        ]);

      setSites(sitesData);
      setWorkers(workersData);
      setMaterials(materialsData);
      setTransactions(txnsData);
      setAttendance(attData);
      setRecentProgress(progressRes.tableReady ? progressRes.records.slice(0, 4) : []);

      if (isAdmin) {
        try {
          const logs = await fetchActivityLogs({ limit: 8 });
          setAdminLogs(logs);
        } catch {
          setAdminLogs([]);
        }
      } else {
        setAdminLogs([]);
      }
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load dashboard overview."));
    } finally {
      setLoading(false);
    }
  }, [isAdmin, selectedSiteId]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const activeSiteObj = useMemo(
    () => sites.find((s) => s.id === selectedSiteId) ?? null,
    [sites, selectedSiteId]
  );

  const visibleSites = useMemo(
    () => (selectedSiteId ? sites.filter((s) => s.id === selectedSiteId) : sites),
    [sites, selectedSiteId]
  );

  const activeSitesCount = useMemo(
    () =>
      visibleSites.filter((s) =>
        ["active", "in progress"].includes((s.status ?? "").toLowerCase())
      ).length,
    [visibleSites]
  );

  const lowStockMaterials = useMemo(
    () => materials.filter((m) => isLowStock(m)),
    [materials]
  );

  const todayStr = todayIsoDate();
  const todayAttendance = useMemo(
    () => attendance.filter((a) => a.attendance_date === todayStr),
    [attendance, todayStr]
  );
  const todayPresent = useMemo(
    () => todayAttendance.filter((a) => a.status === "Present").length,
    [todayAttendance]
  );
  const todayHalfDay = useMemo(
    () => todayAttendance.filter((a) => a.status === "Half Day").length,
    [todayAttendance]
  );
  const todayTradeBreakdown = useMemo(() => {
    const map = new Map<string, number>();
    for (const r of todayAttendance) {
      if (r.status === "Absent") continue;
      const role = r.workers?.role?.trim() || "General";
      map.set(role, (map.get(role) ?? 0) + 1);
    }
    return Array.from(map.entries())
      .map(([trade, count]) => ({ trade, count }))
      .sort((a, b) => b.count - a.count);
  }, [todayAttendance]);

  // Build 7-day attendance trend for Recharts
  const attendanceChartData = useMemo(() => {
    const days: Array<{ date: string; label: string; Present: number; HalfDay: number; Absent: number }> = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date();
      d.setDate(d.getDate() - i);
      const iso = d.toISOString().slice(0, 10);
      const label = new Intl.DateTimeFormat("en-IN", {
        weekday: "short",
        day: "2-digit",
      }).format(d);
      const dayRecords = attendance.filter((r) => r.attendance_date === iso);
      days.push({
        date: iso,
        label,
        Present: dayRecords.filter((r) => r.status === "Present").length,
        HalfDay: dayRecords.filter((r) => r.status === "Half Day").length,
        Absent: dayRecords.filter((r) => r.status === "Absent").length,
      });
    }
    return days;
  }, [attendance]);

  const filteredTxns = useMemo(() => {
    if (!activeSiteObj) return transactions.slice(0, 6);
    return transactions
      .filter(
        (t) =>
          (t.site_name ?? "").toLowerCase() === activeSiteObj.name.toLowerCase()
      )
      .slice(0, 6);
  }, [transactions, activeSiteObj]);

  const roleHeadline = isAdmin
    ? "Executive Operations Overview"
    : isPmOrAdmin
    ? "Project Manager Operations Hub"
    : "Site Supervisor Daily Workspace";

  if (viewMode === "glassy") {
    return (
      <div className="relative -m-4 min-h-screen sm:-m-6 lg:-m-8">
        {/* Floating Top-Right Mode Toggle */}
        <div className="fixed top-3 right-4 z-50 flex items-center gap-1.5 rounded-full border border-white/20 bg-[#0B1628]/85 p-1 text-white shadow-xl backdrop-blur-md">
          <button
            type="button"
            onClick={() => handleSetViewMode("classic")}
            className="flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold text-slate-300 hover:bg-white/10 hover:text-white transition-colors"
          >
            <LayoutDashboard className="h-3.5 w-3.5" />
            Classic Grid
          </button>
          <div className="flex items-center gap-1 rounded-full bg-blue-600 px-3 py-1 text-xs font-bold text-white shadow-xs">
            <Sparkles className="h-3.5 w-3.5 text-amber-300" />
            Glassy Theme
          </div>
        </div>

        <GlassyDashboard
          workspaceName="TSR BUILDERS"
          backgroundImage="/tsrbuilders.png"
          initialTheme="dark"
        />
      </div>
    );
  }

  return (
    <div>
      <PageHeader
        title={activeSiteObj ? `${activeSiteObj.name} — Dashboard` : roleHeadline}
        description={`Signed in as ${profile?.name ?? "Staff"} (${formatRoleLabel(profile?.role)})${activeSiteObj ? ` · Filtered to ${activeSiteObj.location ?? activeSiteObj.name}` : ""}`}
        actions={
          <>
            {/* View Mode Switcher */}
            <div className="flex items-center rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 p-0.5 shadow-xs">
              <button
                type="button"
                onClick={() => handleSetViewMode("classic")}
                className="flex items-center gap-1.5 rounded-lg bg-[rgba(45,53,65,0.85)] px-2.5 py-1 text-xs font-semibold text-white shadow-xs"
              >
                <LayoutDashboard className="h-3.5 w-3.5 text-[#4B83F5]" />
                Dashboard
              </button>
              <button
                type="button"
                onClick={() => handleSetViewMode("glassy")}
                className="flex items-center gap-1.5 rounded-lg px-2.5 py-1 text-xs font-semibold text-[#A7B0BE] hover:bg-white/5 hover:text-white transition-colors"
              >
                <Sparkles className="h-3.5 w-3.5 text-[#E5AD55]" />
                ✨ Spatial Hub
              </button>
            </div>
            <Button variant="outline" size="sm" onClick={loadData} loading={loading}>
              <RefreshCw className="h-3.5 w-3.5" />
              Refresh
            </Button>
            <Link href="/attendance">
              <Button size="sm">
                <ClipboardCheck className="h-4 w-4" />
                Daily Attendance
              </Button>
            </Link>
          </>
        }
      />

      {error && <ErrorBanner message={error} onRetry={loadData} />}

      {/* KPI Row */}
      {loading ? (
        <LoadingCards count={4} />
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            label={isSupervisor ? "Accessible Sites" : "Active Sites"}
            value={activeSitesCount}
            subtitle={`${visibleSites.length} total sites`}
            icon={Building2}
            tone="blue"
            onClick={() => router.push("/sites")}
          />
          <StatCard
            label="Today's Workforce"
            value={todayPresent + todayHalfDay}
            subtitle={
              todayAttendance.length > 0
                ? `${todayPresent} present · ${todayHalfDay} half day · ${workers.length} total`
                : `${workers.length} registered workers`
            }
            icon={HardHat}
            tone="emerald"
            onClick={() => router.push("/attendance")}
          />
          <StatCard
            label="Materials Tracked"
            value={materials.length}
            subtitle={`${transactions.length} recent stock movements`}
            icon={Package}
            tone="slate"
            onClick={() => router.push("/materials")}
          />
          <StatCard
            label="Low Stock Alerts"
            value={lowStockMaterials.length}
            subtitle={
              lowStockMaterials.length > 0
                ? "Requires replenishment"
                : "All stock levels healthy"
            }
            icon={AlertTriangle}
            tone={lowStockMaterials.length > 0 ? "red" : "emerald"}
            onClick={() => router.push("/materials")}
          />
        </div>
      )}

      {/* Today's Active Trade Breakdown (Derived from Existing site_attendance) */}
      {!loading && todayTradeBreakdown.length > 0 && (
        <div className="mt-5 rounded-2xl border border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.50)] backdrop-blur-md px-5 py-3.5 shadow-xs">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold uppercase tracking-wider text-[#A7B0BE]">
              On-Site Today by Trade:
            </span>
            {todayTradeBreakdown.map((item) => (
              <Badge key={item.trade} variant="blue">
                {item.trade}: {item.count}
              </Badge>
            ))}
          </div>
        </div>
      )}

      {/* Quick Operations Bar (Role-Aware) */}
      <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-5">
        <Link
          href="/progress"
          className="flex items-center gap-3 rounded-2xl border border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.50)] backdrop-blur-md p-3.5 text-sm font-medium text-[#F2F4F8] shadow-xs transition-all duration-150 hover:border-[#4B83F5]/40 hover:bg-[rgba(45,53,65,0.70)] hover:shadow-[0_8px_24px_rgba(0,0,0,0.3)]"
        >
          <div className="rounded-xl border border-indigo-500/30 bg-indigo-500/15 p-2 text-indigo-400">
            <Camera className="h-4 w-4" />
          </div>
          <span className="truncate">Site Progress</span>
        </Link>

        <Link
          href="/attendance"
          className="flex items-center gap-3 rounded-2xl border border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.50)] backdrop-blur-md p-3.5 text-sm font-medium text-[#F2F4F8] shadow-xs transition-all duration-150 hover:border-[#4B83F5]/40 hover:bg-[rgba(45,53,65,0.70)] hover:shadow-[0_8px_24px_rgba(0,0,0,0.3)]"
        >
          <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/15 p-2 text-[#39B980]">
            <ClipboardCheck className="h-4 w-4" />
          </div>
          <span className="truncate">Log Attendance</span>
        </Link>

        <Link
          href="/materials"
          className="flex items-center gap-3 rounded-2xl border border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.50)] backdrop-blur-md p-3.5 text-sm font-medium text-[#F2F4F8] shadow-xs transition-all duration-150 hover:border-[#4B83F5]/40 hover:bg-[rgba(45,53,65,0.70)] hover:shadow-[0_8px_24px_rgba(0,0,0,0.3)]"
        >
          <div className="rounded-xl border border-blue-500/30 bg-blue-500/15 p-2 text-[#4B83F5]">
            <Package className="h-4 w-4" />
          </div>
          <span className="truncate">Stock Movement</span>
        </Link>

        <Link
          href="/loading-memos"
          className="flex items-center gap-3 rounded-2xl border border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.50)] backdrop-blur-md p-3.5 text-sm font-medium text-[#F2F4F8] shadow-xs transition-all duration-150 hover:border-[#4B83F5]/40 hover:bg-[rgba(45,53,65,0.70)] hover:shadow-[0_8px_24px_rgba(0,0,0,0.3)]"
        >
          <div className="rounded-xl border border-white/15 bg-white/5 p-2 text-[#A7B0BE]">
            <FileText className="h-4 w-4" />
          </div>
          <span className="truncate">Loading Memo</span>
        </Link>

        <Link
          href={isAdmin ? "/admin" : isPmOrAdmin ? "/sites" : "/workers"}
          className="flex items-center gap-3 rounded-2xl border border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.50)] backdrop-blur-md p-3.5 text-sm font-medium text-[#F2F4F8] shadow-xs transition-all duration-150 hover:border-[#4B83F5]/40 hover:bg-[rgba(45,53,65,0.70)] hover:shadow-[0_8px_24px_rgba(0,0,0,0.3)]"
        >
          <div className="rounded-xl border border-amber-500/30 bg-amber-500/15 p-2 text-[#E5AD55]">
            {isAdmin ? (
              <Users className="h-4 w-4" />
            ) : (
              <Building2 className="h-4 w-4" />
            )}
          </div>
          <span className="truncate">
            {isAdmin ? "Manage Users" : isPmOrAdmin ? "Manage Sites" : "View Workers"}
          </span>
        </Link>
      </div>

      {/* Latest Site Progress & Photos Strip */}
      <Card className="mt-6">
        <CardHeader className="flex flex-row items-center justify-between pb-3">
          <div>
            <CardTitle className="text-base flex items-center gap-2">
              <Camera className="h-4 w-4 text-[#4B83F5]" />
              Latest Field Photos & Site Progress
            </CardTitle>
            <CardDescription className="text-xs">
              Recent photo uploads and daily work updates from field supervisors
            </CardDescription>
          </div>
          <Link href="/progress">
            <Button variant="ghost" size="sm" className="text-xs gap-1.5 cursor-pointer">
              <span>Photo Gallery</span>
              <ArrowRight className="h-3.5 w-3.5" />
            </Button>
          </Link>
        </CardHeader>
        <CardContent>
          {recentProgress.length === 0 ? (
            <div className="flex flex-col sm:flex-row items-center justify-between rounded-2xl bg-white/5 border border-dashed border-[rgba(190,205,225,0.18)] p-4 gap-3 text-center sm:text-left">
              <div className="flex items-center gap-3">
                <div className="rounded-full bg-blue-500/15 border border-blue-500/30 p-2.5 text-[#4B83F5]">
                  <Camera className="h-5 w-5" />
                </div>
                <div>
                  <p className="text-sm font-semibold text-[#F2F4F8]">
                    No progress updates posted yet today
                  </p>
                  <p className="text-xs text-[#A7B0BE]">
                    Supervisors can take photos of work completed on mobile and post progress updates.
                  </p>
                </div>
              </div>
              <Link href="/progress">
                <Button size="sm" className="shrink-0 text-xs">
                  Upload Site Photos
                </Button>
              </Link>
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-3">
              {recentProgress.map((up) => {
                const firstPhoto = up.photos?.[0];
                return (
                  <Link
                    key={up.id}
                    href="/progress"
                    className="group rounded-2xl border border-[rgba(190,205,225,0.15)] p-2.5 hover:border-[#4B83F5]/40 hover:bg-[rgba(35,42,53,0.70)] hover:shadow-md transition-all bg-[rgba(23,28,36,0.60)] backdrop-blur-sm flex flex-col justify-between"
                  >
                    <div className="aspect-4/3 w-full rounded-xl bg-black/40 overflow-hidden relative mb-2">
                      {firstPhoto?.signed_url ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={firstPhoto.signed_url}
                          alt={up.category}
                          className="h-full w-full object-cover group-hover:scale-105 transition-transform duration-200"
                        />
                      ) : (
                        <div className="flex h-full w-full items-center justify-center text-[#778292]">
                          <Camera className="h-6 w-6" />
                        </div>
                      )}
                      <div className="absolute top-1.5 left-1.5 rounded-full bg-black/70 backdrop-blur-xs px-2 py-0.5 text-[10px] font-semibold text-white border border-white/10">
                        {up.category}
                      </div>
                      {up.photos && up.photos.length > 1 && (
                        <div className="absolute bottom-1.5 right-1.5 rounded bg-black/80 px-1.5 py-0.5 text-[10px] font-medium text-white border border-white/10">
                          +{up.photos.length - 1} more
                        </div>
                      )}
                    </div>
                    <div>
                      <div className="flex items-center justify-between text-[11px] text-[#A7B0BE] mb-1">
                        <span className="font-medium text-[#F2F4F8] truncate">
                          {up.sites?.name || "Site"}
                        </span>
                        <span>{up.work_date}</span>
                      </div>
                      <p className="text-xs text-[#A7B0BE] line-clamp-2 leading-relaxed">
                        {up.description}
                      </p>
                    </div>
                  </Link>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Main Analytics + Site Status Grid */}
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
        {/* 7-Day Attendance Chart */}
        <Card className="lg:col-span-2">
          <CardHeader>
            <div>
              <CardTitle>7-Day Attendance Overview</CardTitle>
              <CardDescription>
                Daily named attendance distribution across{" "}
                {activeSiteObj ? activeSiteObj.name : "all active sites"}
              </CardDescription>
            </div>
            <Link href="/reports">
              <Button variant="ghost" size="sm">
                Full Analytics
                <ArrowRight className="h-3.5 w-3.5" />
              </Button>
            </Link>
          </CardHeader>
          <CardContent>
            {attendance.length === 0 && !loading ? (
              <EmptyState
                icon={ClipboardCheck}
                title="No attendance logged in the past 7 days"
                description="Mark daily workforce counts or staff attendance to see trends here."
                action={
                  <Link href="/attendance">
                    <Button size="sm">Open Attendance</Button>
                  </Link>
                }
              />
            ) : (
              <div className="h-64 w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart
                    data={attendanceChartData}
                    margin={{ top: 8, right: 8, left: -20, bottom: 0 }}
                  >
                    <CartesianGrid strokeDasharray="3 3" stroke="rgba(190, 205, 225, 0.08)" vertical={false} />
                    <XAxis
                      dataKey="label"
                      tick={{ fontSize: 11, fill: "#A7B0BE" }}
                      axisLine={false}
                      tickLine={false}
                    />
                    <YAxis
                      allowDecimals={false}
                      tick={{ fontSize: 11, fill: "#A7B0BE" }}
                      axisLine={false}
                      tickLine={false}
                    />
                    <Tooltip
                      contentStyle={{
                        backgroundColor: "rgba(23, 28, 36, 0.95)",
                        borderColor: "rgba(190, 205, 225, 0.20)",
                        borderRadius: "12px",
                        fontSize: "12px",
                        color: "#F2F4F8",
                        boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
                      }}
                    />
                    <Bar dataKey="Present" fill="#39B980" radius={[4, 4, 0, 0]} maxBarSize={26} />
                    <Bar dataKey="HalfDay" name="Half Day" fill="#E5AD55" radius={[4, 4, 0, 0]} maxBarSize={26} />
                    <Bar dataKey="Absent" fill="#E56B72" radius={[4, 4, 0, 0]} maxBarSize={26} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Active Sites Summary */}
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Sites Overview</CardTitle>
              <CardDescription>Current operational status</CardDescription>
            </div>
            <Link href="/sites">
              <Button variant="ghost" size="sm">
                View All
              </Button>
            </Link>
          </CardHeader>
          <CardContent className="space-y-3">
            {visibleSites.length === 0 ? (
              <p className="py-8 text-center text-xs text-[#778292]">
                No sites available yet.
              </p>
            ) : (
              visibleSites.slice(0, 5).map((site) => {
                const progress = Number(site.progress ?? 0);
                return (
                  <Link
                    key={site.id}
                    href={`/sites/${site.id}`}
                    className="block rounded-xl border border-[rgba(190,205,225,0.12)] bg-[rgba(23,28,36,0.50)] p-3 transition-colors hover:border-[#4B83F5]/30 hover:bg-[rgba(35,42,53,0.70)]"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <p className="truncate text-sm font-semibold text-[#F2F4F8]">
                          {site.name}
                        </p>
                        <p className="truncate text-xs text-[#A7B0BE]">
                          {site.location || "No location specified"}
                        </p>
                      </div>
                      <StatusBadge status={site.status} />
                    </div>
                    <div className="mt-2.5 flex items-center gap-2">
                      <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/10">
                        <div
                          className="h-full rounded-full bg-[#4B83F5]"
                          style={{ width: `${Math.min(100, Math.max(0, progress))}%` }}
                        />
                      </div>
                      <span className="text-[11px] font-semibold text-[#A7B0BE]">
                        {progress}%
                      </span>
                    </div>
                  </Link>
                );
              })
            )}
          </CardContent>
        </Card>
      </div>

      {/* Bottom Row: Recent Stock Movements + Low Stock / Admin Activity */}
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* Recent Stock Movements */}
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Recent Material Movements</CardTitle>
              <CardDescription>Latest append-only inventory ledger entries</CardDescription>
            </div>
            <Link href="/materials">
              <Button variant="ghost" size="sm">
                Inventory
              </Button>
            </Link>
          </CardHeader>
          <CardContent className="p-0">
            {filteredTxns.length === 0 ? (
              <p className="p-6 text-center text-xs text-[#778292]">
                No recent stock transactions logged.
              </p>
            ) : (
              <div className="divide-y divide-[rgba(190,205,225,0.08)]">
                {filteredTxns.map((txn) => {
                  const isReceived = txn.transaction_type === "RECEIVED";
                  return (
                    <div
                      key={txn.id}
                      className="flex items-center justify-between gap-3 px-5 py-3.5 hover:bg-white/5 transition-colors"
                    >
                      <div className="flex min-w-0 items-center gap-3">
                        <div
                          className={`rounded-xl border p-2 ${
                            isReceived
                              ? "border-emerald-500/30 bg-emerald-500/15 text-[#39B980]"
                              : "border-blue-500/30 bg-blue-500/15 text-[#4B83F5]"
                          }`}
                        >
                          {isReceived ? (
                            <ArrowDownLeft className="h-4 w-4" />
                          ) : (
                            <ArrowUpRight className="h-4 w-4" />
                          )}
                        </div>
                        <div className="min-w-0">
                          <p className="truncate text-sm font-medium text-[#F2F4F8]">
                            {txn.materials?.name ?? "Material"}{" "}
                            <span className="font-semibold text-white">
                              · {formatNumber(txn.quantity)}{" "}
                              {txn.materials?.unit ?? "units"}
                            </span>
                          </p>
                          <p className="truncate text-xs text-[#A7B0BE]">
                            {txn.site_name || "Central Stock"} ·{" "}
                            {formatDisplayDateTime(txn.created_at)}
                          </p>
                        </div>
                      </div>
                      <StatusBadge status={txn.transaction_type} />
                    </div>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Admin Audit Feed OR Low Stock Watchlist */}
        {isAdmin ? (
          <Card>
            <CardHeader>
              <div>
                <CardTitle>Recent Audit Activity</CardTitle>
                <CardDescription>Administrator-only tamper-evident log</CardDescription>
              </div>
              <Link href="/admin">
                <Button variant="ghost" size="sm">
                  Full Log
                </Button>
              </Link>
            </CardHeader>
            <CardContent className="p-0">
              {adminLogs.length === 0 ? (
                <p className="p-6 text-center text-xs text-[#778292]">
                  No activity logs recorded yet.
                </p>
              ) : (
                <div className="divide-y divide-[rgba(190,205,225,0.08)]">
                  {adminLogs.slice(0, 6).map((log) => (
                    <div
                      key={log.id}
                      className="flex items-start justify-between gap-3 px-5 py-3 hover:bg-white/5 transition-colors"
                    >
                      <div className="flex min-w-0 items-start gap-2.5">
                        <Activity className="mt-0.5 h-4 w-4 shrink-0 text-[#4B83F5]" />
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-1.5">
                            <Badge variant="blue">{log.module}</Badge>
                            <span className="text-xs font-semibold text-[#F2F4F8]">
                              {log.action}
                            </span>
                          </div>
                          {log.description && (
                            <p className="mt-0.5 truncate text-xs text-[#A7B0BE]">
                              {log.description}
                            </p>
                          )}
                          <p className="mt-0.5 text-[11px] text-[#778292]">
                            {log.user_name || "Unknown"} ·{" "}
                            {formatDisplayDateTime(log.created_at)}
                          </p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        ) : (
          <Card>
            <CardHeader>
              <div>
                <CardTitle>Low Stock Watchlist</CardTitle>
                <CardDescription>Items at or below minimum stock threshold</CardDescription>
              </div>
              <Link href="/materials">
                <Button variant="ghost" size="sm">
                  Manage Stock
                </Button>
              </Link>
            </CardHeader>
            <CardContent className="p-0">
              {lowStockMaterials.length === 0 ? (
                <p className="p-6 text-center text-xs text-[#778292]">
                  All tracked materials are above minimum stock thresholds.
                </p>
              ) : (
                <div className="divide-y divide-[rgba(190,205,225,0.08)]">
                  {lowStockMaterials.slice(0, 6).map((mat) => (
                    <Link
                      key={mat.id}
                      href={`/materials/${mat.id}`}
                      className="flex items-center justify-between gap-3 px-5 py-3.5 transition-colors hover:bg-white/5"
                    >
                      <div className="min-w-0">
                        <p className="truncate text-sm font-semibold text-[#F2F4F8]">
                          {mat.name}
                        </p>
                        <p className="text-xs text-[#A7B0BE]">
                          Balance: {formatNumber(mat.balance_qty)} {mat.unit} · Min:{" "}
                          {formatNumber(mat.minimum_stock ?? 10)}
                        </p>
                      </div>
                      <StatusBadge status="Low Stock" />
                    </Link>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}

