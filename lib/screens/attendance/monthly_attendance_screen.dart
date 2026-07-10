import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';

class MonthlyAttendanceScreen extends StatefulWidget {
  final String? workerId;
  final String? workerName;

  const MonthlyAttendanceScreen({super.key, this.workerId, this.workerName});

  @override
  State<MonthlyAttendanceScreen> createState() =>
      _MonthlyAttendanceScreenState();
}

class _MonthlyAttendanceScreenState extends State<MonthlyAttendanceScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List _records = [];
  List _workers = [];
  String? _selectedWorkerId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedWorkerId = widget.workerId;
    if (widget.workerId == null) {
      _loadWorkers();
    } else {
      _load();
    }
  }

  Future<void> _loadWorkers() async {
    try {
      final data = await Supabase.instance.client
          .from('workers')
          .select('id, name')
          .order('name');
      setState(() {
        _workers = data;
        if (data.isNotEmpty && _selectedWorkerId == null) {
          _selectedWorkerId = data[0]['id'];
        }
      });
      _load();
    } catch (e) {
      debugPrint(e.toString());
      setState(() => _loading = false);
    }
  }

  Future<void> _load() async {
    if (_selectedWorkerId == null) return;
    setState(() => _loading = true);
    try {
      final start =
          DateTime(_month.year, _month.month, 1).toIso8601String().split('T')[0];
      final end =
          DateTime(_month.year, _month.month + 1, 0).toIso8601String().split('T')[0];

      final data = await Supabase.instance.client
          .from('site_attendance')
          .select('*, sites(name)')
          .eq('worker_id', _selectedWorkerId!)
          .gte('attendance_date', start)
          .lte('attendance_date', end)
          .order('attendance_date');

      setState(() {
        _records = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() => _loading = false);
    }
  }

  int get _daysInMonth =>
      DateTime(_month.year, _month.month + 1, 0).day;

  String _statusForDay(int day) {
    final dateStr = DateFormat('yyyy-MM-dd')
        .format(DateTime(_month.year, _month.month, day));
    final match = _records.where((r) => r['attendance_date'] == dateStr);
    if (match.isEmpty) return '';
    return match.first['status'] as String? ?? '';
  }

  Color _cellColor(String status) {
    switch (status) {
      case 'Present':
        return AppColors.success;
      case 'Absent':
        return AppColors.danger;
      case 'Half Day':
        return AppColors.warning;
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentCount =
        _records.where((r) => r['status'] == 'Present').length;
    final absentCount =
        _records.where((r) => r['status'] == 'Absent').length;
    final totalDays = _daysInMonth;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.workerName != null
            ? '${widget.workerName} – Monthly'
            : 'Monthly Attendance'),
      ),
      body: Column(
        children: [
          // Worker selector (only when no specific worker)
          if (widget.workerId == null && _workers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DropdownButtonFormField<String>(
                value: _selectedWorkerId,
                decoration: const InputDecoration(
                    labelText: 'Select Worker',
                    prefixIcon:
                        Icon(Icons.person, color: AppColors.roseGold)),
                items: _workers
                    .map((w) => DropdownMenuItem<String>(
                          value: w['id'] as String,
                          child: Text(w['name'] as String? ?? ''),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() => _selectedWorkerId = v);
                  _load();
                },
              ),
            ),

          // Month navigation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() => _month =
                        DateTime(_month.year, _month.month - 1));
                    _load();
                  },
                  icon: const Icon(Icons.chevron_left,
                      color: AppColors.roseGold),
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_month),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: _month.year == DateTime.now().year &&
                          _month.month == DateTime.now().month
                      ? null
                      : () {
                          setState(() => _month =
                              DateTime(_month.year, _month.month + 1));
                          _load();
                        },
                  icon: Icon(Icons.chevron_right,
                      color: _month.year == DateTime.now().year &&
                              _month.month == DateTime.now().month
                          ? AppColors.textSecondary
                          : AppColors.roseGold),
                ),
              ],
            ),
          ),

          // Summary chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _chip('Present', presentCount, AppColors.success),
                const SizedBox(width: 10),
                _chip('Absent', absentCount, AppColors.danger),
                const SizedBox(width: 10),
                _chip('Total Days', totalDays, AppColors.roseGold),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Calendar grid
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // Day headers
                    Row(
                      children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                          .map((d) => Expanded(
                                child: Center(
                                  child: Text(d,
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _buildCalendar(),
                    ),
                    // Legend
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _legendItem(AppColors.success, 'Present'),
                        const SizedBox(width: 16),
                        _legendItem(AppColors.danger, 'Absent'),
                        const SizedBox(width: 16),
                        _legendItem(AppColors.warning, 'Half Day'),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    final firstDay = DateTime(_month.year, _month.month, 1);
    // Monday = 0 offset
    final startOffset = (firstDay.weekday - 1) % 7;
    final totalCells = startOffset + _daysInMonth;
    final rows = (totalCells / 7).ceil();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: rows * 7,
      itemBuilder: (ctx, index) {
        final dayNum = index - startOffset + 1;
        if (dayNum < 1 || dayNum > _daysInMonth) {
          return const SizedBox.shrink();
        }
        final status = _statusForDay(dayNum);
        final isToday = DateTime.now().year == _month.year &&
            DateTime.now().month == _month.month &&
            DateTime.now().day == dayNum;

        return Container(
          decoration: BoxDecoration(
            color: status.isNotEmpty
                ? _cellColor(status).withValues(alpha: 0.25)
                : AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isToday
                  ? AppColors.roseGold
                  : status.isNotEmpty
                      ? _cellColor(status).withValues(alpha: 0.5)
                      : AppColors.border,
              width: isToday ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$dayNum',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isToday ? FontWeight.bold : FontWeight.normal,
                  color: isToday ? AppColors.roseGold : null,
                ),
              ),
              if (status.isNotEmpty)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: _cellColor(status),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
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
                    color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(children: [
      Container(
        width: 10,
        height: 10,
        decoration:
            BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 12)),
    ]);
  }
}
