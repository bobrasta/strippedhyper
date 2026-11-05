import 'package:flutter/material.dart';

import '../../main.dart' show emailBadgeNotifier;
import '../../theme/app_colors.dart';

/// The Email nav badge: an accent pill with the unread count and a coral
/// one with the failed-send count. Each is hidden at 0; shows "99+" above
/// 99. [compact] is the small version that sits on an icon corner (rail,
/// phone tabs): the pills stack, so it stays narrow and right-aligned.
class EmailNavBadge extends StatelessWidget {
  const EmailNavBadge({super.key, this.compact = false});
  final bool compact;

  static String label(int n) => n > 99 ? '99+' : '$n';

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<({int unread, int failed})>(
    valueListenable: emailBadgeNotifier,
    builder: (_, b, _) {
      if (b.unread <= 0 && b.failed <= 0) return const SizedBox.shrink();
      final pills = [
        if (b.unread > 0)
          _pill(label(b.unread), AppColors.teal, const Color(0xFF06120F)),
        if (b.unread > 0 && b.failed > 0) const SizedBox(width: 4, height: 2),
        if (b.failed > 0)
          Tooltip(
            message: '${b.failed} failed to send',
            child: _pill(label(b.failed), AppColors.coral, Colors.white),
          ),
      ];
      return compact
          ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: pills)
          : Row(mainAxisSize: MainAxisSize.min, children: pills);
    },
  );

  Widget _pill(String text, Color bg, Color fg) => Container(
    constraints: BoxConstraints(minWidth: compact ? 15 : 18),
    padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6, vertical: compact ? 0.5 : 1),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      style: TextStyle(
        fontFamily: 'TildaSans',
        fontSize: compact ? 9.5 : 11,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: fg,
      ),
    ),
  );
}
