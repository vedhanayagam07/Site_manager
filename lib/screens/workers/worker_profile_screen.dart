import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/services/activity_log_service.dart';
import '../../core/theme/app_colors.dart';

class WorkerProfileScreen extends StatefulWidget {
  final Map<String, dynamic> worker;

  const WorkerProfileScreen({super.key, required this.worker});

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Map<String, dynamic> _worker;

  List _attendance = [];
  bool _loadingAttendance = true;
  List<BarChartGroupData> _weeklyBars = [];
  List<String> _weekLabels = [];

  @override
  void initState() {
    super.initState();
    _worker = Map<String, dynamic>.from(widget.worker);
    _tabController = TabController(length: 2, vsync: this);
    _loadAttendance();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAttendance() async {
    try {
      final thirtyDaysAgo = DateTime.now()
          .subtract(const Duration(days: 30))
          .toIso8601String()
          .split('T')[0];

      final data = await Supabase.instance.client
          .from('site_attendance')
          .select('*, sites(name)')
          .eq('worker_id', _worker['id'])
          .gte('attendance_date', thirtyDaysAgo)
          .order('attendance_date', ascending: false);

      // Build weekly chart – last 7 days
      final now = DateTime.now();
      final bars = <BarChartGroupData>[];
      final labels = <String>[];

      for (int i = 6; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final dayStr = day.toIso8601String().split('T')[0];
        final present = (data as List).where((r) {
          return r['attendance_date'] == dayStr && r['status'] == 'Present';
        }).length;

        labels.add(DateFormat('EEE').format(day));
        bars.add(
          BarChartGroupData(
            x: 6 - i,
            barRods: [
              BarChartRodData(
                toY: present.toDouble(),
                color: present > 0 ? AppColors.roseGold : AppColors.danger,
                width: 18,
                borderRadius: BorderRadius.circular(6),
              ),
            ],
          ),
        );
      }

      setState(() {
        _attendance = data;
        _weeklyBars = bars;
        _weekLabels = labels;
        _loadingAttendance = false;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() => _loadingAttendance = false);
    }
  }

  Future<void> _editWorker() async {
    final nameCtrl = TextEditingController(text: _worker['name']);
    final phoneCtrl = TextEditingController(text: _worker['phone'] ?? '');
    String? role = _worker['role'];
    String? skill = _worker['skill'];
    String status = _worker['status'] ?? 'Active';

    const roles = [
      'Mason', 'Carpenter', 'Electrician', 'Plumber',
      'Painter', 'Supervisor', 'Site Engineer', 'Contractor',
    ];
    const skills = [
      'Civil Work', 'Electrical', 'Plumbing',
      'Steel Fixing', 'Concrete Work', 'Finishing',
    ];

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Edit Worker'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: roles.contains(role) ? role : null,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: roles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setDlg(() => role = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: skills.contains(skill) ? skill : null,
                  decoration: const InputDecoration(labelText: 'Skill'),
                  items: skills
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setDlg(() => skill = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: ['Active', 'Inactive']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setDlg(() => status = v ?? 'Active'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    try {
      await Supabase.instance.client.from('workers').update({
        'name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'role': role,
        'skill': skill,
        'status': status,
      }).eq('id', _worker['id']);

      await activityLog.log(
        action: 'Worker Updated',
        module: 'Workers',
        description: 'Updated worker: ${nameCtrl.text.trim()}',
      );

      setState(() {
        _worker['name'] = nameCtrl.text.trim();
        _worker['phone'] = phoneCtrl.text.trim();
        _worker['role'] = role;
        _worker['skill'] = skill;
        _worker['status'] = status;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Worker updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deleteWorker() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Delete Worker'),
        content: Text(
            'Delete "${_worker['name']}"?\n\nAll attendance records for this worker will also be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('workers')
          .delete()
          .eq('id', _worker['id']);

      await activityLog.log(
        action: 'Worker Deleted',
        module: 'Workers',
        description: 'Deleted worker: ${_worker['name']}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Worker deleted')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentCount = _attendance.where((r) => r['status'] == 'Present').length;
    final absentCount = _attendance.where((r) => r['status'] == 'Absent').length;
    final total = _attendance.length;
    final attendancePct = total > 0 ? (presentCount / total * 100).round() : 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.background,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: _editWorker,
                tooltip: 'Edit',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: _deleteWorker,
                tooltip: 'Delete',
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.roseGold.withValues(alpha: 0.3),
                      AppColors.background,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: AppColors.roseGold.withValues(alpha: 0.2),
                      child: Text(
                        (_worker['name'] as String? ?? 'W')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.roseGold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _worker['name'] ?? '',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_worker['role'] ?? ''} • ${_worker['status'] ?? 'Active'}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppColors.roseGold,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.roseGold,
              tabs: const [
                Tab(text: 'Details'),
                Tab(text: 'Attendance'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            // ── TAB 1: Details ──────────────────────────────
            ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _infoTile(Icons.phone, 'Phone', _worker['phone'] ?? '—'),
                _infoTile(Icons.work, 'Role', _worker['role'] ?? '—'),
                _infoTile(
                    Icons.engineering, 'Skill', _worker['skill'] ?? '—'),
                _infoTile(Icons.circle,
                    'Status', _worker['status'] ?? '—'),
                const SizedBox(height: 20),
                // Attendance summary card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      const Text('30-Day Attendance',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                      const SizedBox(height: 12),
                      Text(
                        '$attendancePct%',
                        style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.bold,
                            color: AppColors.roseGold),
                      ),
                      Text('$presentCount Present / $absentCount Absent',
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),

            // ── TAB 2: Attendance ───────────────────────────
            _loadingAttendance
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Weekly bar chart
                      if (_weeklyBars.isNotEmpty) ...[
                        const Text('Last 7 Days',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 160,
                          child: BarChart(
                            BarChartData(
                              maxY: 1,
                              barGroups: _weeklyBars,
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
                                    getTitlesWidget: (value, meta) {
                                      final idx = value.toInt();
                                      if (idx < 0 ||
                                          idx >= _weekLabels.length) {
                                        return const SizedBox.shrink();
                                      }
                                      return Text(
                                        _weekLabels[idx],
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      // History list
                      if (_attendance.isEmpty)
                        const Center(
                            child: Text('No attendance records found'))
                      else
                        ..._attendance.map((r) {
                          final status = r['status'] as String? ?? '';
                          final isPresent = status == 'Present';
                          final isHalfDay = status == 'Half Day';
                          final statusColor = isPresent
                              ? AppColors.success
                              : isHalfDay
                                  ? AppColors.warning
                                  : AppColors.danger;
                          final statusIcon = isPresent
                              ? Icons.check_circle
                              : isHalfDay
                                  ? Icons.watch_later
                                  : Icons.cancel;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(statusIcon, color: statusColor),
                              title: Text(
                                DateFormat('EEE, dd MMM yyyy').format(
                                  DateTime.parse(r['attendance_date'] as String),
                                ),
                              ),
                              subtitle: Text(
                                r['sites']?['name'] as String? ?? 'Unknown Site',
                                style: const TextStyle(color: AppColors.textSecondary),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.roseGold, size: 20),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
