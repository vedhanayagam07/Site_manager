import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/file_saver.dart';
import '../../core/services/activity_log_service.dart';
import '../materials/material_report_screen.dart';
import '../attendance/attendance_analytics_screen.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Generate & Export Reports',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a report to preview and download as PDF.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          _ReportCard(
            icon: Icons.people,
            title: 'Worker Report',
            subtitle: 'All workers with role, phone & status',
            color: const Color(0xFF7E9EF5),
            onTap: () => _generateWorkerReport(context),
          ),
          _ReportCard(
            icon: Icons.fact_check,
            title: 'Attendance Report',
            subtitle: "This month's attendance across all sites",
            color: AppColors.success,
            onTap: () => _generateAttendanceReport(context),
          ),
          _ReportCard(
            icon: Icons.inventory_2,
            title: 'Material Inventory Report',
            subtitle: 'Stock levels, low alerts & transactions',
            color: AppColors.warning,
            onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const MaterialReportScreen()),
            ),
          ),
          _ReportCard(
            icon: Icons.location_city,
            title: 'Site Report',
            subtitle: 'All sites with status and progress',
            color: AppColors.roseGold,
            onTap: () => _generateSiteReport(context),
          ),
          _ReportCard(
            icon: Icons.bar_chart,
            title: 'Attendance Analytics',
            subtitle: 'Charts: present/absent trends, top workers',
            color: const Color(0xFFCE93D8),
            onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const AttendanceAnalyticsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: safe font loading with fallback to default
  // ─────────────────────────────────────────────────────────────────────────
  Future<({pw.Font base, pw.Font bold})> _loadFonts() async {
    try {
      final base = await PdfGoogleFonts.notoSansTamilRegular();
      final bold = await PdfGoogleFonts.notoSansTamilBold();
      return (base: base, bold: bold);
    } catch (_) {
      // Fallback to built-in fonts if Google Fonts download fails
      return (base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: safe loading dialog management
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _runWithLoadingDialog(
    BuildContext context,
    Future<void> Function() work,
  ) async {
    bool dialogOpen = false;

    try {
      if (!context.mounted) return;
      _showLoadingDialog(context);
      dialogOpen = true;

      await work();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate report: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (dialogOpen && context.mounted) {
        // Pop only if dialog is still on top
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {
          // Dialog was already dismissed
        }
        dialogOpen = false;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Worker Report
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _generateWorkerReport(BuildContext context) async {
    await _runWithLoadingDialog(context, () async {
      final data = await Supabase.instance.client
          .from('workers')
          .select()
          .order('name');

      final fonts = await _loadFonts();
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
      );
      final now = DateFormat('dd MMM yyyy HH:mm').format(DateTime.now());

      final workers = data as List;

      final activeCount = workers.where((w) => w['status'] == 'Active').length;
      final inactiveCount = workers.length - activeCount;

      // Role breakdown
      final roleMap = <String, int>{};
      for (final w in workers) {
        final role = (w['role'] as String?) ?? 'Unknown';
        roleMap[role] = (roleMap[role] ?? 0) + 1;
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            _pdfHeader('TSR Builders – Worker Report', now),
            pw.SizedBox(height: 8),
            // Summary row
            pw.Row(children: [
              pw.Text('Total: ${workers.length}  ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('Active: $activeCount  ',
                  style: const pw.TextStyle(color: PdfColors.green)),
              pw.Text('Inactive: $inactiveCount',
                  style: const pw.TextStyle(color: PdfColors.red)),
            ]),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: ['Name', 'Role', 'Phone', 'Skill', 'Status'],
              data: workers
                  .map((w) => [
                        w['name'] ?? '',
                        w['role'] ?? '',
                        w['phone'] ?? '',
                        w['skill'] ?? '',
                        w['status'] ?? '',
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1A1A2E),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text('Role Breakdown:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Role', 'Count'],
              data: roleMap.entries
                  .map((e) => [e.key, '${e.value}'])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      );

      if (!context.mounted) return;
      // Dismiss loading dialog before showing options
      Navigator.of(context, rootNavigator: true).pop();

      final filename =
          'worker_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final Uint8List bytes = await pdf.save();

      if (!context.mounted) return;
      await FileSaver.showPdfOptions(context, filename: filename, bytes: bytes);

      await activityLog.log(
        action: 'Report Generated',
        module: 'Reports',
        description: 'Worker Report exported (${workers.length} workers)',
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Attendance Report
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _generateAttendanceReport(BuildContext context) async {
    await _runWithLoadingDialog(context, () async {
      final monthStart =
          DateTime(DateTime.now().year, DateTime.now().month, 1)
              .toIso8601String()
              .split('T')[0];

      final data = await Supabase.instance.client
          .from('site_attendance')
          .select('*, workers(name, role), sites(name)')
          .gte('attendance_date', monthStart)
          .order('attendance_date', ascending: false);

      final fonts = await _loadFonts();
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
      );
      final now = DateFormat('dd MMM yyyy HH:mm').format(DateTime.now());
      final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());

      final records = data as List;
      final present =
          records.where((r) => r['status'] == 'Present').length;
      final absent =
          records.where((r) => r['status'] == 'Absent').length;
      final halfDay =
          records.where((r) => r['status'] == 'Half Day').length;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            _pdfHeader(
                'TSR Builders – Attendance Report – $monthLabel', now),
            pw.SizedBox(height: 8),
            pw.Row(children: [
              pw.Text('Total Records: ${records.length}  ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('Present: $present  ',
                  style: const pw.TextStyle(color: PdfColors.green)),
              pw.Text('Absent: $absent  ',
                  style: const pw.TextStyle(color: PdfColors.red)),
              pw.Text('Half Day: $halfDay',
                  style: const pw.TextStyle(color: PdfColors.orange)),
            ]),
            pw.SizedBox(height: 12),
            if (records.isEmpty)
              pw.Text(
                'No attendance records found for $monthLabel.',
                style: const pw.TextStyle(color: PdfColors.grey),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: ['Date', 'Worker', 'Role', 'Site', 'Status'],
                data: records
                    .map((r) => [
                          r['attendance_date'] ?? '',
                          r['workers']?['name'] ?? '',
                          r['workers']?['role'] ?? '',
                          r['sites']?['name'] ?? 'Central',
                          r['status'] ?? '',
                        ])
                    .toList(),
                headerStyle:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF1A1A2E),
                ),
              ),
          ],
        ),
      );

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final filename =
          'attendance_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final Uint8List bytes = await pdf.save();

      if (!context.mounted) return;
      await FileSaver.showPdfOptions(context, filename: filename, bytes: bytes);

      await activityLog.log(
        action: 'Report Generated',
        module: 'Reports',
        description:
            'Attendance Report exported ($monthLabel, ${records.length} records)',
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Site Report
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _generateSiteReport(BuildContext context) async {
    await _runWithLoadingDialog(context, () async {
      final data = await Supabase.instance.client
          .from('sites')
          .select()
          .order('name');

      final fonts = await _loadFonts();
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
      );
      final now = DateFormat('dd MMM yyyy HH:mm').format(DateTime.now());

      final sites = data as List;
      final activeCount = sites
          .where((s) =>
              (s['status'] as String? ?? '').toLowerCase() == 'active' ||
              (s['status'] as String? ?? '').toLowerCase() ==
                  'in progress')
          .length;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            _pdfHeader('TSR Builders – Site Report', now),
            pw.SizedBox(height: 8),
            pw.Row(children: [
              pw.Text('Total Sites: ${sites.length}  ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('Active: $activeCount',
                  style: const pw.TextStyle(color: PdfColors.green)),
            ]),
            pw.SizedBox(height: 12),
            if (sites.isEmpty)
              pw.Text('No sites found.',
                  style: const pw.TextStyle(color: PdfColors.grey))
            else
              pw.TableHelper.fromTextArray(
                headers: [
                  'Site Name',
                  'Location',
                  'Manager',
                  'Status',
                  'Progress'
                ],
                data: sites
                    .map((s) => [
                          s['name'] ?? '',
                          s['location'] ?? '',
                          s['project_manager'] ?? '',
                          s['status'] ?? '',
                          '${s['progress'] ?? 0}%',
                        ])
                    .toList(),
                headerStyle:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF1A1A2E),
                ),
              ),
          ],
        ),
      );

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final filename =
          'site_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final Uint8List bytes = await pdf.save();

      if (!context.mounted) return;
      await FileSaver.showPdfOptions(context, filename: filename, bytes: bytes);

      await activityLog.log(
        action: 'Report Generated',
        module: 'Reports',
        description: 'Site Report exported (${sites.length} sites)',
      );
    });
  }

  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generating PDF…'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  pw.Widget _pdfHeader(String title, String dateTime) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Generated: $dateTime',
            style:
                const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
        pw.Divider(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Report Card Widget
// ─────────────────────────────────────────────────────────────────────────────
class _ReportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ReportCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
