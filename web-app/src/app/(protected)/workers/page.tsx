"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  Users,
  Plus,
  Search,
  Phone,
  Building2,
  Wrench,
  ArrowRight,
  FileSpreadsheet,
} from "lucide-react";
import { downloadCsv } from "@/lib/csv";
import { workerFormSchema, extractFieldErrors } from "@/lib/validation/schemas";
import { useAuth } from "@/context/auth-context";
import { createWorker, fetchWorkers } from "@/lib/data/workers";
import { fetchActiveSites } from "@/lib/data/sites";
import {
  WORKER_ROLES,
  WORKER_SKILLS,
  type SiteRecord,
  type WorkerRecord,
} from "@/types/database";
import { getErrorMessage } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input, Select } from "@/components/ui/input";
import { Modal } from "@/components/ui/modal";
import { StatusBadge, Badge } from "@/components/ui/badge";
import {
  EmptyState,
  ErrorBanner,
  LoadingTable,
  PageHeader,
} from "@/components/ui/states";
import { useToast } from "@/components/ui/toast";

export default function WorkersPage() {
  const { isPmOrAdmin, selectedSiteId } = useAuth();
  const toast = useToast();

  const [workers, setWorkers] = useState<WorkerRecord[]>([]);
  const [sites, setSites] = useState<SiteRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("All");

  // Add Worker Modal
  const [modalOpen, setModalOpen] = useState(false);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [role, setRole] = useState<string>("Mason");
  const [skill, setSkill] = useState<string>("Civil Work");
  const [status, setStatus] = useState("Active");
  const [siteId, setSiteId] = useState("");
  const [saving, setSaving] = useState(false);
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [workersData, sitesData] = await Promise.all([
        fetchWorkers(selectedSiteId || undefined),
        fetchActiveSites(),
      ]);
      setWorkers(workersData);
      setSites(sitesData);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load workers."));
    } finally {
      setLoading(false);
    }
  }, [selectedSiteId]);

  useEffect(() => {
    load();
  }, [load]);

  const siteNameById = useMemo(() => {
    const map = new Map<string, string>();
    for (const s of sites) map.set(s.id, s.name);
    return map;
  }, [sites]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return workers.filter((w) => {
      const matchesSearch =
        !q ||
        w.name.toLowerCase().includes(q) ||
        (w.role ?? "").toLowerCase().includes(q) ||
        (w.phone ?? "").toLowerCase().includes(q) ||
        (w.skill ?? "").toLowerCase().includes(q);
      const matchesStatus =
        statusFilter === "All" ||
        (w.status ?? "").toLowerCase() === statusFilter.toLowerCase();
      return matchesSearch && matchesStatus;
    });
  }, [workers, search, statusFilter]);

  const activeCount = useMemo(
    () => filtered.filter((w) => w.status === "Active").length,
    [filtered]
  );

  function openAdd() {
    setFormErrors({});
    setName("");
    setPhone("");
    setRole("Mason");
    setSkill("Civil Work");
    setStatus("Active");
    setSiteId(selectedSiteId || "");
    setModalOpen(true);
  }

  function handleExportCsv() {
    downloadCsv(
      `tsr_workers_${new Date().toISOString().slice(0, 10)}.csv`,
      ["Name", "Role", "Skill", "Phone", "Assigned Site", "Status"],
      filtered.map((w) => [
        w.name,
        w.role ?? "",
        w.skill ?? "",
        w.phone ?? "",
        (w.site_id && siteNameById.get(w.site_id)) || w.assigned_site || "Unassigned",
        w.status,
      ])
    );
  }

  async function handleAddWorker(e: React.FormEvent) {
    e.preventDefault();
    const parsed = workerFormSchema.safeParse({
      name,
      phone: phone.replace(/\D/g, ""),
      role,
      skill,
      status,
      site_id: siteId || null,
    });
    if (!parsed.success) {
      setFormErrors(extractFieldErrors(parsed.error));
      return;
    }
    setFormErrors({});
    setSaving(true);
    try {
      await createWorker({
        name: parsed.data.name,
        phone: parsed.data.phone,
        role: parsed.data.role,
        skill: parsed.data.skill,
        status: parsed.data.status,
        site_id: parsed.data.site_id,
        assigned_site: parsed.data.site_id
          ? siteNameById.get(parsed.data.site_id) ?? null
          : null,
      });
      toast.success("Worker added successfully.");
      setModalOpen(false);
      await load();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to save worker."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div>
      <PageHeader
        title="Workers Directory"
        description={`${activeCount} active of ${filtered.length} registered workers & supervisors`}
        actions={
          <>
            <Button
              variant="outline"
              size="sm"
              onClick={handleExportCsv}
              disabled={filtered.length === 0}
            >
              <FileSpreadsheet className="h-4 w-4" />
              CSV
            </Button>
            {isPmOrAdmin && (
              <Button onClick={openAdd}>
                <Plus className="h-4 w-4" />
                Add Worker
              </Button>
            )}
          </>
        }
      />

      {error && <ErrorBanner message={error} onRetry={load} />}

      {/* Search & Filter */}
      <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="relative max-w-md flex-1">
          <Search className="pointer-events-none absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-[#778292]" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by name, role, skill, or phone…"
            className="h-10 w-full rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 pr-3 pl-9 text-sm text-[#F2F4F8] placeholder:text-[#778292] focus:border-[#4B83F5] focus:bg-[#101318]/90 focus:outline-none focus:ring-2 focus:ring-[#4B83F5]/25"
          />
        </div>
        <div className="flex gap-1.5">
          {["All", "Active", "Inactive"].map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => setStatusFilter(s)}
              className={`rounded-xl px-3.5 py-2 text-xs font-semibold transition-all cursor-pointer ${
                statusFilter === s
                  ? "bg-[#4B83F5] text-white border border-[#4B83F5]/40 shadow-[0_0_12px_rgba(75,131,245,0.25)]"
                  : "border border-[rgba(190,205,225,0.18)] bg-[rgba(23,28,36,0.6)] text-[#A7B0BE] hover:bg-white/5 hover:text-[#F2F4F8]"
              }`}
            >
              {s}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <LoadingTable rows={6} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={Users}
          title={workers.length === 0 ? "No Workers Registered" : "No Matching Workers"}
          description={
            workers.length === 0
              ? "Add permanent staff, skilled trades, or supervisors. Temporary daily labourers can be logged by trade headcount in Attendance."
              : "Try adjusting your search query or status filter."
          }
          action={
            isPmOrAdmin && workers.length === 0 ? (
              <Button onClick={openAdd}>
                <Plus className="h-4 w-4" />
                Add Worker
              </Button>
            ) : undefined
          }
        />
      ) : (
        <>
          {/* Desktop Data Table */}
          <Card className="hidden overflow-hidden md:block">
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead className="border-b border-[rgba(190,205,225,0.15)] bg-[rgba(23,28,36,0.7)] text-xs font-semibold uppercase tracking-wider text-[#A7B0BE]">
                  <tr>
                    <th className="px-5 py-3.5">Worker</th>
                    <th className="px-5 py-3.5">Role / Trade</th>
                    <th className="px-5 py-3.5">Skill</th>
                    <th className="px-5 py-3.5">Assigned Site</th>
                    <th className="px-5 py-3.5">Phone</th>
                    <th className="px-5 py-3.5">Status</th>
                    <th className="px-5 py-3.5 text-right">Profile</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[rgba(190,205,225,0.08)]">
                  {filtered.map((w) => {
                    const siteLabel =
                      (w.site_id && siteNameById.get(w.site_id)) ||
                      w.assigned_site ||
                      "Unassigned";
                    return (
                      <tr key={w.id} className="transition-colors hover:bg-white/[0.04]">
                        <td className="px-5 py-4">
                          <Link
                            href={`/workers/${w.id}`}
                            className="flex items-center gap-3 font-semibold text-[#F2F4F8] hover:text-[#4B83F5] transition-colors"
                          >
                            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-blue-500/15 border border-blue-500/30 text-xs font-bold text-[#4B83F5]">
                              {w.name.slice(0, 1).toUpperCase()}
                            </span>
                            <span className="text-sm font-semibold text-[#F2F4F8]">{w.name}</span>
                          </Link>
                        </td>
                        <td className="px-5 py-4">
                          {w.role === "Supervisor" ? (
                            <Badge variant="blue">{w.role}</Badge>
                          ) : (
                            <span className="inline-flex items-center rounded-lg bg-white/[0.05] border border-white/[0.08] px-2.5 py-1 text-xs font-medium text-[#F2F4F8]">
                              {w.role || "—"}
                            </span>
                          )}
                        </td>
                        <td className="px-5 py-4 text-xs text-[#CBD3DF]">
                          {w.skill || "—"}
                        </td>
                        <td className="px-5 py-4 text-xs font-medium text-[#F2F4F8]">
                          {siteLabel}
                        </td>
                        <td className="px-5 py-4 font-mono text-xs text-[#A7B0BE]">
                          {w.phone || "—"}
                        </td>
                        <td className="px-5 py-4">
                          <StatusBadge status={w.status} />
                        </td>
                        <td className="px-5 py-4 text-right">
                          <Link
                            href={`/workers/${w.id}`}
                            className="inline-flex items-center gap-1.5 rounded-lg border border-[rgba(190,205,225,0.18)] bg-white/[0.03] px-3 py-1.5 text-xs font-medium text-[#4B83F5] hover:bg-blue-500/15 hover:border-blue-500/30 hover:text-white transition-all"
                          >
                            View
                            <ArrowRight className="h-3.5 w-3.5" />
                          </Link>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </Card>

          {/* Mobile Responsive Cards */}
          <div className="space-y-3 md:hidden">
            {filtered.map((w) => {
              const siteLabel =
                (w.site_id && siteNameById.get(w.site_id)) ||
                w.assigned_site ||
                "Unassigned";
              return (
                <Link key={w.id} href={`/workers/${w.id}`} className="block">
                  <Card className="transition-all hover:border-[rgba(220,230,245,0.25)]">
                    <CardContent className="p-4">
                      <div className="flex items-start justify-between gap-2">
                        <div className="flex items-center gap-3">
                          <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-blue-500/15 border border-blue-500/30 text-sm font-bold text-[#4B83F5]">
                            {w.name.slice(0, 1).toUpperCase()}
                          </div>
                          <div>
                            <p className="text-sm font-semibold text-[#F2F4F8]">
                              {w.name}
                            </p>
                            <p className="text-xs text-[#A7B0BE]">
                              {w.role || "Worker"}
                            </p>
                          </div>
                        </div>
                        <StatusBadge status={w.status} />
                      </div>
                      <div className="mt-3 flex flex-wrap gap-3 border-t border-[rgba(190,205,225,0.10)] pt-3 text-xs text-[#CBD3DF]">
                        {w.phone && (
                          <span className="inline-flex items-center gap-1.5 font-mono text-[#A7B0BE]">
                            <Phone className="h-3.5 w-3.5 text-[#778292]" />
                            {w.phone}
                          </span>
                        )}
                        <span className="inline-flex items-center gap-1.5 text-[#F2F4F8]">
                          <Building2 className="h-3.5 w-3.5 text-[#4B83F5]" />
                          {siteLabel}
                        </span>
                        {w.skill && (
                          <span className="inline-flex items-center gap-1.5 text-[#CBD3DF]">
                            <Wrench className="h-3.5 w-3.5 text-[#E5AD55]" />
                            {w.skill}
                          </span>
                        )}
                      </div>
                    </CardContent>
                  </Card>
                </Link>
              );
            })}
          </div>
        </>
      )}

      {/* Add Worker Modal */}
      <Modal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        title="Add Worker"
        description="Register a permanent worker, skilled tradesperson, or site supervisor."
      >
        <form onSubmit={handleAddWorker} className="space-y-4">
          <Input
            label="Full Name *"
            required
            error={formErrors.name}
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g., Murugan S"
          />
          <Input
            label="Phone Number (10 digits) *"
            type="tel"
            required
            maxLength={10}
            error={formErrors.phone}
            value={phone}
            onChange={(e) => setPhone(e.target.value.replace(/\D/g, ""))}
            placeholder="9876543210"
          />
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Select
              label="Role / Trade"
              value={role}
              onChange={(e) => setRole(e.target.value)}
            >
              {WORKER_ROLES.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </Select>
            <Select
              label="Skill Set"
              value={skill}
              onChange={(e) => setSkill(e.target.value)}
            >
              {WORKER_SKILLS.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Select
              label="Assigned Site (Optional)"
              value={siteId}
              onChange={(e) => setSiteId(e.target.value)}
            >
              <option value="">— No site assigned —</option>
              {sites.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </Select>
            <Select
              label="Status"
              value={status}
              onChange={(e) => setStatus(e.target.value)}
            >
              <option value="Active">Active</option>
              <option value="Inactive">Inactive</option>
            </Select>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button
              variant="outline"
              onClick={() => setModalOpen(false)}
              disabled={saving}
            >
              Cancel
            </Button>
            <Button type="submit" loading={saving}>
              Save Worker
            </Button>
          </div>
        </form>
      </Modal>
    </div>
  );
}

