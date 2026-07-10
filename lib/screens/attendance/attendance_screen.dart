import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/activity_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loader.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/status_chip.dart';
import 'monthly_attendance_screen.dart';
import 'attendance_analytics_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List _records = [];
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();

  int get _presentCount =>
      _records.where((r) => r['status'] == 'Present').length;
  int get _absentCount =>
      _records.where((r) => r['status'] == 'Absent').length;
  int get _halfDayCount =>
      _records.where((r) => r['status'] == 'Half Day').length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dateStr =
          _selectedDate.toIso8601String().split('T')[0];

      final data = await Supabase.instance.client
          .from('site_attendance')
          .select('*, workers(name, role), sites(name)')
          .eq('attendance_date', dateStr)
          .order('created_at', ascending: false);

      setState(() {
        _records = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              const ColorScheme.dark(primary: AppColors.roseGold),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  Future<void> _correctAttendance(Map record) async {
    String currentStatus = record['status'] ?? 'Absent';

    final newStatus = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Correct – ${record['workers']?['name'] ?? ''}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Present', 'Absent', 'Half Day'].map((s) {
            return RadioListTile<String>(
              title: Text(s),
              value: s,
              groupValue: currentStatus,
              activeColor: AppColors.roseGold,
              onChanged: (v) {
                currentStatus = v!;
                Navigator.pop(ctx, v);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
        ],
      ),
    );

    if (newStatus == null) return;

    try {
      await Supabase.instance.client
          .from('site_attendance')
          .update({'status': newStatus}).eq('id', record['id']);

      final workerName = record['workers']?['name'] ?? 'Worker';
      await activityLog.log(
        action: 'Attendance Corrected',
        module: 'Attendance',
        description: 'Corrected attendance of $workerName to $newStatus',
        oldValue: record['status'],
        newValue: newStatus,
      );

      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendance corrected'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
            content: Text('Failed: ${e.toString()}'),
            backgroundColor: Color(0xFFE57373),
          ));
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'Present':
        return AppColors.success;
      case 'Half Day':
        return AppColors.warning;
      default:
        return AppColors.danger;
    }
  }

  IconData _statusIcon(String? s) {
    switch (s) {
      case 'Present':
        return Icons.check_circle;
      case 'Half Day':
        return Icons.access_time;
      default:
        return Icons.cancel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                  builder: (_) => const AttendanceAnalyticsScreen()),
            ),
            tooltip: 'Analytics',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                  builder: (_) => const MonthlyAttendanceScreen()),
            ),
            tooltip: 'Monthly View',
          ),
        ],
      ),
      body: Column(
        children: [
          // Date picker row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        color: AppColors.roseGold, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('EEEE, dd MMMM yyyy')
                          .format(_selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down,
                        color: AppColors.roseGold),
                  ],
                ),
              ),
            ),
          ),

          // Stats row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                _StatChip(
                    label: 'Present',
                    value: _presentCount,
                    color: AppColors.success),
                const SizedBox(width: 8),
                _StatChip(
                    label: 'Absent',
                    value: _absentCount,
                    color: AppColors.danger),
                const SizedBox(width: 8),
                _StatChip(
                    label: 'Half Day',
                    value: _halfDayCount,
                    color: AppColors.warning),
                const SizedBox(width: 8),
                _StatChip(
                    label: 'Total',
                    value: _records.length,
                    color: AppColors.roseGold),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: _loading
                ? const ShimmerList(count: 6, itemHeight: 80)
                : _records.isEmpty
                    ? EmptyStateWidget(
                        icon: Icons.fact_check_outlined,
                        title: 'No Attendance Records',
                        subtitle:
                            'Go to a site to mark attendance for ${DateFormat('dd MMM').format(_selectedDate)}.',
                      )
                    : RefreshIndicator(
                        color: AppColors.roseGold,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                          itemCount: _records.length,
                          itemBuilder: (context, i) {
                            final r = _records[i];
                            final status = r['status'] as String?;
                            final color = _statusColor(status);

                            return _AttendanceCard(
                              record: r,
                              status: status,
                              color: color,
                              index: i,
                              statusIcon: _statusIcon(status),
                              onEdit: () => _correctAttendance(r),
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

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 20)),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Attendance Card
// ─────────────────────────────────────────────────────────────────────────────
class _AttendanceCard extends StatefulWidget {
  final Map record;
  final String? status;
  final Color color;
  final int index;
  final IconData statusIcon;
  final VoidCallback onEdit;

  const _AttendanceCard({
    required this.record,
    required this.status,
    required this.color,
    required this.index,
    required this.statusIcon,
    required this.onEdit,
  });

  @override
  State<_AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<_AttendanceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 40), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final color = widget.color;

    return FadeTransition(
      opacity: _fade,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border(
            left: BorderSide(color: color, width: 3.5),
            top: BorderSide(color: AppColors.roseGold.withValues(alpha: 0.08)),
            right: BorderSide(color: AppColors.roseGold.withValues(alpha: 0.08)),
            bottom: BorderSide(color: AppColors.roseGold.withValues(alpha: 0.08)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              spreadRadius: -2,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(widget.statusIcon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r['workers']?['name'] ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${r['workers']?['role'] ?? ''}  •  ${r['sites']?['name'] ?? 'Site'}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            StatusChip(label: widget.status ?? '—'),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 16, color: AppColors.textSecondary),
              onPressed: widget.onEdit,
              tooltip: 'Correct',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
      ),
    );
  }
}