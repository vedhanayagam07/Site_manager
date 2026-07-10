import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';

class AttendanceAnalyticsScreen extends StatefulWidget {
  const AttendanceAnalyticsScreen({super.key});

  @override
  State<AttendanceAnalyticsScreen> createState() =>
      _AttendanceAnalyticsScreenState();
}

class _AttendanceAnalyticsScreenState
    extends State<AttendanceAnalyticsScreen> {
  bool _loading = true;
  int _totalPresent = 0;
  int _totalAbsent = 0;
  int _totalHalfDay = 0;

  // Weekly trend – last 4 weeks
  List<FlSpot> _trendSpots = [];
  List<String> _trendLabels = [];

  // Top attendees
  List<Map<String, dynamic>> _topAttendees = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final thirtyDaysAgo = DateTime.now()
          .subtract(const Duration(days: 30))
          .toIso8601String()
          .split('T')[0];

      final data = await Supabase.instance.client
          .from('site_attendance')
          .select('status, attendance_date, worker_id, workers(name)')
          .gte('attendance_date', thirtyDaysAgo);

      final records = data as List;
      final present = records.where((r) => r['status'] == 'Present').length;
      final absent = records.where((r) => r['status'] == 'Absent').length;
      final halfDay = records.where((r) => r['status'] == 'Half Day').length;

      // Weekly trend (last 4 weeks)
      final spots = <FlSpot>[];
      final labels = <String>[];
      for (int w = 3; w >= 0; w--) {
        final weekStart = DateTime.now().subtract(Duration(days: 7 * w + 6));
        final weekEnd = DateTime.now().subtract(Duration(days: 7 * w));
        final weekStartStr = weekStart.toIso8601String().split('T')[0];
        final weekEndStr = weekEnd.toIso8601String().split('T')[0];

        final count = records.where((r) {
          final d = r['attendance_date'] as String;
          return d.compareTo(weekStartStr) >= 0 &&
              d.compareTo(weekEndStr) <= 0 &&
              r['status'] == 'Present';
        }).length;

        spots.add(FlSpot((3 - w).toDouble(), count.toDouble()));
        labels.add('W${4 - w}');
      }

      // Top attendees
      final Map<String, int> workerPresent = {};
      final Map<String, String> workerNames = {};
      for (final r in records) {
        if (r['status'] == 'Present') {
          final wid = r['worker_id'] as String? ?? '';
          workerPresent[wid] = (workerPresent[wid] ?? 0) + 1;
          workerNames[wid] = r['workers']?['name'] ?? wid;
        }
      }

      final top = workerPresent.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topList = top
          .take(5)
          .map((e) => {'name': workerNames[e.key] ?? e.key, 'days': e.value})
          .toList();

      setState(() {
        _totalPresent = present;
        _totalAbsent = absent;
        _totalHalfDay = halfDay;
        _trendSpots = spots;
        _trendLabels = labels;
        _topAttendees = topList;
        _loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalPresent + _totalAbsent + _totalHalfDay;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Attendance Analytics')),
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
                    const Text('Last 30 Days',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    const SizedBox(height: 16),

                    // Pie chart
                    if (total > 0)
                      Container(
                        height: 220,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: PieChart(
                                PieChartData(
                                  sectionsSpace: 3,
                                  centerSpaceRadius: 40,
                                  sections: [
                                    PieChartSectionData(
                                      value: _totalPresent.toDouble(),
                                      color: AppColors.success,
                                      title: '$_totalPresent',
                                      radius: 60,
                                      titleStyle: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    PieChartSectionData(
                                      value: _totalAbsent.toDouble(),
                                      color: AppColors.danger,
                                      title: '$_totalAbsent',
                                      radius: 60,
                                      titleStyle: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    if (_totalHalfDay > 0)
                                      PieChartSectionData(
                                        value: _totalHalfDay.toDouble(),
                                        color: AppColors.warning,
                                        title: '$_totalHalfDay',
                                        radius: 60,
                                        titleStyle: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _legendRow(
                                    AppColors.success, 'Present', _totalPresent),
                                const SizedBox(height: 10),
                                _legendRow(
                                    AppColors.danger, 'Absent', _totalAbsent),
                                const SizedBox(height: 10),
                                _legendRow(AppColors.warning, 'Half Day',
                                    _totalHalfDay),
                              ],
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Trend line chart
                    const Text('Weekly Trend',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      height: 180,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: LineChart(
                        LineChartData(
                          gridData:
                              const FlGridData(show: false),
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
                                      idx >= _trendLabels.length) {
                                    return const SizedBox.shrink();
                                  }
                                  return Text(_trendLabels[idx],
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color:
                                              AppColors.textSecondary));
                                },
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: _trendSpots,
                              isCurved: true,
                              color: AppColors.roseGold,
                              barWidth: 3,
                              dotData: const FlDotData(show: true),
                              belowBarData: BarAreaData(
                                show: true,
                                color:
                                    AppColors.roseGold.withValues(alpha: 0.1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Top attendees
                    const Text('Top 5 Attendees',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ..._topAttendees.map((w) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.roseGold.withValues(alpha: 0.15),
                            child: Text(
                              (w['name'] as String).substring(0, 1),
                              style: const TextStyle(
                                  color: AppColors.roseGold),
                            ),
                          ),
                          title: Text(w['name'] as String),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${w['days']} days',
                              style: const TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _legendRow(Color color, String label, int value) {
    return Row(children: [
      Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text('$label: $value',
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 13)),
    ]);
  }
}
