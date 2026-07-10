import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/services/activity_log_service.dart';
import '../../core/services/file_saver.dart';
import '../../core/theme/app_colors.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String _searchQuery = '';
  String? _moduleFilter;
  DateTime? _fromDate;
  DateTime? _toDate;
  int _page = 0;
  static const int _pageSize = 50;

  final _searchController = TextEditingController();

  final List<String> _modules = [
    'All',
    'Attendance',
    'Materials',
    'Workers',
    'Sites',
    'Reports',
    'Admin',
    'Navigation',
    'Auth',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = true}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _page = 0;
      });
    }
    final logs = await activityLog.fetchLogs(
      searchQuery: _searchQuery,
      moduleFilter: _moduleFilter == 'All' ? null : _moduleFilter,
      fromDate: _fromDate,
      toDate: _toDate,
      limit: _pageSize,
      offset: _page * _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? now) : (_toDate ?? now),
      firstDate: DateTime(2024),
      lastDate: now,
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
    _load();
  }

  Future<void> _exportPdf() async {
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logs to export.')),
      );
      return;
    }

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

    try {
      final font = await PdfGoogleFonts.notoSansTamilRegular();
      final boldFont = await PdfGoogleFonts.notoSansTamilBold();
      final pdf = pw.Document(
          theme: pw.ThemeData.withFont(base: font, bold: boldFont));
      final now = DateFormat('dd MMM yyyy HH:mm').format(DateTime.now());

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            pw.Text('Activity Log Report',
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('Generated: $now',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Time', 'Module', 'Action', 'User', 'Description'],
              data: _logs.map((log) {
                String time = '';
                try {
                  time = DateFormat('dd MMM HH:mm').format(
                      DateTime.parse(log['created_at'] as String).toLocal());
                } catch (_) {}
                return [
                  time,
                  log['module'] ?? '',
                  log['action'] ?? '',
                  log['user_name'] ?? '',
                  log['description'] ?? '',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      );

      final Uint8List bytes = await pdf.save();
      if (!mounted) return;
      Navigator.pop(context); // close loading dialog

      final filename =
          'activity_log_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      await FileSaver.showPdfOptions(context, filename: filename, bytes: bytes);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate PDF: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Color _moduleColor(String? module) {
    switch (module) {
      case 'Attendance':
        return AppColors.success;
      case 'Materials':
        return AppColors.warning;
      case 'Workers':
        return const Color(0xFF7E9EF5);
      case 'Sites':
        return AppColors.roseGold;
      case 'Reports':
        return const Color(0xFFCE93D8);
      case 'Admin':
        return const Color(0xFFEF9A9A);
      case 'Auth':
        return const Color(0xFF80CBC4);
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Activity Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
            onPressed: _exportPdf,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search + filter bar
          Container(
            color: AppColors.card,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (v) {
                    _searchQuery = v;
                    _load();
                  },
                  decoration: InputDecoration(
                    hintText: 'Search by action, user, or description…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.zero,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _searchQuery = '';
                              _load();
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _modules.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final mod = _modules[i];
                      final isSelected = _moduleFilter == null
                          ? mod == 'All'
                          : _moduleFilter == mod;
                      return ChoiceChip(
                        label: Text(mod, style: const TextStyle(fontSize: 12)),
                        selected: isSelected,
                        selectedColor: AppColors.roseGold.withValues(alpha: 0.2),
                        onSelected: (_) {
                          setState(() {
                            _moduleFilter = mod == 'All' ? null : mod;
                          });
                          _load();
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _DateChip(
                      label: _fromDate != null
                          ? 'From: ${DateFormat('dd MMM').format(_fromDate!)}'
                          : 'From Date',
                      onTap: () => _pickDate(true),
                      onClear: _fromDate != null
                          ? () {
                              setState(() => _fromDate = null);
                              _load();
                            }
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _DateChip(
                      label: _toDate != null
                          ? 'To: ${DateFormat('dd MMM').format(_toDate!)}'
                          : 'To Date',
                      onTap: () => _pickDate(false),
                      onClear: _toDate != null
                          ? () {
                              setState(() => _toDate = null);
                              _load();
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Log count
          if (!_loading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.background,
              child: Text(
                '${_logs.length} log${_logs.length == 1 ? '' : 's'}${_pageSize == _logs.length ? ' (showing first $_pageSize)' : ''}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),

          // Log list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_outlined,
                                size: 72,
                                color: AppColors.roseGold.withValues(alpha: 0.3)),
                            const SizedBox(height: 16),
                            const Text('No Activity Logs',
                                style: TextStyle(fontSize: 18)),
                            const SizedBox(height: 8),
                            const Text(
                              'Logs appear here after running the SQL migration\nand performing actions in the app.',
                              style: TextStyle(color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: _logs.length,
                        itemBuilder: (_, i) {
                          final log = _logs[i];
                          final module = log['module'] as String? ?? '';
                          final action = log['action'] as String? ?? '';
                          final user = log['user_name'] as String? ?? 'Unknown';
                          final desc = log['description'] as String? ?? '';
                          final createdAt = log['created_at'] as String?;
                          String timeLabel = '';
                          if (createdAt != null) {
                            try {
                              timeLabel = DateFormat('dd MMM yyyy · HH:mm')
                                  .format(DateTime.parse(createdAt).toLocal());
                            } catch (_) {}
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _moduleColor(module)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.history,
                                        color: _moduleColor(module), size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _moduleColor(module)
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                module,
                                                style: TextStyle(
                                                  color: _moduleColor(module),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                action,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (desc.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            desc,
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Text(
                                          '$user · $timeLabel',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateChip({required this.label, required this.onTap, this.onClear});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 14,
                color: AppColors.roseGold),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close,
                    size: 14, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
