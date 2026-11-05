import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.coralSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.coral.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(Symbols.error_outline, size: 16, color: AppColors.coral),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
              style: TextStyle(color: AppColors.coral, fontSize: 13))),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRetry,
              child: Text('Retry',
                  style: TextStyle(
                      color: AppColors.coral,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ],
        ]),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.coralSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Symbols.cloud_off, size: 28, color: AppColors.coral),
          ),
          const SizedBox(height: 16),
          Text('Something went wrong',
              style: AppTheme.bodyStrong.copyWith(fontSize: 15)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: AppTheme.bodySub.copyWith(fontSize: 13, height: 1.5)),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: context.pal.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.pal.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Symbols.refresh, size: 16, color: AppColors.teal),
                  const SizedBox(width: 8),
                  Text('Try again',
                      style: AppTheme.bodySm.copyWith(color: AppColors.teal,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
