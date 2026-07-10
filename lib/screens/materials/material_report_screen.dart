import 'dart:typed_data';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/activity_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/file_saver.dart';

class MaterialReportScreen extends StatefulWidget {
  const MaterialReportScreen({super.key});

  @override
  State<MaterialReportScreen> createState() => _MaterialReportScreenState();
}

class _MaterialReportScreenState extends State<MaterialReportScreen> {
  List<Map<String, dynamic>> _materials = [];
  List<Map<String, dynamic>> _lowStockItems = [];
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;

  // Site usage map
  List<BarChartGroupData> _siteUsageBars = [];
  List<String> _siteNames = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1)
          .toIso8601String()
          .split('T')[0];

      final mats = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('materials')
            .select()
            .order('name'),
      );

      final txns = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('material_transactions')
            .select()
            .gte('created_at', monthStart)
            .order('created_at', ascending: false),
      );

      final low = mats.where((m) {
        final bal = (m['balance_qty'] as num? ?? 0);
        final min = (m['minimum_stock'] as num? ?? 10);
        return bal <= min;
      }).toList().cast<Map<String, dynamic>>();

      // Site usage from transactions
      final usageMap = <String, double>{};
      for (final t in txns) {
        if (t['transaction_type'] == 'USED') {
          final site = t['site_name'] as String? ?? 'Unknown';
          final key = site.isEmpty ? 'Central Stock' : site;
          usageMap[key] = (usageMap[key] ?? 0) +
              (t['quantity'] as num? ?? 0).toDouble();
        }
      }

      // Build bars
      final sortedSites = usageMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topSites = sortedSites.take(6).toList();
      final bars = <BarChartGroupData>[];
      final siteLabels = <String>[];

      for (int i = 0; i < topSites.length; i++) {
        bars.add(BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: topSites[i].value,
              color: AppColors.roseGold,
              width: 20,
              borderRadius: BorderRadius.circular(6),
            ),
          ],
        ));
        siteLabels.add(topSites[i].key.length > 8
            ? '${topSites[i].key.substring(0, 8)}…'
            : topSites[i].key);
      }

      setState(() {
        _materials = mats;
        _lowStockItems = low;
        _transactions = txns;
        _siteUsageBars = bars;
        _siteNames = siteLabels;
        _loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: safe font loading with fallback
  // ─────────────────────────────────────────────────────────────────────────
  Future<({pw.Font base, pw.Font bold})> _loadFonts() async {
    try {
      final base = await PdfGoogleFonts.notoSansTamilRegular();
      final bold = await PdfGoogleFonts.notoSansTamilBold();
      return (base: base, bold: bold);
    } catch (_) {
      return (base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Enhanced PDF Export
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _exportPdf() async {
    if (!mounted) return;

    // Show loading dialog
    bool dialogOpen = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
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
    dialogOpen = true;

    try {
      final fonts = await _loadFonts();
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
      );
      final now = DateFormat('dd MMM yyyy HH:mm').format(DateTime.now());

      // ── Compute per-material stats ──────────────────────────────────────
      // Map: material_id → {received, used, siteUsage: {site_name: qty}}
      final matStats = <String, Map<String, dynamic>>{};
      for (final m in _materials) {
        matStats[m['id'] as String] = {
          'received': 0.0,
          'used': 0.0,
          'siteUsage': <String, double>{},
        };
      }

      // Also include ALL transactions (not just this month) for totals
      final allTxns = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('material_transactions')
            .select()
            .order('created_at', ascending: false),
      );

      for (final t in allTxns) {
        final matId = t['material_id'] as String?;
        if (matId == null || !matStats.containsKey(matId)) continue;
        final qty = (t['quantity'] as num? ?? 0).toDouble();
        final site = (t['site_name'] as String? ?? '').isEmpty
            ? 'Central Stock'
            : t['site_name'] as String;

        if (t['transaction_type'] == 'RECEIVED') {
          matStats[matId]!['received'] =
              (matStats[matId]!['received'] as double) + qty;
        } else if (t['transaction_type'] == 'USED') {
          matStats[matId]!['used'] =
              (matStats[matId]!['used'] as double) + qty;
          final siteUsage =
              matStats[matId]!['siteUsage'] as Map<String, double>;
          siteUsage[site] = (siteUsage[site] ?? 0) + qty;
        }
      }

      // ── Overall summary ─────────────────────────────────────────────────
      double totalReceived = 0;
      double totalUsed = 0;
      double totalBalance = 0;
      int lowStockCount = 0;

      for (final m in _materials) {
        final bal = (m['balance_qty'] as num? ?? 0).toDouble();
        final min = (m['minimum_stock'] as num? ?? 10).toDouble();
        final stats = matStats[m['id'] as String]!;
        totalReceived += (stats['received'] as double);
        totalUsed += (stats['used'] as double);
        totalBalance += bal;
        if (bal <= min) lowStockCount++;
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            // ── Page Header ───────────────────────────────────────────────
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('TSR Builders – Material Inventory Report',
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('Generated: $now',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey)),
                pw.Divider(),
              ],
            ),
            pw.SizedBox(height: 12),

            // ── Overall Summary Box ───────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFF1A1A2E),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('OVERALL SUMMARY',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          fontSize: 12)),
                  pw.SizedBox(height: 8),
                  pw.TableHelper.fromTextArray(
                    headers: [
                      'Total Materials',
                      'Total Received',
                      'Total Used',
                      'Total Balance',
                      'Low Stock Items'
                    ],
                    data: [
                      [
                        '${_materials.length}',
                        totalReceived.toStringAsFixed(1),
                        totalUsed.toStringAsFixed(1),
                        totalBalance.toStringAsFixed(1),
                        '$lowStockCount',
                      ]
                    ],
                    headerStyle: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFF2D2D44),
                    ),
                    cellStyle: const pw.TextStyle(color: PdfColors.white),
                    cellDecoration: (_, __, ___) => const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // ── Per-Material Detailed Table ───────────────────────────────
            pw.Text('Material-wise Inventory',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: [
                'Material',
                'Unit',
                'Total Received',
                'Total Used',
                'Balance',
                'Status',
                'Supplier',
                'Last Updated',
              ],
              data: _materials.map((m) {
                final id = m['id'] as String;
                final stats = matStats[id] ??
                    {'received': 0.0, 'used': 0.0};
                final bal = (m['balance_qty'] as num? ?? 0).toDouble();
                final min = (m['minimum_stock'] as num? ?? 10).toDouble();
                final isLow = bal <= min;
                final updatedAt = m['updated_at'] != null
                    ? DateFormat('dd MMM yy').format(
                        DateTime.parse(m['updated_at'] as String))
                    : (m['created_at'] != null
                        ? DateFormat('dd MMM yy').format(
                            DateTime.parse(m['created_at'] as String))
                        : '—');
                return [
                  m['name'] ?? '',
                  m['unit'] ?? '',
                  (stats['received'] as double).toStringAsFixed(1),
                  (stats['used'] as double).toStringAsFixed(1),
                  bal.toStringAsFixed(1),
                  isLow ? '⚠ LOW' : 'OK',
                  m['supplier'] ?? m['vendor'] ?? '—',
                  updatedAt,
                ];
              }).toList(),
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1A1A2E),
              ),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                5: pw.Alignment.center,
              },
            ),
            pw.SizedBox(height: 20),

            // ── Site-wise Usage ────────────────────────────────────────────
            pw.Text('Site-wise Material Usage',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            ..._buildSiteUsageSection(matStats),

            pw.SizedBox(height: 20),

            // ── Low Stock Alert ────────────────────────────────────────────
            if (_lowStockItems.isNotEmpty) ...[
              pw.Text('Low Stock Alert',
                  style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.orange)),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: [
                  'Material',
                  'Unit',
                  'Current Stock',
                  'Minimum Required'
                ],
                data: _lowStockItems
                    .map((m) => [
                          m['name'] ?? '',
                          m['unit'] ?? '',
                          '${m['balance_qty'] ?? 0}',
                          '${m['minimum_stock'] ?? 10}',
                        ])
                    .toList(),
                headerStyle:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.orange,
                ),
              ),
              pw.SizedBox(height: 20),
            ],

            // ── This Month Transactions ────────────────────────────────────
            pw.Text(
                'Recent Transactions (${DateFormat('MMMM yyyy').format(DateTime.now())})',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            if (_transactions.isEmpty)
              pw.Text('No transactions this month.',
                  style:
                      const pw.TextStyle(color: PdfColors.grey))
            else
              pw.TableHelper.fromTextArray(
                headers: ['Material', 'Type', 'Qty', 'Site', 'Remarks', 'Date'],
                data: _transactions.take(40).map((t) {
                  final matId = t['material_id'] as String?;
                  final matName = matId != null
                      ? (_materials
                              .where((m) => m['id'] == matId)
                              .firstOrNull?['name'] as String? ??
                          '—')
                      : '—';
                  return [
                    matName,
                    t['transaction_type'] ?? '',
                    '${t['quantity'] ?? 0}',
                    (t['site_name'] as String? ?? '').isEmpty
                        ? 'Central'
                        : t['site_name'],
                    t['remarks'] ?? '',
                    t['created_at'] != null
                        ? DateFormat('dd MMM').format(
                            DateTime.parse(t['created_at'] as String))
                        : '',
                  ];
                }).toList(),
                headerStyle:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF1A1A2E),
                ),
              ),
          ],
        ),
      );

      final Uint8List bytes = await pdf.save();

      if (!mounted) return;
      // Dismiss loading dialog
      Navigator.of(context, rootNavigator: true).pop();
      dialogOpen = false;

      final filename =
          'material_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';

      await FileSaver.showPdfOptions(context, filename: filename, bytes: bytes);

      await activityLog.log(
        action: 'Report Generated',
        module: 'Reports',
        description:
            'Material Inventory Report exported (${_materials.length} materials)',
      );
    } catch (e) {
      debugPrint('[MaterialReport] PDF error: $e');
      if (!mounted) return;
      if (dialogOpen) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate PDF: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ── Build site-wise usage table per material ─────────────────────────────
  List<pw.Widget> _buildSiteUsageSection(
      Map<String, Map<String, dynamic>> matStats) {
    // Collect all unique sites across all materials
    final allSites = <String>{};
    for (final s in matStats.values) {
      final siteMap = s['siteUsage'] as Map<String, double>;
      allSites.addAll(siteMap.keys);
    }

    if (allSites.isEmpty) {
      return [
        pw.Text('No site-wise usage data available.',
            style: const pw.TextStyle(color: PdfColors.grey))
      ];
    }

    // Build rows: [Material, Site1, Site2, …]
    final siteList = allSites.toList()..sort();
    final headers = ['Material', ...siteList];
    final rows = <List<String>>[];

    for (final m in _materials) {
      final id = m['id'] as String;
      final stats = matStats[id];
      if (stats == null) continue;
      final siteUsage = stats['siteUsage'] as Map<String, double>;
      final totalUsed = stats['used'] as double;
      if (totalUsed == 0) continue; // Skip if no usage

      final row = <String>[m['name'] as String? ?? ''];
      for (final site in siteList) {
        final qty = siteUsage[site] ?? 0.0;
        row.add(qty > 0 ? qty.toStringAsFixed(1) : '—');
      }
      rows.add(row);
    }

    if (rows.isEmpty) {
      return [
        pw.Text('No materials have been used yet.',
            style: const pw.TextStyle(color: PdfColors.grey))
      ];
    }

    return [
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFF1A1A2E),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Material Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _loading ? null : _exportPdf,
            tooltip: 'Export PDF',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Low stock alert
                    if (_lowStockItems.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color:
                                  AppColors.warning.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber,
                                color: AppColors.warning),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${_lowStockItems.length} item(s) below minimum stock',
                                style: const TextStyle(
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Quick stats — now showing totals
                    _buildSummaryRow(),
                    const SizedBox(height: 24),

                    // Usage by site chart
                    if (_siteUsageBars.isNotEmpty) ...[
                      const Text('Usage by Site (This Month)',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Container(
                        height: 200,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: BarChart(
                          BarChartData(
                            barGroups: _siteUsageBars,
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(
                                  sideTitles:
                                      SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles:
                                      SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(
                                  sideTitles:
                                      SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (val, meta) {
                                    final idx = val.toInt();
                                    if (idx < 0 ||
                                        idx >= _siteNames.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Text(_siteNames[idx],
                                        style: const TextStyle(
                                            fontSize: 9,
                                            color:
                                                AppColors.textSecondary));
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Low stock list
                    if (_lowStockItems.isNotEmpty) ...[
                      const Text('Low Stock Alert',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ..._lowStockItems.map((m) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.warning_amber,
                                  color: AppColors.warning),
                              title: Text(m['name'] ?? ''),
                              subtitle: Text(
                                  'Stock: ${m['balance_qty']} ${m['unit']} / Min: ${m['minimum_stock']}'),
                            ),
                          )),
                      const SizedBox(height: 16),
                    ],

                    // Recent transactions
                    const Text('Recent Transactions (This Month)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_transactions.isEmpty)
                      const Center(
                          child: Text('No transactions this month',
                              style: TextStyle(
                                  color: AppColors.textSecondary)))
                    else
                      ..._transactions.take(15).map((t) {
                        final isReceive =
                            t['transaction_type'] == 'RECEIVED';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              isReceive
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              color: isReceive
                                  ? AppColors.success
                                  : AppColors.roseGold,
                            ),
                            title: Text(
                                '${t['transaction_type']} – ${t['quantity']}'),
                            subtitle: Text(
                                '${(t['site_name'] as String? ?? '').isEmpty ? 'Central Stock' : t['site_name']}'
                                '\n${t['remarks'] ?? ''}'),
                            trailing: t['created_at'] != null
                                ? Text(
                                    DateFormat('dd MMM').format(
                                        DateTime.parse(
                                            t['created_at'] as String)),
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12),
                                  )
                                : null,
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryRow() {
    // Compute totals from materials list
    double totalReceived = 0;
    double totalUsed = 0;
    double totalBalance = 0;

    // Use transactions for this month
    for (final t in _transactions) {
      final qty = (t['quantity'] as num? ?? 0).toDouble();
      if (t['transaction_type'] == 'RECEIVED') {
        totalReceived += qty;
      } else if (t['transaction_type'] == 'USED') {
        totalUsed += qty;
      }
    }

    for (final m in _materials) {
      totalBalance += (m['balance_qty'] as num? ?? 0).toDouble();
    }

    return Column(
      children: [
        Row(
          children: [
            _statChip('Total Items', '${_materials.length}',
                AppColors.roseGold),
            const SizedBox(width: 10),
            _statChip(
                'Low Stock', '${_lowStockItems.length}', AppColors.warning),
            const SizedBox(width: 10),
            _statChip('Month Txns', '${_transactions.length}',
                AppColors.success),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _statChip(
                'Received',
                totalReceived.toStringAsFixed(0),
                const Color(0xFF7E9EF5)),
            const SizedBox(width: 10),
            _statChip(
                'Used',
                totalUsed.toStringAsFixed(0),
                AppColors.roseGold),
            const SizedBox(width: 10),
            _statChip(
                'Balance',
                totalBalance.toStringAsFixed(0),
                AppColors.success),
          ],
        ),
      ],
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
