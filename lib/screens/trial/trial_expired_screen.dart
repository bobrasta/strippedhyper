import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../services/trial_service.dart';

class TrialExpiredScreen extends StatelessWidget {
  const TrialExpiredScreen({super.key, required this.status});
  final TrialStatus status;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF06080D),
    body: Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Icon
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.coral.withValues(alpha: 0.3)),
            ),
            child: Icon(Symbols.lock, size: 32, color: AppColors.coral),
          ),
          const SizedBox(height: 24),

          // Title
          Text('Trial Expired',
              style: AppTheme.pageTitle.copyWith(
                  color: Colors.white, fontSize: 24)),
          const SizedBox(height: 12),

          // Message
          Text(
            status.message ??
                'Your demo access has ended. Contact us to activate a full licence.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySub.copyWith(
                color: Colors.white60, height: 1.6, fontSize: 14),
          ),
          const SizedBox(height: 32),

          // CTA
          SizedBox(
            width: double.infinity,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.teal,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: AppColors.teal.withValues(alpha: 0.4),
                      blurRadius: 20),
                ],
              ),
              child: Center(
                child: Text('Contact us to continue',
                    style: AppTheme.bodyStrong.copyWith(
                        color: const Color(0xFF06120F), fontSize: 15)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('sales@hypermed.app  ·  +255 711 691 789',
              style: AppTheme.monoXs.copyWith(
                  color: Colors.white38, fontSize: 12)),
        ]),
      ),
    ),
  );
}

// ── Pending activation screen ──────────────────────────────────────────────────

class TrialPendingScreen extends StatelessWidget {
  const TrialPendingScreen({super.key, required this.status});
  final TrialStatus status;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF06080D),
    body: Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
            ),
            child: Icon(Symbols.schedule, size: 32, color: AppColors.amber),
          ),
          const SizedBox(height: 24),
          Text('Awaiting Activation',
              style: AppTheme.pageTitle.copyWith(
                  color: Colors.white, fontSize: 24)),
          const SizedBox(height: 12),
          Text(
            status.message ??
                'Your trial request has been submitted. '
                'Contact your administrator to approve access.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySub.copyWith(
                color: Colors.white60, height: 1.6, fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (status.installId != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Install ID', style: AppTheme.monoXs.copyWith(color: Colors.white38, fontSize: 10)),
                const SizedBox(height: 4),
                SelectableText(
                  status.installId!,
                  style: AppTheme.monoXs.copyWith(color: Colors.white60, fontSize: 11),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Share this ID with your administrator to speed up activation.',
                textAlign: TextAlign.center,
                style: AppTheme.monoXs.copyWith(color: Colors.white24, fontSize: 11)),
            const SizedBox(height: 24),
          ],
          Text('sales@hypermed.app  ·  +255 711 691 789',
              style: AppTheme.monoXs.copyWith(
                  color: Colors.white38, fontSize: 12)),
        ]),
      ),
    ),
  );
}

// ── Trial banner — shown inside the app when ≤ 7 days remain ──────────────────

class TrialBanner extends StatelessWidget {
  const TrialBanner({super.key, required this.status, this.onDismiss});
  final TrialStatus status;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final days = status.daysLeft ?? 0;
    final urgent = days <= 3;
    final color = urgent ? AppColors.coral : AppColors.amber;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withValues(alpha: 0.12),
      child: Row(children: [
        Icon(urgent ? Symbols.warning : Symbols.schedule,
            size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(
          days == 0
              ? 'Trial expires today — contact us to continue'
              : '$days day${days == 1 ? '' : 's'} left in your trial',
          style: AppTheme.bodySm.copyWith(color: color, fontSize: 12.5),
        )),
        if (onDismiss != null)
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Symbols.close, size: 14, color: color),
          ),
      ]),
    );
  }
}
