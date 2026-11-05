import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../theme/hr_category_colors.dart';

/// Replaces the flat "16 Headcount" / "0 Open Vacancies" style card seen
/// across HR Dashboard and Reports. Non-zero values pick up their category
/// color (icon, number, tinted background); zero values stay muted gray so
/// they visually recede instead of carrying equal weight to real numbers.
class HrMetricCard extends StatelessWidget {
  final HrCategory category;
  final String label;
  final int value;

  const HrMetricCard({
    super.key,
    required this.category,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final isZero = value == 0;
    final tint = isZero ? pal.textDim : category.color;
    final bg = isZero ? pal.surface1 : category.soft;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(category.icon, size: 18, color: tint),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: AppTheme.kpiValue.copyWith(color: isZero ? pal.textDim : tint),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTheme.bodySub),
        ],
      ),
    );
  }
}
