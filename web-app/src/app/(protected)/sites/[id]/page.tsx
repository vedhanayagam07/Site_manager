"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import {
  ArrowLeft,
  Building2,
  MapPin,
  UserCog,
  UserPlus,
  UserMinus,
  ClipboardCheck,
  CheckCircle2,
  Trash2,
  Pencil,
  Undo2,
  Lock,
} from "lucide-react";
import { useAuth } from "@/context/auth-context";
import {
  deleteSite,
  fetchSiteById,
  toggleSiteCompletion,
  updateSite,
  type SiteFormPayload,
} from "@/lib/data/sites";
import {
  assignWorkerToSite,
  fetchUnassignedWorkers,
  fetchWorkers,
} from "@/lib/data/workers";
import {
  fetchAttendanceRange,
  upsertSiteAttendance,
} from "@/lib/data/attendance";
import {
  SITE_STATUSES,
  type AttendanceStatus,
  type SiteAttendanceRecord,
  type SiteRecord,
  type WorkerRecord,
} from "@/types/database";
import { formatDisplayDate, getErrorMessage, todayIsoDate } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge, Badge } from "@/components/ui/badge";
import { Input, Select } from "@/components/ui/input";
import { Modal } from "@/components/ui/modal";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { siteFormSchema, extractFieldErrors } from "@/lib/validation/schemas";
import {
  EmptyState,
  ErrorBanner,
  LoadingTable,
} from "@/components/ui/states";
import { useToast } from "@/components/ui/toast";

type SiteTab = "workers" | "mark" | "history" | "weekly";

