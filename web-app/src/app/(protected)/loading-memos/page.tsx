"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  FileText,
  Download,
  Trash2,
  Search,
  Truck,
  Plus,
  FileSpreadsheet,
} from "lucide-react";
import { downloadCsv } from "@/lib/csv";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { loadingMemoSchema, extractFieldErrors } from "@/lib/validation/schemas";
import { useAuth } from "@/context/auth-context";
import {
  createLoadingMemo,
  deleteLoadingMemo,
  fetchLoadingMemos,
} from "@/lib/data/loading-memos";
import { fetchMaterials } from "@/lib/data/materials";
import { downloadLoadingMemoPdf } from "@/lib/pdf/generators";
import { CameraCapture, type CapturedPhoto } from "@/components/camera-capture";
import {
  MATERIAL_UNITS,
  type LoadingMemoRecord,
  type MaterialRecord,
} from "@/types/database";
import { formatDisplayDate, formatNumber, getErrorMessage, todayIsoDate } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input, Select } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  EmptyState,
  ErrorBanner,
  LoadingTable,
  PageHeader,
} from "@/components/ui/states";
import { useToast } from "@/components/ui/toast";

function formatDdMmYyyy(isoDate: string): string {
  if (!isoDate) return "—";
  const parts = isoDate.split("-");
  if (parts.length === 3) return `${parts[2]}/${parts[1]}/${parts[0]}`;
  const d = new Date(isoDate);
  if (Number.isNaN(d.getTime())) return isoDate;
  return `${String(d.getDate()).padStart(2, "0")}/${String(d.getMonth() + 1).padStart(2, "0")}/${d.getFullYear()}`;
}

