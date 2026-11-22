"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  Camera,
  Image as ImageIcon,
  Building2,
  Calendar,
  Filter,
  Plus,
  RefreshCw,
  Search,
  MessageSquare,
  Send,
  Trash2,
  Eye,
  CheckCircle2,
  AlertTriangle,
  Clock,
  User,
  Sparkles,
  ChevronRight,
  ShieldCheck,
  FileCode2,
  Copy,
  Check,
} from "lucide-react";
import { useAuth } from "@/context/auth-context";
import { fetchSites } from "@/lib/data/sites";
import {
  fetchSiteProgressUpdates,
  createSiteProgressUpdate,
  addProgressFeedback,
  deleteSiteProgressUpdate,
  type PreparedUploadPhoto,
} from "@/lib/data/site-progress";
import {
  PROGRESS_WORK_CATEGORIES,
  type ProgressWorkCategory,
  type SiteProgressPhotoRecord,
  type SiteProgressUpdateRecord,
  type SiteRecord,
} from "@/types/database";
import {
  formatDisplayDate,
  formatDisplayDateTime,
  getErrorMessage,
  todayIsoDate,
} from "@/lib/utils";
import { useToast } from "@/components/ui/toast";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { StatCard } from "@/components/ui/stat-card";
import {
  EmptyState,
  ErrorBanner,
  LoadingCards,
  PageHeader,
} from "@/components/ui/states";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { MultiPhotoCapture } from "@/components/multi-photo-capture";
import { PhotoLightbox } from "@/components/photo-lightbox";

// Category badge color mapping for visually appealing tags
const CATEGORY_COLORS: Record<string, string> = {
  Excavation: "bg-amber-100 text-amber-800 border-amber-200",
  Foundation: "bg-orange-100 text-orange-800 border-orange-200",
  Reinforcement: "bg-slate-100 text-slate-800 border-slate-300",
  Concrete: "bg-zinc-100 text-zinc-800 border-zinc-300",
  Masonry: "bg-red-100 text-red-800 border-red-200",
  Plastering: "bg-emerald-100 text-emerald-800 border-emerald-200",
  Electrical: "bg-yellow-100 text-yellow-800 border-yellow-200",
  Plumbing: "bg-cyan-100 text-cyan-800 border-cyan-200",
  Painting: "bg-purple-100 text-purple-800 border-purple-200",
  Flooring: "bg-indigo-100 text-indigo-800 border-indigo-200",
  Roofing: "bg-rose-100 text-rose-800 border-rose-200",
  Finishing: "bg-teal-100 text-teal-800 border-teal-200",
  Other: "bg-gray-100 text-gray-800 border-gray-200",
};

