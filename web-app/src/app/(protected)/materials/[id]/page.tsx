"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import {
  ArrowLeft,
  ArrowDownLeft,
  ArrowUpRight,
  Pencil,
  Trash2,
  Package,
  Shield,
  FileSpreadsheet,
} from "lucide-react";
import { downloadCsv } from "@/lib/csv";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAuth } from "@/context/auth-context";
import {
  deleteMaterial,
  fetchMaterialById,
  fetchMaterialTransactions,
  isLowStock,
  recordStockMovement,
  updateMaterial,
} from "@/lib/data/materials";
import { fetchActiveSites } from "@/lib/data/sites";
import type {
  MaterialRecord,
  MaterialTransactionRecord,
  MaterialTransactionType,
  SiteRecord,
} from "@/types/database";
import { formatDisplayDateTime, formatNumber, getErrorMessage } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input, Select } from "@/components/ui/input";
import { Modal } from "@/components/ui/modal";
import { StatusBadge } from "@/components/ui/badge";
import { EmptyState, ErrorBanner, LoadingTable } from "@/components/ui/states";
import { useToast } from "@/components/ui/toast";

export default function MaterialDetailPage() {
  const params = useParams();
  const router = useRouter();
  const materialId = String(params.id ?? "");
  const { isAdmin, isPmOrAdmin } = useAuth();
  const toast = useToast();

  const [material, setMaterial] = useState<MaterialRecord | null>(null);
  const [transactions, setTransactions] = useState<MaterialTransactionRecord[]>([]);
  const [sites, setSites] = useState<SiteRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Stock modal
  const [moveType, setMoveType] = useState<MaterialTransactionType | null>(null);
  const [qty, setQty] = useState("");
  const [siteName, setSiteName] = useState("");
  const [remarks, setRemarks] = useState("");
  const [savingMove, setSavingMove] = useState(false);

  // Edit modal
  const [editOpen, setEditOpen] = useState(false);
  const [editName, setEditName] = useState("");
  const [editSupplier, setEditSupplier] = useState("");
  const [savingEdit, setSavingEdit] = useState(false);

  // Ledger filter + Delete dialog
  const [ledgerFilter, setLedgerFilter] = useState<"ALL" | MaterialTransactionType>("ALL");
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);

  const filteredTransactions = useMemo(() => {
    if (ledgerFilter === "ALL") return transactions;
    return transactions.filter((t) => t.transaction_type === ledgerFilter);
  }, [transactions, ledgerFilter]);

  const load = useCallback(async () => {
    if (!materialId) return;
    setLoading(true);
    setError(null);
    try {
      const [matData, txnsData, sitesData] = await Promise.all([
        fetchMaterialById(materialId),
        fetchMaterialTransactions({ materialId }),
        fetchActiveSites(),
      ]);
      setMaterial(matData);
      setTransactions(txnsData);
      setSites(sitesData);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load material details."));
    } finally {
      setLoading(false);
    }
  }, [materialId]);

  useEffect(() => {
    load();
  }, [load]);

  async function handleStockSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!material || !moveType) return;
    const qtyNum = parseFloat(qty);
    if (Number.isNaN(qtyNum) || qtyNum <= 0) {
      toast.error("Enter a valid positive quantity.");
      return;
    }

    setSavingMove(true);
    try {
      await recordStockMovement({
        materialId: material.id,
        transactionType: moveType,
        quantity: qtyNum,
        siteName,
        remarks,
      });
      toast.success(
        moveType === "RECEIVED"
          ? "Stock received successfully."
          : "Stock usage logged successfully."
      );
      setMoveType(null);
      setQty("");
      setRemarks("");
      await load();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to log transaction."));
    } finally {
      setSavingMove(false);
    }
  }

  function openEdit() {
    if (!material) return;
    setEditName(material.name);
    setEditSupplier(material.supplier ?? "");
    setEditOpen(true);
  }

  async function handleEditSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!material) return;
    setSavingEdit(true);
    try {
      const updated = await updateMaterial(material.id, {
        name: editName,
        supplier: editSupplier,
      });
      setMaterial(updated);
      setEditOpen(false);
      toast.success("Material updated.");
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to update material."));
    } finally {
      setSavingEdit(false);
    }
  }

  async function handleDelete() {
    if (!material) return;
    setDeleting(true);
    try {
      await deleteMaterial(material.id, material.name);
      toast.success("Material deleted.");
      setDeleteDialogOpen(false);
      router.replace("/materials");
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to delete material."));
    } finally {
      setDeleting(false);
    }
  }

  function handleExportLedgerCsv() {
    if (!material) return;
    downloadCsv(
      `tsr_ledger_${material.name.replace(/[^a-z0-9]/gi, "_")}.csv`,
      ["Date", "Type", "Quantity", "Unit", "Site", "Remarks"],
      filteredTransactions.map((t) => [
        t.created_at,
        t.transaction_type,
        t.quantity,
        material.unit,
        t.site_name || "Central Stock",
        t.remarks || "",
      ])
    );
  }

  if (loading) return <LoadingTable rows={5} />;

  if (!material) {
    return (
      <div>
        <Link
          href="/materials"
          className="mb-4 inline-flex items-center gap-1.5 text-xs font-medium text-slate-500 hover:text-slate-900"
        >
          <ArrowLeft className="h-3.5 w-3.5" />
          Back to Materials
        </Link>
        {error && <ErrorBanner message={error} onRetry={load} />}
        <EmptyState
          icon={Package}
          title="Material Not Found"
          description="This material could not be located."
        />
      </div>
    );
  }

  const low = isLowStock(material);

  return (
    <div>
      <Link
        href="/materials"
        className="mb-4 inline-flex items-center gap-1.5 text-xs font-medium text-slate-500 hover:text-slate-900"
      >
        <ArrowLeft className="h-3.5 w-3.5" />
        Back to Materials Inventory
      </Link>

      {error && <ErrorBanner message={error} onRetry={load} />}

      <Card className="mb-6">
        <CardContent className="p-6">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <div className="flex flex-wrap items-center gap-2.5">
                <h1 className="text-xl font-bold text-slate-900">{material.name}</h1>
                <StatusBadge status={low ? "Low Stock" : "OK"} />
              </div>
              <p className="mt-1 text-xs text-slate-500">
                Unit: {material.unit} · Supplier: {material.supplier || "Unspecified"}
              </p>
            </div>

            <div className="flex flex-wrap gap-2">
              <Button
                size="sm"
                onClick={() => {
                  setMoveType("RECEIVED");
                  setQty("");
                  setSiteName("");
                  setRemarks("");
                }}
              >
                <ArrowDownLeft className="h-4 w-4" />
                Receive Stock
              </Button>
              <Button
                variant="secondary"
                size="sm"
                onClick={() => {
                  setMoveType("USED");
                  setQty("");
                  setSiteName(sites[0]?.name ?? "");
                  setRemarks("");
                }}
              >
                <ArrowUpRight className="h-4 w-4" />
                Use Stock
              </Button>
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

          <div className="mt-6 grid grid-cols-3 gap-3 border-t border-slate-100 pt-5">
            <div className="rounded-lg bg-slate-50 p-3.5">
              <p className="text-[11px] font-medium uppercase text-slate-500">
                Current Balance
              </p>
              <p className="mt-1 text-xl font-bold text-slate-900">
                {formatNumber(material.balance_qty)}{" "}
                <span className="text-xs font-medium text-slate-500">
                  {material.unit}
                </span>
              </p>
            </div>
            <div className="rounded-lg bg-emerald-50/60 p-3.5">
              <p className="text-[11px] font-medium uppercase text-emerald-700">
                Total Received
              </p>
              <p className="mt-1 text-xl font-bold text-emerald-800">
                {formatNumber(material.received_qty)}{" "}
                <span className="text-xs font-medium">{material.unit}</span>
              </p>
            </div>
            <div className="rounded-lg bg-blue-50/60 p-3.5">
              <p className="text-[11px] font-medium uppercase text-blue-700">
                Total Used
              </p>
              <p className="mt-1 text-xl font-bold text-blue-900">
                {formatNumber(material.used_qty)}{" "}
                <span className="text-xs font-medium">{material.unit}</span>
              </p>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Immutable Ledger */}
      <Card>
        <CardHeader>
          <div>
            <CardTitle>Transaction Ledger ({filteredTransactions.length})</CardTitle>
            <CardDescription className="inline-flex items-center gap-1">
              <Shield className="h-3 w-3" />
              Append-only ledger: recorded entries cannot be edited or deleted.
            </CardDescription>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            {(["ALL", "RECEIVED", "USED"] as const).map((mode) => (
              <button
                key={mode}
                type="button"
                onClick={() => setLedgerFilter(mode)}
                className={`rounded-md px-2.5 py-1 text-xs font-medium transition-colors cursor-pointer ${
                  ledgerFilter === mode
                    ? "bg-[#0B1628] text-white"
                    : "border border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
                }`}
              >
                {mode === "ALL" ? "All" : mode === "RECEIVED" ? "Received" : "Used"}
              </button>
            ))}
            <Button
              variant="outline"
              size="sm"
              onClick={handleExportLedgerCsv}
              disabled={filteredTransactions.length === 0}
            >
              <FileSpreadsheet className="h-3.5 w-3.5" />
              CSV
            </Button>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          {filteredTransactions.length === 0 ? (
            <p className="p-8 text-center text-xs text-slate-500">
              No stock transactions match this filter.
            </p>
          ) : (
            <div className="divide-y divide-slate-100">
              {filteredTransactions.map((txn) => {
                const isRec = txn.transaction_type === "RECEIVED";
                return (
                  <div
                    key={txn.id}
                    className="flex items-center justify-between gap-3 px-5 py-3.5"
                  >
                    <div className="flex items-center gap-3">
                      <div
                        className={`rounded-lg p-2 ${
                          isRec
                            ? "bg-emerald-50 text-emerald-700"
                            : "bg-blue-50 text-[#2563EB]"
                        }`}
                      >
                        {isRec ? (
                          <ArrowDownLeft className="h-4 w-4" />
                        ) : (
                          <ArrowUpRight className="h-4 w-4" />
                        )}
                      </div>
                      <div>
                        <p className="text-sm font-semibold text-slate-900">
                          {isRec ? "+" : "-"}
                          {formatNumber(txn.quantity)} {material.unit}
                        </p>
                        <p className="text-xs text-slate-500">
                          {txn.site_name || "Central Stock"}
                          {txn.remarks ? ` · ${txn.remarks}` : ""}
                        </p>
                      </div>
                    </div>
                    <div className="text-right">
                      <StatusBadge status={txn.transaction_type} />
                      <p className="mt-1 text-[11px] text-slate-400">
                        {formatDisplayDateTime(txn.created_at)}
                      </p>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Stock Movement Modal */}
      <Modal
        open={moveType !== null}
        onClose={() => setMoveType(null)}
        title={moveType === "RECEIVED" ? "Receive Stock" : "Use Stock"}
        description={`${material.name} · Current Balance: ${formatNumber(material.balance_qty)} ${material.unit}`}
      >
        <form onSubmit={handleStockSubmit} className="space-y-4">
          <Input
            label={`Quantity (${material.unit}) *`}
            type="number"
            step="any"
            min="0.01"
            required
            value={qty}
            onChange={(e) => setQty(e.target.value)}
          />
          <Select
            label={
              moveType === "USED"
                ? "Select Active Site (Required) *"
                : "Select Active Site (Optional)"
            }
            required={moveType === "USED"}
            value={siteName}
            onChange={(e) => setSiteName(e.target.value)}
          >
            <option value="">
              {moveType === "USED" ? "Select site…" : "None (Central Stock)"}
            </option>
            {sites.map((s) => (
              <option key={s.id} value={s.name}>
                {s.name}
              </option>
            ))}
          </Select>
          <Input
            label="Remarks"
            value={remarks}
            onChange={(e) => setRemarks(e.target.value)}
            placeholder="Notes or challan reference"
          />
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setMoveType(null)}>
              Cancel
            </Button>
            <Button type="submit" loading={savingMove}>
              Confirm Movement
            </Button>
          </div>
        </form>
      </Modal>

      {/* Edit Material Modal */}
      <Modal open={editOpen} onClose={() => setEditOpen(false)} title="Edit Material">
        <form onSubmit={handleEditSubmit} className="space-y-4">
          <Input
            label="Material Name *"
            required
            value={editName}
            onChange={(e) => setEditName(e.target.value)}
          />
          <Input
            label="Supplier"
            value={editSupplier}
            onChange={(e) => setEditSupplier(e.target.value)}
          />
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setEditOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={savingEdit}>
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
        title="Delete Material"
        description={`Permanently delete "${material.name}" from the inventory catalog? Only Administrators are permitted to delete catalog records.`}
        confirmLabel="Delete Material"
      />
    </div>
  );
}

