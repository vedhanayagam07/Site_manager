import '../../screens/workers/workers_screen.dart';
import '../../screens/sites/sites_screen.dart';
import '../../screens/materials/materials_screen.dart';
import '../../screens/attendance/attendance_screen.dart';
import '../../screens/reports/reports_screen.dart';
import '../../screens/admin/admin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/dashboard/dashboard_screen.dart';
import '../providers/role_provider.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/profile/user_profile_screen.dart';

part 'app_router.g.dart';

// ---------------------------------------------------------------------------
// Route path constants
// ---------------------------------------------------------------------------
abstract final class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String dashboard = '/dashboard';
  static const String sites = '/sites';
  static const String siteDetail = '/sites/:siteId';
  static const String attendance = '/attendance';
  static const String materials = '/materials';
  static const String materialDetail = '/materials/:materialId';
  static const String reports = '/reports';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String workers = '/workers';
  static const String workerDetail = '/workers/:workerId';
  static const String admin = '/admin';
}

// ---------------------------------------------------------------------------
// Router provider (code-generated via @riverpod)
// ---------------------------------------------------------------------------
@riverpod
GoRouter appRouter(Ref ref) {
  final authState = ref.watch(_authStateProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final isLoggedIn = authState.maybeWhen(
        data: (session) => session != null,
        orElse: () => false,
      );

      final isSplash = state.matchedLocation == AppRoutes.splash;
      final isLogin = state.matchedLocation == AppRoutes.login;

      if (authState.isLoading) return null;

      if (isLoggedIn) {
        if (isSplash || isLogin) {
          return AppRoutes.dashboard;
        }
      } else {
        if (!isLogin) {
          return AppRoutes.login;
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const _SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            _ScaffoldWithNavBar(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            name: 'dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: AppRoutes.sites,
            name: 'sites',
            builder: (context, state) => const SitesScreen(),
          ),
          GoRoute(
            path: AppRoutes.workers,
            name: 'workers',
            builder: (context, state) => const WorkersScreen(),
          ),
          GoRoute(
            path: AppRoutes.attendance,
            name: 'attendance',
            builder: (context, state) => const AttendanceScreen(),
          ),
          GoRoute(
            path: AppRoutes.materials,
            name: 'materials',
            builder: (context, state) => const MaterialsScreen(),
          ),
          GoRoute(
            path: AppRoutes.reports,
            name: 'reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            name: 'profile',
            builder: (context, state) => const UserProfileScreen(),
          ),
          GoRoute(
            path: AppRoutes.admin,
            name: 'admin',
            builder: (context, state) => const AdminScreen(),
          ),
        ],
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Auth state helper provider
// ---------------------------------------------------------------------------
final _authStateProvider = StreamProvider<Session?>((ref) {
  try {
    return Supabase.instance.client.auth.onAuthStateChange
        .map((event) => event.session);
  } catch (e) {
    debugPrint('Auth state provider error: $e');
    return Stream<Session?>.value(null);
  }
});

// ---------------------------------------------------------------------------
// Splash page — handles Remember Me check on cold start
// ---------------------------------------------------------------------------
class _SplashPage extends StatefulWidget {
  const _SplashPage();

  @override
  State<_SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<_SplashPage> {
  @override
  void initState() {
    super.initState();
    _checkRememberMe();
  }

  Future<void> _checkRememberMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('auth_remember_me') ?? true;
      if (!rememberMe) {
        // User opted out of staying signed in — clear their session
        await Supabase.instance.client.auth.signOut();
      }
    } catch (e) {
      debugPrint('Remember-me check error: $e');
    }
    // GoRouter redirect handles navigation after auth state updates
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                image: const DecorationImage(
                  image: AssetImage('assets/tsrlogo.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'TSR BUILDERS',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Construction Intelligence Platform',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: Color(0xFFC68E65)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom navigation scaffold — shows Admin tab for admin users
// ---------------------------------------------------------------------------
class _ScaffoldWithNavBar extends ConsumerWidget {
  final Widget child;
  const _ScaffoldWithNavBar({required this.child});

  static const _baseDestinations = [
    (
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: 'Home',
      path: AppRoutes.dashboard
    ),
    (
      icon: Icons.location_city_outlined,
      selectedIcon: Icons.location_city,
      label: 'Sites',
      path: AppRoutes.sites
    ),
    (
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: 'Workers',
      path: AppRoutes.workers
    ),
    (
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check,
      label: 'Attendance',
      path: AppRoutes.attendance
    ),
    (
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      label: 'Materials',
      path: AppRoutes.materials
    ),
    (
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      label: 'Reports',
      path: AppRoutes.reports
    ),
  ];

  static const _adminDestination = (
    icon: Icons.admin_panel_settings_outlined,
    selectedIcon: Icons.admin_panel_settings,
    label: 'Admin',
    path: AppRoutes.admin
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(currentUserRoleProvider);
    final role = roleAsync.maybeWhen(data: (r) => r, orElse: () => AppRole.supervisor);
    final isAdmin = role == AppRole.admin;
    final isSupervisor = role == AppRole.supervisor;

    // Supervisor: Home, Sites, Workers, Attendance, Materials, Reports (no Admin)
    // Project Manager: Home, Sites, Workers, Attendance, Materials, Reports (no Admin)
    // Admin: everything + Admin Panel
    // NOTE: Supervisor's OWN attendance is marked by Project Manager (data level, not UI)
    final destinations = [
      _baseDestinations[0], // Home — everyone
      _baseDestinations[1], // Sites — everyone (supervisor needs to assign workers etc.)
      _baseDestinations[2], // Workers — everyone
      _baseDestinations[3], // Attendance — everyone
      _baseDestinations[4], // Materials — everyone
      _baseDestinations[5], // Reports — everyone
      if (isAdmin) _adminDestination, // Admin Panel — admin only
    ];

    final location = GoRouterState.of(context).matchedLocation;
    int selectedIndex = destinations.indexWhere(
      (d) => location.startsWith(d.path),
    );
    if (selectedIndex < 0) selectedIndex = 0;

    return Scaffold(
      body: child,
      extendBody: true, // content flows under nav bar
      bottomNavigationBar: _FloatingNavBar(
        destinations: destinations
            .map((d) => _NavItem(
                  icon: d.icon,
                  selectedIcon: d.selectedIcon,
                  label: d.label,
                ))
            .toList(),
        selectedIndex: selectedIndex,
        onTap: (i) => context.go(destinations[i].path),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Floating Frosted-Glass Navigation Bar
// ─────────────────────────────────────────────────────────────────────────────
class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class _FloatingNavBar extends StatelessWidget {
  final List<_NavItem> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _FloatingNavBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 66,
          decoration: BoxDecoration(
            color: const Color(0xFF141620),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: const Color(0xFFC68E65).withValues(alpha: 0.18),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 30,
                spreadRadius: -4,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: const Color(0xFFC68E65).withValues(alpha: 0.06),
                blurRadius: 20,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(destinations.length, (i) {
                final item = destinations[i];
                final isSelected = i == selectedIndex;
                return _NavBarItem(
                  item: item,
                  isSelected: isSelected,
                  onTap: () => onTap(i),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatefulWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_NavBarItem> createState() => _NavBarItemState();
}

class _NavBarItemState extends State<_NavBarItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scaleAnim =
        Tween<double>(begin: 1, end: 0.88).animate(CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const roseGold = Color(0xFFC68E65);

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: widget.isSelected
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: widget.isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [
                      roseGold.withValues(alpha: 0.22),
                      roseGold.withValues(alpha: 0.10),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                      color: roseGold.withValues(alpha: 0.3), width: 1),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  widget.isSelected
                      ? widget.item.selectedIcon
                      : widget.item.icon,
                  key: ValueKey(widget.isSelected),
                  color: widget.isSelected ? roseGold : Colors.white38,
                  size: widget.isSelected ? 20 : 18,
                ),
              ),
              if (widget.isSelected) ...[
                const SizedBox(width: 6),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: const TextStyle(
                    color: roseGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                  child: Text(widget.item.label),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

