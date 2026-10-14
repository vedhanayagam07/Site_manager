import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates a Loading Memo PDF that closely replicates the sample layout:
///
///   ┌──────────────┬──────────────────────────────┐
///   │  [LOGO]      │  FELSHIA TRADERS             │
///   │  (gray box)  │  ─────────────────────────── │
///   │              │  since 1996                  │
///   │              │  ph: 967723589               │
///   └──────────────┴──────────────────────────────┘
///   ─────────────────────────────────────────────────
///
///                              DATE: DD/MM/YYYY
///
///
///   In the vehicle number, TN69AJ1733, 150 bags of
///          Ramco Supergrade cement to be loaded.
///
class LoadingMemoPdfService {
  static const String _companyName = 'FELSHIA TRADERS';
  static const String _companySince = 'since 1996';
  static const String _companyPhone = 'ph: 967723589';

  /// Build and return a PDF [Uint8List] for the given dispatch values.
  static Future<Uint8List> generate({
    required DateTime date,
    required String vehicleNumber,
    required String materialName,
    required double quantity,
    required String unit,
    String? remarks,
  }) async {
    final pdf = pw.Document();

    // Load the company logo from assets
    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/tsrlogo.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {
      // Logo unavailable — header still renders without it
    }

    // Format quantity: show as integer when it's a whole number
    final qtyDisplay = quantity == quantity.truncateToDouble()
        ? quantity.toInt().toString()
        : quantity.toString();

    // Format date as DD/MM/YYYY to match the sample
    final dateStr = DateFormat('dd/MM/yyyy').format(date);

    // Compose the body sentence exactly as in the sample
    final sentence =
        'In the vehicle number, $vehicleNumber, $qtyDisplay $unit of $materialName to be loaded.';

    // Fonts — use built-in Helvetica family to closely match the sample's
    // sans-serif italic style without requiring downloadable font assets
    final baseFont = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();
    final italicFont = pw.Font.helveticaOblique();
    final boldItalicFont = pw.Font.helveticaBoldOblique();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ── Header block ────────────────────────────────────────────
              _buildHeader(
                logoBytes: logoBytes,
                baseFont: baseFont,
                boldFont: boldFont,
                italicFont: italicFont,
                boldItalicFont: boldItalicFont,
              ),

              // ── Thin horizontal rule below header ────────────────────────
              pw.Container(
                height: 1.5,
                color: PdfColors.blueGrey700,
              ),

              // ── Body ─────────────────────────────────────────────────────
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(40, 0, 40, 40),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      // Date — top right, bold italic
                      pw.SizedBox(height: 36),
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          'DATE: $dateStr',
                          style: pw.TextStyle(
                            font: boldItalicFont,
                            fontSize: 13,
                          ),
                        ),
                      ),

                      pw.SizedBox(height: 60),

                      // Dispatch sentence — centered, like the sample
                      pw.Align(
                        alignment: pw.Alignment.center,
                        child: pw.Container(
                          constraints: const pw.BoxConstraints(maxWidth: 480),
                          child: pw.Text(
                            sentence,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              font: baseFont,
                              fontSize: 14,
                              lineSpacing: 4,
                            ),
                          ),
                        ),
                      ),

                      // Remarks section (only printed when non-empty)
                      if (remarks != null && remarks.trim().isNotEmpty) ...[
                        pw.SizedBox(height: 40),
                        pw.Text(
                          'Remarks: ${remarks.trim()}',
                          style: pw.TextStyle(
                            font: italicFont,
                            fontSize: 11,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static pw.Widget _buildHeader({
    required Uint8List? logoBytes,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required pw.Font italicFont,
    required pw.Font boldItalicFont,
  }) {
    // Header height matches the sample (~165px at 96dpi → ~124pt)
    const headerHeight = 124.0;

    return pw.SizedBox(
      height: headerHeight,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ── Left: logo panel (gray background) ─────────────────────────
          pw.Container(
            width: 152,
            color: const PdfColor.fromInt(0xFF6B6B6B), // gray panel
            child: pw.Center(
              child: logoBytes != null
                  ? pw.Image(
                      pw.MemoryImage(logoBytes),
                      width: 110,
                      height: 100,
                      fit: pw.BoxFit.contain,
                    )
                  : pw.Text(
                      'TSR',
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 28,
                        color: PdfColors.white,
                      ),
                    ),
            ),
          ),

          // ── Thin vertical divider ───────────────────────────────────────
          pw.Container(width: 1.5, color: PdfColors.blueGrey700),

          // ── Right: company info ─────────────────────────────────────────
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(28, 20, 28, 20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  // Company name — large bold italic, matching sample
                  pw.Text(
                    _companyName,
                    style: pw.TextStyle(
                      font: boldItalicFont,
                      fontSize: 30,
                      letterSpacing: 1.0,
                    ),
                  ),
                  // Horizontal rule under name
                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColors.black, thickness: 0.8),
                  pw.SizedBox(height: 6),
                  // Since
                  pw.Text(
                    _companySince,
                    style: pw.TextStyle(
                      font: italicFont,
                      fontSize: 14,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  // Phone
                  pw.Text(
                    _companyPhone,
                    style: pw.TextStyle(
                      font: italicFont,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
