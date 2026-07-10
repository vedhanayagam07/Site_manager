import 'package:flutter/material.dart';
import '../widgets/glass_card.dart';
import '../theme/app_colors.dart';

class ProjectHealthCard extends StatelessWidget {
  const ProjectHealthCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          const Text(
            "PROJECT HEALTH",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),

          const SizedBox(height: 25),

          SizedBox(
            height: 140,
            width: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: 0.87,
                  strokeWidth: 12,
                  backgroundColor: Colors.white10,
                  color: AppColors.roseGold,
                ),

                const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "87%",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text("On Schedule"),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}