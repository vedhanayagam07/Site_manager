import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      List<Map<String, dynamic>> loadedUsers = [];

      // 1. Primary path: query via standard authenticated client (enforced by RLS)
      try {
        final data = await Supabase.instance.client
            .from('user_profiles')
            .select()
            .order('name');
        loadedUsers = List<Map<String, dynamic>>.from(data);
      } catch (rlsError) {
        debugPrint('[UserManagement] Direct select failed ($rlsError), falling back to Edge Function.');
      }

      // 2. Fallback path: invoke the authorized Edge Function if RLS returned empty or threw
      if (loadedUsers.isEmpty) {
        try {
          final res = await Supabase.instance.client.functions.invoke(
            'admin-manage-user',
            body: {'action': 'list_users'},
          );
          if (res.status == 200 && res.data is Map && res.data['users'] is List) {
            loadedUsers = List<Map<String, dynamic>>.from(res.data['users']);
          }
        } catch (edgeError) {
          debugPrint('[UserManagement] Edge function list fallback failed: $edgeError');
        }
      }

      if (!mounted) return;
      setState(() {
        _users = loadedUsers;
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
      final res = await Supabase.instance.client.functions.invoke(
        'admin-manage-user',
        body: {
          'action': 'toggle_status',
          'userId': user['id'] as String,
          'newStatus': newStatus,
        },
      );

      if (res.status != 200) {
        final errorMsg = (res.data is Map && res.data['error'] != null)
            ? res.data['error'].toString()
            : 'Failed to update user status';
        throw Exception(errorMsg);
      }

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
            'Are you sure you want to delete ${user['name'] ?? 'this user'}? This will permanently remove both their profile and login account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'admin-manage-user',
        body: {
          'action': 'delete_user',
          'userId': user['id'] as String,
        },
      );

      if (res.status != 200) {
        final errorMsg = (res.data is Map && res.data['error'] != null)
            ? res.data['error'].toString()
            : 'Failed to delete user';
        throw Exception(errorMsg);
      }

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
                        'Tap + Add User to create the first user.\nMake sure user_profiles table exists in Supabase.',
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
                      final email = user['email'] as String? ?? '';
                      final isActive = status == 'active';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isActive
                                ? AppColors.border
                                : Colors.white10,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            radius: 22,
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
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isActive
                                        ? Colors.white
                                        : Colors.white38,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? AppColors.success
                                          .withValues(alpha: 0.15)
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isActive ? 'Active' : 'Disabled',
                                  style: TextStyle(
                                    color: isActive
                                        ? AppColors.success
                                        : Colors.white38,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (email.isNotEmpty)
                                Text(
                                  email,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12),
                                ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _roleColor(role)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _roleLabel(role),
                                  style: TextStyle(
                                    color: _roleColor(role),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert,
                                color: AppColors.textSecondary),
                            color: AppColors.card,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            onSelected: (val) {
                              if (val == 'edit') {
                                Navigator.of(context, rootNavigator: true)
                                    .push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AddEditUserScreen(user: user),
                                  ),
                                ).then((_) => _load());
                              } else if (val == 'toggle') {
                                _toggleStatus(user);
                              } else if (val == 'delete') {
                                _deleteUser(user);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined,
                                        size: 18, color: AppColors.roseGold),
                                    SizedBox(width: 8),
                                    Text('Edit User'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Row(
                                  children: [
                                    Icon(
                                      isActive
                                          ? Icons.block_outlined
                                          : Icons.check_circle_outline,
                                      size: 18,
                                      color: isActive
                                          ? AppColors.warning
                                          : AppColors.success,
                                    ),
                                    SizedBox(width: 8),
                                    Text(isActive
                                        ? 'Disable User'
                                        : 'Enable User'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline,
                                        size: 18, color: AppColors.danger),
                                    SizedBox(width: 8),
                                    Text('Delete User',
                                        style:
                                            TextStyle(color: AppColors.danger)),
                                  ],
                                ),
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
