"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  Calendar,
  ChevronLeft,
  ChevronRight,
  HardHat,
  Users,
  FileSpreadsheet,
  TrendingUp,
  Clock,
  ArrowUpRight,
  ArrowDownRight,
  ExternalLink,
  Search,
  Filter,
  BarChart3,
  CheckCircle2,
  AlertCircle,
} from "lucide-react";
import { downloadCsv } from "@/lib/csv";
import { useAuth } from "@/context/auth-context";
import { fetchDailyWorkforceAttendanceRange } from "@/lib/data/attendance";
import { fetchSites } from "@/lib/data/sites";
import {
  STANDARD_WORKFORCE_CATEGORIES,
  type DailyWorkforceAttendanceRecord,
  type SiteRecord,
} from "@/types/database";
import {
  formatDisplayDate,
  formatNumber,
  getErrorMessage,
  todayIsoDate,
} from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input, Select } from "@/components/ui/input";
import { LoadingTable, EmptyState, ErrorBanner } from "@/components/ui/states";

function formatDdMmYyyy(isoDate: string): string {
  if (!isoDate) return "—";
  const parts = isoDate.split("-");
  if (parts.length === 3) return `${parts[2]}/${parts[1]}/${parts[0]}`;
  return isoDate;
}

function getWeekMondayAndSunday(d: Date): {
  monday: Date;
  sunday: Date;
  startIso: string;
  endIso: string;
} {
  const target = new Date(d);
  const day = target.getDay(); // 0 is Sun, 1 is Mon...
  const diffToMon = day === 0 ? -6 : 1 - day;
  const mon = new Date(target);
  mon.setDate(target.getDate() + diffToMon);
  mon.setHours(0, 0, 0, 0);

  const sun = new Date(mon);
  sun.setDate(mon.getDate() + 6);
  sun.setHours(23, 59, 59, 999);

  const toIso = (dt: Date) => dt.toISOString().slice(0, 10);
  return { monday: mon, sunday: sun, startIso: toIso(mon), endIso: toIso(sun) };
}

const DAY_NAMES = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

export interface WorkforceReportsProps {
  initialMode?: "daily" | "weekly";
}

