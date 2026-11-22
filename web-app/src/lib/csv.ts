/**
 * Safe CSV export helper with formula-injection neutralization (OWASP CSV Injection mitigation).
 */
function sanitizeCell(value: unknown): string {
  let text = value === null || value === undefined ? "" : String(value);
  // Neutralize spreadsheet formula triggers (=, +, -, @, tab, CR)
  if (/^[=+\-@\t\r]/.test(text)) {
    text = `'${text}`;
  }
  if (/[",\n\r]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

export function downloadCsv(
  filename: string,
  headers: string[],
  rows: Array<Array<unknown>>
): void {
  const lines = [
    headers.map(sanitizeCell).join(","),
    ...rows.map((row) => row.map(sanitizeCell).join(",")),
  ];
  const blob = new Blob(["\uFEFF" + lines.join("\r\n")], {
    type: "text/csv;charset=utf-8;",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename.endsWith(".csv") ? filename : `${filename}.csv`;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

