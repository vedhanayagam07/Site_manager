import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final Map site;

  const AttendanceHistoryScreen({
    super.key,
    required this.site,
  });

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState
    extends State<AttendanceHistoryScreen> {
  List attendance = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadAttendance();
  }

  Future<void> loadAttendance() async {
    try {
      final data = await Supabase.instance.client
          .from('site_attendance')
          .select('*, workers(name)')
          .eq('site_id', widget.site['id'])
          .order(
            'attendance_date',
            ascending: false,
          );

      setState(() {
        attendance = data;
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
          'Attendance History',
        ),
      ),
      body: loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : attendance.isEmpty
              ? const Center(
                  child: Text(
                    'No Attendance Records',
                  ),
                )
              : ListView.builder(
                  itemCount: attendance.length,
                  itemBuilder: (context, index) {
                    final record =
                        attendance[index];

                    final worker =
                        record['workers'];

                    final present =
                        record['status'] ==
                            'Present';

                    return Card(
                      margin:
                          const EdgeInsets.all(
                        8,
                      ),
                      child: ListTile(
                        leading: Icon(
                          present
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: present
                              ? Colors.green
                              : Colors.red,
                        ),
                        title: Text(
                          worker['name'] ??
                              '',
                        ),
                        subtitle: Text(
                          DateFormat(
                            'dd MMM yyyy',
                          ).format(
                            DateTime.parse(
                              record[
                                  'attendance_date'],
                            ),
                          ),
                        ),
                        trailing: Text(
                          record['status'],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}