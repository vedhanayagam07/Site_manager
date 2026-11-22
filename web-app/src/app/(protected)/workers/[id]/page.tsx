"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import {
  ArrowLeft,
  Phone,
  Briefcase,
  Wrench,
  Pencil,
  Trash2,
  User,
} from "lucide-react";
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  Cell,
} from "recharts";
import { useAuth } from "@/context/auth-context";
import {
  deleteWorker,
  fetchWorkerById,
  updateWorker,
} from "@/lib/data/workers";
import { fetchAttendanceRange } from "@/lib/data/attendance";
import {
  WORKER_ROLES,
  WORKER_SKILLS,
  type SiteAttendanceRecord,
  type WorkerRecord,
} from "@/types/database";
import { formatDisplayDate, getErrorMessage } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/ui/badge";
import { Input, Select } from "@/components/ui/input";
import { Modal } from "@/components/ui/modal";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { workerFormSchema, extractFieldErrors } from "@/lib/validation/schemas";
import { EmptyState, ErrorBanner, LoadingTable } from "@/components/ui/states";
import { useToast } from "@/components/ui/toast";

export default function WorkerProfilePage() {
  const params = useParams();
  const router = useRouter();
  const workerId = String(params.id ?? "");
  const { isAdmin, isPmOrAdmin } = useAuth();
  const toast = useToast();

  const [worker, setWorker] = useState<WorkerRecord | null>(null);
  const [attendance, setAttendance] = useState<SiteAttendanceRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Edit modal
  const [editOpen, setEditOpen] = useState(false);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [role, setRole] = useState("");
  const [skill, setSkill] = useState("");
  const [status, setStatus] = useState("Active");
  const [saving, setSaving] = useState(false);
  const [editErrors, setEditErrors] = useState<Record<string, string>>({});
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);

  const load = useCallback(async () => {
    if (!workerId) return;
    setLoading(true);
    setError(null);
    try {
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
      const startIso = thirtyDaysAgo.toISOString().slice(0, 10);

      const [workerData, attData] = await Promise.all([
        fetchWorkerById(workerId),
        fetchAttendanceRange(startIso, undefined, { workerId }),
      ]);
      setWorker(workerData);
      setAttendance(attData);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load worker profile."));
    } finally {
      setLoading(false);
    }
  }, [workerId]);

  useEffect(() => {
    load();
  }, [load]);

  const stats = useMemo(() => {
    const present = attendance.filter((r) => r.status === "Present").length;
    const halfDay = attendance.filter((r) => r.status === "Half Day").length;
    const absent = attendance.filter((r) => r.status === "Absent").length;
    const total = attendance.length;
    const pct = total > 0 ? Math.round(((present + halfDay * 0.5) / total) * 100) : 0;
    return { present, halfDay, absent, total, pct };
  }, [attendance]);

  const weeklyChart = useMemo(() => {
    const days: Array<{ label: string; score: number; status: string }> = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date();
      d.setDate(d.getDate() - i);
      const iso = d.toISOString().slice(0, 10);
      const match = attendance.find((r) => r.attendance_date === iso);
      const st = match?.status ?? "Unmarked";
      const score = st === "Present" ? 1 : st === "Half Day" ? 0.5 : 0;
      days.push({
        label: new Intl.DateTimeFormat("en-IN", { weekday: "short" }).format(d),
        score,
        status: st,
      });
    }
    return days;
  }, [attendance]);

  function openEdit() {
    if (!worker) return;
    setEditErrors({});
    setName(worker.name);
    setPhone(worker.phone ?? "");
    setRole(worker.role ?? "Mason");
    setSkill(worker.skill ?? "Civil Work");
    setStatus(worker.status || "Active");
    setEditOpen(true);
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault();
    if (!worker) return;
    const parsed = workerFormSchema.safeParse({
      name,
      phone: phone.replace(/\D/g, ""),
      role,
      skill,
      status,
      site_id: worker.site_id,
    });
    if (!parsed.success) {
      setEditErrors(extractFieldErrors(parsed.error));
      return;
    }
    setEditErrors({});
    setSaving(true);
    try {
      const updated = await updateWorker(worker.id, {
        name: parsed.data.name,
        phone: parsed.data.phone,
        role: parsed.data.role,
        skill: parsed.data.skill,
        status: parsed.data.status,
      });
      setWorker(updated);
      setEditOpen(false);
      toast.success("Worker updated successfully.");
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to update worker."));
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!worker) return;
    setDeleting(true);
    try {
      await deleteWorker(worker.id, worker.name);
      toast.success("Worker deleted.");
      setDeleteDialogOpen(false);
      router.replace("/workers");
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to delete worker."));
    } finally {
      setDeleting(false);
    }
  }

  if (loading) return <LoadingTable rows={5} />;

  if (!worker) {
    return (
      <div>
        <Link
          href="/workers"
          className="mb-4 inline-flex items-center gap-1.5 text-xs font-medium text-slate-500 hover:text-slate-900"
        >
          <ArrowLeft className="h-3.5 w-3.5" />
          Back to Workers
        </Link>
        {error && <ErrorBanner message={error} onRetry={load} />}
        <EmptyState
          icon={User}
          title="Worker Not Found"
          description="This worker record could not be found."
        />
      </div>
    );
  }

  return (
    <div>
      <Link
        href="/workers"
        className="mb-4 inline-flex items-center gap-1.5 text-xs font-medium text-slate-500 hover:text-slate-900"
      >
        <ArrowLeft className="h-3.5 w-3.5" />
        Back to Workers Directory
      </Link>

      {error && <ErrorBanner message={error} onRetry={load} />}

      {/* Worker Header */}
      <Card className="mb-6">
        <CardContent className="p-6">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-4">
              <div className="flex h-14 w-14 items-center justify-center rounded-full bg-[#0B1628] text-lg font-bold text-white">
                {worker.name.slice(0, 1).toUpperCase()}
              </div>
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <h1 className="text-xl font-bold text-slate-900">{worker.name}</h1>
                  <StatusBadge status={worker.status} />
                </div>
                <div className="mt-1 flex flex-wrap gap-4 text-xs text-slate-500">
                  <span className="inline-flex items-center gap-1">
                    <Briefcase className="h-3.5 w-3.5" />
                    {worker.role || "Worker"}
                  </span>
                  <span className="inline-flex items-center gap-1">
                    <Wrench className="h-3.5 w-3.5" />
                    {worker.skill || "General"}
                  </span>
                  <span className="inline-flex items-center gap-1">
                    <Phone className="h-3.5 w-3.5" />
                    {worker.phone || "—"}
                  </span>
                </div>
              </div>
            </div>

            <div className="flex gap-2">
              {isPmOrAdmin && (
                <Button variant="outline" size="sm" onClick={openEdit}>
                  <Pencil className="h-3.5 w-3.5" />
                  Edit
                </Button>
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
        </CardContent>
      </Card>

      {/* 30-Day Summary + Last 7 Days Chart */}
      <div className="mb-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>30-Day Attendance Score</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col items-center justify-center py-6 text-center">
            <span className="text-4xl font-bold text-[#2563EB]">{stats.pct}%</span>
            <p className="mt-2 text-xs text-slate-500">
              {stats.present} Present · {stats.halfDay} Half Day · {stats.absent} Absent
            </p>
          </CardContent>
        </Card>

        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Last 7 Days Attendance</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="h-44 w-full">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={weeklyChart}>
                  <XAxis dataKey="label" tick={{ fontSize: 11, fill: "#64748B" }} axisLine={false} tickLine={false} />
                  <YAxis domain={[0, 1]} hide />
                  <Tooltip
                    formatter={(_v: unknown, _n: unknown, item: { payload?: { status?: string } }) => [
                      item.payload?.status ?? "Unmarked",
                      "Status",
                    ]}
                  />
                  <Bar dataKey="score" radius={[6, 6, 0, 0]} maxBarSize={32}>
                    {weeklyChart.map((entry, idx) => (
                      <Cell
                        key={idx}
                        fill={
                          entry.status === "Present"
                            ? "#10B981"
                            : entry.status === "Half Day"
                            ? "#F59E0B"
                            : "#CBD5E1"
                        }
                      />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Attendance Log */}
      <Card>
        <CardHeader>
          <CardTitle>Recent Attendance Records ({attendance.length})</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {attendance.length === 0 ? (
            <p className="p-8 text-center text-xs text-slate-500">
              No attendance records logged in the last 30 days.
            </p>
          ) : (
            <div className="divide-y divide-slate-100">
              {attendance.map((r) => (
                <div
                  key={r.id}
                  className="flex items-center justify-between px-5 py-3.5"
                >
                  <div>
                    <p className="text-sm font-medium text-slate-900">
                      {formatDisplayDate(r.attendance_date)}
                    </p>
                    <p className="text-xs text-slate-500">
                      {r.sites?.name ?? "Central / Unassigned"}
                    </p>
                  </div>
                  <StatusBadge status={r.status} />
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Edit Modal */}
      <Modal open={editOpen} onClose={() => setEditOpen(false)} title="Edit Worker">
        <form onSubmit={handleSave} className="space-y-4">
          <Input
            label="Name *"
            required
            error={editErrors.name}
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
          <Input
            label="Phone (10 digits) *"
            maxLength={10}
            error={editErrors.phone}
            value={phone}
            onChange={(e) => setPhone(e.target.value.replace(/\D/g, ""))}
          />
          <div className="grid grid-cols-2 gap-4">
            <Select label="Role" value={role} onChange={(e) => setRole(e.target.value)}>
              {WORKER_ROLES.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </Select>
            <Select label="Skill" value={skill} onChange={(e) => setSkill(e.target.value)}>
              {WORKER_SKILLS.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
          </div>
          <Select label="Status" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="Active">Active</option>
            <option value="Inactive">Inactive</option>
          </Select>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setEditOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={saving}>
              Save Changes
            </Button>
          </div>
        </form>
      </Modal>

      <ConfirmDialog
        open={deleteDialogOpen}
        onClose={() => setDeleteDialogOpen(false)}
        onConfirm={handleDelete}
        loading={deleting}
        title="Delete Worker"
        description={`Permanently delete worker "${worker.name}"? Attendance history associated with this worker may also be removed.`}
        confirmLabel="Delete Worker"
      />
    </div>
  );
}