export default function LoadingMemosPage() {
  const { isAdmin, sites, selectedSiteId } = useAuth();
  const toast = useToast();

  const [memos, setMemos] = useState<LoadingMemoRecord[]>([]);
  const [materials, setMaterials] = useState<MaterialRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Create form
  const [siteId, setSiteId] = useState<string>(selectedSiteId || sites[0]?.id || "");
  const [date, setDate] = useState(todayIsoDate());
  const [vehicleNumber, setVehicleNumber] = useState("");
  const [materialId, setMaterialId] = useState("");
  const [customMaterialName, setCustomMaterialName] = useState("");
  const [quantity, setQuantity] = useState("");
  const [unit, setUnit] = useState<string>("Bags");
  const [remarks, setRemarks] = useState("");
  const [memoPhoto, setMemoPhoto] = useState<CapturedPhoto | null>(null);
  const [generating, setGenerating] = useState(false);
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});
  const [memoToDelete, setMemoToDelete] = useState<LoadingMemoRecord | null>(null);
  const [deletingMemo, setDeletingMemo] = useState(false);

  // Keep siteId in sync with active site if not explicitly set
  useEffect(() => {
    if (!siteId && (selectedSiteId || sites[0]?.id)) {
      setSiteId(selectedSiteId || sites[0]?.id || "");
    }
  }, [selectedSiteId, sites, siteId]);

  // History filters
  const [search, setSearch] = useState("");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [memosData, matsData] = await Promise.all([
        fetchLoadingMemos(),
        fetchMaterials(),
      ]);
      setMemos(memosData);
      setMaterials(matsData);
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load loading memos."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const selectedMaterial = useMemo(
    () => materials.find((m) => m.id === materialId) ?? null,
    [materials, materialId]
  );

  const effectiveMaterialName = selectedMaterial?.name ?? customMaterialName.trim();

  const filteredMemos = useMemo(() => {
    const q = search.trim().toLowerCase();
    return memos.filter((m) => {
      const matchesSearch =
        !q ||
        m.vehicle_number.toLowerCase().includes(q) ||
        m.material_name.toLowerCase().includes(q) ||
        m.generated_by.toLowerCase().includes(q);
      const matchesFrom = !fromDate || m.date >= fromDate;
      const matchesTo = !toDate || m.date <= toDate;
      return matchesSearch && matchesFrom && matchesTo;
    });
  }, [memos, search, fromDate, toDate]);

  async function handleGenerate(e: React.FormEvent) {
    e.preventDefault();
    const parsed = loadingMemoSchema.safeParse({
      date,
      vehicle_number: vehicleNumber,
      material_name: effectiveMaterialName,
      quantity,
      unit,
      remarks,
    });
    if (!parsed.success) {
      setFormErrors(extractFieldErrors(parsed.error));
      return;
    }
    const effectiveSiteId = siteId || selectedSiteId || sites[0]?.id;
    if (!effectiveSiteId) {
      setFormErrors({ site_id: "A construction site must be selected for the loading memo." });
      return;
    }

    setFormErrors({});
    setGenerating(true);
    try {
      const saved = await createLoadingMemo({
        site_id: effectiveSiteId,
        date: parsed.data.date,
        vehicle_number: parsed.data.vehicle_number,
        material_id: selectedMaterial?.id ?? null,
        material_name: parsed.data.material_name,
        quantity: parsed.data.quantity,
        unit: parsed.data.unit,
        remarks: parsed.data.remarks,
      });

      await downloadLoadingMemoPdf({
        ...saved,
        photoDataUrl: memoPhoto?.dataUrl ?? null,
      });
      toast.success(`Loading memo generated & downloaded for ${saved.vehicle_number}.`);

      setVehicleNumber("");
      setQuantity("");
      setRemarks("");
      setMemoPhoto(null);
      await load();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to create loading memo."));
    } finally {
      setGenerating(false);
    }
  }

  async function confirmDeleteMemo() {
    if (!memoToDelete) return;
    setDeletingMemo(true);
    try {
      await deleteLoadingMemo(memoToDelete);
      toast.success("Loading memo deleted.");
      setMemoToDelete(null);
      await load();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to delete loading memo."));
    } finally {
      setDeletingMemo(false);
    }
  }

  function handleExportCsv() {
    downloadCsv(
      `tsr_loading_memos_${new Date().toISOString().slice(0, 10)}.csv`,
      ["Date", "Vehicle Number", "Material", "Quantity", "Unit", "Generated By", "Remarks"],
      filteredMemos.map((m) => [
        m.date,
        m.vehicle_number,
        m.material_name,
        m.quantity,
        m.unit,
        m.generated_by,
        m.remarks ?? "",
      ])
    );
  }

  return (
    <div>
      <PageHeader
        title="Loading Memos"
        description="Generate printable dispatch loading memos and review transit history."
      />

      {error && <ErrorBanner message={error} onRetry={load} />}

      {/* Create Form + Live Dispatch Preview */}
      <div className="mb-6 grid grid-cols-1 gap-6 lg:grid-cols-5">
        <Card className="lg:col-span-3">
          <CardHeader>
            <div>
              <CardTitle>Generate Loading Memo</CardTitle>
              <CardDescription>
                Persists to <code>public.loading_memos</code> and downloads official A4 PDF
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleGenerate} className="space-y-4">
              <Select
                label="Construction Site *"
                value={siteId}
                onChange={(e) => setSiteId(e.target.value)}
                error={formErrors.site_id}
              >
                {sites.length === 0 ? (
                  <option value="">No sites available</option>
                ) : (
                  sites.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.name} ({s.location})
                    </option>
                  ))
                )}
              </Select>

              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Input
                  label="Dispatch Date *"
                  type="date"
                  required
                  error={formErrors.date}
                  value={date}
                  onChange={(e) => setDate(e.target.value)}
                />
                <Input
                  label="Vehicle Number *"
                  required
                  error={formErrors.vehicle_number}
                  value={vehicleNumber}
                  onChange={(e) => setVehicleNumber(e.target.value.toUpperCase())}
                  placeholder="e.g., TN69AJ1733"
                />
              </div>

              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Select
                  label="Select Material"
                  value={materialId}
                  onChange={(e) => {
                    const id = e.target.value;
                    setMaterialId(id);
                    const found = materials.find((m) => m.id === id);
                    if (found?.unit) setUnit(found.unit);
                  }}
                >
                  <option value="">— Custom / Manual Material —</option>
                  {materials.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.name} ({m.unit})
                    </option>
                  ))}
                </Select>

                {!materialId && (
                  <Input
                    label="Material Name *"
                    required
                    error={formErrors.material_name}
                    value={customMaterialName}
                    onChange={(e) => setCustomMaterialName(e.target.value)}
                    placeholder="e.g., Ramco Supergrade Cement"
                  />
                )}
              </div>

              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Input
                  label="Quantity *"
                  type="number"
                  step="any"
                  min="0.01"
                  required
                  error={formErrors.quantity}
                  value={quantity}
                  onChange={(e) => setQuantity(e.target.value)}
                  placeholder="e.g., 150"
                />
                <Select
                  label="Unit *"
                  value={unit}
                  onChange={(e) => setUnit(e.target.value)}
                >
                  {MATERIAL_UNITS.map((u) => (
                    <option key={u} value={u}>
                      {u}
                    </option>
                  ))}
                </Select>
              </div>

              <Input
                label="Remarks (Optional)"
                value={remarks}
                onChange={(e) => setRemarks(e.target.value)}
                placeholder="Delivery instructions or site destination"
              />

              <CameraCapture
                label="Attach Vehicle / Physical Delivery Challan Photo (Optional)"
                description="Snap a photo of the vehicle number plate or paper delivery challan"
                onPhotoCaptured={setMemoPhoto}
                currentPhoto={memoPhoto}
              />

              <Button type="submit" loading={generating} className="w-full sm:w-auto">
                <Plus className="h-4 w-4" />
                Save &amp; Download Memo PDF
              </Button>
            </form>
          </CardContent>
        </Card>

        {/* Live Document Preview */}
        <Card className="lg:col-span-2 bg-slate-50/50">
          <CardHeader className="flex flex-row items-center justify-between pb-3">
            <div>
              <CardTitle className="text-base font-bold text-slate-900">Document Preview</CardTitle>
              <CardDescription className="text-xs">
                Real-time visual replica of the official A4 dispatch instruction
              </CardDescription>
            </div>
            <Badge variant="neutral" className="border-slate-300 font-medium">A4 Format</Badge>
          </CardHeader>
          <CardContent>
            {/* White A4 Document Sheet strictly matching Reference Screenshot */}
            <div className="mx-auto max-w-[620px] rounded-lg border border-slate-300 bg-white p-8 sm:p-12 shadow-sm min-h-[500px]">
              <div>
                {/* 1. Header: Left JFS Logo | Right JFS Typography */}
                <div className="flex items-start justify-between gap-4">
                  <div className="h-16 w-24 shrink-0 overflow-hidden">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src="/jfstraders.png"
                      alt="JFS Traders"
                      className="h-full w-full object-contain object-left"
                    />
                  </div>
                  <div className="text-right">
                    <h2 className="text-xl sm:text-2xl font-light italic tracking-wider text-slate-900">
                      FELSHIA TRADERS
                    </h2>
                    <div className="my-1.5 ml-auto h-[1px] w-48 bg-slate-300" />
                    <p className="text-xs italic text-slate-700 text-center ml-auto w-48">
                      since 1996
                    </p>
                    <p className="text-xs italic text-slate-800 text-center ml-auto w-48">
                      ph: 967723589
                    </p>
                  </div>
                </div>

                {/* 2. Thin Horizontal Divider below Header */}
                <div className="my-6 border-b border-slate-300" />

                {/* 3. Dispatch Date Aligned Right */}
                <div className="text-right">
                  <span className="text-xs sm:text-sm font-semibold italic tracking-wider text-slate-900">
                    DATE: {formatDdMmYyyy(date)}
                  </span>
                </div>

                {/* 4. Main Centered Dispatch Instruction Sentence */}
                <div className="my-16 sm:my-24 px-4 text-center">
                  <p className="text-sm sm:text-base leading-relaxed text-slate-900 font-normal">
                    {vehicleNumber.trim() || effectiveMaterialName || quantity ? (
                      <>
                        In the vehicle number,
                        <span className="font-semibold text-slate-900">
                          {vehicleNumber.toUpperCase().trim() || "TN— — — —"}
                        </span>
                        ,{" "}
                        <span className="font-semibold text-slate-900">
                          {quantity || "0"} {unit}
                        </span>{" "}
                        of{" "}
                        <span className="font-semibold text-slate-900">
                          {effectiveMaterialName || "Selected Material"}
                        </span>{" "}
                        to be loaded.
                      </>
                    ) : (
                      <span className="text-slate-400 italic">
                        Enter dispatch details on the left to generate the loading memo instruction.
                      </span>
                    )}
                  </p>

                  {/* Optional Remarks if supplied */}
                  {remarks.trim() && (
                    <p className="mt-4 text-xs italic text-slate-500">
                      Remarks: {remarks.trim()}
                    </p>
                  )}
                </div>

                {/* Optional Attached Photo */}
                {memoPhoto && (
                  <div className="my-6 flex justify-center">
                    <div className="max-w-xs rounded border border-slate-200 p-1.5">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={memoPhoto.dataUrl}
                        alt="Captured Delivery Challan"
                        className="max-h-36 w-auto rounded object-contain"
                      />
                    </div>
                  </div>
                )}
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Memo History */}
      <Card>
        <CardHeader>
          <div>
            <CardTitle>Dispatch History ({filteredMemos.length})</CardTitle>
            <CardDescription>
              Re-download any past loading memo PDF. Deletion is restricted to Administrators.
            </CardDescription>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={handleExportCsv}
            disabled={filteredMemos.length === 0}
          >
            <FileSpreadsheet className="h-3.5 w-3.5" />
            Export CSV
          </Button>
        </CardHeader>
        <CardContent>
          <div className="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div className="relative">
              <Search className="pointer-events-none absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-slate-400" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search vehicle, material, issuer…"
                className="h-10 w-full rounded-lg border border-slate-300 bg-white pr-3 pl-9 text-sm text-slate-900 focus:border-[#2563EB] focus:outline-none"
              />
            </div>
            <Input
              type="date"
              aria-label="From date"
              value={fromDate}
              onChange={(e) => setFromDate(e.target.value)}
            />
            <Input
              type="date"
              aria-label="To date"
              value={toDate}
              onChange={(e) => setToDate(e.target.value)}
            />
          </div>

          {loading ? (
            <LoadingTable rows={4} />
          ) : filteredMemos.length === 0 ? (
            <EmptyState
              icon={FileText}
              title="No Loading Memos Found"
              description="Generate a loading memo above to record a vehicle dispatch."
            />
          ) : (
            <>
              {/* Desktop Table */}
              <div className="hidden overflow-x-auto md:block">
                <table className="w-full text-left text-sm">
                  <thead className="border-b border-slate-200 bg-slate-50 text-xs font-semibold uppercase text-slate-500">
                    <tr>
                      <th className="px-4 py-3">Date</th>
                      <th className="px-4 py-3">Vehicle</th>
                      <th className="px-4 py-3">Material &amp; Qty</th>
                      <th className="px-4 py-3">Generated By</th>
                      <th className="px-4 py-3 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {filteredMemos.map((memo) => (
                      <tr key={memo.id} className="hover:bg-slate-50/70">
                        <td className="px-4 py-3 text-xs font-medium text-slate-600">
                          {formatDisplayDate(memo.date)}
                        </td>
                        <td className="px-4 py-3">
                          <Badge variant="navy">
                            <Truck className="h-3 w-3" />
                            {memo.vehicle_number}
                          </Badge>
                        </td>
                        <td className="px-4 py-3">
                          <div className="font-semibold text-slate-900">
                            {memo.material_name} — {formatNumber(memo.quantity)}{" "}
                            {memo.unit}
                          </div>
                          {memo.remarks && (
                            <p className="text-xs text-slate-500">{memo.remarks}</p>
                          )}
                        </td>
                        <td className="px-4 py-3 text-xs text-slate-600">
                          {memo.generated_by}
                        </td>
                        <td className="px-4 py-3 text-right">
                          <div className="inline-flex items-center gap-1.5">
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => downloadLoadingMemoPdf(memo)}
                            >
                              <Download className="h-3.5 w-3.5" />
                              PDF
                            </Button>
                            {isAdmin && (
                              <Button
                                variant="ghost"
                                size="icon"
                                onClick={() => setMemoToDelete(memo)}
                                title="Delete loading memo"
                              >
                                <Trash2 className="h-4 w-4 text-red-600" />
                              </Button>
                            )}
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Mobile Cards */}
              <div className="space-y-3 md:hidden">
                {filteredMemos.map((memo) => (
                  <div
                    key={memo.id}
                    className="rounded-xl border border-slate-200 bg-white p-4"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <Badge variant="navy">
                        <Truck className="h-3 w-3" />
                        {memo.vehicle_number}
                      </Badge>
                      <span className="text-xs text-slate-500">
                        {formatDisplayDate(memo.date)}
                      </span>
                    </div>
                    <p className="mt-2.5 text-sm font-semibold text-slate-900">
                      {memo.material_name} — {formatNumber(memo.quantity)} {memo.unit}
                    </p>
                    {memo.remarks && (
                      <p className="mt-1 text-xs text-slate-500">{memo.remarks}</p>
                    )}
                    <div className="mt-3 flex items-center justify-between border-t border-slate-100 pt-2.5">
                      <span className="truncate text-[11px] text-slate-400">
                        {memo.generated_by}
                      </span>
                      <div className="flex items-center gap-1.5">
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => downloadLoadingMemoPdf(memo)}
                        >
                          <Download className="h-3.5 w-3.5" />
                          PDF
                        </Button>
                        {isAdmin && (
                          <Button
                            variant="ghost"
                            size="icon"
                            onClick={() => setMemoToDelete(memo)}
                            title="Delete loading memo"
                          >
                            <Trash2 className="h-4 w-4 text-red-600" />
                          </Button>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </>
          )}
        </CardContent>
      </Card>

      <ConfirmDialog
        open={Boolean(memoToDelete)}
        onClose={() => setMemoToDelete(null)}
        onConfirm={confirmDeleteMemo}
        loading={deletingMemo}
        title="Delete Loading Memo"
        description={`Permanently delete dispatch memo for vehicle "${memoToDelete?.vehicle_number ?? ""}" (${memoToDelete?.material_name ?? ""})? Only Administrators can delete loading memos.`}
        confirmLabel="Delete Memo"
      />
    </div>
  );
}

