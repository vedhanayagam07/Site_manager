"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  Package,
  Plus,
  ArrowLeftRight,
  Search,
  AlertTriangle,
  FileText,
  ArrowRight,
  FileSpreadsheet,
} from "lucide-react";
import { downloadCsv } from "@/lib/csv";
import {
  materialFormSchema,
  stockMovementSchema,
  extractFieldErrors,
} from "@/lib/validation/schemas";
import { useAuth } from "@/context/auth-context";
import {
  createMaterial,
  fetchMaterials,
  isLowStock,
  recordStockMovement,
} from "@/lib/data/materials";
import { fetchActiveSites } from "@/lib/data/sites";
import {
  MATERIAL_UNITS,
  type MaterialRecord,
  type MaterialTransactionType,
  type SiteRecord,
} from "@/types/database";
import { formatNumber, getErrorMessage } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input, Select } from "@/components/ui/input";
import { Modal } from "@/components/ui/modal";
import { Badge, StatusBadge } from "@/components/ui/badge";
import {
  EmptyState,
  ErrorBanner,
  LoadingTable,
  PageHeader,
} from "@/components/ui/states";
import { useToast } from "@/components/ui/toast";
import { CameraCapture, type CapturedPhoto } from "@/components/camera-capture";

export default function MaterialsPage() {
  const { isPmOrAdmin, selectedSiteId } = useAuth();
  const toast = useToast();

  const [materials, setMaterials] = useState<MaterialRecord[]>([]);
  const [sites, setSites] = useState<SiteRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [onlyLowStock, setOnlyLowStock] = useState(false);

  // Add Material Modal (PM/Admin)
  const [addModalOpen, setAddModalOpen] = useState(false);
  const [matName, setMatName] = useState("");
  const [matUnit, setMatUnit] = useState<string>("Bags");
  const [matSupplier, setMatSupplier] = useState("");
  const [matSiteId, setMatSiteId] = useState("");
  const [savingMat, setSavingMat] = useState(false);
  const [matErrors, setMatErrors] = useState<Record<string, string>>({});

  // Stock Movement Modal
  const [txnModalOpen, setTxnModalOpen] = useState(false);
  const [txnMatId, setTxnMatId] = useState("");
  const [txnType, setTxnType] = useState<MaterialTransactionType>("RECEIVED");
  const [txnQty, setTxnQty] = useState("");
  const [txnSiteName, setTxnSiteName] = useState("");
  const [txnRemarks, setTxnRemarks] = useState("");
  const [challanPhoto, setChallanPhoto] = useState<CapturedPhoto | null>(null);
  const [savingTxn, setSavingTxn] = useState(false);
  const [txnErrors, setTxnErrors] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [matsData, sitesData] = await Promise.all([
        fetchMaterials(selectedSiteId || undefined),
        fetchActiveSites(),
      ]);
      setMaterials(matsData);
      setSites(sitesData);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load materials inventory."));
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
    return materials.filter((m) => {
      const matchesSearch =
        !q ||
        m.name.toLowerCase().includes(q) ||
        (m.supplier ?? "").toLowerCase().includes(q);
      const matchesLow = !onlyLowStock || isLowStock(m);
      return matchesSearch && matchesLow;
    });
  }, [materials, search, onlyLowStock]);

  const lowStockCount = useMemo(
    () => materials.filter((m) => isLowStock(m)).length,
    [materials]
  );

  function openAddMaterial() {
    setMatErrors({});
    setMatName("");
    setMatUnit("Bags");
    setMatSupplier("");
    setMatSiteId(selectedSiteId || sites[0]?.id || "");
    setAddModalOpen(true);
  }

  function openStockModal(preselectedMaterialId?: string) {
    setTxnErrors({});
    setTxnMatId(preselectedMaterialId ?? materials[0]?.id ?? "");
    setTxnType("RECEIVED");
    setTxnQty("");
    setTxnSiteName(selectedSiteId ? siteNameById.get(selectedSiteId) ?? "" : "");
    setTxnRemarks("");
    setTxnModalOpen(true);
  }

  function handleExportCsv() {
    downloadCsv(
      `tsr_materials_inventory_${new Date().toISOString().slice(0, 10)}.csv`,
      ["Material", "Site", "Supplier", "Unit", "Received", "Used", "Balance", "Status"],
      filtered.map((m) => [
        m.name,
        (m.site_id && siteNameById.get(m.site_id)) || "Central",
        m.supplier ?? "",
        m.unit,
        m.received_qty ?? 0,
        m.used_qty ?? 0,
        m.balance_qty ?? 0,
        isLowStock(m) ? "LOW STOCK" : "OK",
      ])
    );
  }

  async function handleCreateMaterial(e: React.FormEvent) {
    e.preventDefault();
    const parsed = materialFormSchema.safeParse({
      name: matName,
      unit: matUnit,
      supplier: matSupplier,
      site_id: matSiteId,
    });
    if (!parsed.success) {
      setMatErrors(extractFieldErrors(parsed.error));
      return;
    }
    setMatErrors({});
    setSavingMat(true);
    try {
      await createMaterial(parsed.data);
      toast.success("Material added to catalog.");
      setAddModalOpen(false);
      await load();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to create material."));
    } finally {
      setSavingMat(false);
    }
  }

  async function handleStockMovement(e: React.FormEvent) {
    e.preventDefault();
    const parsed = stockMovementSchema.safeParse({
      materialId: txnMatId,
      transactionType: txnType,
      quantity: txnQty,
      siteName: txnSiteName,
      remarks: txnRemarks,
    });
    if (!parsed.success) {
      setTxnErrors(extractFieldErrors(parsed.error));
      return;
    }
    setTxnErrors({});
    setSavingTxn(true);
    try {
      await recordStockMovement(parsed.data);
      toast.success(
        txnType === "RECEIVED"
          ? "Stock received and balance updated."
          : "Stock usage logged and balance updated."
      );
      setTxnModalOpen(false);
      await load();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to log stock transaction."));
    } finally {
      setSavingTxn(false);
    }
  }

  return (
    <div>
      <PageHeader
        title="Materials Inventory"
        description={`${materials.length} items tracked · ${lowStockCount} low stock alert${lowStockCount === 1 ? "" : "s"}`}
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
            <Link href="/loading-memos">
              <Button variant="outline" size="sm">
                <FileText className="h-4 w-4" />
                Loading Memo
              </Button>
            </Link>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => openStockModal()}
              disabled={materials.length === 0}
            >
              <ArrowLeftRight className="h-4 w-4" />
              Log Stock Movement
            </Button>
            {isPmOrAdmin && (
              <Button size="sm" onClick={openAddMaterial}>
                <Plus className="h-4 w-4" />
                Add Material
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
            placeholder="Search by material name or supplier…"
            className="h-10 w-full rounded-lg border border-slate-300 bg-white pr-3 pl-9 text-sm text-slate-900 placeholder:text-slate-400 focus:border-[#2563EB] focus:outline-none focus:ring-2 focus:ring-[#2563EB]/20"
          />
        </div>

        <button
          type="button"
          onClick={() => setOnlyLowStock((prev) => !prev)}
          className={`inline-flex items-center gap-1.5 rounded-lg border px-3 py-2 text-xs font-semibold transition-colors cursor-pointer ${
            onlyLowStock
              ? "border-red-300 bg-red-50 text-red-700"
              : "border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
          }`}
        >
          <AlertTriangle className="h-3.5 w-3.5" />
          Low Stock Only ({lowStockCount})
        </button>
      </div>

      {loading ? (
        <LoadingTable rows={6} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={Package}
          title={materials.length === 0 ? "No Materials Added" : "No Matching Materials"}
          description={
            materials.length === 0
              ? "Add construction materials to track balances and append-only stock transactions."
              : "Try clearing your search or low-stock filter."
          }
          action={
            isPmOrAdmin && materials.length === 0 ? (
              <Button onClick={openAddMaterial}>
                <Plus className="h-4 w-4" />
                Add Material
              </Button>
            ) : undefined
          }
        />
      ) : (
        <>
          {/* Desktop Table */}
          <Card className="hidden overflow-hidden md:block">
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead className="border-b border-slate-200 bg-slate-50 text-xs font-semibold uppercase text-slate-500">
                  <tr>
                    <th className="px-5 py-3">Material</th>
                    <th className="px-5 py-3">Site</th>
                    <th className="px-5 py-3">Supplier</th>
                    <th className="px-5 py-3 text-right">Received</th>
                    <th className="px-5 py-3 text-right">Used</th>
                    <th className="px-5 py-3 text-right">Balance</th>
                    <th className="px-5 py-3">Status</th>
                    <th className="px-5 py-3 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {filtered.map((m) => {
                    const low = isLowStock(m);
                    return (
                      <tr key={m.id} className="hover:bg-slate-50/70">
                        <td className="px-5 py-3.5">
                          <Link
                            href={`/materials/${m.id}`}
                            className="font-semibold text-slate-900 hover:text-[#2563EB]"
                          >
                            {m.name}
                          </Link>
                        </td>
                        <td className="px-5 py-3.5 text-xs text-slate-600">
                          {(m.site_id && siteNameById.get(m.site_id)) || "Central"}
                        </td>
                        <td className="px-5 py-3.5 text-xs text-slate-600">
                          {m.supplier || "—"}
                        </td>
                        <td className="px-5 py-3.5 text-right text-xs text-slate-600">
                          {formatNumber(m.received_qty)} {m.unit}
                        </td>
                        <td className="px-5 py-3.5 text-right text-xs text-slate-600">
                          {formatNumber(m.used_qty)} {m.unit}
                        </td>
                        <td className="px-5 py-3.5 text-right font-bold text-slate-900">
                          {formatNumber(m.balance_qty)} {m.unit}
                        </td>
                        <td className="px-5 py-3.5">
                          <StatusBadge status={low ? "Low Stock" : "OK"} />
                        </td>
                        <td className="px-5 py-3.5 text-right">
                          <div className="inline-flex items-center gap-2">
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => openStockModal(m.id)}
                            >
                              Move
                            </Button>
                            <Link
                              href={`/materials/${m.id}`}
                              className="inline-flex items-center gap-1 text-xs font-medium text-[#2563EB] hover:underline"
                            >
                              Ledger
                              <ArrowRight className="h-3.5 w-3.5" />
                            </Link>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </Card>

          {/* Mobile Cards */}
          <div className="space-y-3 md:hidden">
            {filtered.map((m) => {
              const low = isLowStock(m);
              return (
                <Link key={m.id} href={`/materials/${m.id}`} className="block">
                  <Card className={low ? "border-red-200" : undefined}>
                    <CardContent className="p-4">
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <p className="text-sm font-semibold text-slate-900">
                            {m.name}
                          </p>
                          <p className="text-xs text-slate-500">
                            {(m.site_id && siteNameById.get(m.site_id)) || "Central"}{" "}
                            {m.supplier ? `· ${m.supplier}` : ""}
                          </p>
                        </div>
                        <StatusBadge status={low ? "Low Stock" : "OK"} />
                      </div>
                      <div className="mt-3 flex items-center justify-between border-t border-slate-100 pt-2.5 text-xs">
                        <span className="font-bold text-slate-900">
                          {formatNumber(m.balance_qty)} {m.unit} in stock
                        </span>
                        <Badge variant="neutral">
                          In: {formatNumber(m.received_qty)} · Out: {formatNumber(m.used_qty)}
                        </Badge>
                      </div>
                    </CardContent>
                  </Card>
                </Link>
              );
            })}
          </div>
        </>
      )}

      {/* Add Material Modal */}
      <Modal
        open={addModalOpen}
        onClose={() => setAddModalOpen(false)}
        title="Add Master Material"
        description="Catalog creation is permitted for Project Managers and Administrators."
      >
        <form onSubmit={handleCreateMaterial} className="space-y-4">
          <Input
            label="Material Name *"
            required
            error={matErrors.name}
            value={matName}
            onChange={(e) => setMatName(e.target.value)}
            placeholder="e.g., Ramco Supergrade Cement"
          />
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Select
              label="Unit *"
              error={matErrors.unit}
              value={matUnit}
              onChange={(e) => setMatUnit(e.target.value)}
            >
              {MATERIAL_UNITS.map((u) => (
                <option key={u} value={u}>
                  {u}
                </option>
              ))}
            </Select>
            <Select
              label="Assign to Site *"
              required
              error={matErrors.site_id}
              value={matSiteId}
              onChange={(e) => setMatSiteId(e.target.value)}
            >
              <option value="">Select a site…</option>
              {sites.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </Select>
          </div>
          <Input
            label="Supplier (Optional)"
            value={matSupplier}
            onChange={(e) => setMatSupplier(e.target.value)}
            placeholder="e.g., Felshia Traders"
          />
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setAddModalOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={savingMat}>
              Save Material
            </Button>
          </div>
        </form>
      </Modal>

      {/* Stock Movement Modal */}
      <Modal
        open={txnModalOpen}
        onClose={() => setTxnModalOpen(false)}
        title="Log Stock Movement"
        description="Transactions are recorded in the immutable material_transactions ledger."
      >
        <form onSubmit={handleStockMovement} className="space-y-4">
          <Select
            label="Material *"
            required
            value={txnMatId}
            onChange={(e) => setTxnMatId(e.target.value)}
          >
            {materials.map((m) => (
              <option key={m.id} value={m.id}>
                {m.name} (Bal: {formatNumber(m.balance_qty)} {m.unit})
              </option>
            ))}
          </Select>

          <div className="grid grid-cols-2 gap-2">
            {(["RECEIVED", "USED"] as MaterialTransactionType[]).map((type) => (
              <button
                key={type}
                type="button"
                onClick={() => setTxnType(type)}
                className={`rounded-lg border py-2.5 text-xs font-semibold transition-colors cursor-pointer ${
                  txnType === type
                    ? type === "RECEIVED"
                      ? "border-emerald-600 bg-emerald-600 text-white"
                      : "border-[#2563EB] bg-[#2563EB] text-white"
                    : "border-slate-200 bg-white text-slate-700 hover:bg-slate-50"
                }`}
              >
                {type === "RECEIVED" ? "Stock Received (IN)" : "Stock Used (OUT)"}
              </button>
            ))}
          </div>

          <Input
            label="Quantity *"
            type="number"
            step="any"
            min="0.01"
            required
            error={txnErrors.quantity}
            value={txnQty}
            onChange={(e) => setTxnQty(e.target.value)}
            placeholder="Enter quantity"
          />

          <Select
            label={txnType === "USED" ? "Active Site (Required) *" : "Active Site (Optional)"}
            required={txnType === "USED"}
            error={txnErrors.siteName}
            value={txnSiteName}
            onChange={(e) => setTxnSiteName(e.target.value)}
          >
            <option value="">
              {txnType === "USED" ? "Select site…" : "None (Central Stock)"}
            </option>
            {sites.map((s) => (
              <option key={s.id} value={s.name}>
                {s.name}
              </option>
            ))}
          </Select>

          <Input
            label="Remarks"
            value={txnRemarks}
            onChange={(e) => setTxnRemarks(e.target.value)}
            placeholder="Challan number, vehicle info, or usage notes"
          />

          {txnType === "RECEIVED" && (
            <CameraCapture
              label="Attach Delivery Challan / Supplier Invoice Photo (Optional)"
              description="Snap a photo of the delivery challan or weighbridge receipt"
              onPhotoCaptured={setChallanPhoto}
              currentPhoto={challanPhoto}
            />
          )}

          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setTxnModalOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={savingTxn}>
              Save Transaction
            </Button>
          </div>
        </form>
      </Modal>
    </div>
  );
}

