import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Premium floating card with layered shadows, optional glow border,
/// and a subtle gloss inner highlight — inspired by Apple VisionOS material.
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? glowColor;
  final bool enableGlow;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.glowColor,
    this.enableGlow = false,
    this.width,
    this.height,
    this.onTap,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final glow = glowColor ?? AppColors.roseGold;
    final br = borderRadius ?? BorderRadius.circular(24);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: br,
        color: AppColors.card,
        border: Border.all(
          color: enableGlow
              ? glow.withValues(alpha: 0.45)
              : AppColors.roseGold.withValues(alpha: 0.12),
          width: 1.2,
        ),
        boxShadow: [
          // Deep base shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
          // Subtle ambient
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          // Glow halo
          if (enableGlow)
            BoxShadow(
              color: glow.withValues(alpha: 0.18),
              blurRadius: 30,
              spreadRadius: -2,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: Stack(
          children: [
            // Inner gloss highlight at top edge
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            if (onTap != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: br,
                  onTap: onTap,
                  splashColor: AppColors.roseGold.withValues(alpha: 0.06),
                  highlightColor: AppColors.roseGold.withValues(alpha: 0.03),
                  child: Padding(
                    padding: padding ?? const EdgeInsets.all(20),
                    child: child,
                  ),
                ),
              )
            else
              Padding(
                padding: padding ?? const EdgeInsets.all(20),
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}
