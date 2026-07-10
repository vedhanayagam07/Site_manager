import '../../core/widgets/project_health_card.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/section_title.dart';
import '../../core/widgets/animated_stat_card.dart';
import '../../core/widgets/shimmer_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../sites/add_edit_site_screen.dart';
import '../workers/add_worker_screen.dart';
import '../materials/add_material_screen.dart';
import '../../core/widgets/voice_assistant_sheet.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with SingleTickerProviderStateMixin {
  String? _userEmail;
  int totalSites = 0;
  int totalWorkers = 0;
  int totalMaterials = 0;
  int lowStockCount = 0;
  bool loadingStats = true;

  List<Map<String, dynamic>> _sitesList = [];
  List<Map<String, dynamic>> _workersList = [];
  List<Map<String, dynamic>> _materialsList = [];
  List<Map<String, dynamic>> _activitiesList = [];

  late AnimationController _heroCtrl;
  late Animation<double> _heroFade;

  @override
  void initState() {
    super.initState();
    _initializeUser();
    loadDashboardStats();

    _heroCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    _heroCtrl.forward();
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    super.dispose();
  }

  void _initializeUser() {
    _userEmail = Supabase.instance.client.auth.currentUser?.email;
  }

  Future<void> loadDashboardStats() async {
    try {
      final results = await Future.wait([
        Supabase.instance.client.from('sites').select(),
        Supabase.instance.client.from('workers').select(),
        Supabase.instance.client.from('materials').select(),
        Supabase.instance.client
            .from('material_transactions')
            .select('*, materials(name)')
            .order('created_at', ascending: false)
            .limit(5),
      ]);

      final sites = results[0] as List;
      final workers = results[1] as List;
      final materials = results[2] as List;

      List attendanceData = [];
      try {
        attendanceData = await Supabase.instance.client
            .from('site_attendance')
            .select('*, workers(name), sites(name)')
            .order('created_at', ascending: false)
            .limit(5);
      } catch (e) {
        debugPrint('Error fetching attendance: $e');
      }

      final txnsData = results[3] as List;

      int lowStock = 0;
      for (final material in materials) {
        final current = (material['balance_qty'] ?? 0) as num;
        final minimum = (material['minimum_stock'] ?? 10) as num;
        if (current <= minimum) lowStock++;
      }

      final List<Map<String, dynamic>> loadedActivities = [];

      for (var t in txnsData) {
        final matName = t['materials']?['name'] ?? 'Material';
        final type = t['transaction_type'] == 'RECEIVED' ? 'Restocked' : 'Used';
        final qty = t['quantity'].toString();
        final site = t['site_name'] != null && t['site_name'].toString().isNotEmpty
            ? ' at ${t['site_name']}'
            : '';
        final timeStr = t['created_at'] != null
            ? DateTime.parse(t['created_at'])
            : DateTime.now();
        loadedActivities.add({
          'title': '$type $qty units of $matName$site',
          'subtitle': DateFormat('dd MMM, hh:mm a').format(timeStr.toLocal()),
          'icon': Icons.inventory_2_outlined,
          'color': type == 'Restocked' ? AppColors.success : AppColors.roseGold,
          'timestamp': timeStr,
        });
      }

      for (var a in attendanceData) {
        final workerName = a['workers']?['name'] ?? 'Worker';
        final siteName = a['sites']?['name'] ?? 'Site';
        final status = a['status'] ?? 'Checked';
        final timeStr = a['created_at'] != null
            ? DateTime.parse(a['created_at'])
            : DateTime.now();
        loadedActivities.add({
          'title': '$workerName → $status',
          'subtitle': '$siteName · ${DateFormat('dd MMM, hh:mm a').format(timeStr.toLocal())}',
          'icon': Icons.fact_check_outlined,
          'color': status == 'Present'
              ? AppColors.success
              : status == 'Half Day'
                  ? AppColors.warning
                  : AppColors.danger,
          'timestamp': timeStr,
        });
      }

      loadedActivities.sort(
          (a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));
      final finalActivities = loadedActivities.take(6).toList();

      if (mounted) {
        setState(() {
          _sitesList = List<Map<String, dynamic>>.from(sites);
          _workersList = List<Map<String, dynamic>>.from(workers);
          _materialsList = List<Map<String, dynamic>>.from(materials);
          _activitiesList = finalActivities;
          totalSites = sites.length;
          totalWorkers = workers.length;
          totalMaterials = materials.length;
          lowStockCount = lowStock;
          loadingStats = false;
        });
      }
    } catch (e) {
      debugPrint('Dashboard Error: $e');
      if (mounted) setState(() => loadingStats = false);
    }
  }

  void _openVoiceAssistant() {
    final workerNames = _workersList
        .map((w) => (w['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final materialNames = _materialsList
        .map((m) => (m['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final siteNames = _sitesList
        .map((s) => (s['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    VoiceAssistantSheet.show(
      context,
      workerNames: workerNames,
      materialNames: materialNames,
      siteNames: siteNames,
      onRefresh: () => loadDashboardStats(),
      onNavigate: (route) {
        if (mounted) context.go(route);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B12),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'TSR BUILDERS',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() => loadingStats = true);
              loadDashboardStats();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Profile',
            onPressed: () => context.go('/profile'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.roseGold,
        onRefresh: () async {
          setState(() => loadingStats = true);
          await loadDashboardStats();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 100), // below app bar

              // ── Hero banner ────────────────────────────────────────────────
              FadeTransition(
                opacity: _heroFade,
                child: _HeroBanner(userEmail: _userEmail),
              ),
              const SizedBox(height: 32),

              const SectionTitle(title: 'Project Overview'),
              const SizedBox(height: 14),

              // ── Stat cards (animated counters + skeleton) ─────────────────
              loadingStats
                  ? const ShimmerGrid(count: 4)
                  : GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 0.95,
                      children: [
                        AnimatedStatCard(
                          title: 'Active Sites',
                          value: totalSites,
                          icon: Icons.location_city,
                          color: const Color(0xFF7E9EF5),
                          onTap: () => context.go('/sites'),
                        ),
                        AnimatedStatCard(
                          title: 'Workers',
                          value: totalWorkers,
                          icon: Icons.people,
                          color: AppColors.roseGold,
                          onTap: () => context.go('/workers'),
                        ),
                        AnimatedStatCard(
                          title: 'Materials',
                          value: totalMaterials,
                          icon: Icons.inventory,
                          color: const Color(0xFF4DD0E1),
                          onTap: () => context.go('/materials'),
                        ),
                        AnimatedStatCard(
                          title: 'Low Stock',
                          value: lowStockCount,
                          icon: Icons.warning_amber,
                          color: lowStockCount > 0
                              ? AppColors.danger
                              : AppColors.success,
                          subtitle: lowStockCount > 0 ? 'Needs attention' : 'All good',
                          onTap: () => context.go('/materials'),
                        ),
                      ],
                    ),

              const SizedBox(height: 32),

              const ProjectHealthCard(),
              const SizedBox(height: 32),

              // ── Site progress ──────────────────────────────────────────────
              const SectionTitle(title: 'Site Progress'),
              const SizedBox(height: 14),
              loadingStats
                  ? const ShimmerList(count: 3, itemHeight: 80)
                  : _sitesList.isEmpty
                      ? const Center(
                          child: Text(
                            'No active sites',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : GlassCard(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: _sitesList.take(3).map((site) {
                              final progress = (site['progress'] ?? 0) as int;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 20.0),
                                child: _SiteProgressRow(
                                    site: site, progress: progress),
                              );
                            }).toList(),
                          ),
                        ),

              const SizedBox(height: 32),

              // ── Quick actions ─────────────────────────────────────────────
              const SectionTitle(title: 'Quick Actions'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _QuickActionItem(
                    icon: Icons.location_city,
                    title: 'Add Site',
                    color: const Color(0xFF7E9EF5),
                    onTap: () async {
                      final result = await Navigator.of(context, rootNavigator: true).push<bool>(
                        MaterialPageRoute(
                            builder: (_) => const AddEditSiteScreen()),
                      );
                      if (result == true) loadDashboardStats();
                    },
                  ),
                  _QuickActionItem(
                    icon: Icons.people,
                    title: 'Add Worker',
                    color: AppColors.roseGold,
                    onTap: () async {
                      await Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                            builder: (_) => const AddWorkerScreen()),
                      );
                      loadDashboardStats();
                    },
                  ),
                  _QuickActionItem(
                    icon: Icons.inventory,
                    title: 'Add Material',
                    color: const Color(0xFF4DD0E1),
                    onTap: () async {
                      final result = await Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                            builder: (_) => const AddMaterialScreen()),
                      );
                      if (result == true) loadDashboardStats();
                    },
                  ),
                  _QuickActionItem(
                    icon: Icons.bar_chart,
                    title: 'Reports',
                    color: const Color(0xFFCE93D8),
                    onTap: () => context.go('/reports'),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // ── Recent Activity ────────────────────────────────────────────
              const SectionTitle(title: 'Recent Activity'),
              const SizedBox(height: 14),
              loadingStats
                  ? const ShimmerList(count: 4, itemHeight: 72)
                  : _activitiesList.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No recent activity. Start logging!',
                              style:
                                  TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      : Column(
                          children: _activitiesList.map((item) {
                            return _ActivityTile(item: item);
                          }).toList(),
                        ),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: _PremiumFab(onPressed: _openVoiceAssistant),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Banner
// ─────────────────────────────────────────────────────────────────────────────
class _HeroBanner extends StatelessWidget {
  final String? userEmail;
  const _HeroBanner({this.userEmail});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB97A52), Color(0xFFD4A574), Color(0xFFC08050)],
          stops: [0, 0.5, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC68E65).withValues(alpha: 0.3),
            blurRadius: 40,
            spreadRadius: -4,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Gloss shimmer overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.15),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.95),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset('assets/tsrlogo.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TSR BUILDERS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Construction Intelligence Platform',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.account_circle_outlined,
                            color: Colors.white60, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            userEmail ?? 'Administrator',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
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
// Site progress row
// ─────────────────────────────────────────────────────────────────────────────
class _SiteProgressRow extends StatefulWidget {
  final Map<String, dynamic> site;
  final int progress;
  const _SiteProgressRow({required this.site, required this.progress});

  @override
  State<_SiteProgressRow> createState() => _SiteProgressRowState();
}

class _SiteProgressRowState extends State<_SiteProgressRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _progressAnim = Tween<double>(begin: 0, end: widget.progress / 100)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.site['name'] ?? 'Site',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
            AnimatedBuilder(
              animation: _progressAnim,
              builder: (_, __) => Text(
                '${(_progressAnim.value * 100).round()}%',
                style: const TextStyle(
                  color: AppColors.roseGold,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AnimatedBuilder(
            animation: _progressAnim,
            builder: (_, __) => LinearProgressIndicator(
              value: _progressAnim.value,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.roseGold),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Activity tile — timeline style
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ActivityTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = (item['color'] as Color?) ?? AppColors.roseGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border(
          left: BorderSide(color: color, width: 3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(item['icon'] as IconData, color: color, size: 18),
        ),
        title: Text(
          item['title'] as String,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          item['subtitle'] as String,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick action item (enhanced with per-color glow)
// ─────────────────────────────────────────────────────────────────────────────
class _QuickActionItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  State<_QuickActionItem> createState() => _QuickActionItemState();
}

class _QuickActionItemState extends State<_QuickActionItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: (MediaQuery.of(context).size.width - 54) / 2,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF13151E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _isPressed
                  ? widget.color
                  : widget.color.withValues(alpha: 0.2),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _isPressed ? 0.2 : 0.45),
                blurRadius: _isPressed ? 8 : 20,
                offset: Offset(0, _isPressed ? 4 : 10),
              ),
              BoxShadow(
                color: widget.color
                    .withValues(alpha: _isPressed ? 0.15 : 0.04),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.15),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Icon(widget.icon, size: 26, color: widget.color),
              ),
              const SizedBox(height: 10),
              Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium pulsing voice FAB
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumFab extends StatefulWidget {
  final VoidCallback onPressed;
  const _PremiumFab({required this.onPressed});

  @override
  State<_PremiumFab> createState() => _PremiumFabState();
}

class _PremiumFabState extends State<_PremiumFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scaleAnim =
        Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          gradient: const LinearGradient(
            colors: [Color(0xFFB77B57), Color(0xFFD4A574)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.roseGold.withValues(alpha: 0.45),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: widget.onPressed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.mic, color: Colors.white),
          label: const Text(
            'Voice Assistant',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}