import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/role_provider.dart';
import '../../core/theme/app_colors.dart';
import 'user_management_screen.dart';
import 'activity_log_screen.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  bool _loading = true;
  Map<String, int> _stats = {};
  List<Map<String, dynamic>> _recentActivity = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final results = await Future.wait([
        client.from('user_profiles').count(CountOption.exact),
        client.from('user_profiles').count(CountOption.exact).eq('status', 'active'),
        client.from('sites').count(CountOption.exact).inFilter('status', ['Active', 'ACTIVE', 'active']),
        client.from('materials').count(CountOption.exact),
        client.from('site_attendance').count(CountOption.exact).eq('attendance_date', today),
      ]);

      List<Map<String, dynamic>> logs = [];
      try {
        final logsData = await client
            .from('activity_logs')
            .select()
            .order('created_at', ascending: false)
            .limit(10);
        logs = List<Map<String, dynamic>>.from(logsData);
      } catch (_) {
        // activity_logs table may not exist yet
      }

      if (!mounted) return;
      setState(() {
        _stats = {
          'totalUsers': results[0],
          'activeUsers': results[1],
          'activeSites': results[2],
          'materials': results[3],
          'todayAttendance': results[4],
        };
        _recentActivity = logs;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminScreen] Error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(currentUserRoleProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin Panel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: roleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildAccessDenied(),
        data: (role) {
          if (role != AppRole.admin) return _buildAccessDenied();
          return _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Stats grid
                        _buildSectionHeader('Overview'),
                        const SizedBox(height: 12),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.2,
                          children: [
                            _StatCard(
                              label: 'Total Users',
                              value: '${_stats['totalUsers'] ?? 0}',
                              icon: Icons.people_outline,
                              color: const Color(0xFF7E9EF5),
                            ),
                            _StatCard(
                              label: 'Active Users',
                              value: '${_stats['activeUsers'] ?? 0}',
                              icon: Icons.person_outline,
                              color: AppColors.success,
                            ),
                            _StatCard(
                              label: 'Active Sites',
                              value: '${_stats['activeSites'] ?? 0}',
                              icon: Icons.location_city_outlined,
                              color: AppColors.roseGold,
                            ),
                            _StatCard(
                              label: 'Materials',
                              value: '${_stats['materials'] ?? 0}',
                              icon: Icons.inventory_2_outlined,
                              color: AppColors.warning,
                            ),
                            _StatCard(
                              label: "Today's Attendance",
                              value: '${_stats['todayAttendance'] ?? 0}',
                              icon: Icons.fact_check_outlined,
                              color: const Color(0xFFCE93D8),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),

                        // Quick access
                        _buildSectionHeader('Management'),
                        const SizedBox(height: 12),
                        _AdminNavCard(
                          icon: Icons.manage_accounts_outlined,
                          title: 'User Management',
                          subtitle: 'Add, edit, disable or remove users',
                          color: const Color(0xFF7E9EF5),
                          onTap: () => Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (_) => const UserManagementScreen(),
                            ),
                          ).then((_) => _load()),
                        ),
                        const SizedBox(height: 12),
                        _AdminNavCard(
                          icon: Icons.history_outlined,
                          title: 'Activity Log',
                          subtitle: 'Full audit trail of all app actions',
                          color: AppColors.roseGold,
                          onTap: () => Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (_) => const ActivityLogScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Recent activity
                        if (_recentActivity.isNotEmpty) ...[
                          _buildSectionHeader('Recent Activity'),
                          const SizedBox(height: 12),
                          ..._recentActivity.map((log) => _ActivityTile(log: log)),
                        ] else ...[
                          _buildSectionHeader('Recent Activity'),
                          const SizedBox(height: 12),
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(
                                child: Text(
                                  'No activity logs yet.\nRun the SQL migration to enable logging.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
        },
      ),
    );
  }

  Widget _buildAccessDenied() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline,
              size: 72, color: AppColors.roseGold.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('Access Denied',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'You must be an Admin to access this panel.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: AppColors.roseGold,
        fontWeight: FontWeight.bold,
        fontSize: 12,
        letterSpacing: 1.1,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat Card
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Navigation Card
// ─────────────────────────────────────────────────────────────────────────────
class _AdminNavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminNavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Activity Tile
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityTile extends StatelessWidget {
  final Map<String, dynamic> log;
  const _ActivityTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final action = log['action'] as String? ?? '';
    final module = log['module'] as String? ?? '';
    final userName = log['user_name'] as String? ?? 'Unknown';
    final desc = log['description'] as String? ?? '';
    final createdAt = log['created_at'] as String?;
    String timeLabel = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        timeLabel = DateFormat('dd MMM HH:mm').format(dt);
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.roseGold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.history, color: AppColors.roseGold, size: 18),
        ),
        title: Text(
          '$action — $module',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Text(
          desc.isNotEmpty ? '$userName · $desc' : userName,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          timeLabel,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ),
    );
  }
}
