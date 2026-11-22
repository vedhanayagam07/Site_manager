import 'package:flutter/material.dart';

/// Skeleton shimmer loader — renders a shimmering placeholder while data loads.
/// Use [ShimmerBlock] for individual shimmer shapes.
class ShimmerLoader extends StatefulWidget {
  final Widget child;
  const ShimmerLoader({super.key, required this.child});

  @override
  State<ShimmerLoader> createState() => _ShimmerLoaderState();
}

class _ShimmerLoaderState extends State<ShimmerLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(_anim.value - 1, 0),
              end: Alignment(_anim.value + 1, 0),
              colors: const [
                Color(0xFF1E2030),
                Color(0xFF2E3050),
                Color(0xFF3A3D60),
                Color(0xFF2E3050),
                Color(0xFF1E2030),
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

/// A single shimmer placeholder rectangle.
class ShimmerBlock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const ShimmerBlock({
    super.key,
    required this.width,
    required this.height,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Full-screen shimmer for a list of cards.
class ShimmerList extends StatelessWidget {
  final int count;
  final double itemHeight;
  const ShimmerList({super.key, this.count = 5, this.itemHeight = 88});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoader(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          count,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              height: itemHeight,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1C2E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const ShimmerBlock(width: 48, height: 48, radius: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ShimmerBlock(
                            width: MediaQuery.of(context).size.width * 0.45,
                            height: 14),
                        const SizedBox(height: 10),
                        ShimmerBlock(
                            width: MediaQuery.of(context).size.width * 0.3,
                            height: 10),
                      ],
                    ),
                  ),
                  const ShimmerBlock(width: 50, height: 22, radius: 11),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grid shimmer for stat cards (2-column).
class ShimmerGrid extends StatelessWidget {
  final int count;
  const ShimmerGrid({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoader(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.2,
        ),
        itemCount: count,
        itemBuilder: (_, __) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1C2E),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              ShimmerBlock(width: 36, height: 36, radius: 10),
              Spacer(),
              ShimmerBlock(width: 48, height: 22),
              SizedBox(height: 8),
              ShimmerBlock(width: 72, height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
