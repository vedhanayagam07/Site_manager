import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/providers/site_provider.dart';

class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    try {
      // Clear remember-me so session isn't restored on next cold start
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auth_remember_me', false);
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
    if (context.mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabaseUser = Supabase.instance.client.auth.currentUser;
    final sitesAsync = ref.watch(allSitesProvider);

    final String displayName =
        supabaseUser?.email?.split('@')[0].toUpperCase() ?? 'SITE MANAGER';
    final String email = supabaseUser?.email ?? 'manager@tsrbuilders.com';
    const String roleLabel = 'Project Manager (TSR)';
    const String sessionType = 'Supabase Authenticated';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.danger),
            tooltip: 'Sign Out',
            onPressed: () => _showLogoutConfirmDialog(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // PROFILE CARD
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.card, Color(0xFF1E212B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: AppColors.roseGold.withValues(alpha: 0.15),
                  child: Text(
                    displayName.substring(0, displayName.length > 1 ? 2 : 1),
                    style: const TextStyle(
                      color: AppColors.roseGold,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  roleLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.roseGold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    sessionType,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // ACCOUNT DETAILS SECTION
          _buildSectionHeader('Account details'),
          Card(
            margin: const EdgeInsets.only(bottom: 24),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.email_outlined, color: AppColors.roseGold),
                    title: const Text('Email Address'),
                    subtitle: Text(email, style: const TextStyle(color: AppColors.textSecondary)),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  const ListTile(
                    leading: Icon(Icons.business_outlined, color: AppColors.roseGold),
                    title: Text('Organization'),
                    subtitle: Text('TSR Builders Pvt Ltd', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
          ),

          // MANAGED SITES SECTION
          _buildSectionHeader('Your Managed Sites'),
          sitesAsync.when(
            data: (sitesList) {
              if (sitesList.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'No managed sites assigned.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                );
              }

              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: sitesList.map((site) {
                      final isLast = sitesList.last.id == site.id;
                      return Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.location_city_outlined, color: AppColors.roseGold),
                            title: Text(site.name),
                            subtitle: Text(site.location, style: const TextStyle(color: AppColors.textSecondary)),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: site.status.toUpperCase() == 'ACTIVE'
                                    ? AppColors.success.withValues(alpha: 0.15)
                                    : AppColors.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                site.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: site.status.toUpperCase() == 'ACTIVE'
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                              ),
                            ),
                          ),
                          if (!isLast) const Divider(height: 1, color: Colors.white10),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, stack) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Error loading sites: $err', style: const TextStyle(color: AppColors.danger)),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showLogoutConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to sign out from Site Manager Pro?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _logout(context, ref);
            },
            child: const Text('Sign Out', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.roseGold,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
