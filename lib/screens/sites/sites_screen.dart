import 'site_detail_screen.dart';
import 'add_edit_site_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loader.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/status_chip.dart';

class SitesScreen extends StatefulWidget {
  const SitesScreen({super.key});

  @override
  State<SitesScreen> createState() => _SitesScreenState();
}

class _SitesScreenState extends State<SitesScreen>
    with SingleTickerProviderStateMixin {
  List sites = [];
  bool loading = true;
  late AnimationController _listCtrl;

  @override
  void initState() {
    super.initState();
    _listCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    loadSites();
  }

  @override
  void dispose() {
    _listCtrl.dispose();
    super.dispose();
  }

  Future<void> loadSites() async {
    setState(() => loading = true);
    try {
      final data = await Supabase.instance.client
          .from('sites')
          .select()
          .order('created_at');

      final prefs = await SharedPreferences.getInstance();
      final List updatedSites = [];
      for (var site in data) {
        final siteMap = Map<String, dynamic>.from(site);
        siteMap['progress'] =
            prefs.getInt('site_progress_${siteMap['id']}') ?? 0;
        updatedSites.add(siteMap);
      }

      setState(() {
        sites = updatedSites;
        loading = false;
      });
      _listCtrl.forward(from: 0);
    } catch (e) {
      debugPrint(e.toString());
      setState(() => loading = false);
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'Completed':
        return AppColors.success;
      case 'On Hold':
        return AppColors.warning;
      default:
        return AppColors.roseGold;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Sites'),
        actions: [
          if (!loading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.roseGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.roseGold.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${sites.length} Sites',
                    style: const TextStyle(
                        color: AppColors.roseGold,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: _buildFab(context),
      ),
      body: loading
          ? const ShimmerList(count: 5, itemHeight: 120)
          : sites.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.location_city_outlined,
                  title: 'No Sites Yet',
                  subtitle: 'Add your first construction site to get started.',
                  actionLabel: 'Add Site',
                  onAction: () async {
                    final result = await Navigator.of(context, rootNavigator: true).push<bool>(
                      MaterialPageRoute(
                          builder: (_) => const AddEditSiteScreen()),
                    );
                    if (result == true) loadSites();
                  },
                )
              : RefreshIndicator(
                  color: AppColors.roseGold,
                  onRefresh: loadSites,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: sites.length,
                    itemBuilder: (context, index) {
                      final site = sites[index];
                      return _SiteCard(
                        site: site,
                        index: index,
                        listCtrl: _listCtrl,
                        statusColor: _statusColor(site['status'] as String?),
                        onTap: () async {
                          await Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                                builder: (_) => SiteDetailScreen(site: site)),
                          );
                          loadSites();
                        },
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildFab(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        gradient: const LinearGradient(
          colors: [Color(0xFFB77B57), Color(0xFFD4A574)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.roseGold.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.of(context, rootNavigator: true).push<bool>(
            MaterialPageRoute(builder: (_) => const AddEditSiteScreen()),
          );
          if (result == true) loadSites();
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Site',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Site Card
// ─────────────────────────────────────────────────────────────────────────────
class _SiteCard extends StatefulWidget {
  final dynamic site;
  final int index;
  final AnimationController listCtrl;
  final Color statusColor;
  final VoidCallback onTap;

  const _SiteCard({
    required this.site,
    required this.index,
    required this.listCtrl,
    required this.statusColor,
    required this.onTap,
  });

  @override
  State<_SiteCard> createState() => _SiteCardState();
}

class _SiteCardState extends State<_SiteCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _progressCtrl;
  late Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();
    final progress =
        ((widget.site['progress'] as num? ?? 0).toInt() / 100).clamp(0.0, 1.0);
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _progressAnim = Tween<double>(begin: 0, end: progress)
        .animate(CurvedAnimation(parent: _progressCtrl, curve: Curves.easeOutCubic));

    final delay =
        Duration(milliseconds: 200 + widget.index * 80);
    Future.delayed(delay, () {
      if (mounted) _progressCtrl.forward();
    });
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    final progress = (site['progress'] as num? ?? 0).toInt();
    final status = site['status'] as String?;

    // Staggered entrance
    final delay = widget.index * 0.07;
    final start = delay.clamp(0.0, 0.9);
    final end = (delay + 0.45).clamp(0.1, 1.0);

    return AnimatedBuilder(
      animation: widget.listCtrl,
      builder: (_, child) {
        final t = ((widget.listCtrl.value - start) / (end - start))
            .clamp(0.0, 1.0);
        final curve = Curves.easeOutCubic.transform(t);
        return Transform.translate(
          offset: Offset(0, (1 - curve) * 35),
          child: Opacity(opacity: curve, child: child),
        );
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _pressed
                    ? widget.statusColor.withValues(alpha: 0.5)
                    : widget.statusColor.withValues(alpha: 0.15),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: -3,
                  offset: const Offset(0, 8),
                ),
                if (_pressed)
                  BoxShadow(
                    color: widget.statusColor.withValues(alpha: 0.1),
                    blurRadius: 16,
                  ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Icon with status color bg
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: widget.statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: widget.statusColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(Icons.location_city,
                            color: widget.statusColor, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              site['name'] ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            if ((site['location'] as String? ?? '').isNotEmpty)
                              Row(
                                children: [
                                  const Icon(Icons.place_outlined,
                                      size: 12,
                                      color: AppColors.textSecondary),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      site['location'] ?? '',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      StatusChip(label: status ?? 'Active'),
                    ],
                  ),
                  if ((site['project_manager'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.manage_accounts_outlined,
                            size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 5),
                        Text(
                          site['project_manager'],
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Animated progress bar
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedBuilder(
                            animation: _progressAnim,
                            builder: (_, __) => LinearProgressIndicator(
                              value: _progressAnim.value,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  widget.statusColor),
                              minHeight: 7,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$progress%',
                        style: TextStyle(
                          color: widget.statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}