export default function SiteDetailPage() {
  const params = useParams();
  const router = useRouter();
  const siteId = String(params.id ?? "");
  const { isAdmin, isPmOrAdmin, refreshSites } = useAuth();
  const toast = useToast();

  const [site, setSite] = useState<SiteRecord | null>(null);
  const [workers, setWorkers] = useState<WorkerRecord[]>([]);
  const [history, setHistory] = useState<SiteAttendanceRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<SiteTab>("workers");

  // Assign worker modal
  const [assignModalOpen, setAssignModalOpen] = useState(false);
  const [unassignedWorkers, setUnassignedWorkers] = useState<WorkerRecord[]>([]);
  const [loadingUnassigned, setLoadingUnassigned] = useState(false);

  // Edit site modal
  const [editOpen, setEditOpen] = useState(false);
  const [editForm, setEditForm] = useState<SiteFormPayload>({
    name: "",
    location: "",
    project_manager: "",
    status: "Active",
    progress: 0,
  });
  const [savingSite, setSavingSite] = useState(false);
  const [editErrors, setEditErrors] = useState<Record<string, string>>({});
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [deletingSite, setDeletingSite] = useState(false);

  // Quick Mark Attendance state
  const [attendanceMap, setAttendanceMap] = useState<Record<string, AttendanceStatus>>({});
  const [savingAttendance, setSavingAttendance] = useState(false);

  const loadAll = useCallback(async () => {
    if (!siteId) return;
    setLoading(true);
    setError(null);
    try {
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
      const startIso = thirtyDaysAgo.toISOString().slice(0, 10);

      const [siteData, workersData, historyData] = await Promise.all([
        fetchSiteById(siteId),
        fetchWorkers(siteId),
        fetchAttendanceRange(startIso, undefined, { siteId }),
      ]);

      setSite(siteData);
      setWorkers(workersData);
      setHistory(historyData);

      const initialMap: Record<string, AttendanceStatus> = {};
      for (const w of workersData) {
        initialMap[w.id] = "Present";
      }
      setAttendanceMap(initialMap);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load site details."));
    } finally {
      setLoading(false);
    }
  }, [siteId]);

  useEffect(() => {
    loadAll();
  }, [loadAll]);

  const weeklySummary = useMemo(() => {
    const weekAgo = new Date();
    weekAgo.setDate(weekAgo.getDate() - 7);
    const cutoff = weekAgo.toISOString().slice(0, 10);
    const counts = new Map<string, { name: string; present: number; halfDay: number; absent: number }>();

    for (const r of history) {
      if (r.attendance_date < cutoff) continue;
      const key = r.worker_id;
      const entry = counts.get(key) ?? {
        name: r.workers?.name ?? "Unknown Worker",
        present: 0,
        halfDay: 0,
        absent: 0,
      };
      if (r.status === "Present") entry.present += 1;
      else if (r.status === "Half Day") entry.halfDay += 1;
      else entry.absent += 1;
      counts.set(key, entry);
    }

    return Array.from(counts.values()).sort((a, b) => b.present - a.present);
  }, [history]);

  async function openAssignModal() {
    setAssignModalOpen(true);
    setLoadingUnassigned(true);
    try {
      const list = await fetchUnassignedWorkers();
      setUnassignedWorkers(list);
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not fetch unassigned workers."));
    } finally {
      setLoadingUnassigned(false);
    }
  }

  async function handleAssign(worker: WorkerRecord) {
    if (!site) return;
    try {
      await assignWorkerToSite(worker, site.id, site.name);
      toast.success(`Assigned ${worker.name} to ${site.name}.`);
      setAssignModalOpen(false);
      await loadAll();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to assign worker."));
    }
  }

  async function handleUnassign(worker: WorkerRecord) {
    try {
      await assignWorkerToSite(worker, null, null);
      toast.success(`Unassigned ${worker.name}.`);
      await loadAll();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to unassign worker."));
    }
  }

  async function handleToggleComplete() {
    if (!site) return;
    try {
      const updated = await toggleSiteCompletion(site);
      setSite(updated);
      await refreshSites();
      toast.success(
        updated.status === "Completed"
          ? "Site marked as Completed."
          : "Site reopened as Active."
      );
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to update site status."));
    }
  }

  async function handleDeleteSite() {
    if (!site) return;
    setDeletingSite(true);
    try {
      await deleteSite(site.id, site.name);
      toast.success("Site deleted.");
      setDeleteDialogOpen(false);
      await refreshSites();
      router.replace("/sites");
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to delete site."));
    } finally {
      setDeletingSite(false);
    }
  }

  function openEdit() {
    if (!site) return;
    setEditErrors({});
    setEditForm({
      name: site.name,
      location: site.location ?? "",
      project_manager: site.project_manager ?? "",
      status: site.status || "Active",
      progress: Number(site.progress ?? 0),
    });
    setEditOpen(true);
  }

  async function handleSaveEdit(e: React.FormEvent) {
    e.preventDefault();
    if (!site) return;
    const parsed = siteFormSchema.safeParse(editForm);
    if (!parsed.success) {
      setEditErrors(extractFieldErrors(parsed.error));
      return;
    }
    setEditErrors({});
    setSavingSite(true);
    try {
      const updated = await updateSite(site.id, parsed.data);
      setSite(updated);
      setEditOpen(false);
      await refreshSites();
      toast.success("Site updated.");
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to update site."));
    } finally {
      setSavingSite(false);
    }
  }

  async function handleSaveAttendance() {
    if (!site || workers.length === 0) return;
    const today = todayIsoDate();

    // Enforce business rule: Supervisor attendance is managed by Project Manager / Admin
    const permittedWorkers = workers.filter(
      (w) => isPmOrAdmin || (w.role ?? "").toLowerCase() !== "supervisor"
    );

    if (permittedWorkers.length === 0) {
      toast.error("No workers eligible for marking by your role.");
      return;
    }

    setSavingAttendance(true);
    try {
      await upsertSiteAttendance(
        permittedWorkers.map((w) => ({
          worker_id: w.id,
          site_id: site.id,
          attendance_date: today,
          status: attendanceMap[w.id] ?? "Present",
        })),
        site.name,
        today
      );
      toast.success("Attendance saved for today.");
      await loadAll();
      setActiveTab("history");
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to save attendance."));
    } finally {
      setSavingAttendance(false);
    }
  }

  if (loading) {
    return <LoadingTable rows={6} />;
  }

  if (!site) {
    return (
      <div>
        <Link
          href="/sites"
          className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-slate-600 hover:text-slate-900"
        >
          <ArrowLeft className="h-4 w-4" />
          Back to Sites
        </Link>
        {error && <ErrorBanner message={error} onRetry={loadAll} />}
        <EmptyState
          icon={Building2}
          title="Site Not Found"
          description="This site does not exist or you do not have permission to view it."
        />
      </div>
    );
  }

  const progress = Number(site.progress ?? 0);
  const isCompleted = site.status === "Completed";

  return (
    <div>
      <Link
        href="/sites"
        className="mb-4 inline-flex items-center gap-1.5 text-xs font-medium text-slate-500 hover:text-slate-900"
      >
        <ArrowLeft className="h-3.5 w-3.5" />
        Back to Construction Sites
      </Link>

      {error && <ErrorBanner message={error} onRetry={loadAll} />}

      {/* Site Header Summary Card */}
      <Card className="mb-6">
        <CardContent className="p-6">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-blue-50 text-[#2563EB]">
                <Building2 className="h-6 w-6" />
              </div>
              <div>
                <div className="flex flex-wrap items-center gap-2.5">
                  <h1 className="text-xl font-bold text-slate-900">{site.name}</h1>
                  <StatusBadge status={site.status} />
                </div>
                <div className="mt-1.5 flex flex-wrap items-center gap-4 text-xs text-slate-500">
                  <span className="inline-flex items-center gap-1">
                    <MapPin className="h-3.5 w-3.5" />
                    {site.location || "No location specified"}
                  </span>
                  <span className="inline-flex items-center gap-1">
                    <UserCog className="h-3.5 w-3.5" />
                    Manager: {site.project_manager || "Unassigned"}
                  </span>
                </div>
              </div>
            </div>

            <div className="flex flex-wrap items-center gap-2">
              {isPmOrAdmin && (
                <Button variant="outline" size="sm" onClick={openAssignModal}>
                  <UserPlus className="h-3.5 w-3.5" />
                  Assign Worker
                </Button>
              )}
              {isPmOrAdmin && (
                <>
                  <Button variant="outline" size="sm" onClick={openEdit}>
                    <Pencil className="h-3.5 w-3.5" />
                    Edit
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={handleToggleComplete}
                  >
                    {isCompleted ? (
                      <>
                        <Undo2 className="h-3.5 w-3.5" />
                        Mark Active
                      </>
                    ) : (
                      <>
                        <CheckCircle2 className="h-3.5 w-3.5 text-emerald-600" />
                        Mark Complete
                      </>
                    )}
                  </Button>
                </>
              )}
              {isAdmin && (
                <Button
                  variant="danger"
                  size="sm"
                  onClick={() => setDeleteDialogOpen(true)}
                >
                  <Trash2 className="h-3.5 w-3.5" />
                  Delete
                </Button>
              )}
            </div>
          </div>

          <div className="mt-5 border-t border-slate-100 pt-4">
            <div className="flex items-center justify-between text-xs">
              <span className="font-medium text-slate-500">Site Progress</span>
              <span className="font-bold text-slate-900">{progress}%</span>
            </div>
            <div className="mt-1.5 h-2 w-full overflow-hidden rounded-full bg-slate-100">
              <div
                className={`h-full rounded-full ${isCompleted ? "bg-emerald-500" : "bg-[#2563EB]"}`}
                style={{ width: `${Math.min(100, Math.max(0, progress))}%` }}
              />
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Tabs */}
      <div className="mb-5 flex flex-wrap gap-1.5 border-b border-slate-200 pb-3">
        {(
          [
            { id: "workers", label: `Assigned Workers (${workers.length})` },
            { id: "mark", label: "Mark Attendance Today" },
            { id: "history", label: `Attendance History (${history.length})` },
            { id: "weekly", label: "Weekly Summary" },
          ] as Array<{ id: SiteTab; label: string }>
        ).map((tab) => (
          <button
            key={tab.id}
            type="button"
            onClick={() => setActiveTab(tab.id)}
            className={`rounded-lg px-3.5 py-2 text-xs font-semibold transition-colors cursor-pointer ${
              activeTab === tab.id
                ? "bg-[#0B1628] text-white"
                : "bg-white text-slate-600 border border-slate-200 hover:bg-slate-50"
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab 1: Assigned Workers */}
      {activeTab === "workers" && (
        <Card>
          <CardHeader>
            <CardTitle>Assigned Workers</CardTitle>
            {isPmOrAdmin && (
              <Button size="sm" variant="outline" onClick={openAssignModal}>
                <UserPlus className="h-3.5 w-3.5" />
                Assign Worker
              </Button>
            )}
          </CardHeader>
          <CardContent className="p-0">
            {workers.length === 0 ? (
              <div className="p-8 text-center text-xs text-slate-500">
                No permanent workers are assigned to this site yet. For temporary
                daily labourers, use the{" "}
                <Link href="/attendance" className="font-semibold text-[#2563EB] underline">
                  Category Headcount
                </Link>{" "}
                tab in Attendance.
              </div>
            ) : (
              <div className="divide-y divide-slate-100">
                {workers.map((w) => (
                  <div
                    key={w.id}
                    className="flex items-center justify-between gap-3 px-5 py-3.5"
                  >
                    <Link
                      href={`/workers/${w.id}`}
                      className="min-w-0 flex-1 hover:text-[#2563EB]"
                    >
                      <p className="truncate text-sm font-semibold text-slate-900">
                        {w.name}
                      </p>
                      <p className="text-xs text-slate-500">
                        {w.role || "Worker"}
                        {w.phone ? ` · ${w.phone}` : ""}
                      </p>
                    </Link>
                    <div className="flex items-center gap-2">
                      <StatusBadge status={w.status} />
                      {isPmOrAdmin && (
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => handleUnassign(w)}
                          title="Unassign from site"
                        >
                          <UserMinus className="h-4 w-4 text-red-600" />
                        </Button>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Tab 2: Quick Mark Attendance */}
      {activeTab === "mark" && (
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Mark Named Attendance — {formatDisplayDate(todayIsoDate())}</CardTitle>
            </div>
            <Link href="/attendance">
              <Button size="sm" variant="outline">
                Category Headcount Mode
              </Button>
            </Link>
          </CardHeader>
          <CardContent>
            {workers.length === 0 ? (
              <EmptyState
                icon={ClipboardCheck}
                title="No Assigned Workers"
                description="Assign permanent workers to this site or switch to Daily Workforce Category Counts in the Attendance module."
              />
            ) : (
              <div className="space-y-3">
                {workers.map((w) => {
                  const isSupWorker = (w.role ?? "").toLowerCase() === "supervisor";
                  const lockedForRole = isSupWorker && !isPmOrAdmin;
                  const current = attendanceMap[w.id] ?? "Present";

                  return (
                    <div
                      key={w.id}
                      className="flex flex-col justify-between gap-3 rounded-lg border border-slate-200 p-3.5 sm:flex-row sm:items-center"
                    >
                      <div>
                        <div className="flex items-center gap-2">
                          <p className="text-sm font-semibold text-slate-900">
                            {w.name}
                          </p>
                          {isSupWorker && <Badge variant="blue">Supervisor</Badge>}
                        </div>
                        <p className="text-xs text-slate-500">{w.role || "Worker"}</p>
                      </div>

                      {lockedForRole ? (
                        <div className="inline-flex items-center gap-1.5 rounded-md bg-slate-100 px-3 py-1.5 text-xs text-slate-600">
                          <Lock className="h-3.5 w-3.5" />
                          Managed by Project Manager
                        </div>
                      ) : (
                        <div className="flex gap-1.5">
                          {(["Present", "Half Day", "Absent"] as AttendanceStatus[]).map(
                            (st) => {
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
                                    setAttendanceMap((prev) => ({ ...prev, [w.id]: st }))
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
                            }
                          )}
                        </div>
                      )}
                    </div>
                  );
                })}

                <div className="pt-3">
                  <Button
                    onClick={handleSaveAttendance}
                    loading={savingAttendance}
                    className="w-full sm:w-auto"
                  >
                    <ClipboardCheck className="h-4 w-4" />
                    Save Today&apos;s Attendance
                  </Button>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Tab 3: History */}
      {activeTab === "history" && (
        <Card>
          <CardHeader>
            <CardTitle>Last 30 Days Attendance History</CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            {history.length === 0 ? (
              <p className="p-8 text-center text-xs text-slate-500">
                No attendance records found for this site in the past 30 days.
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-left text-sm">
                  <thead className="border-b border-slate-200 bg-slate-50 text-xs font-semibold uppercase text-slate-500">
                    <tr>
                      <th className="px-5 py-3">Date</th>
                      <th className="px-5 py-3">Worker</th>
                      <th className="px-5 py-3">Role</th>
                      <th className="px-5 py-3">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {history.map((r) => (
                      <tr key={r.id} className="hover:bg-slate-50/70">
                        <td className="px-5 py-3 text-xs font-medium text-slate-700">
                          {formatDisplayDate(r.attendance_date)}
                        </td>
                        <td className="px-5 py-3 font-medium text-slate-900">
                          {r.workers?.name ?? "Unknown"}
                        </td>
                        <td className="px-5 py-3 text-xs text-slate-500">
                          {r.workers?.role ?? "—"}
                        </td>
                        <td className="px-5 py-3">
                          <StatusBadge status={r.status} />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Tab 4: Weekly Summary */}
      {activeTab === "weekly" && (
        <Card>
          <CardHeader>
            <CardTitle>Last 7 Days Attendance Summary</CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            {weeklySummary.length === 0 ? (
              <p className="p-8 text-center text-xs text-slate-500">
                No attendance logged in the last 7 days.
              </p>
            ) : (
              <div className="divide-y divide-slate-100">
                {weeklySummary.map((row) => (
                  <div
                    key={row.name}
                    className="flex items-center justify-between px-5 py-3.5"
                  >
                    <div>
                      <p className="text-sm font-semibold text-slate-900">{row.name}</p>
                      <p className="text-xs text-slate-500">
                        Present: {row.present} · Half Day: {row.halfDay} · Absent:{" "}
                        {row.absent}
                      </p>
                    </div>
                    <Badge variant="success">{row.present} Present Days</Badge>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Assign Worker Modal */}
      <Modal
        open={assignModalOpen}
        onClose={() => setAssignModalOpen(false)}
        title="Assign Worker to Site"
        description={`Select an unassigned worker to assign to ${site.name}.`}
      >
        {loadingUnassigned ? (
          <p className="py-6 text-center text-xs text-slate-500">Loading workers…</p>
        ) : unassignedWorkers.length === 0 ? (
          <p className="py-6 text-center text-xs text-slate-500">
            No unassigned workers available. Add a worker in the Workers section first.
          </p>
        ) : (
          <div className="divide-y divide-slate-100">
            {unassignedWorkers.map((w) => (
              <div
                key={w.id}
                className="flex items-center justify-between py-3"
              >
                <div>
                  <p className="text-sm font-semibold text-slate-900">{w.name}</p>
                  <p className="text-xs text-slate-500">
                    {w.role || "Worker"} {w.phone ? `· ${w.phone}` : ""}
                  </p>
                </div>
                <Button size="sm" onClick={() => handleAssign(w)}>
                  Assign
                </Button>
              </div>
            ))}
          </div>
        )}
      </Modal>

      {/* Edit Site Modal */}
      <Modal
        open={editOpen}
        onClose={() => setEditOpen(false)}
        title="Edit Site"
      >
        <form onSubmit={handleSaveEdit} className="space-y-4">
          <Input
            label="Site Name *"
            required
            error={editErrors.name}
            value={editForm.name}
            onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
          />
          <Input
            label="Location"
            error={editErrors.location}
            value={editForm.location}
            onChange={(e) =>
              setEditForm({ ...editForm, location: e.target.value })
            }
          />
          <Input
            label="Project Manager"
            error={editErrors.project_manager}
            value={editForm.project_manager}
            onChange={(e) =>
              setEditForm({ ...editForm, project_manager: e.target.value })
            }
          />
          <div className="grid grid-cols-2 gap-4">
            <Select
              label="Status"
              value={editForm.status}
              onChange={(e) =>
                setEditForm({ ...editForm, status: e.target.value })
              }
            >
              {SITE_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
            <Input
              label="Progress (%)"
              type="number"
              min={0}
              max={100}
              error={editErrors.progress}
              value={editForm.progress}
              onChange={(e) =>
                setEditForm({
                  ...editForm,
                  progress: Number(e.target.value) || 0,
                })
              }
            />
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setEditOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={savingSite}>
              Save Changes
            </Button>
          </div>
        </form>
      </Modal>

      <ConfirmDialog
        open={deleteDialogOpen}
        onClose={() => setDeleteDialogOpen(false)}
        onConfirm={handleDeleteSite}
        loading={deletingSite}
        title="Delete Construction Site"
        description={`Are you sure you want to permanently delete "${site.name}"? Associated workers and attendance records will remain unlinked.`}
        confirmLabel="Delete Site"
      />
    </div>
  );
}

