import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/activity_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/voice_assistant_sheet.dart';
import '../../core/services/voice_parser.dart';

class MarkAttendanceScreen extends StatefulWidget {
  final Map site;

  const MarkAttendanceScreen({
    super.key,
    required this.site,
  });

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  List workers = [];
  Map<String, String> attendance = {}; // worker_id -> 'Present' / 'Absent' / 'Half Day'

  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    loadWorkers();
  }

  Future<void> loadWorkers() async {
    try {
      final data = await Supabase.instance.client
          .from('workers')
          .select()
          .eq('site_id', widget.site['id']);

      final Map<String, String> initialAttendance = {};
      for (final worker in data) {
        initialAttendance[worker['id']] = 'Present'; // Default to Present
      }

      setState(() {
        workers = data;
        attendance = initialAttendance;
        loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> saveAttendance() async {
    setState(() => saving = true);
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      // Prepare batch records
      final List<Map<String, dynamic>> records = workers.map((worker) {
        return {
          'worker_id': worker['id'],
          'site_id': widget.site['id'],
          'attendance_date': today,
          'status': attendance[worker['id']] ?? 'Present',
        };
      }).toList();

      // Optimize: Single batch database call instead of a loop
      await Supabase.instance.client
          .from('site_attendance')
          .upsert(records);

      await activityLog.log(
        action: 'Attendance Saved',
        module: 'Attendance',
        description: 'Saved attendance for ${widget.site['name']} for date $today',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendance Saved Successfully'),
          backgroundColor: AppColors.success,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save attendance: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  void _openVoiceAssistant() {
    final List<String> workerNames = workers
        .map((w) => (w['name'] as String?) ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    VoiceAssistantSheet.show(
      context,
      workerNames: workerNames,
      onActionConfirmed: (action) {
        if (action.type == VoiceActionType.attendance && action.targetName != null) {
          // Find matching worker (fuzzy matching)
          final matchedWorker = workers.firstWhere(
            (w) {
              final name = (w['name'] as String).toLowerCase().trim();
              final target = action.targetName!.toLowerCase().trim();
              return name == target || name.contains(target) || target.contains(name);
            },
            orElse: () => null,
          );

          if (matchedWorker != null && action.value != null) {
            setState(() {
              attendance[matchedWorker['id']] = action.value!;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Marked ${matchedWorker['name']} as ${action.value}'),
                backgroundColor: AppColors.roseGold,
              ),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Mark Attendance – ${widget.site['name'] ?? ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic, color: AppColors.roseGold),
            onPressed: _openVoiceAssistant,
            tooltip: 'Voice Assist (Tamil/English)',
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Column(
              children: [
                Expanded(
                  child: workers.isEmpty
                      ? const Center(
                          child: Text(
                            'No workers assigned to this site.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: workers.length,
                          itemBuilder: (context, index) {
                            final worker = workers[index];
                            final wId = worker['id'];
                            final currentStatus = attendance[wId] ?? 'Present';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      worker['name'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      worker['role'] ?? '',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // Segmented row of options (Present, Half Day, Absent)
                                    Row(
                                      children: [
                                        _buildStatusOption(wId, 'Present', currentStatus, AppColors.success),
                                        const SizedBox(width: 8),
                                        _buildStatusOption(wId, 'Half Day', currentStatus, AppColors.warning),
                                        const SizedBox(width: 8),
                                        _buildStatusOption(wId, 'Absent', currentStatus, AppColors.danger),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: saving || workers.isEmpty ? null : saveAttendance,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.roseGold,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Save Attendance',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: workers.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: _openVoiceAssistant,
              backgroundColor: AppColors.roseGold,
              child: const Icon(Icons.mic, color: Colors.white),
            ),
    );
  }

  Widget _buildStatusOption(String workerId, String status, String currentStatus, Color color) {
    final isSelected = currentStatus == status;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            attendance[workerId] = status;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
            border: Border.all(
              color: isSelected ? color : AppColors.border.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            status,
            style: TextStyle(
              color: isSelected ? color : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}