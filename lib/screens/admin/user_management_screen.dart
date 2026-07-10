import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/activity_log_service.dart';
import '../../core/theme/app_colors.dart';
import 'add_edit_user_screen.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  // Use service role key to bypass RLS for all admin user operations
  SupabaseClient? _adminClient;

  SupabaseClient _getAdminClient() {
    if (_adminClient != null) return _adminClient!;
    final serviceKey = dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';
    final url = dotenv.env['SUPABASE_URL'] ?? '';
    _adminClient = SupabaseClient(url, serviceKey);
    return _adminClient!;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _getAdminClient()
          .from('user_profiles')
          .select();
      if (!mounted) return;
      setState(() {
        _users = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      debugPrint('[UserManagement] Error loading users: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load users: $e'),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> user) async {
    final current = user['status'] as String? ?? 'active';
    final newStatus = current == 'active' ? 'disabled' : 'active';

    try {
      await _getAdminClient()
          .from('user_profiles')
          .update({'status': newStatus})
          .eq('id', user['id'] as String);

      await activityLog.log(
        action: newStatus == 'active' ? 'User Enabled' : 'User Disabled',
        module: 'Admin',
        description: '${user['name'] ?? user['id']} → $newStatus',
        oldValue: current,
        newValue: newStatus,
      );

      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${user['name'] ?? 'User'} ${newStatus == 'active' ? 'enabled' : 'disabled'}'),
          backgroundColor:
              newStatus == 'active' ? AppColors.success : AppColors.warning,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete User',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            'Are you sure you want to delete ${user['name'] ?? 'this user'}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(
                      color: AppColors.danger, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _getAdminClient()
          .from('user_profiles')
          .delete()
          .eq('id', user['id'] as String);

      await activityLog.log(
        action: 'User Deleted',
        module: 'Admin',
        description: 'Deleted user: ${user['name'] ?? user['id']}',
      );

      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'admin':
        return AppColors.roseGold;
      case 'projectManager':
        return const Color(0xFF7E9EF5);
      default:
        return AppColors.textSecondary;
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'projectManager':
        return 'Project Manager';
      default:
        return 'Supervisor';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.roseGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_users.length} Users',
                  style:
                      const TextStyle(color: AppColors.roseGold, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const AddEditUserScreen()),
        ).then((_) => _load()),
        icon: const Icon(Icons.person_add),
        label: const Text('Add User'),
        backgroundColor: AppColors.roseGold,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline,
                          size: 72,
                          color: AppColors.roseGold.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      const Text('No Users Found',
                          style: TextStyle(fontSize: 20)),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap + Add User to create the first user.\nMake sure user_profiles table exists.',
                        style: TextStyle(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _users.length,
                    itemBuilder: (_, index) {
                      final user = _users[index];
                      final name =
                          user['name'] as String? ?? 'Unnamed User';
                      final role = user['role'] as String? ?? 'supervisor';
                      final status =
                          user['status'] as String? ?? 'active';
                      final isActive = status == 'active';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor:
                                    _roleColor(role).withValues(alpha: 0.15),
                                child: Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    color: _roleColor(role),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _roleColor(role)
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            _roleLabel(role),
                                            style: TextStyle(
                                              color: _roleColor(role),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? AppColors.success
                                                    .withValues(alpha: 0.12)
                                                : AppColors.danger
                                                    .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isActive ? 'Active' : 'Disabled',
                                            style: TextStyle(
                                              color: isActive
                                                  ? AppColors.success
                                                  : AppColors.danger,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                color: AppColors.card,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    Navigator.of(context, rootNavigator: true).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            AddEditUserScreen(user: user),
                                      ),
                                    ).then((_) => _load());
                                  } else if (value == 'toggle') {
                                    _toggleStatus(user);
                                  } else if (value == 'delete') {
                                    _deleteUser(user);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_outlined,
                                            size: 18),
                                        SizedBox(width: 10),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'toggle',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isActive
                                              ? Icons.block
                                              : Icons.check_circle_outline,
                                          size: 18,
                                          color: isActive
                                              ? AppColors.warning
                                              : AppColors.success,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(isActive ? 'Disable' : 'Enable'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline,
                                            size: 18,
                                            color: AppColors.danger),
                                        SizedBox(width: 10),
                                        Text('Delete',
                                            style: TextStyle(
                                                color: AppColors.danger)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
