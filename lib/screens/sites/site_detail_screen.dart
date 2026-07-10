import 'weekly_attendance_screen.dart';
import 'attendance_history_screen.dart';
import 'mark_attendance_screen.dart';
import 'add_edit_site_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/activity_log_service.dart';
import '../../core/theme/app_colors.dart';

class SiteDetailScreen extends StatefulWidget {
  final Map site;

  const SiteDetailScreen({super.key, required this.site});

  @override
  State<SiteDetailScreen> createState() => _SiteDetailScreenState();
}

class _SiteDetailScreenState extends State<SiteDetailScreen> {
  List workers = [];
  bool loadingWorkers = true;
  late Map<String, dynamic> _site;

  @override
  void initState() {
    super.initState();
    _site = Map<String, dynamic>.from(widget.site);
    _loadLocalProgress();
    loadWorkers();
  }

  Future<void> _loadLocalProgress() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _site['progress'] = prefs.getInt('site_progress_${_site['id']}') ?? 0;
    });
  }

  Future<void> loadWorkers() async {
    try {
      final data = await Supabase.instance.client
          .from('workers')
          .select()
          .eq('site_id', _site['id']);

      setState(() {
        workers = data;
        loadingWorkers = false;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() => loadingWorkers = false);
    }
  }

  Future<void> assignWorker() async {
    try {
      final availableWorkers = await Supabase.instance.client
          .from('workers')
          .select()
          .isFilter('site_id', null);

      if (!mounted) return;

      final selectedWorker = await showDialog<Map>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text('Assign Worker'),
            content: SizedBox(
              width: 400,
              child: availableWorkers.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No unassigned workers available'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: availableWorkers.length,
                      itemBuilder: (context, index) {
                        final worker = availableWorkers[index];
                        return ListTile(
                          title: Text(worker['name'] ?? ''),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(worker['role'] ?? ''),
                              if (worker['phone'] != null)
                                Text(worker['phone']),
                            ],
                          ),
                          onTap: () => Navigator.pop(context, worker),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );

      if (selectedWorker == null) return;

      await Supabase.instance.client
          .from('workers')
          .update({'site_id': _site['id']}).eq('id', selectedWorker['id']);

      await activityLog.log(
        action: 'Worker Assigned',
        module: 'Sites',
        description: 'Assigned worker ${selectedWorker['name']} to site ${_site['name']}',
      );

      loadWorkers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Worker Assigned')),
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _editSite() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditSiteScreen(site: _site),
      ),
    );

    if (result == true) {
      // Refresh site data
      try {
        final fresh = await Supabase.instance.client
            .from('sites')
            .select()
            .eq('id', _site['id'])
            .single();
        final prefs = await SharedPreferences.getInstance();
        final freshMap = Map<String, dynamic>.from(fresh);
        freshMap['progress'] = prefs.getInt('site_progress_${freshMap['id']}') ?? 0;
        setState(() => _site = freshMap);
      } catch (_) {}
    }
  }

  Future<void> _deleteSite() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Delete Site'),
        content: Text(
            'Delete "${_site['name']}"?\n\nAll workers, attendance records, and data for this site will remain but be unlinked.'),
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
          .from('sites')
          .delete()
          .eq('id', _site['id']);

      await activityLog.log(
        action: 'Site Deleted',
        module: 'Sites',
        description: 'Deleted site: ${_site['name']}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Site deleted')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _toggleCompletion() async {
    final isCompleted = _site['status'] == 'Completed';
    final newStatus = isCompleted ? 'Active' : 'Completed';
    final newProgress = isCompleted ? (_site['progress'] ?? 0) : 100;

    try {
      await Supabase.instance.client.from('sites').update({
        'status': newStatus,
      }).eq('id', _site['id']);

      await activityLog.log(
        action: 'Site Updated',
        module: 'Sites',
        description: 'Marked site ${_site['name']} as $newStatus ($newProgress% progress)',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('site_progress_${_site['id']}', newProgress);

      setState(() {
        _site['status'] = newStatus;
        _site['progress'] = newProgress;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                isCompleted ? 'Site marked as Active' : 'Site marked as Completed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_site['progress'] as num? ?? 0).toInt();
    final isCompleted = _site['status'] == 'Completed';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_site['name'] ?? ''),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editSite,
            tooltip: 'Edit Site',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _deleteSite,
            tooltip: 'Delete Site',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Site info cards
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _infoRow(Icons.place, 'Location',
                        _site['location'] ?? '—'),
                    const Divider(height: 20, color: AppColors.border),
                    _infoRow(Icons.manage_accounts, 'Manager',
                        _site['project_manager'] ?? '—'),
                    const Divider(height: 20, color: AppColors.border),
                    _infoRow(Icons.circle, 'Status',
                        _site['status'] ?? '—'),
                    const Divider(height: 20, color: AppColors.border),
                    // Progress
                    Row(
                      children: [
                        const Icon(Icons.trending_up,
                            color: AppColors.roseGold, size: 18),
                        const SizedBox(width: 12),
                        const Text('Progress',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13)),
                        const Spacer(),
                        Text(
                          '$progress%',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.roseGold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isCompleted
                              ? AppColors.success
                              : AppColors.roseGold,
                        ),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Action buttons
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _actionBtn(Icons.person_add, 'Assign Worker', assignWorker),
                _actionBtn(
                  Icons.fact_check,
                  'Mark Attendance',
                  () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              MarkAttendanceScreen(site: _site)),
                    );
                  },
                ),
                _actionBtn(
                  Icons.history,
                  'Attendance History',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            AttendanceHistoryScreen(site: _site)),
                  ),
                ),
                _actionBtn(
                  Icons.calendar_view_week,
                  'Weekly Summary',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            WeeklyAttendanceScreen(site: _site)),
                  ),
                ),
                _actionBtn(
                  isCompleted
                      ? Icons.undo
                      : Icons.check_circle_outline,
                  isCompleted ? 'Mark Active' : 'Mark Complete',
                  _toggleCompletion,
                  color: isCompleted
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Workers list
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Assigned Workers (${workers.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: loadingWorkers
                  ? const Center(child: CircularProgressIndicator())
                  : workers.isEmpty
                      ? const Center(
                          child: Text(
                          'No Workers Assigned',
                          style:
                              TextStyle(color: AppColors.textSecondary),
                        ))
                      : ListView.builder(
                          itemCount: workers.length,
                          itemBuilder: (context, index) {
                            final worker = workers[index];

                            return Card(
                              margin:
                                  const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.roseGold
                                      .withValues(alpha: 0.15),
                                  child: Text(
                                    (worker['name'] as String? ?? 'W')
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: const TextStyle(
                                        color: AppColors.roseGold),
                                  ),
                                ),
                                title: Text(worker['name'] ?? ''),
                                subtitle:
                                    Text(worker['role'] ?? ''),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.person_remove,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () async {
                                    await Supabase.instance.client
                                        .from('workers')
                                        .update({'site_id': null}).eq(
                                            'id', worker['id']);
                                    await activityLog.log(
                                      action: 'Worker Unassigned',
                                      module: 'Sites',
                                      description: 'Unassigned worker ${worker['name']} from site ${_site['name']}',
                                    );
                                    loadWorkers();
                                  },
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.roseGold, size: 18),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 52) / 2,
      height: 48,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: FilledButton.styleFrom(
          backgroundColor: (color ?? AppColors.roseGold).withValues(alpha: 0.85),
        ),
      ),
    );
  }
}