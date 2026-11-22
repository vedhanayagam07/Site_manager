"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  Building2,
  MapPin,
  Plus,
  Search,
  UserCog,
  Pencil,
  ArrowRight,
  FileSpreadsheet,
} from "lucide-react";
import { downloadCsv } from "@/lib/csv";
import { siteFormSchema, extractFieldErrors } from "@/lib/validation/schemas";
import { useAuth } from "@/context/auth-context";
import {
  createSite,
  fetchSites,
  updateSite,
  type SiteFormPayload,
} from "@/lib/data/sites";
import { SITE_STATUSES, type SiteRecord } from "@/types/database";
import { getErrorMessage } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input, Select } from "@/components/ui/input";
import { Modal } from "@/components/ui/modal";
import { StatusBadge } from "@/components/ui/badge";
import {
  EmptyState,
  ErrorBanner,
  LoadingCards,
  PageHeader,
} from "@/components/ui/states";
import { useToast } from "@/components/ui/toast";

export default function SitesPage() {
  const { isPmOrAdmin, refreshSites } = useAuth();
  const toast = useToast();

  const [sites, setSites] = useState<SiteRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("All");

  // Add/Edit Modal
  const [modalOpen, setModalOpen] = useState(false);
  const [editingSite, setEditingSite] = useState<SiteRecord | null>(null);
  const [form, setForm] = useState<SiteFormPayload>({
    name: "",
    location: "",
    project_manager: "",
    status: "Active",
    progress: 0,
  });
  const [saving, setSaving] = useState(false);
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await fetchSites();
      setSites(data);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load construction sites."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const filteredSites = useMemo(() => {
    const q = search.trim().toLowerCase();
    return sites.filter((s) => {
      const matchesSearch =
        !q ||
        s.name.toLowerCase().includes(q) ||
        (s.location ?? "").toLowerCase().includes(q) ||
        (s.project_manager ?? "").toLowerCase().includes(q);
      const matchesStatus =
        statusFilter === "All" ||
        (s.status ?? "").toLowerCase() === statusFilter.toLowerCase();
      return matchesSearch && matchesStatus;
    });
  }, [sites, search, statusFilter]);

  function openAddModal() {
    setEditingSite(null);
    setFormErrors({});
    setForm({
      name: "",
      location: "",
      project_manager: "",
      status: "Active",
      progress: 0,
    });
    setModalOpen(true);
  }

  function openEditModal(site: SiteRecord, e: React.MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    setEditingSite(site);
    setFormErrors({});
    setForm({
      name: site.name,
      location: site.location ?? "",
      project_manager: site.project_manager ?? "",
      status: site.status || "Active",
      progress: Number(site.progress ?? 0),
    });
    setModalOpen(true);
  }

  function handleExportCsv() {
    downloadCsv(
      `tsr_sites_${new Date().toISOString().slice(0, 10)}.csv`,
      ["Site Name", "Location", "Project Manager", "Status", "Progress (%)"],
      filteredSites.map((s) => [
        s.name,
        s.location ?? "",
        s.project_manager ?? "",
        s.status,
        s.progress ?? 0,
      ])
    );
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault();
    const parsed = siteFormSchema.safeParse(form);
    if (!parsed.success) {
      setFormErrors(extractFieldErrors(parsed.error));
      return;
    }
    setFormErrors({});
    setSaving(true);
    try {
      if (editingSite) {
        await updateSite(editingSite.id, parsed.data);
        toast.success("Site updated successfully.");
      } else {
        await createSite(parsed.data);
        toast.success("Site created successfully.");
      }
      setModalOpen(false);
      await Promise.all([load(), refreshSites()]);
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to save site."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div>
      <PageHeader
        title="Construction Sites"
        description={`${sites.length} total project sites`}
        actions={
          <>
            <Button
              variant="outline"
              size="sm"
              onClick={handleExportCsv}
              disabled={filteredSites.length === 0}
            >
              <FileSpreadsheet className="h-4 w-4" />
              CSV
            </Button>
            {isPmOrAdmin && (
              <Button onClick={openAddModal}>
                <Plus className="h-4 w-4" />
                Add Site
              </Button>
            )}
          </>
        }
      />

      {error && <ErrorBanner message={error} onRetry={load} />}

      {/* Filter Bar */}
      <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="relative max-w-md flex-1">
          <Search className="pointer-events-none absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-slate-400" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by site name, location, or manager…"
            className="h-10 w-full rounded-lg border border-slate-300 bg-white pr-3 pl-9 text-sm text-slate-900 placeholder:text-slate-400 focus:border-[#2563EB] focus:outline-none focus:ring-2 focus:ring-[#2563EB]/20"
          />
        </div>

        <div className="flex flex-wrap gap-1.5">
          {["All", ...SITE_STATUSES].map((status) => (
            <button
              key={status}
              type="button"
              onClick={() => setStatusFilter(status)}
              className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-colors cursor-pointer ${
                statusFilter === status
                  ? "bg-[#0B1628] text-white"
                  : "border border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
              }`}
            >
              {status}
            </button>
          ))}
        </div>
      </div>

      {/* Sites Grid */}
      {loading ? (
        <LoadingCards count={6} />
      ) : filteredSites.length === 0 ? (
        <EmptyState
          icon={Building2}
          title={sites.length === 0 ? "No Sites Yet" : "No Matching Sites"}
          description={
            sites.length === 0
              ? "Create your first construction site to start tracking workers, attendance, and materials."
              : "Try adjusting your search query or status filter."
          }
          action={
            isPmOrAdmin && sites.length === 0 ? (
              <Button onClick={openAddModal}>
                <Plus className="h-4 w-4" />
                Add Site
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
          {filteredSites.map((site) => {
            const progress = Number(site.progress ?? 0);
            return (
              <Link key={site.id} href={`/sites/${site.id}`} className="group block">
                <Card className="h-full transition-all group-hover:border-slate-300 group-hover:shadow-sm">
                  <CardContent className="flex h-full flex-col justify-between p-5">
                    <div>
                      <div className="flex items-start justify-between gap-2">
                        <div className="flex min-w-0 items-center gap-3">
                          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-blue-50 text-[#2563EB]">
                            <Building2 className="h-5 w-5" />
                          </div>
                          <div className="min-w-0">
                            <h3 className="truncate text-base font-semibold text-slate-900 group-hover:text-[#2563EB]">
                              {site.name}
                            </h3>
                            <p className="mt-0.5 flex items-center gap-1 truncate text-xs text-slate-500">
                              <MapPin className="h-3 w-3 shrink-0" />
                              {site.location || "No location specified"}
                            </p>
                          </div>
                        </div>
                        <StatusBadge status={site.status} />
                      </div>

                      <div className="mt-4 flex items-center gap-1.5 text-xs text-slate-600">
                        <UserCog className="h-3.5 w-3.5 text-slate-400" />
                        <span>
                          Manager:{" "}
                          <strong className="font-medium text-slate-800">
                            {site.project_manager || "Unassigned"}
                          </strong>
                        </span>
                      </div>
                    </div>

                    <div className="mt-5 border-t border-slate-100 pt-4">
                      <div className="flex items-center justify-between text-xs">
                        <span className="font-medium text-slate-500">
                          Completion Progress
                        </span>
                        <span className="font-semibold text-slate-900">
                          {progress}%
                        </span>
                      </div>
                      <div className="mt-1.5 h-2 w-full overflow-hidden rounded-full bg-slate-100">
                        <div
                          className={`h-full rounded-full transition-all ${
                            site.status === "Completed"
                              ? "bg-emerald-500"
                              : "bg-[#2563EB]"
                          }`}
                          style={{ width: `${Math.min(100, Math.max(0, progress))}%` }}
                        />
                      </div>

                      <div className="mt-3.5 flex items-center justify-between">
                        {isPmOrAdmin ? (
                          <button
                            type="button"
                            onClick={(e) => openEditModal(site, e)}
                            className="inline-flex items-center gap-1 text-xs font-medium text-slate-500 hover:text-slate-900 cursor-pointer"
                          >
                            <Pencil className="h-3 w-3" />
                            Edit
                          </button>
                        ) : (
                          <span />
                        )}
                        <span className="inline-flex items-center gap-1 text-xs font-medium text-[#2563EB]">
                          Open Site
                          <ArrowRight className="h-3.5 w-3.5" />
                        </span>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              </Link>
            );
          })}
        </div>
      )}

      {/* Add / Edit Site Modal */}
      <Modal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        title={editingSite ? "Edit Site" : "Add New Construction Site"}
        description="Site creation and editing is authorized for Project Managers and Administrators."
      >
        <form onSubmit={handleSave} className="space-y-4">
          <Input
            label="Site Name *"
            required
            error={formErrors.name}
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
            placeholder="e.g., Green Valley Phase II"
          />
          <Input
            label="Location / Address"
            error={formErrors.location}
            value={form.location}
            onChange={(e) => setForm({ ...form, location: e.target.value })}
            placeholder="e.g., Velachery, Chennai"
          />
          <Input
            label="Project Manager"
            error={formErrors.project_manager}
            value={form.project_manager}
            onChange={(e) => setForm({ ...form, project_manager: e.target.value })}
            placeholder="Manager name"
          />
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Select
              label="Site Status"
              value={form.status}
              onChange={(e) => setForm({ ...form, status: e.target.value })}
            >
              {SITE_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
            <Input
              label="Progress (0–100%)"
              type="number"
              min={0}
              max={100}
              error={formErrors.progress}
              value={form.progress}
              onChange={(e) =>
                setForm({ ...form, progress: Number(e.target.value) || 0 })
              }
            />
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
              {editingSite ? "Update Site" : "Create Site"}
            </Button>
          </div>
        </form>
      </Modal>
    </div>
  );
}

