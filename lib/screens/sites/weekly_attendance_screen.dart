import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WeeklyAttendanceScreen extends StatefulWidget {
  final Map site;

  const WeeklyAttendanceScreen({
    super.key,
    required this.site,
  });

  @override
  State<WeeklyAttendanceScreen> createState() =>
      _WeeklyAttendanceScreenState();
}

class _WeeklyAttendanceScreenState
    extends State<WeeklyAttendanceScreen> {
  List attendanceData = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadAttendance();
  }

  Future<void> loadAttendance() async {
    try {
      final weekAgo = DateTime.now()
          .subtract(const Duration(days: 7))
          .toIso8601String()
          .split('T')[0];

      final data = await Supabase.instance.client
          .from('site_attendance')
          .select('*, workers(name)')
          .eq('site_id', widget.site['id'])
          .gte(
            'attendance_date',
            weekAgo,
          );

      final Map<String, int> summary = {};

      for (final row in data) {
        if (row['status'] == 'Present') {
          final name =
              row['workers']['name'];

          summary[name] =
              (summary[name] ?? 0) + 1;
        }
      }

      attendanceData =
          summary.entries
              .map(
                (e) => {
                  'name': e.key,
                  'days': e.value,
                },
              )
              .toList();

      setState(() {
        loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());

      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Weekly Attendance',
        ),
      ),
      body: loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : attendanceData.isEmpty
              ? const Center(
                  child: Text(
                    'No Attendance Found',
                  ),
                )
              : ListView.builder(
                  itemCount:
                      attendanceData.length,
                  itemBuilder:
                      (context, index) {
                    final worker =
                        attendanceData[index];

                    return Card(
                      margin:
                          const EdgeInsets.all(
                        8,
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.person,
                        ),
                        title: Text(
                          worker['name'],
                        ),
                        subtitle: Text(
                          'Present Days: ${worker['days']}',
                        ),
                        trailing: CircleAvatar(
                          child: Text(
                            worker['days']
                                .toString(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}