export default function SiteProgressPage() {
  const { user, profile, isAdmin, isPmOrAdmin, isSupervisor, selectedSiteId } =
    useAuth();
  const toast = useToast();

  const [activeTab, setActiveTab] = useState<"gallery" | "upload">("gallery");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [tableReady, setTableReady] = useState(true);

  const [sites, setSites] = useState<SiteRecord[]>([]);
  const [updates, setUpdates] = useState<SiteProgressUpdateRecord[]>([]);

  // Filter states for Gallery
  const [filterSiteId, setFilterSiteId] = useState<string>(selectedSiteId || "");
  const [filterCategory, setFilterCategory] = useState<string>("");
  const [startDate, setStartDate] = useState<string>("");
  const [endDate, setEndDate] = useState<string>("");
  const [onlyMyUploads, setOnlyMyUploads] = useState<boolean>(false);
  const [needsFeedbackOnly, setNeedsFeedbackOnly] = useState<boolean>(false);

  function applyDatePreset(preset: "all" | "today" | "yesterday" | "week") {
    const today = todayIsoDate();
    if (preset === "all") {
      setStartDate("");
      setEndDate("");
    } else if (preset === "today") {
      setStartDate(today);
      setEndDate(today);
    } else if (preset === "yesterday") {
      const y = new Date();
      y.setDate(y.getDate() - 1);
      const yStr = y.toISOString().slice(0, 10);
      setStartDate(yStr);
      setEndDate(yStr);
    } else if (preset === "week") {
      const w = new Date();
      w.setDate(w.getDate() - 6);
      setStartDate(w.toISOString().slice(0, 10));
      setEndDate(today);
    }
  }

  // Upload Form State
  const [uploadSiteId, setUploadSiteId] = useState<string>(selectedSiteId || "");
  const [uploadDate, setUploadDate] = useState<string>(todayIsoDate());
  const [uploadCategory, setUploadCategory] =
    useState<ProgressWorkCategory>("Masonry");
  const [uploadDescription, setUploadDescription] = useState<string>("");
  const [uploadRemarks, setUploadRemarks] = useState<string>("");
  const [uploadedPhotos, setUploadedPhotos] = useState<PreparedUploadPhoto[]>([]);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [uploadProgressPercent, setUploadProgressPercent] = useState<number>(0);
  const [uploadStatusText, setUploadStatusText] = useState<string>("");

  // Feedback State (for PM / Admin)
  const [activeFeedbackUpdateId, setActiveFeedbackUpdateId] = useState<
    string | null
  >(null);
  const [feedbackDraft, setFeedbackDraft] = useState<string>("");
  const [isSubmittingFeedback, setIsSubmittingFeedback] = useState(false);

  // Lightbox State
  const [lightboxOpen, setLightboxOpen] = useState(false);
  const [lightboxUpdate, setLightboxUpdate] =
    useState<SiteProgressUpdateRecord | null>(null);
  const [lightboxPhotoIdx, setLightboxPhotoIdx] = useState(0);

  // Deletion State (PM / Admin only)
  const [deleteTarget, setDeleteTarget] =
    useState<SiteProgressUpdateRecord | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  // Keep site filter in sync with global switcher if user selected one
  useEffect(() => {
    if (selectedSiteId) {
      setFilterSiteId(selectedSiteId);
      if (!uploadSiteId) setUploadSiteId(selectedSiteId);
    }
  }, [selectedSiteId, uploadSiteId]);

  const loadData = useCallback(async () => {
    setError(null);
    try {
      const [sitesData, progressResult] = await Promise.all([
        fetchSites(),
        fetchSiteProgressUpdates({
          siteId: filterSiteId || undefined,
          category: filterCategory || undefined,
          startDate: startDate || undefined,
          endDate: endDate || undefined,
        }),
      ]);

      setSites(sitesData);
      setTableReady(progressResult.tableReady);

      if (!progressResult.tableReady) {
        setUpdates([]);
      } else {
        setUpdates(progressResult.records);
      }

      if (!uploadSiteId && sitesData.length > 0) {
        setUploadSiteId(sitesData[0].id);
      }
    } catch (err) {
      console.error("[SiteProgress] Load error:", err);
      setError(getErrorMessage(err));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [filterSiteId, filterCategory, startDate, endDate, uploadSiteId]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  async function handleRefresh() {
    setRefreshing(true);
    await loadData();
  }

  // Upload handler
  async function handleCreateProgress(e: React.FormEvent) {
    e.preventDefault();
    if (!uploadSiteId) {
      toast.error("Please select a site");
      return;
    }
    if (!uploadDescription.trim()) {
      toast.error("Please enter a description of the work completed");
      return;
    }

    const selectedSite = sites.find((s) => s.id === uploadSiteId);
    const siteName = selectedSite ? selectedSite.name : "Site";

    setIsSubmitting(true);
    setUploadProgressPercent(5);
    setUploadStatusText("Starting upload...");

    try {
      const res = await createSiteProgressUpdate(
        {
          site_id: uploadSiteId,
          work_date: uploadDate,
          category: uploadCategory,
          description: uploadDescription,
          remarks: uploadRemarks,
        },
        uploadedPhotos,
        siteName,
        (pct, text) => {
          setUploadProgressPercent(pct);
          setUploadStatusText(text);
        }
      );

      if (!res.success) {
        toast.error(res.error || "Failed to save progress update");
        return;
      }

      toast.success(
        `Site progress saved with ${uploadedPhotos.length} photo(s)!`
      );

      // Reset form
      setUploadDescription("");
      setUploadRemarks("");
      setUploadedPhotos([]);
      setActiveTab("gallery");
      await loadData();
    } catch (err) {
      console.error("[SiteProgress] Submission error:", err);
      toast.error(getErrorMessage(err));
    } finally {
      setIsSubmitting(false);
      setUploadProgressPercent(0);
      setUploadStatusText("");
    }
  }

  // PM / Admin feedback handler
  async function handleSubmitFeedback(updateId: string) {
    if (!feedbackDraft.trim()) {
      toast.error("Feedback comment cannot be empty");
      return;
    }

    setIsSubmittingFeedback(true);
    try {
      const target = updates.find((u) => u.id === updateId);
      const res = await addProgressFeedback(
        updateId,
        feedbackDraft,
        target?.sites?.name || "Site"
      );

      if (!res.success) {
        toast.error(res.error || "Failed to post feedback");
        return;
      }

      toast.success("Feedback posted successfully");
      setActiveFeedbackUpdateId(null);
      setFeedbackDraft("");
      await loadData();
    } catch (err) {
      toast.error(getErrorMessage(err));
    } finally {
      setIsSubmittingFeedback(false);
    }
  }

  // Delete handler (PM / Admin only)
  async function handleConfirmDelete() {
    if (!deleteTarget) return;
    setIsDeleting(true);
    try {
      const res = await deleteSiteProgressUpdate(
        deleteTarget.id,
        deleteTarget.photos || [],
        deleteTarget.sites?.name || "Site"
      );

      if (!res.success) {
        toast.error(res.error || "Failed to delete progress update");
        return;
      }

      toast.success("Progress update and photos deleted");
      setDeleteTarget(null);
      await loadData();
    } catch (err) {
      toast.error(getErrorMessage(err));
    } finally {
      setIsDeleting(false);
    }
  }

  // Open Lightbox
  function handleOpenLightbox(
    update: SiteProgressUpdateRecord,
    photoIndex: number
  ) {
    setLightboxUpdate(update);
    setLightboxPhotoIdx(photoIndex);
    setLightboxOpen(true);
  }

  // Computed stats
  const totalPhotosCount = useMemo(() => {
    return updates.reduce((sum, u) => sum + (u.photos?.length || 0), 0);
  }, [updates]);

  const uniqueSitesCount = useMemo(() => {
    return new Set(updates.map((u) => u.site_id)).size;
  }, [updates]);

  const categoryCountMap = useMemo(() => {
    const map: Record<string, number> = {};
    for (const u of updates) {
      map[u.category] = (map[u.category] || 0) + 1;
    }
    return map;
  }, [updates]);

  const pendingFeedbackCount = useMemo(() => {
    return updates.filter((u) => !u.feedback || u.feedback.trim() === "").length;
  }, [updates]);

  const displayedUpdates = useMemo(() => {
    let list = updates;
    if (onlyMyUploads && user?.id) {
      list = list.filter((u) => u.created_by === user.id);
    }
    if (needsFeedbackOnly) {
      list = list.filter((u) => !u.feedback || u.feedback.trim() === "");
    }
    return list;
  }, [updates, onlyMyUploads, user?.id, needsFeedbackOnly]);

  return (
    <div className="space-y-6 pb-16">
      {/* Page Header */}
      <PageHeader
        title="Daily Site Progress & Photo Gallery"
        description="Field progress monitoring with high-resolution photo uploads and management feedback"
        actions={
          <div className="flex items-center gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={handleRefresh}
              disabled={refreshing || loading}
              className="gap-2 cursor-pointer"
            >
              <RefreshCw
                className={`h-4 w-4 ${refreshing ? "animate-spin" : ""}`}
              />
              <span className="hidden sm:inline">Refresh</span>
            </Button>

            <Button
              type="button"
              size="sm"
              onClick={() =>
                setActiveTab(activeTab === "gallery" ? "upload" : "gallery")
              }
              className="gap-2 bg-[#2563EB] hover:bg-[#1D4ED8] text-white cursor-pointer"
            >
              {activeTab === "gallery" ? (
                <>
                  <Camera className="h-4 w-4" />
                  <span>Upload Progress</span>
                </>
              ) : (
                <>
                  <ImageIcon className="h-4 w-4" />
                  <span>View Gallery</span>
                </>
              )}
            </Button>
          </div>
        }
      />

      {/* Migration Notice Banner if DB table is pending */}
      {!tableReady && (
        <Card className="border-amber-300 bg-amber-50/70 shadow-xs">
          <CardContent className="p-4 sm:p-5">
            <div className="flex items-start gap-3">
              <div className="rounded-lg bg-amber-100 p-2 text-amber-800">
                <AlertTriangle className="h-5 w-5" />
              </div>
              <div className="flex-1 space-y-1">
                <h3 className="text-sm font-semibold text-amber-900">
                  Database & Storage Setup Proposal Ready
                </h3>
                <p className="text-xs text-amber-800 leading-relaxed">
                  The additive tables{" "}
                  <code className="font-mono font-semibold bg-amber-100/80 px-1 py-0.5 rounded">
                    public.site_progress_updates
                  </code>
                  ,{" "}
                  <code className="font-mono font-semibold bg-amber-100/80 px-1 py-0.5 rounded">
                    public.site_progress_photos
                  </code>
                  , and the private Supabase Storage bucket{" "}
                  <code className="font-mono font-semibold bg-amber-100/80 px-1 py-0.5 rounded">
                    site-progress-photos
                  </code>{" "}
                  have not yet been executed in your Supabase project.
                </p>
                <div className="pt-2 flex flex-wrap items-center gap-2">
                  <span className="text-[11px] text-amber-700">
                    File:{" "}
                    <code className="font-mono bg-white px-1.5 py-0.5 rounded border border-amber-200">
                      supabase/migrations/20261120_site_progress_photos_PROPOSAL.sql
                    </code>
                  </span>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Primary Tab Navigation */}
      <div className="flex border-b border-slate-200">
        <button
          type="button"
          onClick={() => setActiveTab("gallery")}
          className={`flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-medium transition-colors cursor-pointer ${
            activeTab === "gallery"
              ? "border-[#2563EB] text-[#2563EB]"
              : "border-transparent text-slate-500 hover:text-slate-800"
          }`}
        >
          <ImageIcon className="h-4 w-4" />
          <span>Photo Gallery & Updates</span>
          {updates.length > 0 && (
            <span className="rounded-full bg-blue-100 px-2 py-0.5 text-[11px] font-semibold text-blue-700">
              {updates.length}
            </span>
          )}
        </button>

        <button
          type="button"
          onClick={() => setActiveTab("upload")}
          className={`flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-medium transition-colors cursor-pointer ${
            activeTab === "upload"
              ? "border-[#2563EB] text-[#2563EB]"
              : "border-transparent text-slate-500 hover:text-slate-800"
          }`}
        >
          <Camera className="h-4 w-4" />
          <span>New Progress Upload</span>
        </button>
      </div>

      {/* ────────────────────────────────────────────────────────────────────── */}
      {/* TAB 1: PHOTO GALLERY & FEED                                            */}
      {/* ────────────────────────────────────────────────────────────────────── */}
      {activeTab === "gallery" && (
        <div className="space-y-6">
          {/* Stats Bar */}
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <StatCard
              label="Progress Updates"
              value={updates.length}
              icon={Building2}
              subtitle="Logged updates"
              tone="blue"
            />
            <StatCard
              label="Total Site Photos"
              value={totalPhotosCount}
              icon={Camera}
              subtitle="Compressed & stored"
              tone="emerald"
            />
            <StatCard
              label="Active Sites"
              value={uniqueSitesCount}
              icon={CheckCircle2}
              subtitle="Sites with entries"
              tone="slate"
            />
          </div>

          {/* Quick Category Chips Strip */}
          <div className="flex items-center gap-1.5 overflow-x-auto pb-1 pt-0.5 no-scrollbar">
            <button
              type="button"
              onClick={() => setFilterCategory("")}
              className={`shrink-0 rounded-full px-3 py-1 text-xs font-semibold transition-all cursor-pointer ${
                filterCategory === ""
                  ? "bg-[#2563EB] text-white shadow-xs"
                  : "bg-white text-slate-600 border border-slate-200 hover:border-slate-300"
              }`}
            >
              All Trades ({updates.length})
            </button>
            {PROGRESS_WORK_CATEGORIES.map((cat) => {
              const count = categoryCountMap[cat] || 0;
              const isSelected = filterCategory === cat;
              return (
                <button
                  key={cat}
                  type="button"
                  onClick={() => setFilterCategory(isSelected ? "" : cat)}
                  className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium transition-all cursor-pointer flex items-center gap-1.5 ${
                    isSelected
                      ? "bg-[#2563EB] text-white shadow-xs"
                      : "bg-white text-slate-700 border border-slate-200 hover:border-slate-300"
                  }`}
                >
                  <span>{cat}</span>
                  {count > 0 && (
                    <span
                      className={`rounded-full px-1.5 py-0.2 text-[10px] font-bold ${
                        isSelected
                          ? "bg-white/20 text-white"
                          : "bg-slate-100 text-slate-600"
                      }`}
                    >
                      {count}
                    </span>
                  )}
                </button>
              );
            })}
          </div>

          {/* Filters Bar */}
          <Card className="border-slate-200 shadow-2xs">
            <CardContent className="p-3 sm:p-4 space-y-3">
              {/* Date Presets and Toggles */}
              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 pb-3">
                <div className="flex flex-wrap items-center gap-1.5 text-xs">
                  <span className="font-semibold text-slate-500 mr-1">Date:</span>
                  <button
                    type="button"
                    onClick={() => applyDatePreset("all")}
                    className={`rounded-md px-2.5 py-1 text-xs font-medium transition-colors cursor-pointer ${
                      startDate === "" && endDate === ""
                        ? "bg-blue-100 text-[#2563EB] font-semibold"
                        : "text-slate-600 hover:bg-slate-100"
                    }`}
                  >
                    All Time
                  </button>
                  <button
                    type="button"
                    onClick={() => applyDatePreset("today")}
                    className={`rounded-md px-2.5 py-1 text-xs font-medium transition-colors cursor-pointer ${
                      startDate === todayIsoDate() && endDate === todayIsoDate()
                        ? "bg-blue-100 text-[#2563EB] font-semibold"
                        : "text-slate-600 hover:bg-slate-100"
                    }`}
                  >
                    Today
                  </button>
                  <button
                    type="button"
                    onClick={() => applyDatePreset("yesterday")}
                    className="rounded-md px-2.5 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 transition-colors cursor-pointer"
                  >
                    Yesterday
                  </button>
                  <button
                    type="button"
                    onClick={() => applyDatePreset("week")}
                    className="rounded-md px-2.5 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 transition-colors cursor-pointer"
                  >
                    Last 7 Days
                  </button>
                </div>

                <div className="flex flex-wrap items-center gap-2">
                  {/* Supervisor/Author Filter */}
                  <button
                    type="button"
                    onClick={() => setOnlyMyUploads(!onlyMyUploads)}
                    className={`rounded-lg px-2.5 py-1 text-xs font-medium border transition-colors cursor-pointer ${
                      onlyMyUploads
                        ? "bg-emerald-50 border-emerald-300 text-emerald-700 font-semibold"
                        : "border-slate-200 text-slate-600 hover:bg-slate-50"
                    }`}
                  >
                    My Uploads Only
                  </button>

                  {/* PM/Admin Needs Review Filter */}
                  {isPmOrAdmin && (
                    <button
                      type="button"
                      onClick={() => setNeedsFeedbackOnly(!needsFeedbackOnly)}
                      className={`rounded-lg px-2.5 py-1 text-xs font-medium border transition-colors cursor-pointer flex items-center gap-1.5 ${
                        needsFeedbackOnly
                          ? "bg-amber-50 border-amber-300 text-amber-800 font-semibold"
                          : "border-slate-200 text-slate-600 hover:bg-slate-50"
                      }`}
                    >
                      <span>Needs Review</span>
                      {pendingFeedbackCount > 0 && (
                        <span className="rounded-full bg-amber-200 px-1.5 py-0.2 text-[10px] font-bold text-amber-900">
                          {pendingFeedbackCount}
                        </span>
                      )}
                    </button>
                  )}
                </div>
              </div>

              {/* Explicit Dropdowns & Date Inputs */}
              <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-3 pt-1">
                {/* Site Filter */}
                <div>
                  <label className="block text-xs font-medium text-slate-600 mb-1">
                    Site
                  </label>
                  <select
                    value={filterSiteId}
                    onChange={(e) => setFilterSiteId(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-xs text-slate-800 focus:border-[#2563EB] focus:outline-hidden"
                  >
                    <option value="">All Sites</option>
                    {sites.map((site) => (
                      <option key={site.id} value={site.id}>
                        {site.name}
                      </option>
                    ))}
                  </select>
                </div>

                {/* Category Filter */}
                <div>
                  <label className="block text-xs font-medium text-slate-600 mb-1">
                    Work Category
                  </label>
                  <select
                    value={filterCategory}
                    onChange={(e) => setFilterCategory(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-xs text-slate-800 focus:border-[#2563EB] focus:outline-hidden"
                  >
                    <option value="">All Categories</option>
                    {PROGRESS_WORK_CATEGORIES.map((cat) => (
                      <option key={cat} value={cat}>
                        {cat}
                      </option>
                    ))}
                  </select>
                </div>

                {/* Start Date */}
                <div>
                  <label className="block text-xs font-medium text-slate-600 mb-1">
                    From Date
                  </label>
                  <input
                    type="date"
                    value={startDate}
                    onChange={(e) => setStartDate(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-1.5 text-xs text-slate-800 focus:border-[#2563EB] focus:outline-hidden"
                  />
                </div>

                {/* End Date */}
                <div>
                  <label className="block text-xs font-medium text-slate-600 mb-1">
                    To Date
                  </label>
                  <input
                    type="date"
                    value={endDate}
                    onChange={(e) => setEndDate(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-1.5 text-xs text-slate-800 focus:border-[#2563EB] focus:outline-hidden"
                  />
                </div>
              </div>

              {(filterSiteId ||
                filterCategory ||
                startDate ||
                endDate ||
                onlyMyUploads ||
                needsFeedbackOnly) && (
                <div className="flex items-center justify-between pt-1">
                  <span className="text-xs text-slate-500">
                    Showing {displayedUpdates.length} of {updates.length} updates
                  </span>
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => {
                      setFilterSiteId("");
                      setFilterCategory("");
                      setStartDate("");
                      setEndDate("");
                      setOnlyMyUploads(false);
                      setNeedsFeedbackOnly(false);
                    }}
                    className="text-xs text-slate-500 hover:text-slate-800 cursor-pointer"
                  >
                    Clear Filters
                  </Button>
                </div>
              )}
            </CardContent>
          </Card>

          {/* Gallery Feed */}
          {loading ? (
            <LoadingCards count={3} />
          ) : error ? (
            <ErrorBanner message={error} onRetry={loadData} />
          ) : displayedUpdates.length === 0 ? (
            <EmptyState
              icon={Camera}
              title="No Site Progress Updates Found"
              description={
                updates.length > 0
                  ? "No progress updates match the currently active filters. Try adjusting or clearing filters."
                  : tableReady
                  ? "No progress photos or descriptions have been submitted yet."
                  : "Database tables have not been created yet. Review the SQL proposal to initialize."
              }
              action={
                updates.length > 0 ? (
                  <Button
                    variant="outline"
                    onClick={() => {
                      setFilterSiteId("");
                      setFilterCategory("");
                      setStartDate("");
                      setEndDate("");
                      setOnlyMyUploads(false);
                      setNeedsFeedbackOnly(false);
                    }}
                  >
                    Reset Filters
                  </Button>
                ) : (
                  <Button
                    onClick={() => setActiveTab("upload")}
                    className="bg-[#2563EB] hover:bg-[#1D4ED8] text-white"
                  >
                    <Plus className="h-4 w-4 mr-1.5" />
                    Post Today&apos;s Progress
                  </Button>
                )
              }
            />
          ) : (
            <div className="space-y-4">
              {displayedUpdates.map((update) => {
                const photos = update.photos || [];
                const catColor =
                  CATEGORY_COLORS[update.category] || CATEGORY_COLORS.Other;

                return (
                  <Card
                    key={update.id}
                    className="border-slate-200 shadow-2xs hover:border-slate-300 transition-all overflow-hidden"
                  >
                    {/* Header: Site, Date, Category */}
                    <div className="border-b border-slate-100 bg-slate-50/70 p-3 sm:p-4">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <div className="flex items-center gap-2 min-w-0">
                          <span
                            className={`rounded-full border px-2.5 py-0.5 text-xs font-semibold ${catColor}`}
                          >
                            {update.category}
                          </span>
                          <h4 className="font-semibold text-slate-900 truncate text-sm">
                            {update.sites?.name || "Site"}
                          </h4>
                        </div>

                        <div className="flex items-center gap-3 text-xs text-slate-500">
                          <span className="flex items-center gap-1">
                            <Calendar className="h-3.5 w-3.5 text-blue-500" />
                            {formatDisplayDate(update.work_date)}
                          </span>

                          {/* PM/Admin Delete Action */}
                          {isPmOrAdmin && (
                            <button
                              type="button"
                              onClick={() => setDeleteTarget(update)}
                              aria-label="Delete progress update"
                              className="rounded p-1 text-slate-400 hover:bg-rose-50 hover:text-rose-600 transition-colors cursor-pointer"
                              title="Delete update"
                            >
                              <Trash2 className="h-3.5 w-3.5" />
                            </button>
                          )}
                        </div>
                      </div>

                      {/* Sub-meta: Author & Time */}
                      <div className="mt-1.5 flex flex-wrap items-center gap-3 text-[11px] text-slate-400">
                        <span className="flex items-center gap-1">
                          <User className="h-3 w-3" />
                          Logged by:{" "}
                          <span className="text-slate-600 font-medium">
                            {update.creator_profile?.name || "Field Supervisor"}
                          </span>
                        </span>
                        <span className="flex items-center gap-1">
                          <Clock className="h-3 w-3" />
                          {new Date(update.created_at).toLocaleTimeString([], {
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </span>
                      </div>
                    </div>

                    <CardContent className="p-3 sm:p-5 space-y-4">
                      {/* Description */}
                      <div className="text-sm text-slate-700 whitespace-pre-line leading-relaxed">
                        {update.description}
                      </div>

                      {/* Optional Remarks */}
                      {update.remarks && (
                        <div className="rounded-lg bg-slate-50 border border-slate-100 p-2.5 text-xs text-slate-600">
                          <span className="font-medium text-slate-700">
                            Notes / Remarks:{" "}
                          </span>
                          {update.remarks}
                        </div>
                      )}

                      {/* Photo Gallery Grid */}
                      {photos.length > 0 && (
                        <div className="space-y-1.5">
                          <div className="flex items-center justify-between text-xs text-slate-500 font-medium">
                            <span>
                              Site Photos ({photos.length}) — Click to enlarge
                            </span>
                          </div>

                          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2.5">
                            {photos.map((photo, pIdx) => (
                              <div
                                key={photo.id || pIdx}
                                onClick={() =>
                                  handleOpenLightbox(update, pIdx)
                                }
                                className="group relative aspect-4/3 overflow-hidden rounded-xl bg-slate-100 border border-slate-200 cursor-pointer shadow-2xs hover:shadow-md transition-all"
                              >
                                {photo.signed_url ? (
                                  // eslint-disable-next-line @next/next/no-img-element
                                  <img
                                    src={photo.signed_url}
                                    alt={
                                      photo.caption ||
                                      `${update.category} photo ${pIdx + 1}`
                                    }
                                    className="h-full w-full object-cover group-hover:scale-105 transition-transform duration-200"
                                  />
                                ) : (
                                  <div className="flex h-full w-full items-center justify-center bg-slate-100 text-slate-400">
                                    <ImageIcon className="h-6 w-6" />
                                  </div>
                                )}

                                {/* Hover overlay */}
                                <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center text-white gap-1.5 text-xs font-medium">
                                  <Eye className="h-4 w-4" />
                                  <span>View</span>
                                </div>

                                {/* Caption pill if available */}
                                {photo.caption && (
                                  <div className="absolute bottom-1 inset-x-1 truncate rounded bg-black/70 px-1.5 py-0.5 text-[10px] text-white">
                                    {photo.caption}
                                  </div>
                                )}
                              </div>
                            ))}
                          </div>
                        </div>
                      )}

                      {/* Management Feedback Section */}
                      <div className="pt-2 border-t border-slate-100">
                        {update.feedback ? (
                          <div className="rounded-xl border border-blue-200 bg-blue-50/60 p-3 sm:p-4 text-xs space-y-1.5">
                            <div className="flex items-center justify-between">
                              <span className="font-semibold text-blue-900 flex items-center gap-1.5">
                                <MessageSquare className="h-3.5 w-3.5 text-blue-600" />
                                PM / Admin Review Feedback:
                              </span>
                              {update.feedback_at && (
                                <span className="text-[10px] text-blue-700">
                                  {formatDisplayDateTime(update.feedback_at)}
                                </span>
                              )}
                            </div>
                            <p className="text-slate-800 leading-relaxed font-normal">
                              {update.feedback}
                            </p>
                            {update.reviewer_profile && (
                              <div className="text-[10px] text-blue-600 font-medium">
                                Reviewed by: {update.reviewer_profile.name} (
                                {update.reviewer_profile.role})
                              </div>
                            )}

                            {/* Option for PM/Admin to update feedback */}
                            {isPmOrAdmin && (
                              <div className="pt-1">
                                <button
                                  type="button"
                                  onClick={() => {
                                    setActiveFeedbackUpdateId(update.id);
                                    setFeedbackDraft(update.feedback || "");
                                  }}
                                  className="text-[11px] font-semibold text-blue-700 hover:underline cursor-pointer"
                                >
                                  Edit feedback
                                </button>
                              </div>
                            )}
                          </div>
                        ) : (
                          <div>
                            {isPmOrAdmin ? (
                              activeFeedbackUpdateId === update.id ? (
                                <div className="space-y-2 rounded-xl border border-slate-200 p-3 bg-slate-50">
                                  <label className="block text-xs font-semibold text-slate-700">
                                    Leave Management Feedback:
                                  </label>
                                  <textarea
                                    rows={2}
                                    value={feedbackDraft}
                                    onChange={(e) =>
                                      setFeedbackDraft(e.target.value)}
                                    placeholder="Add feedback, instructions, or observations for the field supervisor..."
                                    className="w-full rounded-lg border border-slate-300 p-2 text-xs text-slate-800 focus:border-[#2563EB] focus:outline-hidden"
                                  />
                                  <div className="flex justify-end gap-2">
                                    <Button
                                      type="button"
                                      variant="ghost"
                                      size="sm"
                                      onClick={() => {
                                        setActiveFeedbackUpdateId(null);
                                        setFeedbackDraft("");
                                      }}
                                      className="text-xs"
                                    >
                                      Cancel
                                    </Button>
                                    <Button
                                      type="button"
                                      size="sm"
                                      onClick={() =>
                                        handleSubmitFeedback(update.id)
                                      }
                                      disabled={isSubmittingFeedback}
                                      className="text-xs bg-[#2563EB] hover:bg-[#1D4ED8] text-white"
                                    >
                                      <Send className="h-3 w-3 mr-1" />
                                      Submit Feedback
                                    </Button>
                                  </div>
                                </div>
                              ) : (
                                <Button
                                  type="button"
                                  variant="ghost"
                                  size="sm"
                                  onClick={() => {
                                    setActiveFeedbackUpdateId(update.id);
                                    setFeedbackDraft("");
                                  }}
                                  className="text-xs text-slate-500 hover:text-blue-600 cursor-pointer"
                                >
                                  <MessageSquare className="h-3.5 w-3.5 mr-1" />
                                  Add Management Feedback
                                </Button>
                              )
                            ) : (
                              <span className="text-[11px] text-slate-400 italic">
                                No reviewer feedback recorded yet.
                              </span>
                            )}
                          </div>
                        )}
                      </div>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* ────────────────────────────────────────────────────────────────────── */}
      {/* TAB 2: NEW PROGRESS UPLOAD (Mobile-First 1-Handed Operation)            */}
      {/* ────────────────────────────────────────────────────────────────────── */}
      {activeTab === "upload" && (
        <Card className="border-slate-200 shadow-sm max-w-2xl mx-auto">
          <CardHeader>
            <CardTitle className="text-base sm:text-lg flex items-center gap-2">
              <Camera className="h-5 w-5 text-[#2563EB]" />
              Post Daily Site Progress
            </CardTitle>
            <CardDescription className="text-xs">
              Record completed work and attach compressed site photos directly from
              field camera or mobile gallery.
            </CardDescription>
          </CardHeader>

          <CardContent>
            <form onSubmit={handleCreateProgress} className="space-y-4">
              {/* Site Selector */}
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Construction Site <span className="text-rose-500">*</span>
                </label>
                <select
                  required
                  value={uploadSiteId}
                  onChange={(e) => setUploadSiteId(e.target.value)}
                  className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm text-slate-800 focus:border-[#2563EB] focus:outline-hidden"
                >
                  <option value="" disabled>
                    Select Site...
                  </option>
                  {sites.map((site) => (
                    <option key={site.id} value={site.id}>
                      {site.name} {site.location ? `(${site.location})` : ""}
                    </option>
                  ))}
                </select>
              </div>

              {/* Work Date */}
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Work Date <span className="text-rose-500">*</span>
                </label>
                <input
                  type="date"
                  required
                  value={uploadDate}
                  onChange={(e) => setUploadDate(e.target.value)}
                  className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm text-slate-800 focus:border-[#2563EB] focus:outline-hidden"
                />
              </div>

              {/* Work Category Quick Chips */}
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1.5">
                  Work Category <span className="text-rose-500">*</span>
                </label>
                <div className="flex flex-wrap gap-1.5">
                  {PROGRESS_WORK_CATEGORIES.map((cat) => {
                    const isSelected = uploadCategory === cat;
                    return (
                      <button
                        key={cat}
                        type="button"
                        onClick={() => setUploadCategory(cat)}
                        className={`rounded-full px-3 py-1 text-xs font-medium transition-all cursor-pointer ${
                          isSelected
                            ? "bg-[#2563EB] text-white shadow-xs scale-105"
                            : "bg-slate-100 text-slate-700 hover:bg-slate-200"
                        }`}
                      >
                        {cat}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Work Description */}
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Work Description <span className="text-rose-500">*</span>
                </label>
                <textarea
                  required
                  rows={3}
                  value={uploadDescription}
                  onChange={(e) => setUploadDescription(e.target.value)}
                  placeholder="Describe the tasks executed today (e.g. 2nd floor column reinforcement steel binding completed, formwork aligned)..."
                  className="w-full rounded-lg border border-slate-300 p-2.5 text-sm text-slate-800 focus:border-[#2563EB] focus:outline-hidden"
                />
              </div>

              {/* Optional Remarks */}
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Optional Remarks / Delays / Safety Notes
                </label>
                <input
                  type="text"
                  value={uploadRemarks}
                  onChange={(e) => setUploadRemarks(e.target.value)}
                  placeholder="e.g. Heavy rain delayed concreting by 2 hours"
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm text-slate-800 focus:border-[#2563EB] focus:outline-hidden"
                />
              </div>

              {/* Multi-Photo Capture Component */}
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1.5">
                  Attach Progress Photos
                </label>
                <MultiPhotoCapture
                  photos={uploadedPhotos}
                  onChange={setUploadedPhotos}
                  maxPhotos={12}
                  disabled={isSubmitting}
                />
              </div>

              {/* Upload Progress Bar */}
              {isSubmitting && (
                <div className="space-y-1.5 rounded-xl bg-blue-50 p-3 border border-blue-200">
                  <div className="flex justify-between text-xs font-medium text-blue-900">
                    <span>{uploadStatusText || "Uploading..."}</span>
                    <span>{uploadProgressPercent}%</span>
                  </div>
                  <div className="h-2 w-full overflow-hidden rounded-full bg-blue-200">
                    <div
                      className="h-full bg-[#2563EB] transition-all duration-300"
                      style={{ width: `${uploadProgressPercent}%` }}
                    />
                  </div>
                </div>
              )}

              {/* Form Buttons */}
              <div className="pt-2 flex items-center justify-end gap-3">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setActiveTab("gallery")}
                  disabled={isSubmitting}
                  className="cursor-pointer"
                >
                  Cancel
                </Button>

                <Button
                  type="submit"
                  disabled={isSubmitting}
                  className="bg-[#2563EB] hover:bg-[#1D4ED8] text-white px-6 cursor-pointer"
                >
                  {isSubmitting ? (
                    <>
                      <RefreshCw className="h-4 w-4 mr-2 animate-spin" />
                      Uploading ({uploadProgressPercent}%)
                    </>
                  ) : (
                    <>
                      <CheckCircle2 className="h-4 w-4 mr-2" />
                      Submit Progress
                    </>
                  )}
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      {/* Lightbox Modal */}
      <PhotoLightbox
        isOpen={lightboxOpen}
        onClose={() => setLightboxOpen(false)}
        update={lightboxUpdate}
        activePhotoIndex={lightboxPhotoIdx}
        onNavigate={(idx) => setLightboxPhotoIdx(idx)}
      />

      {/* Confirm Delete Dialog (PM / Admin) */}
      <ConfirmDialog
        open={Boolean(deleteTarget)}
        title="Delete Site Progress Update"
        description="Are you sure you want to permanently delete this progress record and all attached photos from storage? This action cannot be undone."
        confirmLabel={isDeleting ? "Deleting..." : "Delete Permanently"}
        variant="danger"
        loading={isDeleting}
        onConfirm={handleConfirmDelete}
        onClose={() => setDeleteTarget(null)}
      />
    </div>
  );
}
