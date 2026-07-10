import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loader.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/status_chip.dart';
import 'add_worker_screen.dart';
import 'worker_profile_screen.dart';

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  late AnimationController _listCtrl;

  @override
  void initState() {
    super.initState();
    _listCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('workers')
          .select()
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(data);
      setState(() {
        _workers = list;
        _filtered = list;
        _loading = false;
      });
      _listCtrl.forward(from: 0);
    } catch (e) {
      debugPrint(e.toString());
      setState(() => _loading = false);
    }
  }

  void _search(String q) {
    final query = q.toLowerCase();
    setState(() {
      _filtered = _workers.where((w) {
        return (w['name'] ?? '').toLowerCase().contains(query) ||
            (w['role'] ?? '').toLowerCase().contains(query) ||
            (w['phone'] ?? '').toString().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeCount =
        _filtered.where((w) => w['status'] == 'Active').length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Workers'),
        actions: [
          if (!_loading)
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
                    '$activeCount active / ${_filtered.length} total',
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
      body: _loading
          ? const ShimmerList(count: 6)
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _search,
                    decoration: InputDecoration(
                      hintText: 'Search by name, role, phone…',
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.textSecondary, size: 20),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _search('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _filtered.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.people_outline,
                          title: 'No Workers Found',
                          subtitle: _searchCtrl.text.isEmpty
                              ? 'Add your first worker to get started.'
                              : 'No workers match your search.',
                          actionLabel:
                              _searchCtrl.text.isEmpty ? 'Add Worker' : null,
                          onAction: _searchCtrl.text.isEmpty
                              ? () async {
                                  await Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const AddWorkerScreen()),
                                  );
                                  _load();
                                }
                              : null,
                        )
                      : RefreshIndicator(
                          color: AppColors.roseGold,
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              final worker = _filtered[index];
                              return _WorkerCard(
                                worker: worker,
                                index: index,
                                listCtrl: _listCtrl,
                                onTap: () async {
                                  final changed =
                                      await Navigator.of(context, rootNavigator: true).push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => WorkerProfileScreen(
                                          worker: worker),
                                    ),
                                  );
                                  if (changed == true) _load();
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
          await Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => const AddWorkerScreen()),
          );
          _load();
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Worker',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Worker Card
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerCard extends StatefulWidget {
  final Map<String, dynamic> worker;
  final int index;
  final AnimationController listCtrl;
  final VoidCallback onTap;

  const _WorkerCard({
    required this.worker,
    required this.index,
    required this.listCtrl,
    required this.onTap,
  });

  @override
  State<_WorkerCard> createState() => _WorkerCardState();
}

class _WorkerCardState extends State<_WorkerCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final worker = widget.worker;
    final name = (worker['name'] as String? ?? 'W');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'W';
    final isActive = worker['status'] == 'Active';
    final avatarColor =
        isActive ? AppColors.roseGold : AppColors.textSecondary;

    // Staggered entrance animation
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
                color: _pressed
                    ? AppColors.roseGold.withValues(alpha: 0.5)
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
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: avatarColor.withValues(alpha: 0.12),
                      border: Border.all(
                        color: avatarColor.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: avatarColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          worker['name'] ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${worker['role'] ?? '—'}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if ((worker['phone'] as String?) != null &&
                            (worker['phone'] as String).isNotEmpty)
                          Text(
                            worker['phone'],
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Status chip
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusChip(label: worker['status'] ?? 'Active'),
                      const SizedBox(height: 6),
                      const Icon(Icons.chevron_right,
                          size: 16, color: AppColors.textSecondary),
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