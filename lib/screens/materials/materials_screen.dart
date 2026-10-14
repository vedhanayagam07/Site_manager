import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loader.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/status_chip.dart';
import '../loading_memo/loading_memo_screen.dart';
import 'add_material_screen.dart';
import 'add_material_transaction_screen.dart';
import 'material_detail_screen.dart';

class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({super.key});

  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> materials = [];
  List<Map<String, dynamic>> filteredMaterials = [];
  List<Map<String, dynamic>> sites = [];
  String? selectedFilterSiteId = '';
  final searchController = TextEditingController();
  bool loading = true;
  late AnimationController _listCtrl;

  @override
  void initState() {
    super.initState();
    _listCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    loadMaterials();
  }

  @override
  void dispose() {
    searchController.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  Future<void> loadMaterials() async {
    setState(() => loading = true);
    try {
      final data = await Supabase.instance.client
          .from('materials')
          .select()
          .order('name');
      final sitesData = await Supabase.instance.client
          .from('sites')
          .select()
          .order('name');

      setState(() {
        materials = List<Map<String, dynamic>>.from(data);
        sites = List<Map<String, dynamic>>.from(sitesData);
        loading = false;
      });
      applyFilters();
      _listCtrl.forward(from: 0);
    } catch (e) {
      debugPrint(e.toString());
      setState(() => loading = false);
    }
  }

  void applyFilters() {
    final searchValue = searchController.text.trim().toLowerCase();
    setState(() {
      filteredMaterials = materials.where((material) {
        final name = material['name'].toString().toLowerCase();
        final matchesSearch = name.contains(searchValue);
        if (selectedFilterSiteId != null && selectedFilterSiteId!.isNotEmpty) {
          return matchesSearch &&
              material['site_id'].toString() == selectedFilterSiteId;
        }
        return matchesSearch;
      }).toList();
    });
  }

  int get _lowStockCount => filteredMaterials.where((m) {
        final bal = (m['balance_qty'] as num? ?? 0);
        final min = (m['minimum_stock'] as num? ?? 10);
        return bal <= min;
      }).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Materials'),
        actions: [
          if (!loading && _lowStockCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: StatusChip(
                    label: '⚠ $_lowStockCount Low'),
              ),
            ),
          if (!loading)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.roseGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.roseGold.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${filteredMaterials.length} Items',
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFab(
              heroTag: 'loadingMemo',
              icon: Icons.receipt_long_outlined,
              label: 'Loading Memo',
              onTap: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                      builder: (_) => const LoadingMemoScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _buildFab(
              heroTag: 'stockMovement',
              icon: Icons.swap_horiz,
              label: 'Stock',
              onTap: () async {
                final result = await Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                      builder: (_) => const AddMaterialTransactionScreen()),
                );
                if (result == true) loadMaterials();
              },
            ),
            const SizedBox(height: 10),
            _buildFab(
              heroTag: 'addMaterial',
              icon: Icons.add,
              label: 'Material',
              onTap: () async {
                final result = await Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const AddMaterialScreen()),
                );
                if (result == true) loadMaterials();
              },
            ),
          ],
        ),
      ),
      body: loading
          ? const ShimmerList(count: 6)
          : Column(
              children: [
                // Filters
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          onChanged: (_) => applyFilters(),
                          decoration: const InputDecoration(
                            hintText: 'Search materials…',
                            prefixIcon: Icon(Icons.search,
                                color: AppColors.textSecondary, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (sites.isNotEmpty)
                        PopupMenuButton<String>(
                          color: AppColors.card,
                          icon: const Icon(Icons.filter_list,
                              color: AppColors.roseGold),
                          tooltip: 'Filter by site',
                          onSelected: (value) {
                            setState(
                                () => selectedFilterSiteId = value);
                            applyFilters();
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem<String>(
                              value: '',
                              child: Text('All Sites'),
                            ),
                            ...sites.map((site) => PopupMenuItem<String>(
                                  value: site['id'].toString(),
                                  child:
                                      Text(site['name'] ?? ''),
                                )),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: filteredMaterials.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.inventory_2_outlined,
                          title: searchController.text.isEmpty &&
                                  (selectedFilterSiteId ?? '').isEmpty
                              ? 'No Materials Added'
                              : 'No Results',
                          subtitle: searchController.text.isEmpty &&
                                  (selectedFilterSiteId ?? '').isEmpty
                              ? 'Add your first material to track inventory.'
                              : 'Try a different search or filter.',
                        )
                      : RefreshIndicator(
                          color: AppColors.roseGold,
                          onRefresh: loadMaterials,
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 120),
                            itemCount: filteredMaterials.length,
                            itemBuilder: (context, index) {
                              final material = filteredMaterials[index];
                              return _MaterialCard(
                                material: material,
                                index: index,
                                listCtrl: _listCtrl,
                                onTap: () async {
                                  final result = await Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute(
                                      builder: (_) => MaterialDetailScreen(
                                          material: material),
                                    ),
                                  );
                                  if (result == true) loadMaterials();
                                },
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFab({
    required String heroTag,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        gradient: const LinearGradient(
          colors: [Color(0xFFB77B57), Color(0xFFD4A574)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.roseGold.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        heroTag: heroTag,
        onPressed: onTap,
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Material Card
// ─────────────────────────────────────────────────────────────────────────────
class _MaterialCard extends StatefulWidget {
  final Map<String, dynamic> material;
  final int index;
  final AnimationController listCtrl;
  final VoidCallback onTap;

  const _MaterialCard({
    required this.material,
    required this.index,
    required this.listCtrl,
    required this.onTap,
  });

  @override
  State<_MaterialCard> createState() => _MaterialCardState();
}

class _MaterialCardState extends State<_MaterialCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _barCtrl;
  late Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    final mat = widget.material;
    final currentStock = (mat['balance_qty'] as num? ?? 0).toDouble();
    final maximumStock = (mat['total_received'] as num? ?? currentStock * 2)
        .toDouble()
        .clamp(1.0, double.infinity);
    final ratio = (currentStock / maximumStock).clamp(0.0, 1.0);

    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _barAnim = Tween<double>(begin: 0, end: ratio).animate(
        CurvedAnimation(parent: _barCtrl, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: 150 + widget.index * 60), () {
      if (mounted) _barCtrl.forward();
    });
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mat = widget.material;
    final currentStock = (mat['balance_qty'] as num? ?? 0).toDouble();
    final minimumStock = (mat['minimum_stock'] as num? ?? 10).toDouble();
    final isLow = currentStock <= minimumStock;

    final stockColor = isLow
        ? AppColors.danger
        : currentStock <= minimumStock * 1.5
            ? AppColors.warning
            : AppColors.success;

    // Staggered entrance
    final delay = widget.index * 0.07;
    final start = delay.clamp(0.0, 0.9);
    final end = (delay + 0.4).clamp(0.1, 1.0);

    return AnimatedBuilder(
      animation: widget.listCtrl,
      builder: (_, child) {
        final t = ((widget.listCtrl.value - start) / (end - start))
            .clamp(0.0, 1.0);
        final curve = Curves.easeOutCubic.transform(t);
        return Transform.translate(
          offset: Offset(0, (1 - curve) * 30),
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
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isLow
                    ? AppColors.danger.withValues(alpha: 0.35)
                    : _pressed
                        ? AppColors.roseGold.withValues(alpha: 0.4)
                        : AppColors.roseGold.withValues(alpha: 0.1),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 14,
                  spreadRadius: -3,
                  offset: const Offset(0, 6),
                ),
                if (isLow)
                  BoxShadow(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    blurRadius: 16,
                  ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Icon
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: stockColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: stockColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(Icons.inventory_2,
                            color: stockColor, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mat['name'] ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${currentStock.toStringAsFixed(0)} ${mat['unit'] ?? ''} in stock',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isLow)
                        const StatusChip(label: 'LOW STOCK')
                      else
                        const Icon(Icons.chevron_right,
                            size: 18, color: AppColors.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Stock level bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AnimatedBuilder(
                      animation: _barAnim,
                      builder: (_, __) => LinearProgressIndicator(
                        value: _barAnim.value,
                        backgroundColor: Colors.white10,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(stockColor),
                        minHeight: 5,
                      ),
                    ),
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
