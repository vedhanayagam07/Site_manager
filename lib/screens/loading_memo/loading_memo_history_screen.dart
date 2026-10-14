import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/role_provider.dart';
import '../../core/services/file_saver.dart';
import '../../core/services/loading_memo_pdf_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/shimmer_loader.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Loading Memo History Screen
// ─────────────────────────────────────────────────────────────────────────────
class LoadingMemoHistoryScreen extends StatefulWidget {
  const LoadingMemoHistoryScreen({super.key});

  @override
  State<LoadingMemoHistoryScreen> createState() =>
      _LoadingMemoHistoryScreenState();
}

class _LoadingMemoHistoryScreenState extends State<LoadingMemoHistoryScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _memos = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _search = '';

  // Date range filter
  DateTime? _fromDate;
  DateTime? _toDate;

  final _searchController = TextEditingController();
  late AnimationController _listCtrl;

  // Role check for delete
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _listCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadData();
    _checkRole();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  // ── Data ────────────────────────────────────────────────────────────────────

  Future<void> _checkRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      if (user.email == 'admin@tsrbuilders.com' ||
          user.email == 'admin@tsrnuilders.com') {
        setState(() => _isAdmin = true);
        return;
      }
      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      if (mounted) {
        setState(() =>
            _isAdmin = (profile?['role'] as String?) == AppRole.admin);
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      var query = Supabase.instance.client
          .from('loading_memos')
          .select()
          .order('created_at', ascending: false);

      final data = await query;
      setState(() {
        _memos = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
      _applyFilters();
      _listCtrl.forward(from: 0);
    } catch (e) {
      debugPrint('[MemoHistory] Error: $e');
      setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    final q = _search.toLowerCase();
    setState(() {
      _filtered = _memos.where((m) {
        // Search filter
        final matchesSearch = q.isEmpty ||
            (m['vehicle_number'] as String? ?? '').toLowerCase().contains(q) ||
            (m['material_name'] as String? ?? '').toLowerCase().contains(q) ||
            (m['generated_by'] as String? ?? '').toLowerCase().contains(q);

        // Date range filter
        if (_fromDate != null || _toDate != null) {
          final raw = m['date'] as String?;
          if (raw == null) return false;
          final mDate = DateTime.tryParse(raw);
          if (mDate == null) return false;
          if (_fromDate != null && mDate.isBefore(_fromDate!)) return false;
          if (_toDate != null &&
              mDate.isAfter(_toDate!.copyWith(hour: 23, minute: 59))) {
            return false;
          }
        }

        return matchesSearch;
      }).toList();
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _regenerateAndShow(Map<String, dynamic> memo) async {
    try {
      // Show loading indicator in a non-blocking way
      final scaffold = ScaffoldMessenger.of(context);
      scaffold.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Generating PDF…'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );

      final dateStr = memo['date'] as String? ?? '';
      final date = DateTime.tryParse(dateStr) ?? DateTime.now();

      final pdfBytes = await LoadingMemoPdfService.generate(
        date: date,
        vehicleNumber: memo['vehicle_number'] as String? ?? '',
        materialName: memo['material_name'] as String? ?? '',
        quantity: (memo['quantity'] as num?)?.toDouble() ?? 1,
        unit: memo['unit'] as String? ?? 'Bags',
        remarks: memo['remarks'] as String?,
      );

      scaffold.hideCurrentSnackBar();

      if (!mounted) return;

      final filename =
          'LoadingMemo_${memo['vehicle_number']}_${DateFormat('ddMMMyyyy').format(date)}.pdf';
      await FileSaver.showPdfOptions(context, filename: filename, bytes: pdfBytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _deleteMemo(Map<String, dynamic> memo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Memo',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Delete memo for vehicle ${memo['vehicle_number']}?\nThis cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('loading_memos')
          .delete()
          .eq('id', memo['id']);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Memo deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.roseGold,
            surface: AppColors.card,
          ),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _fromDate = range.start;
        _toDate = range.end;
      });
      _applyFilters();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _applyFilters();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Memo History'),
        actions: [
          // Date range filter button
          IconButton(
            tooltip: 'Filter by date range',
            icon: Icon(
              Icons.date_range_outlined,
              color: (_fromDate != null || _toDate != null)
                  ? AppColors.roseGold
                  : Colors.white54,
            ),
            onPressed: _pickDateRange,
          ),
          if (_fromDate != null || _toDate != null)
            IconButton(
              tooltip: 'Clear date filter',
              icon: const Icon(Icons.clear, color: AppColors.warning),
              onPressed: _clearDateFilter,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.roseGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.roseGold.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${_filtered.length} Memos',
                  style: const TextStyle(
                      color: AppColors.roseGold,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const ShimmerList(count: 5)
          : Column(
              children: [
                // ── Search bar ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) {
                      _search = v;
                      _applyFilters();
                    },
                    decoration: const InputDecoration(
                      hintText: 'Search by vehicle, material, generated by…',
                      prefixIcon: Icon(Icons.search,
                          color: AppColors.textSecondary, size: 20),
                    ),
                  ),
                ),

                // ── Date range indicator ───────────────────────────────────
                if (_fromDate != null && _toDate != null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.roseGold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.roseGold.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.filter_list,
                              size: 14, color: AppColors.roseGold),
                          const SizedBox(width: 8),
                          Text(
                            '${DateFormat('dd MMM yyyy').format(_fromDate!)} → ${DateFormat('dd MMM yyyy').format(_toDate!)}',
                            style: const TextStyle(
                              color: AppColors.roseGold,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 6),

                // ── List ───────────────────────────────────────────────────
                Expanded(
                  child: _filtered.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.receipt_long_outlined,
                          title: _search.isEmpty &&
                                  _fromDate == null &&
                                  _toDate == null
                              ? 'No Memos Generated Yet'
                              : 'No Results',
                          subtitle: _search.isEmpty &&
                                  _fromDate == null &&
                                  _toDate == null
                              ? 'Generate a loading memo to see it here.'
                              : 'Try adjusting your search or date filter.',
                        )
                      : RefreshIndicator(
                          color: AppColors.roseGold,
                          onRefresh: _loadData,
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 100),
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              return _MemoHistoryCard(
                                memo: _filtered[index],
                                index: index,
                                listCtrl: _listCtrl,
                                isAdmin: _isAdmin,
                                onPreview: () =>
                                    _regenerateAndShow(_filtered[index]),
                                onDelete: () => _deleteMemo(_filtered[index]),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History card widget
// ─────────────────────────────────────────────────────────────────────────────
class _MemoHistoryCard extends StatefulWidget {
  final Map<String, dynamic> memo;
  final int index;
  final AnimationController listCtrl;
  final bool isAdmin;
  final VoidCallback onPreview;
  final VoidCallback onDelete;

  const _MemoHistoryCard({
    required this.memo,
    required this.index,
    required this.listCtrl,
    required this.isAdmin,
    required this.onPreview,
    required this.onDelete,
  });

  @override
  State<_MemoHistoryCard> createState() => _MemoHistoryCardState();
}

class _MemoHistoryCardState extends State<_MemoHistoryCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.memo;
    final rawDate = m['date'] as String?;
    final date = rawDate != null
        ? DateTime.tryParse(rawDate)
        : null;
    final dateStr =
        date != null ? DateFormat('dd MMM yyyy').format(date) : '—';

    final vehicle = m['vehicle_number'] as String? ?? '—';
    final materialName = m['material_name'] as String? ?? '—';
    final qty = (m['quantity'] as num?)?.toStringAsFixed(
            (m['quantity'] is int || m['quantity'] == (m['quantity'] as num?)?.truncateToDouble())
                ? 0
                : 1) ??
        '—';
    final unit = m['unit'] as String? ?? '';
    final generatedBy = m['generated_by'] as String? ?? '—';

    // Staggered entrance
    final delay = widget.index * 0.07;
    final start = delay.clamp(0.0, 0.9);
    final end = (delay + 0.4).clamp(0.1, 1.0);

    return AnimatedBuilder(
      animation: widget.listCtrl,
      builder: (_, child) {
        final t =
            ((widget.listCtrl.value - start) / (end - start)).clamp(0.0, 1.0);
        final curve = Curves.easeOutCubic.transform(t);
        return Transform.translate(
          offset: Offset(0, (1 - curve) * 24),
          child: Opacity(opacity: curve, child: child),
        );
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPreview();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _pressed
                    ? AppColors.roseGold.withValues(alpha: 0.4)
                    : AppColors.roseGold.withValues(alpha: 0.1),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1 — date + vehicle + actions
                  Row(
                    children: [
                      // Document icon
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppColors.roseGold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.roseGold.withValues(alpha: 0.25)),
                        ),
                        child: const Icon(Icons.receipt_long,
                            color: AppColors.roseGold, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              dateStr,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Action buttons
                      _ActionButton(
                        icon: Icons.picture_as_pdf_outlined,
                        color: AppColors.roseGold,
                        tooltip: 'Preview PDF',
                        onTap: widget.onPreview,
                      ),
                      if (widget.isAdmin) ...[
                        const SizedBox(width: 4),
                        _ActionButton(
                          icon: Icons.delete_outline,
                          color: AppColors.danger,
                          tooltip: 'Delete',
                          onTap: widget.onDelete,
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 10),

                  // Row 2 — material + quantity
                  Row(
                    children: [
                      _InfoChip(
                        icon: Icons.inventory_2_outlined,
                        label: materialName,
                      ),
                      const SizedBox(width: 8),
                      _InfoChip(
                        icon: Icons.scale_outlined,
                        label: '$qty $unit',
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Row 3 — generated by
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        generatedBy,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
