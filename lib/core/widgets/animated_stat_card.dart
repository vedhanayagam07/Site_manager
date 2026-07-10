import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Animated stat card — counts up to [value] with easing animation.
/// Shows an icon in a glowing ring, a label, and an animated counter.
class AnimatedStatCard extends StatefulWidget {
  final String title;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String? subtitle;

  const AnimatedStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color = AppColors.roseGold,
    this.onTap,
    this.subtitle,
  });

  @override
  State<AnimatedStatCard> createState() => _AnimatedStatCardState();
}

class _AnimatedStatCardState extends State<AnimatedStatCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<int> _counterAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _counterAnim = IntTween(begin: 0, end: widget.value).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutExpo),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.4)),
    );
    // Start after a tiny delay so cards cascade
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void didUpdateWidget(AnimatedStatCard old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _counterAnim = IntTween(begin: _counterAnim.value, end: widget.value)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutExpo));
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: AppColors.card,
            border: Border.all(
              color: widget.color.withValues(alpha: 0.18),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: -4,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: widget.color.withValues(alpha: 0.08),
                blurRadius: 20,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with glow ring
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.12),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.2),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Icon(widget.icon, size: 20, color: widget.color),
              ),
              const SizedBox(height: 12),
              // Animated counter
              AnimatedBuilder(
                animation: _counterAnim,
                builder: (_, __) => Text(
                  '${_counterAnim.value}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: widget.color.withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Title
              Text(
                widget.title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: TextStyle(
                    color: widget.color.withValues(alpha: 0.8),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
