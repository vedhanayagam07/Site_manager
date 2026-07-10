import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Color-coded status badge chip — colored border + tinted background.
class StatusChip extends StatelessWidget {
  final String label;
  final Color? color;

  const StatusChip({super.key, required this.label, this.color});

  static Color _colorFor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'present':
      case 'completed':
        return AppColors.success;
      case 'inactive':
      case 'absent':
        return AppColors.danger;
      case 'half day':
      case 'on hold':
      case 'in progress':
        return AppColors.warning;
      case 'low stock':
        return AppColors.danger;
      default:
        return AppColors.roseGold;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? _colorFor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: c.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
