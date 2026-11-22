import { jsPDF } from "jspdf";
import autoTable from "jspdf-autotable";
import type {
  ActivityLogRecord,
  LoadingMemoRecord,
  MaterialRecord,
  MaterialTransactionRecord,
  SiteAttendanceRecord,
  SiteRecord,
  WorkerRecord,
} from "@/types/database";
import { formatDisplayDate, formatDisplayDateTime, formatNumber } from "@/lib/utils";

async function loadImageDataUrl(path: string): Promise<string | null> {
  try {
    const res = await fetch(path);
    if (!res.ok) return null;
    const blob = await res.blob();
    return await new Promise<string>((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(String(reader.result));
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  } catch {
    return null;
  }
}

function formatDdMmYyyy(isoDate: string): string {
  const d = new Date(isoDate);
  if (Number.isNaN(d.getTime())) return isoDate;
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yyyy = d.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
}

export interface LoadingMemoPdfOptions {
  date: string;
  vehicle_number: string;
  material_name: string;
  quantity: number;
  unit: string;
  remarks?: string | null;
  id?: string;
  generated_by?: string | null;
  destination?: string | null;
  photoDataUrl?: string | null;
}

/**
 * Generates an elegant, professional A4 portrait Loading Memo PDF
 * strictly matching the minimalist transport dispatch layout.
 */
export async function downloadLoadingMemoPdf(
  memo: LoadingMemoPdfOptions
): Promise<void> {
  const doc = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
  const pageWidth = doc.internal.pageSize.getWidth(); // 595.28 pt
  const pageHeight = doc.internal.pageSize.getHeight(); // 841.89 pt
  const margin = 50;
  const contentWidth = pageWidth - margin * 2;

  // Load JFS Traders primary logo
  const jfsLogo = await loadImageDataUrl("/jfstraders.png");

  // ZERO watermarks across the document!

  // 1. Header Section
  const headerTop = 46;
  const logoHeight = 54;
  const logoWidth = logoHeight * 1.5; // 81 pt (3:2 aspect ratio)

  // LEFT: JFS Traders Logo
  if (jfsLogo) {
    doc.addImage(jfsLogo, "PNG", margin, headerTop, logoWidth, logoHeight);
  }

  // RIGHT: FELSHIA TRADERS Typography
  const rightX = pageWidth - margin;
  doc.setTextColor(17, 24, 39); // Slate-900 #111827
  doc.setFont("helvetica", "italic");
  doc.setFontSize(22);
  doc.text("FELSHIA TRADERS", rightX, headerTop + 22, { align: "right" });

  const titleWidth = doc.getTextWidth("FELSHIA TRADERS");
  const blockCenterX = rightX - titleWidth / 2;

  // Thin underline beneath FELSHIA TRADERS
  doc.setDrawColor(209, 213, 219); // Gray-300
  doc.setLineWidth(1);
  doc.line(rightX - titleWidth, headerTop + 28, rightX, headerTop + 28);

  // Subtitles
  doc.setTextColor(31, 41, 55);
  doc.setFont("helvetica", "italic");
  doc.setFontSize(11);
  doc.text("since 1996", blockCenterX, headerTop + 42, { align: "center" });

  doc.setFontSize(11.5);
  doc.text("ph: 967723589", blockCenterX, headerTop + 57, { align: "center" });

  // 2. Horizontal Divider below Header
  const dividerY = headerTop + logoHeight + 16; // ~116 pt
  doc.setDrawColor(156, 163, 175); // Slate-400
  doc.setLineWidth(1);
  doc.line(margin, dividerY, pageWidth - margin, dividerY);

  // 3. Dispatch Date Aligned Right
  const dateY = dividerY + 36; // ~152 pt
  doc.setTextColor(17, 24, 39);
  doc.setFont("helvetica", "italic");
  doc.setFontSize(11);
  doc.text(`DATE: ${formatDdMmYyyy(memo.date)}`, rightX, dateY, { align: "right" });

  // 4. Centered Dispatch Instruction Sentence (Body)
  const cleanVehicle = memo.vehicle_number.toUpperCase().trim() || "TN— — — —";
  const qtyDisplay = Number.isInteger(Number(memo.quantity))
    ? String(Math.trunc(Number(memo.quantity)))
    : String(memo.quantity);

  const sentence = `In the vehicle number,${cleanVehicle}, ${qtyDisplay} ${memo.unit} of ${memo.material_name} to be loaded.`;

  const bodyY = dateY + 95; // ~247 pt
  doc.setTextColor(17, 24, 39);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(13);

  const wrappedSentence = doc.splitTextToSize(sentence, contentWidth - 40);
  doc.text(wrappedSentence, pageWidth / 2, bodyY, { align: "center", lineHeightFactor: 1.6 });

  // 5. Optional Remarks & Delivery Instructions (only when supplied)
  let currentY = bodyY + wrappedSentence.length * 22 + 25;
  if (memo.remarks?.trim()) {
    doc.setTextColor(75, 85, 99);
    doc.setFont("helvetica", "italic");
    doc.setFontSize(9.5);
    const remarksText = `Remarks: ${memo.remarks.trim()}`;
    const wrappedRemarks = doc.splitTextToSize(remarksText, contentWidth - 60);
    doc.text(wrappedRemarks, pageWidth / 2, currentY, { align: "center", lineHeightFactor: 1.4 });
    currentY += wrappedRemarks.length * 16 + 25;
  }

  // Optional Attached Photo (if supplied)
  if (memo.photoDataUrl) {
    try {
      const maxPhotoW = 200;
      const maxPhotoH = 130;
      const photoX = (pageWidth - maxPhotoW) / 2;
      doc.setDrawColor(229, 231, 235);
      doc.rect(photoX - 4, currentY - 4, maxPhotoW + 8, maxPhotoH + 8, "S");
      doc.addImage(memo.photoDataUrl, "JPEG", photoX, currentY, maxPhotoW, maxPhotoH);
      currentY += maxPhotoH + 30;
    } catch {
      // Continue gracefully if image rendering fails
    }
  }

  // Document ends cleanly after the dispatch instruction, optional remarks, and optional photo.
  const cleanVehicleFileName = memo.vehicle_number.replace(/[^A-Za-z0-9_-]/g, "") || "Dispatch";
  doc.save(`Loading-Memo-${cleanVehicleFileName}-${memo.date}.pdf`);
}

function addReportHeader(doc: jsPDF, title: string, subtitle?: string): number {
  doc.setFillColor(11, 22, 40);
  doc.rect(0, 0, doc.internal.pageSize.getWidth(), 72, "F");

  doc.setTextColor(255, 255, 255);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(16);
  doc.text(`TSR BUILDERS — ${title}`, 40, 32);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(9.5);
  doc.setTextColor(203, 213, 225);
  const generated = `Generated: ${formatDisplayDateTime(new Date().toISOString())}`;
  doc.text(subtitle ? `${subtitle}  |  ${generated}` : generated, 40, 52);

  doc.setTextColor(15, 23, 42);
  return 92;
}

export function exportWorkerReportPdf(workers: WorkerRecord[]): void {
  const doc = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
  const activeCount = workers.filter((w) => w.status === "Active").length;
  const startY = addReportHeader(
    doc,
    "Worker Directory Report",
    `Total: ${workers.length} | Active: ${activeCount} | Inactive: ${workers.length - activeCount}`
  );

  autoTable(doc, {
    startY,
    head: [["Name", "Role", "Phone", "Skill", "Site", "Status"]],
    body: workers.map((w) => [
      w.name,
      w.role ?? "—",
      w.phone ?? "—",
      w.skill ?? "—",
      w.assigned_site ?? "Unassigned",
      w.status,
    ]),
    headStyles: { fillColor: [11, 22, 40], textColor: [255, 255, 255], fontSize: 9 },
    bodyStyles: { fontSize: 8.5, textColor: [30, 41, 59] },
    alternateRowStyles: { fillColor: [248, 250, 252] },
  });

  doc.save(`tsr_worker_report_${new Date().toISOString().slice(0, 10)}.pdf`);
}

export function exportSiteReportPdf(sites: SiteRecord[]): void {
  const doc = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
  const activeCount = sites.filter((s) =>
    ["active", "in progress"].includes((s.status ?? "").toLowerCase())
  ).length;
  const startY = addReportHeader(
    doc,
    "Site Portfolio Report",
    `Total Sites: ${sites.length} | Active: ${activeCount}`
  );

  autoTable(doc, {
    startY,
    head: [["Site Name", "Location", "Project Manager", "Status", "Progress"]],
    body: sites.map((s) => [
      s.name,
      s.location ?? "—",
      s.project_manager ?? "—",
      s.status,
      `${s.progress ?? 0}%`,
    ]),
    headStyles: { fillColor: [11, 22, 40], textColor: [255, 255, 255], fontSize: 9 },
    bodyStyles: { fontSize: 8.5, textColor: [30, 41, 59] },
    alternateRowStyles: { fillColor: [248, 250, 252] },
  });

  doc.save(`tsr_site_report_${new Date().toISOString().slice(0, 10)}.pdf`);
}

export function exportAttendanceReportPdf(
  records: SiteAttendanceRecord[],
  periodLabel: string
): void {
  const doc = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
  const present = records.filter((r) => r.status === "Present").length;
  const absent = records.filter((r) => r.status === "Absent").length;
  const halfDay = records.filter((r) => r.status === "Half Day").length;
  const startY = addReportHeader(
    doc,
    `Attendance Report (${periodLabel})`,
    `Records: ${records.length} | Present: ${present} | Half Day: ${halfDay} | Absent: ${absent}`
  );

  autoTable(doc, {
    startY,
    head: [["Date", "Worker", "Role", "Site", "Status"]],
    body: records.map((r) => [
      formatDisplayDate(r.attendance_date),
      r.workers?.name ?? "—",
      r.workers?.role ?? "—",
      r.sites?.name ?? "Central",
      r.status,
    ]),
    headStyles: { fillColor: [11, 22, 40], textColor: [255, 255, 255], fontSize: 9 },
    bodyStyles: { fontSize: 8.5, textColor: [30, 41, 59] },
    alternateRowStyles: { fillColor: [248, 250, 252] },
  });

  doc.save(`tsr_attendance_report_${new Date().toISOString().slice(0, 10)}.pdf`);
}

export function exportMaterialReportPdf(
  materials: MaterialRecord[],
  transactions: MaterialTransactionRecord[]
): void {
  const doc = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
  const lowStock = materials.filter(
    (m) => Number(m.balance_qty ?? 0) <= Number(m.minimum_stock ?? 10)
  ).length;
  const startY = addReportHeader(
    doc,
    "Material Inventory Report",
    `Catalog Items: ${materials.length} | Low Stock Alerts: ${lowStock} | Recent Txns: ${transactions.length}`
  );

  autoTable(doc, {
    startY,
    head: [["Material", "Unit", "Received", "Used", "Balance", "Status", "Supplier"]],
    body: materials.map((m) => {
      const bal = Number(m.balance_qty ?? 0);
      const min = Number(m.minimum_stock ?? 10);
      return [
        m.name,
        m.unit,
        formatNumber(m.received_qty),
        formatNumber(m.used_qty),
        formatNumber(bal),
        bal <= min ? "LOW STOCK" : "OK",
        m.supplier || "—",
      ];
    }),
    headStyles: { fillColor: [11, 22, 40], textColor: [255, 255, 255], fontSize: 9 },
    bodyStyles: { fontSize: 8.5, textColor: [30, 41, 59] },
    alternateRowStyles: { fillColor: [248, 250, 252] },
  });

  const finalY = (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY ?? 300;
  if (transactions.length > 0) {
    doc.setFont("helvetica", "bold");
    doc.setFontSize(11);
    doc.text("Recent Stock Transactions", 40, finalY + 28);

    autoTable(doc, {
      startY: finalY + 38,
      head: [["Date", "Material", "Type", "Qty", "Site", "Remarks"]],
      body: transactions.slice(0, 40).map((t) => [
        formatDisplayDate(t.created_at),
        t.materials?.name ?? "—",
        t.transaction_type,
        formatNumber(t.quantity),
        t.site_name || "Central",
        t.remarks || "—",
      ]),
      headStyles: { fillColor: [30, 58, 138], textColor: [255, 255, 255], fontSize: 8.5 },
      bodyStyles: { fontSize: 8, textColor: [30, 41, 59] },
      alternateRowStyles: { fillColor: [248, 250, 252] },
    });
  }

  doc.save(`tsr_material_report_${new Date().toISOString().slice(0, 10)}.pdf`);
}

export function exportActivityLogPdf(logs: ActivityLogRecord[]): void {
  const doc = new jsPDF({ orientation: "landscape", unit: "pt", format: "a4" });
  const startY = addReportHeader(doc, "Activity Audit Log", `Total Entries: ${logs.length}`);

  autoTable(doc, {
    startY,
    head: [["Timestamp", "Module", "Action", "User", "Description"]],
    body: logs.map((l) => [
      formatDisplayDateTime(l.created_at),
      l.module,
      l.action,
      l.user_name ?? "Unknown",
      l.description ?? "—",
    ]),
    headStyles: { fillColor: [11, 22, 40], textColor: [255, 255, 255], fontSize: 9 },
    bodyStyles: { fontSize: 8.5, textColor: [30, 41, 59] },
    alternateRowStyles: { fillColor: [248, 250, 252] },
  });

  doc.save(`tsr_activity_log_${new Date().toISOString().slice(0, 10)}.pdf`);
}

