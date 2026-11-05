import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

import '../../theme/app_palette.dart';
enum BtnVariant { primary, ghost, danger, normal }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = BtnVariant.normal,
    this.small = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final BtnVariant variant;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final h = small ? 28.0 : 34.0;
    final fs = small ? 12.0 : 13.0;
    final px = small ? 10.0 : 14.0;
    final r  = small ?  6.0 :  8.0;

    final (Color fg, Color bg, Color border) = switch (variant) {
      BtnVariant.primary => (
        const Color(0xFF06120F),
        AppColors.teal,
        Colors.transparent,
      ),
      BtnVariant.ghost => (
        context.pal.textMute,
        Colors.transparent,
        context.pal.border,
      ),
      BtnVariant.danger => (
        AppColors.coral,
        AppColors.coralSoft,
        AppColors.coral.withValues(alpha: 0.3),
      ),
      BtnVariant.normal => (
        context.pal.text,
        context.pal.surface1,
        context.pal.borderStrong,
      ),
    };

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: h,
        padding: EdgeInsets.symmetric(horizontal: px),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(r),
          border: Border.all(color: border),
          boxShadow: variant == BtnVariant.primary
              ? [
                  BoxShadow(color: AppColors.teal.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 4)),
                  BoxShadow(color: AppColors.teal.withValues(alpha: 0.50), spreadRadius: -1, blurRadius: 0),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: small ? 15 : 17, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label,
              style: AppTheme.bodySm.copyWith(
                color: fg, fontSize: fs,
                fontWeight: variant == BtnVariant.primary ? FontWeight.w600 : FontWeight.w500,
              )),
          ],
        ),
      ),
    );
  }
}