export function WorkforceReports({
  initialMode = "daily",
}: WorkforceReportsProps) {
  const { isPmOrAdmin, isSupervisor, sites: userAccessibleSites, selectedSiteId } =
    useAuth();

  const [mode, setMode] = useState<"daily" | "weekly">(initialMode);
  const [allSites, setAllSites] = useState<SiteRecord[]>([]);
  const [siteFilter, setSiteFilter] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Daily Mode State
  const [selectedDate, setSelectedDate] = useState<string>(todayIsoDate());
  const [dailySearch, setDailySearch] = useState<string>("");
  const [dailyRecords, setDailyRecords] = useState<DailyWorkforceAttendanceRecord[]>([]);

  // Weekly Mode State
  const [weekCursor, setWeekCursor] = useState<Date>(() => new Date());
  const [customRangeMode, setCustomRangeMode] = useState(false);
  const [customStart, setCustomStart] = useState("");
  const [customEnd, setCustomEnd] = useState("");
  const [weeklyRecords, setWeeklyRecords] = useState<DailyWorkforceAttendanceRecord[]>([]);

  // Load authorized sites list
  useEffect(() => {
    fetchSites()
      .then((data) => {
        setAllSites(data);
        const preferred =
          selectedSiteId ||
          (isSupervisor && userAccessibleSites.length > 0
            ? userAccessibleSites[0].id
            : "");
        setSiteFilter(preferred);
      })
      .catch((err) =>
        setError(getErrorMessage(err, "Failed to load sites directory."))
      );
  }, [isSupervisor, selectedSiteId, userAccessibleSites]);

  // Sync with global header site switcher
  useEffect(() => {
    if (selectedSiteId) {
      setSiteFilter(selectedSiteId);
    }
  }, [selectedSiteId]);

  // Sites selectable based on user role (Supervisors restricted to assigned sites)
  const selectableSites = useMemo(() => {
    if (isSupervisor && userAccessibleSites.length > 0) {
      return userAccessibleSites;
    }
    return allSites;
  }, [isSupervisor, userAccessibleSites, allSites]);

  // Computed Week Range (Monday through Sunday)
  const weekRange = useMemo(() => {
    if (customRangeMode && customStart && customEnd) {
      return {
        monday: new Date(customStart),
        sunday: new Date(customEnd),
        startIso: customStart,
        endIso: customEnd,
      };
    }
    return getWeekMondayAndSunday(weekCursor);
  }, [customRangeMode, customStart, customEnd, weekCursor]);

  // ───────────────────────────────────────────────────────────────────────────
  // DATA FETCHING: DAY-WISE RECORDS
  // ───────────────────────────────────────────────────────────────────────────
  const loadDailyData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const records = await fetchDailyWorkforceAttendanceRange(
        selectedDate,
        selectedDate,
        siteFilter || undefined
      );
      setDailyRecords(records);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load daily workforce records."));
    } finally {
      setLoading(false);
    }
  }, [selectedDate, siteFilter]);

  // ───────────────────────────────────────────────────────────────────────────
  // DATA FETCHING: WEEK-WISE RECORDS
  // ───────────────────────────────────────────────────────────────────────────
  const loadWeeklyData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const records = await fetchDailyWorkforceAttendanceRange(
        weekRange.startIso,
        weekRange.endIso,
        siteFilter || undefined
      );
      setWeeklyRecords(records);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load weekly workforce records."));
    } finally {
      setLoading(false);
    }
  }, [weekRange.startIso, weekRange.endIso, siteFilter]);

  // Trigger loading when tab or date/site filters change
  useEffect(() => {
    if (mode === "daily") {
      loadDailyData();
    } else {
      loadWeeklyData();
    }
  }, [mode, loadDailyData, loadWeeklyData]);

  // ───────────────────────────────────────────────────────────────────────────
  // DAY-WISE CALCULATIONS & AGGREGATIONS
  // ───────────────────────────────────────────────────────────────────────────
  const filteredDailyRecords = useMemo(() => {
    if (!dailySearch.trim()) return dailyRecords;
    const q = dailySearch.trim().toLowerCase();
    return dailyRecords.filter((r) => {
      const siteName = (r.sites?.name ?? "").toLowerCase();
      const remarks = (r.remarks ?? "").toLowerCase();
      const hasMatchingTrade = (r.category_counts ?? []).some((c) =>
        c.category.toLowerCase().includes(q)
      );
      return siteName.includes(q) || remarks.includes(q) || hasMatchingTrade;
    });
  }, [dailyRecords, dailySearch]);

  const dailyAggregates = useMemo(() => {
    let totalHeadcount = 0;
    let totalManDays = 0;
    let totalFullDay = 0;
    let totalHalfDay = 0;

    const tradeTotals: Record<
      string,
      { fullDay: number; halfDay: number; headcount: number; manDays: number }
    > = {};

    for (const cat of STANDARD_WORKFORCE_CATEGORIES) {
      tradeTotals[cat] = { fullDay: 0, halfDay: 0, headcount: 0, manDays: 0 };
    }

    for (const rec of filteredDailyRecords) {
      const counts = rec.category_counts ?? [];
      for (const item of counts) {
        const cat = item.category;
        const fd =
          typeof item.full_day_count === "number"
            ? item.full_day_count
            : Number(item.count || 0);
        const hd =
          typeof item.half_day_count === "number"
            ? item.half_day_count
            : 0;
        const hc = fd + hd;
        const md = fd + hd * 0.5;

        totalFullDay += fd;
        totalHalfDay += hd;
        totalHeadcount += hc;
        totalManDays += md;

        if (!tradeTotals[cat]) {
          tradeTotals[cat] = { fullDay: 0, halfDay: 0, headcount: 0, manDays: 0 };
        }
        tradeTotals[cat].fullDay += fd;
        tradeTotals[cat].halfDay += hd;
        tradeTotals[cat].headcount += hc;
        tradeTotals[cat].manDays += md;
      }
    }

    return {
      totalHeadcount,
      totalManDays,
      totalFullDay,
      totalHalfDay,
      tradeTotals,
      siteCount: filteredDailyRecords.length,
    };
  }, [filteredDailyRecords]);

  // ───────────────────────────────────────────────────────────────────────────
  // WEEK-WISE CALCULATIONS & AGGREGATIONS (Monday through Sunday)
  // ───────────────────────────────────────────────────────────────────────────
  const weeklyDailyBreakdown = useMemo(() => {
    // Generate the 7 calendar dates for Monday..Sunday
    const days: Array<{
      dayIndex: number;
      dayName: string;
      dateIso: string;
      isSubmitted: boolean;
      fullDay: number | null;
      halfDay: number | null;
      headcount: number | null;
      manDays: number | null;
      siteCount: number;
      records: DailyWorkforceAttendanceRecord[];
    }> = [];

    const start = new Date(weekRange.startIso);
    for (let i = 0; i < 7; i++) {
      const cur = new Date(start);
      cur.setDate(start.getDate() + i);
      const iso = cur.toISOString().slice(0, 10);
      const dayName = DAY_NAMES[i] ?? `Day ${i + 1}`;

      const recs = weeklyRecords.filter((r) => r.attendance_date === iso);
      const isSubmitted = recs.length > 0;

      if (isSubmitted) {
        let fdSum = 0;
        let hdSum = 0;
        for (const r of recs) {
          const counts = r.category_counts ?? [];
          for (const item of counts) {
            const fd =
              typeof item.full_day_count === "number"
                ? item.full_day_count
                : Number(item.count || 0);
            const hd =
              typeof item.half_day_count === "number"
                ? item.half_day_count
                : 0;
            fdSum += fd;
            hdSum += hd;
          }
        }
        days.push({
          dayIndex: i,
          dayName,
          dateIso: iso,
          isSubmitted: true,
          fullDay: fdSum,
          halfDay: hdSum,
          headcount: fdSum + hdSum,
          manDays: fdSum + hdSum * 0.5,
          siteCount: recs.length,
          records: recs,
        });
      } else {
        days.push({
          dayIndex: i,
          dayName,
          dateIso: iso,
          isSubmitted: false,
          fullDay: null,
          halfDay: null,
          headcount: null,
          manDays: null,
          siteCount: 0,
          records: [],
        });
      }
    }

    return days;
  }, [weekRange.startIso, weeklyRecords]);

  // Weekly Overview Metrics (1 through 7)
  const weeklyMetrics = useMemo(() => {
    const submittedDays = weeklyDailyBreakdown.filter((d) => d.isSubmitted);

    const totalFullDay = submittedDays.reduce(
      (sum, d) => sum + (d.fullDay ?? 0),
      0
    );
    const totalHalfDay = submittedDays.reduce(
      (sum, d) => sum + (d.halfDay ?? 0),
      0
    );
    const totalAttendances = submittedDays.reduce(
      (sum, d) => sum + (d.headcount ?? 0),
      0
    );
    const totalManDays = submittedDays.reduce(
      (sum, d) => sum + (d.manDays ?? 0),
      0
    );

    const averageDailyHeadcount =
      submittedDays.length > 0
        ? (totalAttendances / submittedDays.length).toFixed(1)
        : "—";

    let highestDay: { dayName: string; dateIso: string; headcount: number } | null =
      null;
    let lowestDay: { dayName: string; dateIso: string; headcount: number } | null =
      null;

    if (submittedDays.length > 0) {
      const sortedByHc = [...submittedDays].sort(
        (a, b) => (b.headcount ?? 0) - (a.headcount ?? 0)
      );
      const top = sortedByHc[0];
      const bottom = sortedByHc[sortedByHc.length - 1];

      highestDay = {
        dayName: top.dayName,
        dateIso: top.dateIso,
        headcount: top.headcount ?? 0,
      };
      lowestDay = {
        dayName: bottom.dayName,
        dateIso: bottom.dateIso,
        headcount: bottom.headcount ?? 0,
      };
    }

    // Trade category breakdown across the entire week
    const categoryTotals: Record<
      string,
      { fullDay: number; halfDay: number; headcount: number; manDays: number }
    > = {};

    for (const cat of STANDARD_WORKFORCE_CATEGORIES) {
      categoryTotals[cat] = { fullDay: 0, halfDay: 0, headcount: 0, manDays: 0 };
    }

    for (const rec of weeklyRecords) {
      const counts = rec.category_counts ?? [];
      for (const item of counts) {
        const cat = item.category;
        const fd =
          typeof item.full_day_count === "number"
            ? item.full_day_count
            : Number(item.count || 0);
        const hd =
          typeof item.half_day_count === "number"
            ? item.half_day_count
            : 0;

        if (!categoryTotals[cat]) {
          categoryTotals[cat] = { fullDay: 0, halfDay: 0, headcount: 0, manDays: 0 };
        }
        categoryTotals[cat].fullDay += fd;
        categoryTotals[cat].halfDay += hd;
        categoryTotals[cat].headcount += fd + hd;
        categoryTotals[cat].manDays += fd + hd * 0.5;
      }
    }

    const categoriesArray = Object.entries(categoryTotals)
      .map(([trade, stats]) => ({
        trade,
        ...stats,
        percentageOfManDays:
          totalManDays > 0
            ? ((stats.manDays / totalManDays) * 100).toFixed(1)
            : "0.0",
      }))
      .sort((a, b) => b.headcount - a.headcount);

    return {
      totalFullDay,
      totalHalfDay,
      totalAttendances,
      totalManDays,
      averageDailyHeadcount,
      highestDay,
      lowestDay,
      submittedDaysCount: submittedDays.length,
      categoriesArray,
    };
  }, [weeklyDailyBreakdown, weeklyRecords]);

  // ───────────────────────────────────────────────────────────────────────────
  // CSV EXPORTS
  // ───────────────────────────────────────────────────────────────────────────
  function handleExportDailyCsv() {
    const rows: string[][] = [];
    for (const rec of filteredDailyRecords) {
      const siteName = rec.sites?.name || "Unassigned Site";
      const counts = rec.category_counts ?? [];

      const tradeMap: Record<string, { fd: number; hd: number }> = {};
      for (const c of counts) {
        tradeMap[c.category] = {
          fd:
            typeof c.full_day_count === "number"
              ? c.full_day_count
              : Number(c.count || 0),
          hd: typeof c.half_day_count === "number" ? c.half_day_count : 0,
        };
      }

      let rowFd = 0;
      let rowHd = 0;
      for (const t of Object.values(tradeMap)) {
        rowFd += t.fd;
        rowHd += t.hd;
      }

      const row = [
        rec.attendance_date,
        siteName,
        String(tradeMap["Masons"]?.fd || 0),
        String(tradeMap["Masons"]?.hd || 0),
        String(tradeMap["Painters"]?.fd || 0),
        String(tradeMap["Painters"]?.hd || 0),
        String(tradeMap["Helpers"]?.fd || 0),
        String(tradeMap["Helpers"]?.hd || 0),
        String(tradeMap["Carpenters"]?.fd || 0),
        String(tradeMap["Carpenters"]?.hd || 0),
        String(tradeMap["Electricians"]?.fd || 0),
        String(tradeMap["Electricians"]?.hd || 0),
        String(tradeMap["Plumbers"]?.fd || 0),
        String(tradeMap["Plumbers"]?.hd || 0),
        String(tradeMap["Other"]?.fd || 0),
        String(tradeMap["Other"]?.hd || 0),
        String(rowFd),
        String(rowHd),
        String(rowFd + rowHd),
        String(rowFd + rowHd * 0.5),
        rec.remarks || "",
      ];
      rows.push(row);
    }

    downloadCsv(
      `tsr_workforce_daily_${selectedDate}.csv`,
      [
        "Date",
        "Site",
        "Masons (FD)",
        "Masons (HD)",
        "Painters (FD)",
        "Painters (HD)",
        "Helpers (FD)",
        "Helpers (HD)",
        "Carpenters (FD)",
        "Carpenters (HD)",
        "Electricians (FD)",
        "Electricians (HD)",
        "Plumbers (FD)",
        "Plumbers (HD)",
        "Other (FD)",
        "Other (HD)",
        "Total Full Day",
        "Total Half Day",
        "Total Headcount",
        "Total Man-Days",
        "Remarks",
      ],
      rows
    );
  }

  function handleExportWeeklyCsv() {
    const dailyRows: string[][] = weeklyDailyBreakdown.map((d) => [
      d.dateIso,
      d.dayName,
      d.isSubmitted ? "Submitted" : "Not submitted",
      d.isSubmitted ? String(d.fullDay) : "—",
      d.isSubmitted ? String(d.halfDay) : "—",
      d.isSubmitted ? String(d.headcount) : "—",
      d.isSubmitted ? String(d.manDays) : "—",
    ]);

    downloadCsv(
      `tsr_workforce_weekly_${weekRange.startIso}_to_${weekRange.endIso}.csv`,
      ["Date", "Day", "Status", "Full Day", "Half Day", "Headcount", "Man-Days"],
      dailyRows
    );
  }

  const activeSiteName = useMemo(() => {
    if (!siteFilter) return "All Authorized Sites";
    return allSites.find((s) => s.id === siteFilter)?.name || "Selected Site";
  }, [allSites, siteFilter]);

  return (
    <div className="space-y-6">
      {error && <ErrorBanner message={error} />}

      {/* Top Reporting Controls & Tab Switcher */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-1.5 rounded-xl border border-[rgba(190,205,225,0.18)] bg-[rgba(23,28,36,0.6)] p-1 backdrop-blur-sm">
          <button
            type="button"
            onClick={() => setMode("daily")}
            className={`flex items-center gap-2 rounded-lg px-4 py-2 text-xs font-semibold transition-all cursor-pointer ${
              mode === "daily"
                ? "bg-[#4B83F5] text-white shadow-[0_0_12px_rgba(75,131,245,0.3)]"
                : "text-[#A7B0BE] hover:text-[#F2F4F8]"
            }`}
          >
            <Calendar className="h-3.5 w-3.5" />
            Day-Wise Report
          </button>
          <button
            type="button"
            onClick={() => setMode("weekly")}
            className={`flex items-center gap-2 rounded-lg px-4 py-2 text-xs font-semibold transition-all cursor-pointer ${
              mode === "weekly"
                ? "bg-[#4B83F5] text-white shadow-[0_0_12px_rgba(75,131,245,0.3)]"
                : "text-[#A7B0BE] hover:text-[#F2F4F8]"
            }`}
          >
            <TrendingUp className="h-3.5 w-3.5" />
            Weekly Report (Mon–Sun)
          </button>
        </div>

        {/* Global Export Button */}
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={mode === "daily" ? handleExportDailyCsv : handleExportWeeklyCsv}
            disabled={
              mode === "daily"
                ? filteredDailyRecords.length === 0
                : weeklyDailyBreakdown.every((d) => !d.isSubmitted)
            }
          >
            <FileSpreadsheet className="h-4 w-4" />
            Export CSV ({mode === "daily" ? "Daily" : "Weekly"})
          </Button>
        </div>
      </div>

      {/* Filter Surface */}
      <Card>
        <CardContent className="grid grid-cols-1 gap-4 p-4 sm:grid-cols-2 lg:grid-cols-3">
          {/* Site Filter */}
          <div>
            <Select
              label={
                isSupervisor
                  ? "Assigned Construction Site"
                  : "Construction Site Filter"
              }
              value={siteFilter}
              onChange={(e) => setSiteFilter(e.target.value)}
            >
              {isPmOrAdmin && (
                <option value="">— All Authorized Sites (Consolidated) —</option>
              )}
              {selectableSites.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name} {s.location ? `(${s.location})` : ""}
                </option>
              ))}
            </Select>
            {isSupervisor && (
              <p className="mt-1 text-[11px] text-[#A7B0BE]">
                Supervisor Access: Scoped strictly to your assigned construction sites.
              </p>
            )}
          </div>

          {/* Date / Week Selection */}
          {mode === "daily" ? (
            <div>
              <Input
                label="Attendance Date"
                type="date"
                max={todayIsoDate()}
                value={selectedDate}
                onChange={(e) => setSelectedDate(e.target.value)}
              />
            </div>
          ) : (
            <div>
              <label className="block text-xs font-medium text-[#A7B0BE] mb-1.5">
                Weekly Period (Monday – Sunday)
              </label>
              {!customRangeMode ? (
                <div className="flex items-center gap-1.5">
                  <button
                    type="button"
                    onClick={() =>
                      setWeekCursor(
                        (prev) => new Date(prev.getTime() - 7 * 86400000)
                      )
                    }
                    aria-label="Previous week"
                    className="flex h-10 w-10 items-center justify-center rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 text-[#A7B0BE] hover:bg-white/5 hover:text-[#F2F4F8] transition-colors cursor-pointer"
                  >
                    <ChevronLeft className="h-4 w-4" />
                  </button>
                  <div className="flex-1 rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 px-3 py-2 text-center text-xs font-semibold text-[#F2F4F8]">
                    {formatDdMmYyyy(weekRange.startIso)} – {formatDdMmYyyy(weekRange.endIso)}
                  </div>
                  <button
                    type="button"
                    onClick={() =>
                      setWeekCursor(
                        (prev) => new Date(prev.getTime() + 7 * 86400000)
                      )
                    }
                    aria-label="Next week"
                    className="flex h-10 w-10 items-center justify-center rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 text-[#A7B0BE] hover:bg-white/5 hover:text-[#F2F4F8] transition-colors cursor-pointer"
                  >
                    <ChevronRight className="h-4 w-4" />
                  </button>
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-10 text-xs"
                    onClick={() => setWeekCursor(new Date())}
                  >
                    Current
                  </Button>
                </div>
              ) : (
                <div className="flex items-center gap-2">
                  <input
                    type="date"
                    value={customStart}
                    onChange={(e) => setCustomStart(e.target.value)}
                    className="h-10 w-full rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 px-2.5 py-1 text-xs text-[#F2F4F8] focus:border-[#4B83F5] focus:outline-none"
                  />
                  <span className="text-xs text-[#778292]">to</span>
                  <input
                    type="date"
                    value={customEnd}
                    onChange={(e) => setCustomEnd(e.target.value)}
                    className="h-10 w-full rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 px-2.5 py-1 text-xs text-[#F2F4F8] focus:border-[#4B83F5] focus:outline-none"
                  />
                </div>
              )}
            </div>
          )}

          {/* Toggle Range Mode in Weekly / Search in Daily */}
          {mode === "daily" ? (
            <div>
              <Input
                label="Filter by Site or Keyword"
                placeholder="Search site, notes, trades…"
                value={dailySearch}
                onChange={(e) => setDailySearch(e.target.value)}
              />
            </div>
          ) : (
            <div className="flex flex-col justify-end">
              <button
                type="button"
                onClick={() => {
                  setCustomRangeMode(!customRangeMode);
                  if (!customRangeMode) {
                    setCustomStart(weekRange.startIso);
                    setCustomEnd(weekRange.endIso);
                  }
                }}
                className="inline-flex h-10 items-center justify-center gap-1.5 rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 px-3 text-xs font-medium text-[#A7B0BE] hover:bg-white/5 hover:text-[#F2F4F8] transition-colors cursor-pointer"
              >
                <Filter className="h-3.5 w-3.5" />
                {customRangeMode ? "Use Monday–Sunday Preset" : "Custom Date Range"}
              </button>
            </div>
          )}
        </CardContent>
      </Card>

      {/* ───────────────────────────────────────────────────────────────────── */}
      {/* MODE A: DAY-WISE WORKFORCE REPORTING                                   */}
      {/* ───────────────────────────────────────────────────────────────────── */}
      {mode === "daily" && (
        <div className="space-y-6">
          {/* Daily KPI Metric Cards */}
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
            <Card className="border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.60)]">
              <CardContent className="p-4 sm:p-5">
                <p className="text-[11px] font-bold uppercase tracking-wider text-[#A7B0BE]">
                  Total Headcount
                </p>
                <p className="mt-1 text-2xl font-black text-[#F2F4F8] sm:text-3xl">
                  {dailyAggregates.totalHeadcount}
                  <span className="ml-1 text-xs font-semibold text-[#A7B0BE]">
                    Staff
                  </span>
                </p>
                <p className="mt-1 text-[11px] text-[#778292]">
                  {dailyAggregates.totalFullDay} Full + {dailyAggregates.totalHalfDay} Half Day
                </p>
              </CardContent>
            </Card>

            <Card className="border-[rgba(75,131,245,0.30)] bg-[rgba(45,53,65,0.68)]">
              <CardContent className="p-4 sm:p-5">
                <p className="text-[11px] font-bold uppercase tracking-wider text-[#4B83F5]">
                  Man-Day Equivalent
                </p>
                <p className="mt-1 text-2xl font-black text-[#F2F4F8] sm:text-3xl">
                  {dailyAggregates.totalManDays.toFixed(1).replace(/\.0$/, "")}
                  <span className="ml-1 text-xs font-semibold text-[#4B83F5]">
                    MD
                  </span>
                </p>
                <p className="mt-1 text-[11px] text-[#A7B0BE]">
                  Full + (Half × 0.5)
                </p>
              </CardContent>
            </Card>

            <Card className="border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.60)]">
              <CardContent className="p-4 sm:p-5">
                <p className="text-[11px] font-bold uppercase tracking-wider text-[#A7B0BE]">
                  Full-Day Deployments
                </p>
                <p className="mt-1 text-2xl font-black text-[#F2F4F8] sm:text-3xl">
                  {dailyAggregates.totalFullDay}
                  <span className="ml-1 text-xs font-semibold text-[#39B980]">
                    (1.0 MD)
                  </span>
                </p>
                <p className="mt-1 text-[11px] text-[#778292]">
                  100% Shift Attendance
                </p>
              </CardContent>
            </Card>

            <Card className="border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.60)]">
              <CardContent className="p-4 sm:p-5">
                <p className="text-[11px] font-bold uppercase tracking-wider text-[#A7B0BE]">
                  Half-Day Deployments
                </p>
                <p className="mt-1 text-2xl font-black text-[#F2F4F8] sm:text-3xl">
                  {dailyAggregates.totalHalfDay}
                  <span className="ml-1 text-xs font-semibold text-[#E5AD55]">
                    (0.5 MD)
                  </span>
                </p>
                <p className="mt-1 text-[11px] text-[#778292]">
                  50% Shift Attendance
                </p>
              </CardContent>
            </Card>
          </div>

          {/* Daily Deployment Table */}
          {loading ? (
            <LoadingTable rows={4} />
          ) : filteredDailyRecords.length === 0 ? (
            <Card>
              <CardContent className="p-8 text-center">
                <AlertCircle className="mx-auto h-8 w-8 text-[#E5AD55]" />
                <h4 className="mt-3 text-sm font-bold text-[#F2F4F8]">
                  {siteFilter
                    ? `Not Submitted: ${activeSiteName}`
                    : "No Workforce Attendance Records"}
                </h4>
                <p className="mt-1 text-xs text-[#A7B0BE]">
                  {siteFilter
                    ? `No workforce attendance was submitted for ${activeSiteName} on ${formatDdMmYyyy(selectedDate)}. This date is marked as "Not submitted", not zero.`
                    : `No construction sites submitted attendance for ${formatDdMmYyyy(selectedDate)}.`}
                </p>
                <div className="mt-4">
                  <Link
                    href={`/attendance?date=${selectedDate}${siteFilter ? `&siteId=${siteFilter}` : ""}`}
                  >
                    <Button size="sm">
                      <HardHat className="h-4 w-4" />
                      Record Workforce Attendance
                    </Button>
                  </Link>
                </div>
              </CardContent>
            </Card>
          ) : (
            <Card className="overflow-hidden">
              <CardHeader>
                <div>
                  <CardTitle>
                    Daily Deployment Summary — {formatDdMmYyyy(selectedDate)}
                  </CardTitle>
                  <CardDescription>
                    Aggregated anonymous workforce deployment by trade category across {filteredDailyRecords.length} reporting construction site(s).
                  </CardDescription>
                </div>
              </CardHeader>
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs">
                  <thead className="border-b border-[rgba(190,205,225,0.15)] bg-[rgba(23,28,36,0.7)] font-semibold uppercase tracking-wider text-[#A7B0BE]">
                    <tr>
                      <th className="px-4 py-3.5">Construction Site</th>
                      <th className="px-3 py-3.5 text-center">Masons</th>
                      <th className="px-3 py-3.5 text-center">Painters</th>
                      <th className="px-3 py-3.5 text-center">Helpers</th>
                      <th className="px-3 py-3.5 text-center">Carpenters</th>
                      <th className="px-3 py-3.5 text-center">Electricians</th>
                      <th className="px-3 py-3.5 text-center">Plumbers</th>
                      <th className="px-3 py-3.5 text-center">Other</th>
                      <th className="px-3 py-3.5 text-center">Full Day</th>
                      <th className="px-3 py-3.5 text-center">Half Day</th>
                      <th className="px-3 py-3.5 text-center font-bold text-[#F2F4F8]">Headcount</th>
                      <th className="px-3 py-3.5 text-right font-bold text-[#4B83F5]">Man-Days</th>
                      <th className="px-4 py-3.5 text-right">Source</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[rgba(190,205,225,0.08)]">
                    {filteredDailyRecords.map((rec) => {
                      const counts = rec.category_counts ?? [];
                      const tradeMap: Record<string, { fd: number; hd: number }> = {};
                      let recFd = 0;
                      let recHd = 0;

                      for (const c of counts) {
                        const fd =
                          typeof c.full_day_count === "number"
                            ? c.full_day_count
                            : Number(c.count || 0);
                        const hd =
                          typeof c.half_day_count === "number"
                            ? c.half_day_count
                            : 0;
                        tradeMap[c.category] = { fd, hd };
                        recFd += fd;
                        recHd += hd;
                      }

                      const recHeadcount = recFd + recHd;
                      const recManDays = recFd + recHd * 0.5;

                      return (
                        <tr
                          key={rec.id}
                          className="transition-colors hover:bg-white/[0.04]"
                        >
                          <td className="px-4 py-3.5 font-semibold text-[#F2F4F8]">
                            <div>
                              <p className="text-sm font-semibold text-[#F2F4F8]">
                                {rec.sites?.name || "Unassigned Site"}
                              </p>
                              {rec.remarks && (
                                <p className="text-[11px] font-normal text-[#A7B0BE] line-clamp-1">
                                  {rec.remarks}
                                </p>
                              )}
                            </div>
                          </td>

                          {/* 7 Standard Trade Categories */}
                          {STANDARD_WORKFORCE_CATEGORIES.map((cat) => {
                            const b = tradeMap[cat] ?? { fd: 0, hd: 0 };
                            const total = b.fd + b.hd;
                            return (
                              <td
                                key={cat}
                                className="px-3 py-3.5 text-center text-[#CBD3DF]"
                              >
                                {total > 0 ? (
                                  <div className="font-medium">
                                    <span className="font-semibold text-[#F2F4F8]">
                                      {total}
                                    </span>
                                    <span className="block text-[10px] text-[#778292]">
                                      {b.fd}F / {b.hd}H
                                    </span>
                                  </div>
                                ) : (
                                  <span className="text-[#586578]">—</span>
                                )}
                              </td>
                            );
                          })}

                          {/* Full Day */}
                          <td className="px-3 py-3.5 text-center font-semibold text-[#39B980]">
                            {recFd}
                          </td>

                          {/* Half Day */}
                          <td className="px-3 py-3.5 text-center font-semibold text-[#E5AD55]">
                            {recHd}
                          </td>

                          {/* Headcount */}
                          <td className="px-3 py-3.5 text-center font-bold text-[#F2F4F8]">
                            {recHeadcount}
                          </td>

                          {/* Man-Days */}
                          <td className="px-3 py-3.5 text-right font-black text-[#4B83F5]">
                            {recManDays.toFixed(1).replace(/\.0$/, "")}
                          </td>

                          {/* Link to Source Attendance */}
                          <td className="px-4 py-3.5 text-right">
                            <Link
                              href={`/attendance?date=${rec.attendance_date}&siteId=${rec.site_id}`}
                              className="inline-flex items-center gap-1 text-[11px] font-semibold text-[#4B83F5] hover:underline"
                            >
                              Edit
                              <ExternalLink className="h-3 w-3" />
                            </Link>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                  {/* Aggregated Total Row */}
                  <tfoot className="border-t-2 border-[rgba(190,205,225,0.20)] bg-[rgba(23,28,36,0.85)] font-bold">
                    <tr>
                      <td className="px-4 py-3 text-xs uppercase tracking-wider text-[#A7B0BE]">
                        Consolidated Totals ({filteredDailyRecords.length} Sites)
                      </td>
                      {STANDARD_WORKFORCE_CATEGORIES.map((cat) => {
                        const t = dailyAggregates.tradeTotals[cat];
                        return (
                          <td
                            key={cat}
                            className="px-3 py-3 text-center text-[#F2F4F8]"
                          >
                            {t && t.headcount > 0 ? (
                              <div>
                                <span className="text-xs">{t.headcount}</span>
                                <span className="block text-[9px] text-[#A7B0BE]">
                                  {t.fullDay}F/{t.halfDay}H
                                </span>
                              </div>
                            ) : (
                              <span className="text-[#586578]">—</span>
                            )}
                          </td>
                        );
                      })}
                      <td className="px-3 py-3 text-center text-[#39B980]">
                        {dailyAggregates.totalFullDay}
                      </td>
                      <td className="px-3 py-3 text-center text-[#E5AD55]">
                        {dailyAggregates.totalHalfDay}
                      </td>
                      <td className="px-3 py-3 text-center text-sm font-black text-[#F2F4F8]">
                        {dailyAggregates.totalHeadcount}
                      </td>
                      <td className="px-3 py-3 text-right text-sm font-black text-[#4B83F5]">
                        {dailyAggregates.totalManDays.toFixed(1).replace(/\.0$/, "")} MD
                      </td>
                      <td className="px-4 py-3" />
                    </tr>
                  </tfoot>
                </table>
              </div>
            </Card>
          )}
        </div>
      )}

      {/* ───────────────────────────────────────────────────────────────────── */}
      {/* MODE B: WEEK-WISE WORKFORCE REPORTING (Monday through Sunday)          */}
      {/* ───────────────────────────────────────────────────────────────────── */}
      {mode === "weekly" && (
        <div className="space-y-6">
          {/* Weekly Overview Metrics (1 through 7) */}
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-4 lg:grid-cols-7">
            {/* 1. Total Full-Day */}
            <Card className="border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.60)]">
              <CardContent className="p-3.5">
                <p className="text-[10px] font-bold uppercase tracking-wider text-[#A7B0BE]">
                  1. Full-Day Deployments
                </p>
                <p className="mt-1 text-xl font-black text-[#39B980] sm:text-2xl">
                  {weeklyMetrics.totalFullDay}
                </p>
                <p className="text-[10px] text-[#778292]">1.0 MD Shifting</p>
              </CardContent>
            </Card>

            {/* 2. Total Half-Day */}
            <Card className="border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.60)]">
              <CardContent className="p-3.5">
                <p className="text-[10px] font-bold uppercase tracking-wider text-[#A7B0BE]">
                  2. Half-Day Deployments
                </p>
                <p className="mt-1 text-xl font-black text-[#E5AD55] sm:text-2xl">
                  {weeklyMetrics.totalHalfDay}
                </p>
                <p className="text-[10px] text-[#778292]">0.5 MD Shifting</p>
              </CardContent>
            </Card>

            {/* 3. Total Worker Attendances Across Week */}
            <Card className="border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.60)]">
              <CardContent className="p-3.5">
                <p className="text-[10px] font-bold uppercase tracking-wider text-[#A7B0BE]">
                  3. Total Attendances
                </p>
                <p className="mt-1 text-xl font-black text-[#F2F4F8] sm:text-2xl">
                  {weeklyMetrics.totalAttendances}
                </p>
                <p className="text-[10px] text-[#778292]">Total Worker-Shifts</p>
              </CardContent>
            </Card>

            {/* 4. Total Man-Days Equivalents */}
            <Card className="border-[rgba(75,131,245,0.30)] bg-[rgba(45,53,65,0.68)]">
              <CardContent className="p-3.5">
                <p className="text-[10px] font-bold uppercase tracking-wider text-[#4B83F5]">
                  4. Man-Day Equiv.
                </p>
                <p className="mt-1 text-xl font-black text-[#F2F4F8] sm:text-2xl">
                  {weeklyMetrics.totalManDays.toFixed(1).replace(/\.0$/, "")}
                  <span className="ml-1 text-xs text-[#4B83F5]">MD</span>
                </p>
                <p className="text-[10px] text-[#A7B0BE]">FD + (HD × 0.5)</p>
              </CardContent>
            </Card>

            {/* 5. Average Daily Headcount */}
            <Card className="border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.60)]">
              <CardContent className="p-3.5">
                <p className="text-[10px] font-bold uppercase tracking-wider text-[#A7B0BE]">
                  5. Daily Avg Headcount
                </p>
                <p className="mt-1 text-xl font-black text-[#F2F4F8] sm:text-2xl">
                  {weeklyMetrics.averageDailyHeadcount}
                </p>
                <p className="text-[10px] text-[#778292]">
                  Over {weeklyMetrics.submittedDaysCount} submitted days
                </p>
              </CardContent>
            </Card>

            {/* 6. Highest Deployment Day */}
            <Card className="border-[rgba(57,185,128,0.30)] bg-[rgba(35,42,53,0.60)]">
              <CardContent className="p-3.5">
                <p className="text-[10px] font-bold uppercase tracking-wider text-[#39B980]">
                  6. Peak Deployment
                </p>
                <p className="mt-1 text-sm font-black text-[#F2F4F8] truncate">
                  {weeklyMetrics.highestDay
                    ? `${weeklyMetrics.highestDay.dayName.slice(0, 3)} (${weeklyMetrics.highestDay.headcount})`
                    : "—"}
                </p>
                <p className="text-[10px] text-[#778292]">
                  {weeklyMetrics.highestDay
                    ? formatDdMmYyyy(weeklyMetrics.highestDay.dateIso)
                    : "No data"}
                </p>
              </CardContent>
            </Card>

            {/* 7. Lowest Deployment Day */}
            <Card className="border-[rgba(229,173,85,0.30)] bg-[rgba(35,42,53,0.60)]">
              <CardContent className="p-3.5">
                <p className="text-[10px] font-bold uppercase tracking-wider text-[#E5AD55]">
                  7. Min Deployment
                </p>
                <p className="mt-1 text-sm font-black text-[#F2F4F8] truncate">
                  {weeklyMetrics.lowestDay
                    ? `${weeklyMetrics.lowestDay.dayName.slice(0, 3)} (${weeklyMetrics.lowestDay.headcount})`
                    : "—"}
                </p>
                <p className="text-[10px] text-[#778292]">
                  {weeklyMetrics.lowestDay
                    ? formatDdMmYyyy(weeklyMetrics.lowestDay.dateIso)
                    : "No data"}
                </p>
              </CardContent>
            </Card>
          </div>

          {/* Daily Breakdown Table for the Week */}
          <Card className="overflow-hidden">
            <CardHeader>
              <div>
                <CardTitle>
                  Weekly Daily Breakdown ({formatDdMmYyyy(weekRange.startIso)} – {formatDdMmYyyy(weekRange.endIso)})
                </CardTitle>
                <CardDescription>
                  Day-by-day attendance status. Days without logged records are explicitly labeled &quot;Not submitted&quot;.
                </CardDescription>
              </div>
            </CardHeader>
            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs">
                <thead className="border-b border-[rgba(190,205,225,0.15)] bg-[rgba(23,28,36,0.7)] font-semibold uppercase tracking-wider text-[#A7B0BE]">
                  <tr>
                    <th className="px-5 py-3.5">Day &amp; Date</th>
                    <th className="px-5 py-3.5">Submission Status</th>
                    <th className="px-5 py-3.5 text-center">Full Day (1.0 MD)</th>
                    <th className="px-5 py-3.5 text-center">Half Day (0.5 MD)</th>
                    <th className="px-5 py-3.5 text-center font-bold text-[#F2F4F8]">Headcount</th>
                    <th className="px-5 py-3.5 text-right font-bold text-[#4B83F5]">Man-Days Equiv.</th>
                    <th className="px-5 py-3.5 text-right">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[rgba(190,205,225,0.08)]">
                  {weeklyDailyBreakdown.map((d) => (
                    <tr
                      key={d.dateIso}
                      className={
                        d.isSubmitted
                          ? "transition-colors hover:bg-white/[0.04]"
                          : "bg-white/[0.01] opacity-70"
                      }
                    >
                      <td className="px-5 py-4">
                        <span className="font-bold text-[#F2F4F8]">{d.dayName}</span>
                        <span className="ml-2 font-mono text-[11px] text-[#A7B0BE]">
                          {formatDdMmYyyy(d.dateIso)}
                        </span>
                      </td>

                      <td className="px-5 py-4">
                        {d.isSubmitted ? (
                          <span className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-500/15 border border-emerald-500/30 px-2.5 py-0.5 text-xs font-semibold text-[#39B980]">
                            <CheckCircle2 className="h-3.5 w-3.5" />
                            Submitted ({d.siteCount} {d.siteCount === 1 ? "site" : "sites"})
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1.5 rounded-lg bg-amber-500/15 border border-amber-500/30 px-2.5 py-0.5 text-xs font-semibold text-[#E5AD55]">
                            <Clock className="h-3.5 w-3.5" />
                            Not submitted
                          </span>
                        )}
                      </td>

                      <td className="px-5 py-4 text-center font-semibold text-[#39B980]">
                        {d.isSubmitted ? d.fullDay : "—"}
                      </td>

                      <td className="px-5 py-4 text-center font-semibold text-[#E5AD55]">
                        {d.isSubmitted ? d.halfDay : "—"}
                      </td>

                      <td className="px-5 py-4 text-center font-bold text-[#F2F4F8]">
                        {d.isSubmitted ? d.headcount : "—"}
                      </td>

                      <td className="px-5 py-4 text-right font-black text-[#4B83F5]">
                        {d.isSubmitted
                          ? `${d.manDays?.toFixed(1).replace(/\.0$/, "")} MD`
                          : "—"}
                      </td>

                      <td className="px-5 py-4 text-right">
                        <Link
                          href={`/attendance?date=${d.dateIso}${siteFilter ? `&siteId=${siteFilter}` : ""}`}
                          className="inline-flex items-center gap-1 text-xs font-semibold text-[#4B83F5] hover:underline"
                        >
                          {d.isSubmitted ? "Review" : "Submit"}
                          <ExternalLink className="h-3 w-3" />
                        </Link>
                      </td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="border-t-2 border-[rgba(190,205,225,0.20)] bg-[rgba(23,28,36,0.85)] font-bold">
                  <tr>
                    <td className="px-5 py-3 text-xs uppercase tracking-wider text-[#A7B0BE]">
                      Weekly Total ({weeklyMetrics.submittedDaysCount} of 7 Days Active)
                    </td>
                    <td className="px-5 py-3" />
                    <td className="px-5 py-3 text-center text-[#39B980]">
                      {weeklyMetrics.totalFullDay}
                    </td>
                    <td className="px-5 py-3 text-center text-[#E5AD55]">
                      {weeklyMetrics.totalHalfDay}
                    </td>
                    <td className="px-5 py-3 text-center text-sm font-black text-[#F2F4F8]">
                      {weeklyMetrics.totalAttendances}
                    </td>
                    <td className="px-5 py-3 text-right text-sm font-black text-[#4B83F5]">
                      {weeklyMetrics.totalManDays.toFixed(1).replace(/\.0$/, "")} MD
                    </td>
                    <td className="px-5 py-3" />
                  </tr>
                </tfoot>
              </table>
            </div>
          </Card>

          {/* Trade Category-Wise Weekly Totals Table */}
          <Card className="overflow-hidden">
            <CardHeader>
              <div>
                <CardTitle>Trade Category-Wise Weekly Deployments</CardTitle>
                <CardDescription>
                  Cumulative full-day, half-day, headcount, and man-day totals aggregated by craft trade across the weekly reporting window.
                </CardDescription>
              </div>
            </CardHeader>
            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs">
                <thead className="border-b border-[rgba(190,205,225,0.15)] bg-[rgba(23,28,36,0.7)] font-semibold uppercase tracking-wider text-[#A7B0BE]">
                  <tr>
                    <th className="px-5 py-3.5">Craft Trade</th>
                    <th className="px-5 py-3.5 text-center">Full Day (1.0 MD)</th>
                    <th className="px-5 py-3.5 text-center">Half Day (0.5 MD)</th>
                    <th className="px-5 py-3.5 text-center font-bold text-[#F2F4F8]">Total Headcount</th>
                    <th className="px-5 py-3.5 text-right font-bold text-[#4B83F5]">Man-Day Equiv.</th>
                    <th className="px-5 py-3.5 text-right">% of Weekly Effort</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[rgba(190,205,225,0.08)]">
                  {weeklyMetrics.categoriesArray.map((row) => {
                    const hasEffort = row.headcount > 0;
                    return (
                      <tr
                        key={row.trade}
                        className={
                          hasEffort
                            ? "transition-colors hover:bg-white/[0.04]"
                            : "opacity-40"
                        }
                      >
                        <td className="px-5 py-3.5 font-bold text-[#F2F4F8]">
                          {row.trade}
                        </td>
                        <td className="px-5 py-3.5 text-center font-semibold text-[#39B980]">
                          {row.fullDay}
                        </td>
                        <td className="px-5 py-3.5 text-center font-semibold text-[#E5AD55]">
                          {row.halfDay}
                        </td>
                        <td className="px-5 py-3.5 text-center font-bold text-[#F2F4F8]">
                          {row.headcount}
                        </td>
                        <td className="px-5 py-3.5 text-right font-black text-[#4B83F5]">
                          {row.manDays.toFixed(1).replace(/\.0$/, "")} MD
                        </td>
                        <td className="px-5 py-3.5 text-right font-mono text-xs text-[#CBD3DF]">
                          {row.percentageOfManDays}%
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </Card>
        </div>
      )}
    </div>
  );
}
