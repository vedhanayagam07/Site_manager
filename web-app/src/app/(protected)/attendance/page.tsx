"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  ClipboardCheck,
  HardHat,
  Calendar,
  BarChart3,
  Plus,
  Minus,
  Save,
  ChevronLeft,
  ChevronRight,
  Lock,
  Info,
  Pencil,
  CheckCheck,
  FileSpreadsheet,
  UserCheck,
  Users,
  ShieldCheck,
  WifiOff,
  CloudOff,
  Clock,
} from "lucide-react";
import { downloadCsv } from "@/lib/csv";
import {
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
} from "recharts";
import { useAuth } from "@/context/auth-context";
import { useOfflineSync } from "@/hooks/use-offline-sync";
import { triggerHapticFeedback } from "@/lib/platform";
import {
  getOfflineOutbox,
  queueOfflineItem,
} from "@/lib/offline/outbox";
import type { WorkforceAttendancePayload, SupervisorAttendancePayload } from "@/lib/offline/types";
import {
  correctAttendanceStatus,
  fetchAttendanceByDate,
  fetchAttendanceRange,
  fetchDailyWorkforceAttendance,
  fetchDailyWorkforceAttendanceRange,
  saveDailyWorkforceAttendance,
  fetchSupervisorAttendance,
  saveSupervisorAttendance,
  fetchSupervisorsForSite,
  fetchSupervisorAttendanceHistory,
  upsertSiteAttendance,
  type SupervisorSiteCandidate,
} from "@/lib/data/attendance";
import { fetchSites } from "@/lib/data/sites";
import { fetchWorkers } from "@/lib/data/workers";
import {
  STANDARD_WORKFORCE_CATEGORIES,
  SUPERVISOR_ATTENDANCE_STATUSES,
  type AttendanceStatus,
  type DailyWorkforceAttendanceRecord,
  type SiteAttendanceRecord,
  type SiteRecord,
  type SupervisorAttendanceRecord,
  type SupervisorAttendanceStatus,
  type WorkerRecord,
} from "@/types/database";
import { formatDisplayDate, getErrorMessage, todayIsoDate } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Input, Select } from "@/components/ui/input";
import { Modal } from "@/components/ui/modal";
import {
  EmptyState,
  ErrorBanner,
  LoadingTable,
  PageHeader,
} from "@/components/ui/states";
import { useToast } from "@/components/ui/toast";
import { WorkforceReports } from "@/components/workforce-reports";

type AttendanceTab = "workforce" | "supervisor" | "named" | "monthly" | "analytics" | "reports";

