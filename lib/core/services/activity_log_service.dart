import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IMPORTANT: Run this SQL once in your Supabase SQL editor before using logs:
//
// CREATE TABLE IF NOT EXISTS activity_logs (
//   id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
//   user_id     TEXT,
//   user_name   TEXT,
//   role        TEXT,
//   action      TEXT        NOT NULL,
//   module      TEXT        NOT NULL,
//   old_value   TEXT,
//   new_value   TEXT,
//   description TEXT,
//   created_at  TIMESTAMPTZ DEFAULT NOW()
// );
// ─────────────────────────────────────────────────────────────────────────────

class ActivityLogService {
  static final ActivityLogService _instance = ActivityLogService._internal();
  factory ActivityLogService() => _instance;
  ActivityLogService._internal();

  /// Log an important action to the activity_logs table.
  /// Silently fails — never throws — so it never breaks the calling operation.
  Future<void> log({
    required String action,
    required String module,
    String? description,
    String? oldValue,
    String? newValue,
  }) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;

      String? userId = user?.id;
      String? userName = user?.email;

      // Try to fetch the user's profile name
      if (user != null) {
        try {
          final profile = await client
              .from('user_profiles')
              .select('name, role')
              .eq('id', user.id)
              .maybeSingle();
          if (profile != null) {
            userName = (profile['name'] as String?)?.isNotEmpty == true
                ? profile['name'] as String
                : user.email;
          }
        } catch (_) {
          // Table may not exist yet — use auth email
        }
      } else {
        // Demo session fallback
        userId = 'demo-user-001';
        userName = 'Demo User';
      }

      await client.from('activity_logs').insert({
        'user_id': userId,
        'user_name': userName,
        'action': action,
        'module': module,
        'old_value': oldValue,
        'new_value': newValue,
        'description': description,
      });
    } catch (e) {
      // Never interrupt the app — just log to debug output
      debugPrint('[ActivityLog] Failed to write log: $e');
    }
  }

  /// Fetch activity logs for the admin screen with optional filters.
  Future<List<Map<String, dynamic>>> fetchLogs({
    String? searchQuery,
    String? moduleFilter,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var query = Supabase.instance.client
          .from('activity_logs')
          .select();

      if (fromDate != null) {
        query = query.gte('created_at', fromDate.toIso8601String());
      }
      if (toDate != null) {
        query = query.lte(
          'created_at',
          toDate.copyWith(hour: 23, minute: 59, second: 59).toIso8601String(),
        );
      }
      if (moduleFilter != null && moduleFilter.isNotEmpty) {
        query = query.eq('module', moduleFilter);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      final logs = List<Map<String, dynamic>>.from(data);

      // Apply search filter in-memory (simpler than server-side ilike on multiple cols)
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        return logs.where((log) {
          return (log['action'] as String? ?? '').toLowerCase().contains(q) ||
              (log['user_name'] as String? ?? '').toLowerCase().contains(q) ||
              (log['description'] as String? ?? '').toLowerCase().contains(q) ||
              (log['module'] as String? ?? '').toLowerCase().contains(q);
        }).toList();
      }

      return logs;
    } catch (e) {
      debugPrint('[ActivityLog] Failed to fetch logs: $e');
      return [];
    }
  }
}

/// Singleton shorthand for convenience across the app.
final activityLog = ActivityLogService();
