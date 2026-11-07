import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show notificationCountNotifier;
import '../../models/notification.dart';
import '../../services/notification_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/shimmer_box.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.onOpenNotification});
  final ValueChanged<AppNotification>? onOpenNotification;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

const _categoryOrder = ['Approvals', 'Inventory', 'HR', 'Sales', 'Updates', 'System'];
const _categoryHeaders = {
  'Approvals': 'Approvals Needed',
  'Inventory': 'Inventory',
  'HR':        'HR',
  'Sales':     'Sales',
  'Updates':   'Updates',
  'System':    'System',
};

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known notifications instantly
    // if we have them cached, then quietly refresh — same reasoning as
    // InventoryItemsScreen, so this screen doesn't blank to a shimmer on
    // every navigation.
    final cached = NotificationService.cachedDefaultList;
    if (cached != null) {
      _notifications = cached;
      _loading = false;
      // After this frame: initState runs while the shell is building, and
      // the top bar's bell listens to this notifier (setState-during-build).
      final unread = _unreadCount;
      WidgetsBinding.instance.addPostFrameCallback((_) => notificationCountNotifier.value = unread);
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_notifications.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final data = await NotificationService.instance.list(noCache: true);
      if (mounted) {
        setState(() { _notifications = data; _loading = false; });
        notificationCountNotifier.value = _unreadCount;
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to load notifications.'; });
    }
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> _markAllRead() async {
    setState(() {
      _notifications = _notifications.map((n) => AppNotification(
        id: n.id, type: n.type, title: n.title, body: n.body,
        entityType: n.entityType, entityId: n.entityId,
        isRead: true, createdAt: n.createdAt,
      )).toList();
    });
    notificationCountNotifier.value = 0;
    try { await NotificationService.instance.markAllRead(); } catch (_) {}
  }

  Future<void> _markRead(AppNotification n) async {
    if (n.isRead) return;
    setState(() {
      _notifications = _notifications.map((x) => x.id == n.id
          ? AppNotification(id: x.id, type: x.type, title: x.title, body: x.body,
              entityType: x.entityType, entityId: x.entityId,
              isRead: true, createdAt: x.createdAt)
          : x).toList();
    });
    notificationCountNotifier.value = _unreadCount;
    try { await NotificationService.instance.markRead(n.id); } catch (_) {}
  }

  void _open(AppNotification n) {
    _markRead(n);
    widget.onOpenNotification?.call(n);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.pal.border)),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Notifications', style: AppTheme.pageTitle),
              const SizedBox(height: 2),
              Text('Tap a notification to act on it.',
                  style: AppTheme.bodySub.copyWith(fontSize: 12.5)),
            ])),
            if (_unreadCount > 0) ...[
              GestureDetector(
                onTap: _markAllRead,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.pal.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Mark all read',
                      style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 10),
            ],
            GestureDetector(
              onTap: _load,
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  border: Border.all(color: context.pal.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Symbols.refresh, size: 17, color: context.pal.textMute),
              ),
            ),
          ]),
        ),

        // Body
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return SingleChildScrollView(child: shimmerList(count: 10));
    }

    // A background refresh failing while stale-but-valid cached
    // notifications are already showing shouldn't blow that away —
    // only surface the error when there's nothing else to show.
    if (_error != null && _notifications.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Symbols.error_outline, size: 36, color: AppColors.coral),
        const SizedBox(height: 10),
        Text(_error!, style: AppTheme.bodySub.copyWith(color: AppColors.coral)),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _load,
          child: Text('Retry', style: AppTheme.bodySm.copyWith(color: AppColors.teal)),
        ),
      ]));
    }

    if (_notifications.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Symbols.notifications_off, size: 40, color: context.pal.textDim),
        const SizedBox(height: 12),
        Text('No notifications', style: AppTheme.pageTitle.copyWith(fontSize: 16)),
        const SizedBox(height: 6),
        Text("You're all caught up.", style: AppTheme.bodySub),
      ]));
    }

    final grouped = <String, List<AppNotification>>{};
    for (final n in _notifications) {
      grouped.putIfAbsent(n.type.category, () => []).add(n);
    }
    final sections = _categoryOrder.where((c) => grouped[c]?.isNotEmpty == true).toList();

    final children = <Widget>[];
    for (final cat in sections) {
      final items = grouped[cat]!;
      children.add(_CategoryHeader(_categoryHeaders[cat] ?? cat, count: items.length));
      for (var i = 0; i < items.length; i++) {
        children.add(_NotificationRow(
          notification: items[i],
          isLast: i == items.length - 1,
          onTap: () => _open(items[i]),
        ));
      }
    }
    return ListView(padding: EdgeInsets.zero, children: children);
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader(this.label, {required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
    color: context.pal.surface2,
    child: Row(children: [
      Text(label.toUpperCase(), style: AppTheme.labelCaps),
      const SizedBox(width: 6),
      Text('($count)', style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
    ]),
  );
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.notification,
    required this.isLast,
    required this.onTap,
  });

  final AppNotification notification;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    final color = notification.type.color;
    final action = notification.type.actionLabel;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: unread ? context.pal.surface1 : Colors.transparent,
          border: isLast ? null : Border(
              bottom: BorderSide(color: context.pal.divider)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(notification.type.icon, size: 18, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(notification.title,
                  style: AppTheme.bodyStrong.copyWith(
                    fontSize: 13,
                    fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                  ))),
              if (unread)
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                      color: AppColors.teal, shape: BoxShape.circle),
                ),
            ]),
            const SizedBox(height: 3),
            Text(notification.body,
                style: AppTheme.bodySub.copyWith(fontSize: 12.5, height: 1.4),
                maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 7),
            Row(children: [
              Text(notification.createdAt,
                  style: AppTheme.monoXs.copyWith(
                      color: context.pal.textDim, fontSize: 10.5)),
              if (action != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(action, style: AppTheme.bodySub.copyWith(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }
}