export default function AttendancePage() {
  const { user, profile, isPmOrAdmin, isSupervisor, sites: userAccessibleSites, selectedSiteId } = useAuth();
  const { isOnline } = useOfflineSync();
  const toast = useToast();

  const [tab, setTab] = useState<AttendanceTab>("workforce");
  const [selectedDate, setSelectedDate] = useState<string>(todayIsoDate());
  const [allSites, setAllSites] = useState<SiteRecord[]>([]);
  const [activeSiteId, setActiveSiteId] = useState<string>("");
  const [error, setError] = useState<string | null>(null);

  // ───────────────────────────────────────────────────────────────────────────
  // MODULE A: Daily Workforce Attendance State (Full-Day & Half-Day Tracking)
  // ───────────────────────────────────────────────────────────────────────────
  const [workforceTableReady, setWorkforceTableReady] = useState<boolean>(true);
  const [existingWorkforceSubmission, setExistingWorkforceSubmission] =
    useState<DailyWorkforceAttendanceRecord | null>(null);
  const [isLocallyQueued, setIsLocallyQueued] = useState<boolean>(false);
  const [workforceBreakdowns, setWorkforceBreakdowns] = useState<
    Record<string, { fullDay: number; halfDay: number }>
  >(() => {
    const init: Record<string, { fullDay: number; halfDay: number }> = {};
    for (const c of STANDARD_WORKFORCE_CATEGORIES) {
      init[c] = { fullDay: 0, halfDay: 0 };
    }
    return init;
  });
  const [customTrade, setCustomTrade] = useState("");
  const [workforceRemarks, setWorkforceRemarks] = useState("");
  const [loadingWorkforce, setLoadingWorkforce] = useState(true);
  const [savingWorkforce, setSavingWorkforce] = useState(false);

  // ───────────────────────────────────────────────────────────────────────────
  // MODULE B: Supervisor Personal Attendance State
  // ───────────────────────────────────────────────────────────────────────────
  const [supervisorTableReady, setSupervisorTableReady] = useState<boolean>(true);
  const [siteSupervisors, setSiteSupervisors] = useState<SupervisorSiteCandidate[]>([]);
  const [supervisorDraft, setSupervisorDraft] = useState<
    Record<string, { status: SupervisorAttendanceStatus; remarks: string }>
  >({});
  const [mySupervisorHistory, setMySupervisorHistory] = useState<SupervisorAttendanceRecord[]>([]);
  const [loadingSupervisor, setLoadingSupervisor] = useState(false);
  const [savingSupervisor, setSavingSupervisor] = useState(false);

  // ───────────────────────────────────────────────────────────────────────────
  // MODULE C: Named Worker Attendance State (Existing site_attendance)
  // ───────────────────────────────────────────────────────────────────────────
  const [namedRecords, setNamedRecords] = useState<SiteAttendanceRecord[]>([]);
  const [siteWorkers, setSiteWorkers] = useState<WorkerRecord[]>([]);
  const [markDraft, setMarkDraft] = useState<Record<string, AttendanceStatus>>({});
  const [loadingNamed, setLoadingNamed] = useState(true);
  const [savingNamed, setSavingNamed] = useState(false);
  const [correctModalRecord, setCorrectModalRecord] =
    useState<SiteAttendanceRecord | null>(null);
  const [correctStatus, setCorrectStatus] = useState<AttendanceStatus>("Present");

  // ───────────────────────────────────────────────────────────────────────────
  // MODULE D & E: Monthly Calendar & Analytics State
  // ───────────────────────────────────────────────────────────────────────────
  const [allWorkers, setAllWorkers] = useState<WorkerRecord[]>([]);
  const [monthlyWorkerId, setMonthlyWorkerId] = useState<string>("");
  const [monthCursor, setMonthCursor] = useState<Date>(() => {
    const n = new Date();
    return new Date(n.getFullYear(), n.getMonth(), 1);
  });
  const [monthlyViewMode, setMonthlyViewMode] = useState<"workforce" | "worker">("workforce");
  const [monthlyRecords, setMonthlyRecords] = useState<SiteAttendanceRecord[]>([]);
  const [monthlyWorkforceRecords, setMonthlyWorkforceRecords] = useState<DailyWorkforceAttendanceRecord[]>([]);
  const [selectedDayWorkforce, setSelectedDayWorkforce] = useState<DailyWorkforceAttendanceRecord | null>(null);
  const [loadingMonthly, setLoadingMonthly] = useState(false);
  const [analyticsRecords, setAnalyticsRecords] = useState<SiteAttendanceRecord[]>([]);
  const [analyticsWorkforceRecords, setAnalyticsWorkforceRecords] = useState<DailyWorkforceAttendanceRecord[]>([]);
  const [loadingAnalytics, setLoadingAnalytics] = useState(false);

  // Load all sites and workers once
  useEffect(() => {
    Promise.all([fetchSites(), fetchWorkers()])
      .then(([sData, wData]) => {
        setAllSites(sData);
        setAllWorkers(wData);
        if (wData.length > 0 && !monthlyWorkerId) {
          setMonthlyWorkerId(wData[0].id);
        }
        const preferred = selectedSiteId || (isSupervisor ? userAccessibleSites[0]?.id : sData[0]?.id) || "";
        setActiveSiteId(preferred);
      })
      .catch((err) => setError(getErrorMessage(err, "Failed to load site directory.")));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Sync with global header site switcher
  useEffect(() => {
    if (selectedSiteId) {
      setActiveSiteId(selectedSiteId);
    }
  }, [selectedSiteId]);

  // Sites list available for selection:
  // Supervisors can only submit/manage for assigned sites; PM and Admin can manage all sites
  const selectableSites = useMemo(() => {
    if (isSupervisor && userAccessibleSites.length > 0) {
      return userAccessibleSites;
    }
    return allSites;
  }, [isSupervisor, userAccessibleSites, allSites]);

  const activeSite = useMemo(
    () => allSites.find((s) => s.id === activeSiteId) ?? null,
    [allSites, activeSiteId]
  );

  // ───────────────────────────────────────────────────────────────────────────
  // MODULE A: Load Daily Workforce Attendance (One submission per site per date)
  // ───────────────────────────────────────────────────────────────────────────
  const loadWorkforceAttendance = useCallback(async () => {
    if (!activeSiteId) {
      setLoadingWorkforce(false);
      return;
    }
    setLoadingWorkforce(true);
    setError(null);
    try {
      // 1. Check local offline outbox for pending draft
      const outbox = getOfflineOutbox();
      const pendingDraft = outbox.find(
        (item) =>
          item.type === "workforce_attendance" &&
          item.siteId === activeSiteId &&
          item.dateStr === selectedDate &&
          (item.status === "pending" || item.status === "failed")
      );

      if (pendingDraft) {
        setIsLocallyQueued(true);
        const payload = pendingDraft.payload as WorkforceAttendancePayload;
        if (payload.categoryBreakdowns) {
          setWorkforceBreakdowns(payload.categoryBreakdowns);
        } else if (payload.categoryCounts) {
          const converted: Record<string, { fullDay: number; halfDay: number }> = {};
          for (const [k, v] of Object.entries(payload.categoryCounts)) {
            converted[k] = { fullDay: v, halfDay: 0 };
          }
          setWorkforceBreakdowns(converted);
        }
        setWorkforceRemarks(payload.remarks || "");
        setExistingWorkforceSubmission(null);
        return;
      }

      setIsLocallyQueued(false);
      const res = await fetchDailyWorkforceAttendance(selectedDate, activeSiteId);
      setWorkforceTableReady(res.tableReady);
      setExistingWorkforceSubmission(res.record);

      const nextBreakdowns: Record<string, { fullDay: number; halfDay: number }> = {};
      for (const cat of STANDARD_WORKFORCE_CATEGORIES) {
        nextBreakdowns[cat] = { fullDay: 0, halfDay: 0 };
      }

      let loadedRemarks = "";
      if (res.record) {
        loadedRemarks = res.record.remarks || "";
        if (res.record.category_counts && res.record.category_counts.length > 0) {
          for (const item of res.record.category_counts) {
            const fd =
              typeof item.full_day_count === "number"
                ? item.full_day_count
                : Number(item.count || 0);
            const hd =
              typeof item.half_day_count === "number"
                ? item.half_day_count
                : 0;
            nextBreakdowns[item.category] = { fullDay: fd, halfDay: hd };
          }
        }
      }

      setWorkforceBreakdowns(nextBreakdowns);
      setWorkforceRemarks(loadedRemarks);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load daily workforce attendance."));
    } finally {
      setLoadingWorkforce(false);
    }
  }, [activeSiteId, selectedDate]);

  // Calculations for Workforce Deployment
  const totalHeadcount = useMemo(() => {
    return Object.values(workforceBreakdowns).reduce(
      (sum, val) =>
        sum +
        Math.max(0, Math.floor(val.fullDay || 0)) +
        Math.max(0, Math.floor(val.halfDay || 0)),
      0
    );
  }, [workforceBreakdowns]);

  const totalManDays = useMemo(() => {
    return Object.values(workforceBreakdowns).reduce(
      (sum, val) =>
        sum +
        Math.max(0, Math.floor(val.fullDay || 0)) +
        Math.max(0, Math.floor(val.halfDay || 0)) * 0.5,
      0
    );
  }, [workforceBreakdowns]);

  const totalFullDay = useMemo(() => {
    return Object.values(workforceBreakdowns).reduce(
      (sum, val) => sum + Math.max(0, Math.floor(val.fullDay || 0)),
      0
    );
  }, [workforceBreakdowns]);

  const totalHalfDay = useMemo(() => {
    return Object.values(workforceBreakdowns).reduce(
      (sum, val) => sum + Math.max(0, Math.floor(val.halfDay || 0)),
      0
    );
  }, [workforceBreakdowns]);

  function adjustCategoryCount(
    category: string,
    type: "fullDay" | "halfDay",
    delta: number
  ) {
    triggerHapticFeedback();
    setWorkforceBreakdowns((prev) => {
      const current = prev[category] ?? { fullDay: 0, halfDay: 0 };
      const nextVal = Math.min(9999, Math.max(0, (current[type] ?? 0) + delta));
      return {
        ...prev,
        [category]: {
          ...current,
          [type]: nextVal,
        },
      };
    });
  }

  function setCategoryDirectCount(
    category: string,
    type: "fullDay" | "halfDay",
    rawVal: string
  ) {
    const parsed = parseInt(rawVal, 10);
    const valid = Number.isNaN(parsed) ? 0 : Math.min(9999, Math.max(0, parsed));
    setWorkforceBreakdowns((prev) => ({
      ...prev,
      [category]: {
        ...(prev[category] ?? { fullDay: 0, halfDay: 0 }),
        [type]: valid,
      },
    }));
  }

  function addCustomWorkforceTrade() {
    const trimmed = customTrade.trim();
    if (!trimmed) return;
    if (!(trimmed in workforceBreakdowns)) {
      setWorkforceBreakdowns((prev) => ({
        ...prev,
        [trimmed]: { fullDay: 0, halfDay: 0 },
      }));
    }
    setCustomTrade("");
  }

  async function handleSaveWorkforceAttendance() {
    if (!activeSite) {
      toast.error("Please select a construction site first.");
      return;
    }

    const legacyCounts: Record<string, number> = {};
    for (const [cat, b] of Object.entries(workforceBreakdowns)) {
      legacyCounts[cat] = b.fullDay + b.halfDay;
    }

    // Offline outbox interceptor
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      queueOfflineItem({
        type: "workforce_attendance",
        siteId: activeSite.id,
        siteName: activeSite.name,
        dateStr: selectedDate,
        payload: {
          siteId: activeSite.id,
          siteName: activeSite.name,
          dateStr: selectedDate,
          remarks: workforceRemarks,
          categoryCounts: legacyCounts,
          categoryBreakdowns: workforceBreakdowns,
          totalWorkforce: totalHeadcount,
          totalManDays: totalManDays,
        },
      });
      setIsLocallyQueued(true);
      toast.warning(
        `Offline: Attendance for ${activeSite.name} (${totalHeadcount} workers, ${totalManDays.toFixed(1).replace(/\.0$/, "")} man-days) stored in local Outbox. Will synchronize when connected.`
      );
      return;
    }

    setSavingWorkforce(true);
    try {
      await saveDailyWorkforceAttendance({
        siteId: activeSite.id,
        siteName: activeSite.name,
        dateStr: selectedDate,
        remarks: workforceRemarks,
        categoryCounts: legacyCounts,
        categoryBreakdowns: workforceBreakdowns,
      });

      setIsLocallyQueued(false);
      toast.success(
        existingWorkforceSubmission
          ? `Updated workforce attendance for ${activeSite.name} (${totalHeadcount} workers, ${totalManDays.toFixed(1).replace(/\.0$/, "")} man-days).`
          : `Saved workforce attendance for ${activeSite.name} (${totalHeadcount} workers, ${totalManDays.toFixed(1).replace(/\.0$/, "")} man-days).`
      );
      await loadWorkforceAttendance();
    } catch (err) {
      // Fallback: If network connection drops mid-request, safely save to offline outbox
      if (
        typeof navigator !== "undefined" &&
        (!navigator.onLine ||
          getErrorMessage(err).toLowerCase().includes("fetch") ||
          getErrorMessage(err).toLowerCase().includes("network"))
      ) {
        queueOfflineItem({
          type: "workforce_attendance",
          siteId: activeSite.id,
          siteName: activeSite.name,
          dateStr: selectedDate,
          payload: {
            siteId: activeSite.id,
            siteName: activeSite.name,
            dateStr: selectedDate,
            remarks: workforceRemarks,
            categoryCounts: legacyCounts,
            categoryBreakdowns: workforceBreakdowns,
            totalWorkforce: totalHeadcount,
            totalManDays: totalManDays,
          },
        });
        setIsLocallyQueued(true);
        toast.warning(
          `Connection lost. Attendance for ${activeSite.name} (${totalHeadcount} workers, ${totalManDays.toFixed(1).replace(/\.0$/, "")} man-days) safely stored in local Outbox.`
        );
      } else {
        toast.error(getErrorMessage(err, "Failed to save daily workforce attendance."));
      }
    } finally {
      setSavingWorkforce(false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MODULE B: Supervisor Personal Attendance
  // ───────────────────────────────────────────────────────────────────────────
  const loadSupervisorAttendanceData = useCallback(async () => {
    setLoadingSupervisor(true);
    setError(null);
    try {
      if (isPmOrAdmin) {
        if (!activeSiteId) {
          setLoadingSupervisor(false);
          return;
        }
        const [candRes, attRes] = await Promise.all([
          fetchSupervisorsForSite(activeSiteId),
          fetchSupervisorAttendance(selectedDate, activeSiteId),
        ]);
        setSupervisorTableReady(attRes.tableReady && candRes.tableReady);
        setSiteSupervisors(candRes.supervisors);

        // Pre-populate draft from existing attendance or default to 'Present'
        const draft: Record<string, { status: SupervisorAttendanceStatus; remarks: string }> = {};
        for (const s of candRes.supervisors) {
          const existing = attRes.records.find((r) => r.supervisor_id === s.id);
          draft[s.id] = {
            status: existing?.status ?? "Present",
            remarks: existing?.remarks ?? "",
          };
        }
        setSupervisorDraft(draft);
      } else if (user) {
        // If user is a supervisor, load their own personal attendance history
        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
        const history = await fetchSupervisorAttendanceHistory(
          user.id,
          thirtyDaysAgo.toISOString().slice(0, 10)
        );
        setMySupervisorHistory(history);
      }
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load supervisor attendance data."));
    } finally {
      setLoadingSupervisor(false);
    }
  }, [activeSiteId, isPmOrAdmin, selectedDate, user]);

  async function handleSaveSupervisorAttendanceBatch() {
    if (!activeSite) {
      toast.error("Please select a construction site.");
      return;
    }
    if (siteSupervisors.length === 0) {
      toast.error("No supervisors associated with this site.");
      return;
    }

    // Exclude self-marking if PM/Admin is listed as supervisor
    const validCandidates = siteSupervisors.filter((s) => s.id !== user?.id);
    if (validCandidates.length === 0) {
      toast.error("Supervisors cannot mark their own attendance.");
      return;
    }

    const recordsToSave = validCandidates.map((s) => ({
      supervisorId: s.id,
      supervisorName: s.name,
      siteId: activeSite.id,
      siteName: activeSite.name,
      dateStr: selectedDate,
      status: supervisorDraft[s.id]?.status ?? "Present",
      remarks: supervisorDraft[s.id]?.remarks ?? "",
    }));

    // Offline outbox interceptor
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      queueOfflineItem({
        type: "supervisor_attendance",
        siteId: activeSite.id,
        siteName: activeSite.name,
        dateStr: selectedDate,
        payload: { records: recordsToSave },
      });
      toast.warning(
        `Offline: Personal attendance for ${recordsToSave.length} supervisor(s) stored in local Outbox. Will synchronize when connected.`
      );
      return;
    }

    setSavingSupervisor(true);
    try {
      await saveSupervisorAttendance(recordsToSave);
      toast.success(`Saved personal attendance for ${recordsToSave.length} supervisor(s).`);
      await loadSupervisorAttendanceData();
    } catch (err) {
      if (
        typeof navigator !== "undefined" &&
        (!navigator.onLine ||
          getErrorMessage(err).toLowerCase().includes("fetch") ||
          getErrorMessage(err).toLowerCase().includes("network"))
      ) {
        queueOfflineItem({
          type: "supervisor_attendance",
          siteId: activeSite.id,
          siteName: activeSite.name,
          dateStr: selectedDate,
          payload: { records: recordsToSave },
        });
        toast.warning(
          `Connection lost. Attendance for ${recordsToSave.length} supervisor(s) safely stored in local Outbox.`
        );
      } else {
        toast.error(getErrorMessage(err, "Failed to save supervisor attendance."));
      }
    } finally {
      setSavingSupervisor(false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MODULE C: Load Named Staff Attendance
  // ───────────────────────────────────────────────────────────────────────────
  const loadNamed = useCallback(async () => {
    setLoadingNamed(true);
    setError(null);
    try {
      const [records, workersForSite] = await Promise.all([
        fetchAttendanceByDate(selectedDate, activeSiteId || undefined),
        activeSiteId ? fetchWorkers(activeSiteId) : fetchWorkers(),
      ]);
      setNamedRecords(records);
      setSiteWorkers(workersForSite);

      const draft: Record<string, AttendanceStatus> = {};
      for (const w of workersForSite) {
        const existing = records.find((r) => r.worker_id === w.id);
        draft[w.id] = existing?.status ?? "Present";
      }
      setMarkDraft(draft);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load named staff attendance."));
    } finally {
      setLoadingNamed(false);
    }
  }, [activeSiteId, selectedDate]);

  // ───────────────────────────────────────────────────────────────────────────
  // MODULE D & E: Monthly Calendar & Analytics
  // ───────────────────────────────────────────────────────────────────────────
  const loadMonthly = useCallback(async () => {
    setLoadingMonthly(true);
    try {
      const start = new Date(monthCursor.getFullYear(), monthCursor.getMonth(), 1)
        .toISOString()
        .slice(0, 10);
      const end = new Date(monthCursor.getFullYear(), monthCursor.getMonth() + 1, 0)
        .toISOString()
        .slice(0, 10);

      if (monthlyViewMode === "workforce") {
        const wfRecords = await fetchDailyWorkforceAttendanceRange(
          start,
          end,
          activeSiteId || undefined
        );
        setMonthlyWorkforceRecords(wfRecords);
        if (wfRecords.length > 0) {
          setSelectedDayWorkforce(wfRecords[0]);
        } else {
          setSelectedDayWorkforce(null);
        }
      } else if (monthlyWorkerId) {
        const data = await fetchAttendanceRange(start, end, {
          workerId: monthlyWorkerId,
        });
        setMonthlyRecords(data);
      }
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load monthly attendance."));
    } finally {
      setLoadingMonthly(false);
    }
  }, [monthlyViewMode, monthlyWorkerId, monthCursor, activeSiteId]);

  const loadAnalytics = useCallback(async () => {
    setLoadingAnalytics(true);
    try {
      const thirtyAgo = new Date();
      thirtyAgo.setDate(thirtyAgo.getDate() - 30);
      const startIso = thirtyAgo.toISOString().slice(0, 10);
      const endIso = new Date().toISOString().slice(0, 10);

      const [data, wfData] = await Promise.all([
        fetchAttendanceRange(startIso, undefined, {
          siteId: selectedSiteId || undefined,
        }),
        fetchDailyWorkforceAttendanceRange(startIso, endIso, selectedSiteId || undefined),
      ]);
      setAnalyticsRecords(data);
      setAnalyticsWorkforceRecords(wfData);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load attendance analytics."));
    } finally {
      setLoadingAnalytics(false);
    }
  }, [selectedSiteId]);

  // Trigger loads on tab or filter switch
  useEffect(() => {
    if (tab === "workforce") loadWorkforceAttendance();
    if (tab === "supervisor") loadSupervisorAttendanceData();
    if (tab === "named") loadNamed();
    if (tab === "monthly") loadMonthly();
    if (tab === "analytics") loadAnalytics();
  }, [tab, loadWorkforceAttendance, loadSupervisorAttendanceData, loadNamed, loadMonthly, loadAnalytics]);

  // Named summary calculations
  const namedStats = useMemo(() => {
    const present = namedRecords.filter((r) => r.status === "Present").length;
    const halfDay = namedRecords.filter((r) => r.status === "Half Day").length;
    const absent = namedRecords.filter((r) => r.status === "Absent").length;
    const tradeMap = new Map<string, number>();
    for (const r of namedRecords) {
      if (r.status === "Absent") continue;
      const role = r.workers?.role?.trim() || "General";
      tradeMap.set(role, (tradeMap.get(role) ?? 0) + 1);
    }
    const trades = Array.from(tradeMap.entries())
      .map(([trade, count]) => ({ trade, count }))
      .sort((a, b) => b.count - a.count);
    return { present, halfDay, absent, total: namedRecords.length, trades };
  }, [namedRecords]);

  function handleMarkAllNamedPresent() {
    setMarkDraft((prev) => {
      const next = { ...prev };
      for (const w of siteWorkers) {
        const isSup = (w.role ?? "").toLowerCase() === "supervisor";
        if (isSup && !isPmOrAdmin) continue;
        next[w.id] = "Present";
      }
      return next;
    });
  }

  async function handleSaveNamedBatch() {
    if (!activeSite) {
      toast.error("Please select a site to mark attendance.");
      return;
    }
    const permitted = siteWorkers.filter(
      (w) => isPmOrAdmin || (w.role ?? "").toLowerCase() !== "supervisor"
    );
    if (permitted.length === 0) {
      toast.error("No eligible staff to mark for your role.");
      return;
    }

    setSavingNamed(true);
    try {
      await upsertSiteAttendance(
        permitted.map((w) => ({
          worker_id: w.id,
          site_id: activeSite.id,
          attendance_date: selectedDate,
          status: markDraft[w.id] ?? "Present",
        })),
        activeSite.name,
        selectedDate
      );
      toast.success("Named attendance saved successfully.");
      await loadNamed();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to save named attendance."));
    } finally {
      setSavingNamed(false);
    }
  }

  async function handleCorrectSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!correctModalRecord) return;
    try {
      await correctAttendanceStatus(
        correctModalRecord.id,
        correctStatus,
        correctModalRecord.workers?.name ?? "Worker",
        correctModalRecord.status
      );
      toast.success("Attendance record corrected.");
      setCorrectModalRecord(null);
      await loadNamed();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to correct attendance."));
    }
  }

  function handleExportNamedCsv() {
    downloadCsv(
      `tsr_named_attendance_${selectedDate}.csv`,
      ["Date", "Worker", "Role", "Site", "Status"],
      namedRecords.map((r) => [
        r.attendance_date,
        r.workers?.name ?? "Unknown",
        r.workers?.role ?? "",
        r.sites?.name ?? "",
        r.status,
      ])
    );
  }

  // Monthly calendar metadata (Staff Directory)
  const calendarMeta = useMemo(() => {
    const year = monthCursor.getFullYear();
    const month = monthCursor.getMonth();
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const firstWeekday = (new Date(year, month, 1).getDay() + 6) % 7; // Mon=0
    const statusByDay = new Map<number, AttendanceStatus>();
    for (const r of monthlyRecords) {
      const dayNum = parseInt(r.attendance_date.slice(8, 10), 10);
      if (!Number.isNaN(dayNum)) statusByDay.set(dayNum, r.status);
    }
    return { year, month, daysInMonth, firstWeekday, statusByDay };
  }, [monthCursor, monthlyRecords]);

  // Monthly workforce calendar metadata (Module A: Site Workforce Headcounts & Man-Days)
  const workforceCalendarMeta = useMemo(() => {
    const year = monthCursor.getFullYear();
    const month = monthCursor.getMonth();
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const firstWeekday = (new Date(year, month, 1).getDay() + 6) % 7; // Mon=0
    const recordsByDay = new Map<number, DailyWorkforceAttendanceRecord>();
    for (const r of monthlyWorkforceRecords) {
      const dayNum = parseInt(r.attendance_date.slice(8, 10), 10);
      if (!Number.isNaN(dayNum)) recordsByDay.set(dayNum, r);
    }
    return { year, month, daysInMonth, firstWeekday, recordsByDay };
  }, [monthCursor, monthlyWorkforceRecords]);

  // Analytics for workforce (Headcount vs Man-Days & Category Breakdown)
  const workforceAnalytics = useMemo(() => {
    let totalHeadcountSum = 0;
    let totalManDaysSum = 0;
    let totalFullDaySum = 0;
    let totalHalfDaySum = 0;

    const categoryStats: Record<
      string,
      { fullDay: number; halfDay: number; headcount: number; manDays: number }
    > = {};

    for (const cat of STANDARD_WORKFORCE_CATEGORIES) {
      categoryStats[cat] = { fullDay: 0, halfDay: 0, headcount: 0, manDays: 0 };
    }

    const trendByDate: Array<{
      date: string;
      label: string;
      Headcount: number;
      ManDays: number;
    }> = [];

    for (const rec of analyticsWorkforceRecords) {
      const hc = rec.total_workforce || 0;
      const md = Number(rec.total_man_days ?? rec.total_workforce ?? 0);
      totalHeadcountSum += hc;
      totalManDaysSum += md;

      trendByDate.push({
        date: rec.attendance_date,
        label: rec.attendance_date.slice(5),
        Headcount: hc,
        ManDays: Number(md.toFixed(1)),
      });

      if (rec.category_counts) {
        for (const c of rec.category_counts) {
          const catName = c.category;
          if (!categoryStats[catName]) {
            categoryStats[catName] = {
              fullDay: 0,
              halfDay: 0,
              headcount: 0,
              manDays: 0,
            };
          }
          const fd =
            typeof c.full_day_count === "number"
              ? c.full_day_count
              : Number(c.count || 0);
          const hd =
            typeof c.half_day_count === "number"
              ? c.half_day_count
              : 0;
          categoryStats[catName].fullDay += fd;
          categoryStats[catName].halfDay += hd;
          categoryStats[catName].headcount += fd + hd;
          categoryStats[catName].manDays += fd + hd * 0.5;
          totalFullDaySum += fd;
          totalHalfDaySum += hd;
        }
      }
    }

    const categoriesArray = Object.entries(categoryStats)
      .map(([category, stats]) => ({ category, ...stats }))
      .sort((a, b) => b.headcount - a.headcount);

    return {
      totalHeadcount: totalHeadcountSum,
      totalManDays: totalManDaysSum,
      totalFullDay: totalFullDaySum,
      totalHalfDay: totalHalfDaySum,
      categoriesArray,
      trendByDate,
      totalDays: analyticsWorkforceRecords.length,
    };
  }, [analyticsWorkforceRecords]);

  // Analytics helpers
  const analyticsData = useMemo(() => {
    const present = analyticsRecords.filter((r) => r.status === "Present").length;
    const absent = analyticsRecords.filter((r) => r.status === "Absent").length;
    const halfDay = analyticsRecords.filter((r) => r.status === "Half Day").length;
    const pie = [
      { name: "Present", value: present, color: "#10B981" },
      { name: "Half Day", value: halfDay, color: "#F59E0B" },
      { name: "Absent", value: absent, color: "#EF4444" },
    ].filter((s) => s.value > 0);

    const weeks: Array<{ label: string; Present: number }> = [];
    for (let w = 3; w >= 0; w--) {
      const start = new Date();
      start.setDate(start.getDate() - (7 * w + 6));
      const end = new Date();
      end.setDate(end.getDate() - 7 * w);
      const startStr = start.toISOString().slice(0, 10);
      const endStr = end.toISOString().slice(0, 10);
      const count = analyticsRecords.filter(
        (r) =>
          r.attendance_date >= startStr &&
          r.attendance_date <= endStr &&
          r.status === "Present"
      ).length;
      weeks.push({ label: `Week ${4 - w}`, Present: count });
    }

    const byWorker = new Map<string, { name: string; days: number }>();
    for (const r of analyticsRecords) {
      if (r.status !== "Present") continue;
      const cur = byWorker.get(r.worker_id) ?? {
        name: r.workers?.name ?? "Worker",
        days: 0,
      };
      cur.days += 1;
      byWorker.set(r.worker_id, cur);
    }
    const topAttendees = Array.from(byWorker.values())
      .sort((a, b) => b.days - a.days)
      .slice(0, 5);

    return { present, absent, halfDay, pie, weeks, topAttendees };
  }, [analyticsRecords]);

  return (
    <div>
      <PageHeader
        title="Workforce & Attendance Center"
        description="Comprehensive attendance management featuring Daily Workforce Headcounts (Module A) and Supervisor Personal Attendance (Module B)."
      />

      {error && <ErrorBanner message={error} />}

      {/* Navigation Tabs */}
      <div className="mb-5 flex flex-wrap gap-1.5 border-b border-slate-200 pb-3">
        {(
          [
            { id: "workforce", label: "Module A: Daily Workforce", icon: HardHat },
            { id: "supervisor", label: "Module B: Supervisor Attendance", icon: UserCheck },
            { id: "named", label: "Staff Directory", icon: ClipboardCheck },
            { id: "monthly", label: "Monthly Calendar", icon: Calendar },
            { id: "analytics", label: "Analytics & Trends", icon: BarChart3 },
            { id: "reports", label: "Workforce Reports", icon: BarChart3 },
          ] as Array<{
            id: AttendanceTab;
            label: string;
            icon: React.ComponentType<{ className?: string }>;
          }>
        ).map((item) => {
          const Icon = item.icon;
          const active = tab === item.id;
          return (
            <button
              key={item.id}
              type="button"
              onClick={() => setTab(item.id)}
              className={`inline-flex items-center gap-2 rounded-lg px-3.5 py-2 text-xs font-semibold transition-colors cursor-pointer ${
                active
                  ? "bg-[#0B1628] text-white shadow-sm"
                  : "border border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
              }`}
            >
              <Icon className="h-3.5 w-3.5" />
              {item.label}
            </button>
          );
        })}
      </div>

      {/* Controls Strip (for Workforce, Supervisor, and Named tabs) */}
      {(tab === "workforce" || tab === "supervisor" || tab === "named") && (
        <Card className="mb-5">
          <CardContent className="grid grid-cols-1 gap-4 p-4 sm:grid-cols-2">
            <div>
              <Select
                label={
                  isSupervisor
                    ? "Your Assigned Construction Site"
                    : "Construction Site (PM / Admin Global Access)"
                }
                value={activeSiteId}
                onChange={(e) => setActiveSiteId(e.target.value)}
              >
                <option value="">Select a site…</option>
                {selectableSites.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name} {s.location ? `(${s.location})` : ""}
                  </option>
                ))}
              </Select>
              {isSupervisor && (
                <p className="mt-1 text-[11px] text-slate-500">
                  Supervisor Mode: Restricted strictly to sites assigned to your account.
                </p>
              )}
            </div>

            <Input
              label="Attendance Date"
              type="date"
              max={todayIsoDate()}
              value={selectedDate}
              onChange={(e) => setSelectedDate(e.target.value)}
            />
          </CardContent>
        </Card>
      )}

      {/* ───────────────────────────────────────────────────────────────────── */}
      {/* TAB 1: MODULE A — DAILY WORKFORCE ATTENDANCE                           */}
      {/* ───────────────────────────────────────────────────────────────────── */}
      {tab === "workforce" && (
        <div>
          {!workforceTableReady && (
            <div className="mb-5 rounded-xl border border-amber-200 bg-amber-50 p-4 text-xs text-amber-950">
              <div className="flex items-start gap-2.5">
                <Info className="mt-0.5 h-4 w-4 shrink-0 text-amber-700" />
                <div className="space-y-1.5">
                  <p className="font-semibold">
                    Pending Database Proposal: <code>public.daily_workforce_attendance</code>
                  </p>
                  <p className="text-amber-900 leading-relaxed">
                    The additive Daily Workforce migration (
                    <code className="rounded bg-amber-100 px-1.5 py-0.5 font-mono">
                      supabase/migrations/20261120_workforce_and_supervisor_attendance_PROPOSAL.sql
                    </code>
                    ) has been prepared and is ready for administrator execution. Once applied in
                    Supabase, records will persist directly to the parent header and trade detail tables.
                  </p>
                </div>
              </div>
            </div>
          )}

          {loadingWorkforce ? (
            <LoadingTable rows={4} />
          ) : !activeSite ? (
            <EmptyState
              icon={HardHat}
              title="Select a Construction Site"
              description="Choose an authorized site above to view or submit daily trade category counts."
            />
          ) : (
            <>
              <Card>
              <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    <CardTitle>Daily Workforce Headcount — {activeSite.name}</CardTitle>
                    {isLocallyQueued ? (
                      <Badge variant="warning">Stored in Outbox (Pending Sync)</Badge>
                    ) : existingWorkforceSubmission ? (
                      <Badge variant="blue">Synced with Database</Badge>
                    ) : (
                      <Badge variant="success">New Daily Submission</Badge>
                    )}
                  </div>
                  <CardDescription className="mt-1">
                    {formatDisplayDate(selectedDate)} · Anonymous trade category counts with automatic total workforce calculation.
                  </CardDescription>
                </div>

                <div className="flex flex-wrap items-center gap-3">
                  <div className="rounded-xl border border-slate-200 bg-slate-50 px-4 py-2 text-right">
                    <p className="text-[10px] font-bold uppercase tracking-wider text-slate-500">
                      Total Workers (Headcount)
                    </p>
                    <p className="text-2xl font-black text-slate-900">
                      {totalHeadcount}{" "}
                      <span className="text-xs font-semibold text-slate-500">
                        Staff
                      </span>
                    </p>
                    <p className="text-[10px] text-slate-500">
                      {totalFullDay} Full Day + {totalHalfDay} Half Day
                    </p>
                  </div>

                  <div className="rounded-xl border border-blue-200 bg-blue-50/80 px-4 py-2 text-right">
                    <p className="text-[10px] font-bold uppercase tracking-wider text-blue-700">
                      Total Man-Days (Equivalent)
                    </p>
                    <p className="text-2xl font-black text-blue-900">
                      {totalManDays.toFixed(1).replace(/\.0$/, "")}{" "}
                      <span className="text-xs font-semibold text-blue-700">
                        MD
                      </span>
                    </p>
                    <p className="text-[10px] text-blue-600 font-medium">
                      Full + (Half × 0.5)
                    </p>
                  </div>
                </div>
              </CardHeader>

              <CardContent className="space-y-6">
                {/* Trade Category Section */}
                <div>
                  <div className="mb-3 flex items-center justify-between">
                    <p className="text-xs font-bold uppercase tracking-wider text-slate-500">
                      Trade Categories (Full-Day &amp; Half-Day Deployment)
                    </p>
                    <span className="hidden text-[11px] font-medium text-slate-400 sm:inline">
                      1 Full-Day Worker = 1.0 MD · 1 Half-Day Worker = 0.5 MD
                    </span>
                  </div>

                  {/* Desktop Structured Table (md+) */}
                  <div className="hidden overflow-hidden rounded-xl border border-slate-200 bg-white md:block">
                    <table className="w-full text-left text-xs">
                      <thead className="border-b border-slate-200 bg-slate-50 font-bold uppercase tracking-wider text-slate-500">
                        <tr>
                          <th className="px-4 py-3">Trade Category</th>
                          <th className="px-4 py-3 text-center">Full Day (1.0 MD)</th>
                          <th className="px-4 py-3 text-center">Half Day (0.5 MD)</th>
                          <th className="px-4 py-3 text-center">Headcount</th>
                          <th className="px-4 py-3 text-right">Man-Day Equiv.</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100">
                        {Object.entries(workforceBreakdowns).map(([cat, b]) => {
                          const catHeadcount = b.fullDay + b.halfDay;
                          const catManDays = b.fullDay + b.halfDay * 0.5;
                          const hasWorkers = catHeadcount > 0;

                          return (
                            <tr
                              key={cat}
                              className={
                                hasWorkers
                                  ? "bg-blue-50/30"
                                  : "hover:bg-slate-50/50"
                              }
                            >
                              <td className="px-4 py-3">
                                <span className="font-bold text-slate-900">{cat}</span>
                                {hasWorkers && (
                                  <span className="ml-2 rounded-full bg-blue-100 px-2 py-0.5 text-[10px] font-semibold text-blue-800">
                                    Active
                                  </span>
                                )}
                              </td>

                              {/* Full Day Controls */}
                              <td className="px-4 py-3">
                                <div className="flex items-center justify-center gap-1.5">
                                  <button
                                    type="button"
                                    onClick={() =>
                                      adjustCategoryCount(cat, "fullDay", -1)
                                    }
                                    disabled={b.fullDay <= 0}
                                    aria-label={`Decrease ${cat} full-day`}
                                    className="flex h-8 w-8 items-center justify-center rounded-lg border border-slate-300 bg-white text-slate-700 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-30 cursor-pointer"
                                  >
                                    <Minus className="h-3.5 w-3.5" />
                                  </button>
                                  <input
                                    type="number"
                                    min={0}
                                    max={9999}
                                    value={b.fullDay}
                                    onChange={(e) =>
                                      setCategoryDirectCount(
                                        cat,
                                        "fullDay",
                                        e.target.value
                                      )
                                    }
                                    aria-label={`${cat} full-day count`}
                                    className="h-8 w-14 rounded-lg border border-slate-300 bg-white text-center text-sm font-black text-slate-900 focus:border-[#2563EB] focus:outline-none"
                                  />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      adjustCategoryCount(cat, "fullDay", 1)
                                    }
                                    aria-label={`Increase ${cat} full-day`}
                                    className="flex h-8 w-8 items-center justify-center rounded-lg border border-[#2563EB] bg-[#2563EB] text-white hover:bg-[#1D4ED8] cursor-pointer"
                                  >
                                    <Plus className="h-3.5 w-3.5" />
                                  </button>
                                </div>
                              </td>

                              {/* Half Day Controls */}
                              <td className="px-4 py-3">
                                <div className="flex items-center justify-center gap-1.5">
                                  <button
                                    type="button"
                                    onClick={() =>
                                      adjustCategoryCount(cat, "halfDay", -1)
                                    }
                                    disabled={b.halfDay <= 0}
                                    aria-label={`Decrease ${cat} half-day`}
                                    className="flex h-8 w-8 items-center justify-center rounded-lg border border-slate-300 bg-white text-slate-700 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-30 cursor-pointer"
                                  >
                                    <Minus className="h-3.5 w-3.5" />
                                  </button>
                                  <input
                                    type="number"
                                    min={0}
                                    max={9999}
                                    value={b.halfDay}
                                    onChange={(e) =>
                                      setCategoryDirectCount(
                                        cat,
                                        "halfDay",
                                        e.target.value
                                      )
                                    }
                                    aria-label={`${cat} half-day count`}
                                    className="h-8 w-14 rounded-lg border border-amber-300 bg-amber-50/30 text-center text-sm font-black text-amber-900 focus:border-amber-500 focus:outline-none"
                                  />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      adjustCategoryCount(cat, "halfDay", 1)
                                    }
                                    aria-label={`Increase ${cat} half-day`}
                                    className="flex h-8 w-8 items-center justify-center rounded-lg border border-amber-600 bg-amber-500 text-white hover:bg-amber-600 cursor-pointer"
                                  >
                                    <Plus className="h-3.5 w-3.5" />
                                  </button>
                                </div>
                              </td>

                              {/* Headcount */}
                              <td className="px-4 py-3 text-center">
                                <span className="font-extrabold text-slate-900">
                                  {catHeadcount}
                                </span>{" "}
                                <span className="text-[10px] text-slate-500">
                                  workers
                                </span>
                              </td>

                              {/* Man-Days */}
                              <td className="px-4 py-3 text-right">
                                <span className="font-mono text-sm font-black text-blue-900">
                                  {catManDays.toFixed(1).replace(/\.0$/, "")}
                                </span>{" "}
                                <span className="text-[10px] font-bold text-blue-700">
                                  MD
                                </span>
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>

                  {/* Mobile Compact Stacked Cards (< md) */}
                  <div className="grid grid-cols-1 gap-3 md:hidden">
                    {Object.entries(workforceBreakdowns).map(([cat, b]) => {
                      const catHeadcount = b.fullDay + b.halfDay;
                      const catManDays = b.fullDay + b.halfDay * 0.5;
                      const hasWorkers = catHeadcount > 0;

                      return (
                        <div
                          key={cat}
                          className={`rounded-xl border p-3.5 transition-all ${
                            hasWorkers
                              ? "border-blue-300 bg-blue-50/40 shadow-xs"
                              : "border-slate-200 bg-white"
                          }`}
                        >
                          <div className="mb-2.5 flex items-center justify-between">
                            <span className="text-sm font-bold text-slate-900">
                              {cat}
                            </span>
                            <div className="flex items-center gap-1.5">
                              <span className="rounded bg-slate-100 px-2 py-0.5 text-xs font-bold text-slate-700">
                                {catHeadcount} Workers
                              </span>
                              <span className="rounded bg-blue-100 px-2 py-0.5 text-xs font-black text-blue-900">
                                {catManDays.toFixed(1).replace(/\.0$/, "")} MD
                              </span>
                            </div>
                          </div>

                          <div className="grid grid-cols-2 gap-2 border-t border-slate-100 pt-2.5">
                            {/* Full Day Input Card */}
                            <div className="rounded-lg bg-slate-50 p-2">
                              <div className="flex items-center justify-between text-[10px] font-bold text-slate-600 uppercase">
                                <span>Full Day</span>
                                <span className="text-slate-400">1.0 MD</span>
                              </div>
                              <div className="mt-1.5 flex items-center justify-between">
                                <button
                                  type="button"
                                  onClick={() =>
                                    adjustCategoryCount(cat, "fullDay", -1)
                                  }
                                  disabled={b.fullDay <= 0}
                                  className="flex h-8 w-8 items-center justify-center rounded-lg border border-slate-300 bg-white text-slate-700 disabled:opacity-30"
                                >
                                  <Minus className="h-3.5 w-3.5" />
                                </button>
                                <input
                                  type="number"
                                  min={0}
                                  max={9999}
                                  value={b.fullDay}
                                  onChange={(e) =>
                                    setCategoryDirectCount(
                                      cat,
                                      "fullDay",
                                      e.target.value
                                    )
                                  }
                                  className="h-8 w-12 rounded-lg border border-slate-300 bg-white text-center text-sm font-bold text-slate-900"
                                />
                                <button
                                  type="button"
                                  onClick={() =>
                                    adjustCategoryCount(cat, "fullDay", 1)
                                  }
                                  className="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-600 text-white"
                                >
                                  <Plus className="h-3.5 w-3.5" />
                                </button>
                              </div>
                            </div>

                            {/* Half Day Input Card */}
                            <div className="rounded-lg bg-amber-50/50 p-2">
                              <div className="flex items-center justify-between text-[10px] font-bold text-amber-800 uppercase">
                                <span>Half Day</span>
                                <span className="text-amber-600">0.5 MD</span>
                              </div>
                              <div className="mt-1.5 flex items-center justify-between">
                                <button
                                  type="button"
                                  onClick={() =>
                                    adjustCategoryCount(cat, "halfDay", -1)
                                  }
                                  disabled={b.halfDay <= 0}
                                  className="flex h-8 w-8 items-center justify-center rounded-lg border border-slate-300 bg-white text-slate-700 disabled:opacity-30"
                                >
                                  <Minus className="h-3.5 w-3.5" />
                                </button>
                                <input
                                  type="number"
                                  min={0}
                                  max={9999}
                                  value={b.halfDay}
                                  onChange={(e) =>
                                    setCategoryDirectCount(
                                      cat,
                                      "halfDay",
                                      e.target.value
                                    )
                                  }
                                  className="h-8 w-12 rounded-lg border border-amber-300 bg-white text-center text-sm font-bold text-amber-900"
                                />
                                <button
                                  type="button"
                                  onClick={() =>
                                    adjustCategoryCount(cat, "halfDay", 1)
                                  }
                                  className="flex h-8 w-8 items-center justify-center rounded-lg bg-amber-500 text-white"
                                >
                                  <Plus className="h-3.5 w-3.5" />
                                </button>
                              </div>
                            </div>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>

                {/* Add Custom Trade + Remarks */}
                <div className="grid grid-cols-1 gap-4 border-t border-slate-100 pt-5 sm:grid-cols-2">
                  <div className="flex items-end gap-2">
                    <div className="flex-1">
                      <Input
                        label="Add Custom Trade Category"
                        placeholder="e.g., Bar Bender, Tile Mason, Welder"
                        value={customTrade}
                        onChange={(e) => setCustomTrade(e.target.value)}
                      />
                    </div>
                    <Button variant="outline" onClick={addCustomWorkforceTrade}>
                      <Plus className="h-4 w-4" />
                      Add Trade
                    </Button>
                  </div>

                  <div>
                    <Input
                      label="Shift / Site Remarks & Weather Conditions"
                      placeholder="e.g., First floor slab pouring shift, sunny weather"
                      value={workforceRemarks}
                      onChange={(e) => setWorkforceRemarks(e.target.value)}
                    />
                  </div>
                </div>

                {/* Submission Action Bar */}
                <div className="flex flex-col items-start justify-between gap-3 border-t border-slate-100 pt-4 sm:flex-row sm:items-center">
                  <div>
                    {existingWorkforceSubmission ? (
                      <p className="text-xs text-slate-500">
                        Existing submission found for this site &amp; date. Modifying values will update the record.
                      </p>
                    ) : (
                      <p className="text-xs text-slate-500">
                        Ready to submit. Single submission per site per date with full editability.
                      </p>
                    )}
                  </div>

                  <Button
                    onClick={handleSaveWorkforceAttendance}
                    loading={savingWorkforce}
                  >
                    <Save className="h-4 w-4" />
                    {isLocallyQueued
                      ? "Update Outbox Entry"
                      : existingWorkforceSubmission
                      ? "Update Workforce Attendance"
                      : "Submit Daily Workforce Attendance"}
                  </Button>
                </div>
              </CardContent>
            </Card>

            {/* Mobile Sticky 1-Handed Quick Submit Bar */}
            <div className="fixed bottom-[calc(env(safe-area-inset-bottom)+3.5rem)] left-0 right-0 z-20 flex items-center justify-between border-t border-slate-200 bg-white/95 px-4 py-2.5 shadow-lg backdrop-blur-md sm:hidden">
              <div>
                <p className="text-[10px] font-bold uppercase tracking-wider text-slate-500">
                  Daily Workforce
                </p>
                <p className="text-base font-black text-slate-900">
                  {totalHeadcount}{" "}
                  <span className="text-xs font-semibold text-slate-500">
                    Workers
                  </span>{" "}
                  ·{" "}
                  <span className="text-blue-700">
                    {totalManDays.toFixed(1).replace(/\.0$/, "")} MD
                  </span>
                </p>
              </div>
              <Button
                size="sm"
                onClick={handleSaveWorkforceAttendance}
                loading={savingWorkforce}
                className="h-10 px-4"
              >
                <Save className="h-4 w-4" />
                {isLocallyQueued
                  ? "Update Outbox"
                  : existingWorkforceSubmission
                  ? "Update"
                  : "Submit"}
              </Button>
            </div>
          </>
          )}
        </div>
      )}

      {/* ───────────────────────────────────────────────────────────────────── */}
      {/* TAB 2: MODULE B — SUPERVISOR PERSONAL ATTENDANCE                      */}
      {/* ───────────────────────────────────────────────────────────────────── */}
      {tab === "supervisor" && (
        <div className="space-y-5">
          {!supervisorTableReady && (
            <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-xs text-amber-950">
              <div className="flex items-start gap-2.5">
                <Info className="mt-0.5 h-4 w-4 shrink-0 text-amber-700" />
                <div className="space-y-1.5">
                  <p className="font-semibold">
                    Pending Database Migration: <code>public.supervisor_attendance</code>
                  </p>
                  <p className="text-amber-900 leading-relaxed">
                    Supervisor Personal Attendance uses dedicated table <code>supervisor_attendance</code> with
                    database-level self-marking prevention. Please review the proposed migration in{" "}
                    <code className="rounded bg-amber-100 px-1.5 py-0.5 font-mono">
                      supabase/migrations/20261120_workforce_and_supervisor_attendance_PROPOSAL.sql
                    </code>
                    .
                  </p>
                </div>
              </div>
            </div>
          )}

          {/* Supervisor View vs Project Manager / Admin View */}
          {!isPmOrAdmin ? (
            /* Supervisor Personal View: Read-only attendance history */
            <div className="space-y-5">
              <div className="rounded-xl border border-blue-200 bg-blue-50/70 p-4 text-xs text-blue-950">
                <div className="flex items-start gap-2.5">
                  <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-[#2563EB]" />
                  <div>
                    <p className="font-bold">Company Policy: Supervisor Personal Attendance Governance</p>
                    <p className="mt-1 text-blue-900 leading-relaxed">
                      Your daily personal attendance is recorded exclusively by your <strong>Project Manager</strong>{" "}
                      or <strong>Administrator</strong>. By security and audit policy, supervisors are prohibited
                      from self-marking personal attendance. Below is your verified attendance history.
                    </p>
                  </div>
                </div>
              </div>

              <Card>
                <CardHeader>
                  <CardTitle>My Personal Attendance History (Past 30 Days)</CardTitle>
                  <CardDescription>
                    Official record for {profile?.name || user?.email}
                  </CardDescription>
                </CardHeader>
                <CardContent className="p-0">
                  {mySupervisorHistory.length === 0 ? (
                    <p className="p-8 text-center text-xs text-slate-500">
                      No personal attendance entries recorded for your account yet.
                    </p>
                  ) : (
                    <div className="divide-y divide-slate-100">
                      {mySupervisorHistory.map((rec) => (
                        <div key={rec.id} className="flex items-center justify-between p-4">
                          <div>
                            <p className="text-sm font-semibold text-slate-900">
                              {formatDisplayDate(rec.attendance_date)}
                            </p>
                            <p className="text-xs text-slate-500">
                              Site: {rec.sites?.name || "Assigned Site"}
                              {rec.remarks && ` · Remarks: ${rec.remarks}`}
                            </p>
                          </div>
                          <StatusBadge status={rec.status} />
                        </div>
                      ))}
                    </div>
                  )}
                </CardContent>
              </Card>
            </div>
          ) : (
            /* PM / Admin Management View */
            <div>
              {loadingSupervisor ? (
                <LoadingTable rows={4} />
              ) : !activeSite ? (
                <EmptyState
                  icon={UserCheck}
                  title="Select a Construction Site"
                  description="Choose a site above to record or review attendance for assigned supervisors."
                />
              ) : siteSupervisors.length === 0 ? (
                <EmptyState
                  icon={Users}
                  title="No Supervisors Associated With This Site"
                  description="There are currently no active supervisors linked to this site in public.site_memberships or user_profiles."
                />
              ) : (
                <Card>
                  <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                    <div>
                      <div className="flex items-center gap-2">
                        <CardTitle>Supervisor Attendance — {activeSite.name}</CardTitle>
                        <Badge variant="navy">{siteSupervisors.length} Supervisor(s)</Badge>
                      </div>
                      <CardDescription className="mt-1">
                        {formatDisplayDate(selectedDate)} · Managed strictly by Project Managers and Administrators.
                      </CardDescription>
                    </div>

                    <Button
                      onClick={handleSaveSupervisorAttendanceBatch}
                      loading={savingSupervisor}
                    >
                      <Save className="h-4 w-4" />
                      Save Supervisor Attendance
                    </Button>
                  </CardHeader>

                  <CardContent className="space-y-4">
                    <div className="divide-y divide-slate-100 rounded-xl border border-slate-200">
                      {siteSupervisors.map((s) => {
                        const isSelf = user?.id === s.id;
                        const current = supervisorDraft[s.id]?.status ?? "Present";
                        const currentRemarks = supervisorDraft[s.id]?.remarks ?? "";

                        return (
                          <div
                            key={s.id}
                            className={`flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between ${
                              isSelf ? "bg-slate-50 opacity-80" : "bg-white"
                            }`}
                          >
                            <div className="min-w-0">
                              <div className="flex items-center gap-2">
                                <p className="truncate text-sm font-bold text-slate-900">{s.name}</p>
                                {s.isAssignedToSite ? (
                                  <Badge variant="blue">Assigned to Site</Badge>
                                ) : (
                                  <Badge variant="warning">Active Staff</Badge>
                                )}
                              </div>
                              <p className="text-xs text-slate-500">{s.email}</p>
                            </div>

                            {isSelf ? (
                              <div className="flex items-center gap-2 text-xs font-semibold text-amber-700 bg-amber-50 px-3 py-1.5 rounded-lg border border-amber-200">
                                <Lock className="h-3.5 w-3.5" />
                                Self-marking prohibited by company policy
                              </div>
                            ) : (
                              <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
                                <div className="flex gap-1.5">
                                  {SUPERVISOR_ATTENDANCE_STATUSES.map((st) => {
                                    const active = current === st;
                                    const activeCls =
                                      st === "Present"
                                        ? "bg-emerald-600 text-white border-emerald-600"
                                        : st === "Half Day"
                                        ? "bg-amber-500 text-white border-amber-500"
                                        : st === "Absent"
                                        ? "bg-red-600 text-white border-red-600"
                                        : "bg-purple-600 text-white border-purple-600";

                                    return (
                                      <button
                                        key={st}
                                        type="button"
                                        onClick={() =>
                                          setSupervisorDraft((prev) => ({
                                            ...prev,
                                            [s.id]: {
                                              status: st,
                                              remarks: prev[s.id]?.remarks ?? "",
                                            },
                                          }))
                                        }
                                        className={`rounded-lg border px-3 py-1.5 text-xs font-semibold transition-colors cursor-pointer ${
                                          active
                                            ? activeCls
                                            : "border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
                                        }`}
                                      >
                                        {st}
                                      </button>
                                    );
                                  })}
                                </div>

                                <input
                                  type="text"
                                  placeholder="Remarks (optional)"
                                  value={currentRemarks}
                                  onChange={(e) =>
                                    setSupervisorDraft((prev) => ({
                                      ...prev,
                                      [s.id]: {
                                        status: prev[s.id]?.status ?? "Present",
                                        remarks: e.target.value,
                                      },
                                    }))
                                  }
                                  className="h-8 rounded-lg border border-slate-300 bg-white px-2.5 text-xs text-slate-900 placeholder:text-slate-400 focus:border-[#2563EB] focus:outline-none"
                                />
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  </CardContent>
                </Card>
              )}
            </div>
          )}
        </div>
      )}

      {/* ───────────────────────────────────────────────────────────────────── */}
      {/* TAB 3: STAFF DIRECTORY (Existing site_attendance)                     */}
      {/* ───────────────────────────────────────────────────────────────────── */}
      {tab === "named" && (
        <div className="space-y-5">
          {/* Summary Strip */}
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div className="rounded-xl border border-emerald-200 bg-emerald-50/70 p-3.5">
              <p className="text-[11px] font-semibold uppercase text-emerald-700">Present</p>
              <p className="mt-1 text-2xl font-bold text-emerald-800">{namedStats.present}</p>
            </div>
            <div className="rounded-xl border border-amber-200 bg-amber-50/70 p-3.5">
              <p className="text-[11px] font-semibold uppercase text-amber-700">Half Day</p>
              <p className="mt-1 text-2xl font-bold text-amber-800">{namedStats.halfDay}</p>
            </div>
            <div className="rounded-xl border border-red-200 bg-red-50/70 p-3.5">
              <p className="text-[11px] font-semibold uppercase text-red-700">Absent</p>
              <p className="mt-1 text-2xl font-bold text-red-800">{namedStats.absent}</p>
            </div>
            <div className="rounded-xl border border-slate-200 bg-white p-3.5">
              <p className="text-[11px] font-semibold uppercase text-slate-500">Total Logged</p>
              <p className="mt-1 text-2xl font-bold text-slate-900">{namedStats.total}</p>
            </div>
          </div>

          {/* Active Trade Breakdown */}
          {namedStats.trades.length > 0 && (
            <div className="flex flex-wrap items-center gap-2 rounded-xl border border-slate-200 bg-white px-4 py-3">
              <span className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                Active Trade Breakdown:
              </span>
              {namedStats.trades.map((t) => (
                <Badge key={t.trade} variant="blue">
                  {t.trade}: {t.count}
                </Badge>
              ))}
            </div>
          )}

          {loadingNamed ? (
            <LoadingTable rows={5} />
          ) : (
            <>
              {activeSite && siteWorkers.length > 0 && (
                <Card>
                  <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                    <div>
                      <CardTitle>
                        Mark Named Workers — {activeSite.name} ({formatDisplayDate(selectedDate)})
                      </CardTitle>
                      <CardDescription>
                        Records directly to existing <code>public.site_attendance</code>
                      </CardDescription>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={handleMarkAllNamedPresent}
                      >
                        <CheckCheck className="h-3.5 w-3.5" />
                        Mark All Present
                      </Button>
                      <Button
                        size="sm"
                        onClick={handleSaveNamedBatch}
                        loading={savingNamed}
                      >
                        <Save className="h-3.5 w-3.5" />
                        Save Batch
                      </Button>
                    </div>
                  </CardHeader>
                  <CardContent className="space-y-2.5">
                    {siteWorkers.map((w) => {
                      const isSup = (w.role ?? "").toLowerCase() === "supervisor";
                      const locked = isSup && !isPmOrAdmin;
                      const current = markDraft[w.id] ?? "Present";
                      return (
                        <div
                          key={w.id}
                          className="flex flex-col justify-between gap-3 rounded-lg border border-slate-200 p-3 sm:flex-row sm:items-center"
                        >
                          <div>
                            <div className="flex items-center gap-2">
                              <span className="text-sm font-semibold text-slate-900">{w.name}</span>
                              {isSup && <Badge variant="blue">Supervisor</Badge>}
                            </div>
                            <p className="text-xs text-slate-500">{w.role || "Worker"}</p>
                          </div>

                          {locked ? (
                            <span className="inline-flex items-center gap-1.5 rounded-md bg-slate-100 px-3 py-1.5 text-xs font-medium text-slate-600">
                              <Lock className="h-3.5 w-3.5" />
                              Managed via Supervisor Attendance Module
                            </span>
                          ) : (
                            <div className="flex gap-1.5">
                              {(["Present", "Half Day", "Absent"] as AttendanceStatus[]).map((st) => {
                                const active = current === st;
                                const activeCls =
                                  st === "Present"
                                    ? "bg-emerald-600 text-white border-emerald-600"
                                    : st === "Half Day"
                                    ? "bg-amber-500 text-white border-amber-500"
                                    : "bg-red-600 text-white border-red-600";
                                return (
                                  <button
                                    key={st}
                                    type="button"
                                    onClick={() =>
                                      setMarkDraft((prev) => ({
                                        ...prev,
                                        [w.id]: st,
                                      }))
                                    }
                                    className={`rounded-lg border px-3 py-1.5 text-xs font-semibold transition-colors cursor-pointer ${
                                      active
                                        ? activeCls
                                        : "border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
                                    }`}
                                  >
                                    {st}
                                  </button>
                                );
                              })}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </CardContent>
                </Card>
              )}

              {/* Logged Records for Date */}
              <Card>
                <CardHeader>
                  <CardTitle>
                    Recorded Worker Attendance for {formatDisplayDate(selectedDate)} ({namedRecords.length})
                  </CardTitle>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={handleExportNamedCsv}
                    disabled={namedRecords.length === 0}
                  >
                    <FileSpreadsheet className="h-3.5 w-3.5" />
                    Export CSV
                  </Button>
                </CardHeader>
                <CardContent className="p-0">
                  {namedRecords.length === 0 ? (
                    <p className="p-8 text-center text-xs text-slate-500">
                      No worker attendance entries logged for this date.
                    </p>
                  ) : (
                    <div className="divide-y divide-slate-100">
                      {namedRecords.map((r) => {
                        const isSup = (r.workers?.role ?? "").toLowerCase() === "supervisor";
                        const canCorrect = !isSup || isPmOrAdmin;
                        return (
                          <div
                            key={r.id}
                            className="flex items-center justify-between gap-3 px-5 py-3.5"
                          >
                            <div>
                              <p className="text-sm font-semibold text-slate-900">
                                {r.workers?.name ?? "Unknown"}
                              </p>
                              <p className="text-xs text-slate-500">
                                {r.workers?.role ?? "Worker"} · {r.sites?.name ?? "Site"}
                              </p>
                            </div>
                            <div className="flex items-center gap-2">
                              <StatusBadge status={r.status} />
                              {canCorrect && (
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  title="Correct attendance"
                                  onClick={() => {
                                    setCorrectModalRecord(r);
                                    setCorrectStatus(r.status);
                                  }}
                                >
                                  <Pencil className="h-3.5 w-3.5" />
                                </Button>
                              )}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  )}
                </CardContent>
              </Card>
            </>
          )}
        </div>
      )}

      {/* ───────────────────────────────────────────────────────────────────── */}
      {/* TAB 4: MONTHLY CALENDAR                                               */}
      {/* ───────────────────────────────────────────────────────────────────── */}
      {tab === "monthly" && (
        <div className="space-y-5">
          <Card>
            <CardHeader>
              <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                {/* View Mode Toggle */}
                <div className="flex items-center gap-1.5 rounded-lg border border-slate-200 bg-slate-100 p-1">
                  <button
                    type="button"
                    onClick={() => setMonthlyViewMode("workforce")}
                    className={`rounded-md px-3 py-1.5 text-xs font-semibold transition-colors cursor-pointer ${
                      monthlyViewMode === "workforce"
                        ? "bg-white text-slate-900 shadow-xs"
                        : "text-slate-600 hover:text-slate-900"
                    }`}
                  >
                    Site Workforce (Headcount &amp; Man-Days)
                  </button>
                  <button
                    type="button"
                    onClick={() => setMonthlyViewMode("worker")}
                    className={`rounded-md px-3 py-1.5 text-xs font-semibold transition-colors cursor-pointer ${
                      monthlyViewMode === "worker"
                        ? "bg-white text-slate-900 shadow-xs"
                        : "text-slate-600 hover:text-slate-900"
                    }`}
                  >
                    Individual Staff Calendar
                  </button>
                </div>

                {/* Filter Selector */}
                <div className="flex flex-wrap items-center gap-3">
                  {monthlyViewMode === "workforce" ? (
                    <div className="w-64">
                      <Select
                        label="Construction Site"
                        value={activeSiteId}
                        onChange={(e) => setActiveSiteId(e.target.value)}
                      >
                        <option value="">All Permitted Sites</option>
                        {selectableSites.map((s) => (
                          <option key={s.id} value={s.id}>
                            {s.name}
                          </option>
                        ))}
                      </Select>
                    </div>
                  ) : (
                    <div className="w-64">
                      <Select
                        label="Select Worker"
                        value={monthlyWorkerId}
                        onChange={(e) => setMonthlyWorkerId(e.target.value)}
                      >
                        {allWorkers.map((w) => (
                          <option key={w.id} value={w.id}>
                            {w.name} ({w.role || "Worker"})
                          </option>
                        ))}
                      </Select>
                    </div>
                  )}

                  {/* Month Navigation */}
                  <div className="flex items-center gap-1.5 pt-4">
                    <Button
                      variant="outline"
                      size="icon"
                      onClick={() =>
                        setMonthCursor(
                          new Date(
                            monthCursor.getFullYear(),
                            monthCursor.getMonth() - 1,
                            1
                          )
                        )
                      }
                    >
                      <ChevronLeft className="h-4 w-4" />
                    </Button>
                    <span className="min-w-[130px] text-center text-sm font-semibold text-slate-900">
                      {new Intl.DateTimeFormat("en-IN", {
                        month: "long",
                        year: "numeric",
                      }).format(monthCursor)}
                    </span>
                    <Button
                      variant="outline"
                      size="icon"
                      onClick={() =>
                        setMonthCursor(
                          new Date(
                            monthCursor.getFullYear(),
                            monthCursor.getMonth() + 1,
                            1
                          )
                        )
                      }
                    >
                      <ChevronRight className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              </div>
            </CardHeader>

            <CardContent>
              {loadingMonthly ? (
                <LoadingTable rows={4} />
              ) : monthlyViewMode === "workforce" ? (
                /* Workforce Calendar View */
                <>
                  <div className="mb-3 grid grid-cols-7 gap-2 text-center text-xs font-bold uppercase tracking-wider text-slate-500">
                    {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((d) => (
                      <div key={d}>{d}</div>
                    ))}
                  </div>
                  <div className="grid grid-cols-7 gap-2">
                    {Array.from({ length: workforceCalendarMeta.firstWeekday }).map(
                      (_, i) => (
                        <div key={`empty-wf-${i}`} />
                      )
                    )}
                    {Array.from({ length: workforceCalendarMeta.daysInMonth }).map(
                      (_, idx) => {
                        const day = idx + 1;
                        const rec = workforceCalendarMeta.recordsByDay.get(day);
                        const isSelected =
                          selectedDayWorkforce?.attendance_date.endsWith(
                            `-${String(day).padStart(2, "0")}`
                          );

                        return (
                          <div
                            key={`wf-day-${day}`}
                            onClick={() => {
                              if (rec) setSelectedDayWorkforce(rec);
                            }}
                            className={`flex min-h-[4.5rem] flex-col justify-between rounded-xl border p-2 text-xs transition-all ${
                              rec
                                ? isSelected
                                  ? "border-blue-600 bg-blue-50/80 shadow-xs ring-2 ring-blue-500 cursor-pointer"
                                  : "border-blue-200 bg-white hover:border-blue-400 hover:bg-blue-50/30 cursor-pointer"
                                : "border-slate-100 bg-slate-50/50 text-slate-400"
                            }`}
                          >
                            <span className="font-bold text-slate-800">{day}</span>
                            {rec && (
                              <div className="space-y-1">
                                <div className="flex items-center justify-between rounded bg-slate-100 px-1.5 py-0.5 text-[10px] font-bold text-slate-700">
                                  <span>HC:</span>
                                  <span>{rec.total_workforce}</span>
                                </div>
                                <div className="flex items-center justify-between rounded bg-blue-100 px-1.5 py-0.5 text-[10px] font-black text-blue-900">
                                  <span>MD:</span>
                                  <span>
                                    {(
                                      rec.total_man_days ?? rec.total_workforce
                                    )
                                      .toFixed(1)
                                      .replace(/\.0$/, "")}
                                  </span>
                                </div>
                              </div>
                            )}
                          </div>
                        );
                      }
                    )}
                  </div>
                </>
              ) : (
                /* Individual Staff Calendar View */
                <>
                  <div className="mb-3 grid grid-cols-7 gap-2 text-center text-xs font-semibold text-slate-500">
                    {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((d) => (
                      <div key={d}>{d}</div>
                    ))}
                  </div>
                  <div className="grid grid-cols-7 gap-2">
                    {Array.from({ length: calendarMeta.firstWeekday }).map(
                      (_, i) => (
                        <div key={`empty-${i}`} />
                      )
                    )}
                    {Array.from({ length: calendarMeta.daysInMonth }).map(
                      (_, idx) => {
                        const day = idx + 1;
                        const st = calendarMeta.statusByDay.get(day);
                        const cellStyle =
                          st === "Present"
                            ? "border-emerald-200 bg-emerald-50 text-emerald-800"
                            : st === "Half Day"
                            ? "border-amber-200 bg-amber-50 text-amber-800"
                            : st === "Absent"
                            ? "border-red-200 bg-red-50 text-red-800"
                            : "border-slate-200 bg-white text-slate-700";

                        return (
                          <div
                            key={day}
                            className={`flex h-14 flex-col items-center justify-center rounded-lg border text-xs font-semibold ${cellStyle}`}
                          >
                            <span>{day}</span>
                            {st && (
                              <span className="mt-0.5 text-[10px] font-medium">
                                {st === "Half Day" ? "Half" : st}
                              </span>
                            )}
                          </div>
                        );
                      }
                    )}
                  </div>
                </>
              )}
            </CardContent>
          </Card>

          {/* Detailed Category Breakdown Card for Selected Date */}
          {monthlyViewMode === "workforce" && selectedDayWorkforce && (
            <Card>
              <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    <CardTitle>
                      Workforce Inspection —{" "}
                      {formatDisplayDate(selectedDayWorkforce.attendance_date)}
                    </CardTitle>
                    <Badge variant="navy">
                      {selectedDayWorkforce.sites?.name || "Assigned Site"}
                    </Badge>
                  </div>
                  <CardDescription className="mt-1">
                    {selectedDayWorkforce.total_workforce} Total Headcount ·{" "}
                    {(
                      selectedDayWorkforce.total_man_days ??
                      selectedDayWorkforce.total_workforce
                    )
                      .toFixed(1)
                      .replace(/\.0$/, "")}{" "}
                    Equivalent Man-Days
                    {selectedDayWorkforce.remarks &&
                      ` · Remarks: ${selectedDayWorkforce.remarks}`}
                  </CardDescription>
                </div>

                <Button
                  size="sm"
                  onClick={() => {
                    setSelectedDate(selectedDayWorkforce.attendance_date);
                    setActiveSiteId(selectedDayWorkforce.site_id);
                    setTab("workforce");
                  }}
                >
                  <Pencil className="h-3.5 w-3.5" />
                  Reopen &amp; Edit Submission
                </Button>
              </CardHeader>
              <CardContent>
                <div className="overflow-x-auto rounded-xl border border-slate-200">
                  <table className="w-full text-left text-xs">
                    <thead className="border-b border-slate-200 bg-slate-50 font-bold uppercase text-slate-500">
                      <tr>
                        <th className="px-4 py-2.5">Trade Category</th>
                        <th className="px-4 py-2.5 text-center">Full Day (1.0 MD)</th>
                        <th className="px-4 py-2.5 text-center">Half Day (0.5 MD)</th>
                        <th className="px-4 py-2.5 text-center">Headcount</th>
                        <th className="px-4 py-2.5 text-right">Equivalent Man-Days</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {(selectedDayWorkforce.category_counts ?? []).map((cat) => {
                        const fd =
                          typeof cat.full_day_count === "number"
                            ? cat.full_day_count
                            : Number(cat.count || 0);
                        const hd =
                          typeof cat.half_day_count === "number"
                            ? cat.half_day_count
                            : 0;
                        const hc = fd + hd;
                        const md = fd + hd * 0.5;

                        return (
                          <tr key={cat.id || cat.category} className="hover:bg-slate-50/50">
                            <td className="px-4 py-2.5 font-bold text-slate-900">
                              {cat.category}
                            </td>
                            <td className="px-4 py-2.5 text-center font-semibold text-slate-800">
                              {fd}
                            </td>
                            <td className="px-4 py-2.5 text-center font-semibold text-amber-700">
                              {hd}
                            </td>
                            <td className="px-4 py-2.5 text-center font-black text-slate-900">
                              {hc}
                            </td>
                            <td className="px-4 py-2.5 text-right font-mono font-black text-blue-900">
                              {md.toFixed(1).replace(/\.0$/, "")} MD
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      )}

      {/* ───────────────────────────────────────────────────────────────────── */}
      {/* TAB 5: ANALYTICS & TRENDS                                             */}
      {/* ───────────────────────────────────────────────────────────────────── */}
      {tab === "analytics" && (
        <div className="space-y-6">
          {/* Workforce 30-Day Metrics Bar */}
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            <Card>
              <CardContent className="p-4">
                <p className="text-[10px] font-bold uppercase tracking-wider text-slate-500">
                  Total Headcount (30 Days)
                </p>
                <p className="mt-1 text-2xl font-black text-slate-900">
                  {workforceAnalytics.totalHeadcount}{" "}
                  <span className="text-xs font-semibold text-slate-500">
                    Workers
                  </span>
                </p>
                <p className="mt-0.5 text-[11px] text-slate-400">
                  Gross deployed worker instances
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-4">
                <p className="text-[10px] font-bold uppercase tracking-wider text-blue-700">
                  Total Man-Days (Equivalent)
                </p>
                <p className="mt-1 text-2xl font-black text-blue-900">
                  {workforceAnalytics.totalManDays.toFixed(1).replace(/\.0$/, "")}{" "}
                  <span className="text-xs font-semibold text-blue-700">
                    MD
                  </span>
                </p>
                <p className="mt-0.5 text-[11px] text-blue-600">
                  Full + (Half × 0.5) equivalent labor
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-4">
                <p className="text-[10px] font-bold uppercase tracking-wider text-slate-500">
                  Full-Day Deployments
                </p>
                <p className="mt-1 text-2xl font-black text-emerald-700">
                  {workforceAnalytics.totalFullDay}
                </p>
                <p className="mt-0.5 text-[11px] text-slate-400">
                  1.0 Man-Day shifts recorded
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-4">
                <p className="text-[10px] font-bold uppercase tracking-wider text-amber-700">
                  Half-Day Deployments
                </p>
                <p className="mt-1 text-2xl font-black text-amber-600">
                  {workforceAnalytics.totalHalfDay}
                </p>
                <p className="mt-0.5 text-[11px] text-slate-400">
                  0.5 Man-Day shifts recorded
                </p>
              </CardContent>
            </Card>
          </div>

          {/* Daily Headcount vs Man-Days Trend */}
          <Card>
            <CardHeader className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <CardTitle>Daily Workforce Headcount vs. Equivalent Man-Days</CardTitle>
                <CardDescription>
                  Comparing actual physical workers against calculated labor units over 30 days
                </CardDescription>
              </div>
              <div className="flex items-center gap-3 text-xs">
                <div className="flex items-center gap-1.5 font-medium text-slate-700">
                  <span className="h-3 w-3 rounded-full bg-[#0B1628]" />
                  Headcount (Workers)
                </div>
                <div className="flex items-center gap-1.5 font-medium text-blue-700">
                  <span className="h-3 w-3 rounded-full bg-[#2563EB]" />
                  Equivalent Man-Days
                </div>
              </div>
            </CardHeader>
            <CardContent className="h-72">
              {loadingAnalytics ? (
                <LoadingTable rows={4} />
              ) : workforceAnalytics.trendByDate.length === 0 ? (
                <p className="pt-24 text-center text-xs text-slate-500">
                  No daily workforce submissions recorded in this period.
                </p>
              ) : (
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={workforceAnalytics.trendByDate}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                    <XAxis dataKey="label" stroke="#64748b" fontSize={11} />
                    <YAxis stroke="#64748b" fontSize={11} />
                    <Tooltip />
                    <Line
                      type="monotone"
                      dataKey="Headcount"
                      name="Headcount"
                      stroke="#0B1628"
                      strokeWidth={2.5}
                      dot={{ r: 3 }}
                    />
                    <Line
                      type="monotone"
                      dataKey="ManDays"
                      name="Equivalent Man-Days"
                      stroke="#2563EB"
                      strokeWidth={2}
                      strokeDasharray="4 4"
                      dot={{ r: 3 }}
                    />
                  </LineChart>
                </ResponsiveContainer>
              )}
            </CardContent>
          </Card>

          {/* Category-Wise Breakdown Table */}
          <Card>
            <CardHeader>
              <CardTitle>Trade Category Breakdown (30-Day Aggregates)</CardTitle>
              <CardDescription>
                Detailed labor volume split by trade category, full-day shifts, and half-day shifts
              </CardDescription>
            </CardHeader>
            <CardContent className="p-0">
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs">
                  <thead className="border-b border-slate-200 bg-slate-50 font-bold uppercase text-slate-500">
                    <tr>
                      <th className="px-5 py-3">Trade Category</th>
                      <th className="px-5 py-3 text-center">Full Day (1.0 MD)</th>
                      <th className="px-5 py-3 text-center">Half Day (0.5 MD)</th>
                      <th className="px-5 py-3 text-center">Gross Headcount</th>
                      <th className="px-5 py-3 text-right">Total Man-Days</th>
                      <th className="px-5 py-3 text-right">% of Man-Days</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {workforceAnalytics.categoriesArray.map((row) => {
                      const share =
                        workforceAnalytics.totalManDays > 0
                          ? ((row.manDays / workforceAnalytics.totalManDays) * 100).toFixed(1)
                          : "0.0";

                      return (
                        <tr key={row.category} className="hover:bg-slate-50/50">
                          <td className="px-5 py-3 font-bold text-slate-900">
                            {row.category}
                          </td>
                          <td className="px-5 py-3 text-center font-medium text-slate-700">
                            {row.fullDay}
                          </td>
                          <td className="px-5 py-3 text-center font-medium text-amber-700">
                            {row.halfDay}
                          </td>
                          <td className="px-5 py-3 text-center font-extrabold text-slate-900">
                            {row.headcount}
                          </td>
                          <td className="px-5 py-3 text-right font-mono font-black text-blue-900">
                            {row.manDays.toFixed(1).replace(/\.0$/, "")} MD
                          </td>
                          <td className="px-5 py-3 text-right font-semibold text-slate-500">
                            {share}%
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>

          {/* Named Staff Analytics Cards */}
          <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle>Staff Attendance Distribution (Last 30 Days)</CardTitle>
                <CardDescription>
                  {analyticsRecords.length} recorded staff attendance events
                </CardDescription>
              </CardHeader>
              <CardContent className="h-64">
                {loadingAnalytics ? (
                  <LoadingTable rows={4} />
                ) : analyticsData.pie.length === 0 ? (
                  <p className="pt-20 text-center text-xs text-slate-500">
                    No staff attendance records for the selected period.
                  </p>
                ) : (
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie
                        data={analyticsData.pie}
                        dataKey="value"
                        nameKey="name"
                        cx="50%"
                        cy="50%"
                        outerRadius={80}
                        label={({ name, percent }: { name?: string; percent?: number }) =>
                          `${name ?? ""} ${(Number(percent || 0) * 100).toFixed(0)}%`
                        }
                      >
                        {analyticsData.pie.map((entry) => (
                          <Cell key={entry.name} fill={entry.color} />
                        ))}
                      </Pie>
                      <Tooltip />
                    </PieChart>
                  </ResponsiveContainer>
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Weekly Staff Attendance Trend</CardTitle>
                <CardDescription>Four-week rolling staff attendance volume</CardDescription>
              </CardHeader>
              <CardContent className="h-64">
                {loadingAnalytics ? (
                  <LoadingTable rows={4} />
                ) : (
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={analyticsData.weeks}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                      <XAxis dataKey="label" stroke="#64748b" fontSize={12} />
                      <YAxis stroke="#64748b" fontSize={12} />
                      <Tooltip />
                      <Line
                        type="monotone"
                        dataKey="Present"
                        stroke="#2563EB"
                        strokeWidth={2.5}
                        dot={{ r: 4 }}
                      />
                    </LineChart>
                  </ResponsiveContainer>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      )}

      {/* ───────────────────────────────────────────────────────────────────── */}
      {/* TAB 6: WORKFORCE REPORTS (DAY-WISE & WEEK-WISE REPORTING)             */}
      {/* ───────────────────────────────────────────────────────────────────── */}
      {tab === "reports" && <WorkforceReports />}

      {/* Attendance Correction Modal */}
      {correctModalRecord && (
        <Modal
          open={true}
          onClose={() => setCorrectModalRecord(null)}
          title={`Correct Attendance — ${correctModalRecord.workers?.name ?? "Worker"}`}
          description={`Logged for ${formatDisplayDate(correctModalRecord.attendance_date)}`}
        >
          <form onSubmit={handleCorrectSubmit} className="space-y-4">
            <Select
              label="Select Verified Status"
              value={correctStatus}
              onChange={(e) => setCorrectStatus(e.target.value as AttendanceStatus)}
            >
              <option value="Present">Present</option>
              <option value="Half Day">Half Day</option>
              <option value="Absent">Absent</option>
            </Select>
            <div className="flex justify-end gap-2 pt-2">
              <Button
                variant="outline"
                type="button"
                onClick={() => setCorrectModalRecord(null)}
              >
                Cancel
              </Button>
              <Button type="submit">Confirm Correction</Button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
