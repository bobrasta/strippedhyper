import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show authTokenNotifier, notificationCountNotifier, roleDisplayName, userNameNotifier, userRoleNotifier;
import '../../models/notification.dart';
import '../../models/search_result.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/search_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'current_user_avatar.dart';
import 'labeled_field.dart';
import 'sidebar.dart' show allNavPages;
import '../chat/chat_dock.dart' show ChatUnreadBadge, openChatFullScreen;
import '../../services/chat_controller.dart' show chatAvailableNotifier;

class TopBar extends StatefulWidget {
  const TopBar({super.key, this.onMenuPressed, this.onOpenNotification, this.onOpenSearchResult,
      this.onOpenProfile, this.title, this.compact = false, this.canOpenPage});
  /// Which menu screens this user may open — search lists only those under "Pages".
  final bool Function(String key)? canOpenPage;
  /// The avatar opens the user's own profile (Settings → Profile).
  final VoidCallback? onOpenProfile;
  final VoidCallback? onMenuPressed;
  /// Phone layout: brand + current page [title], search opens full screen,
  /// theme and log out move into the avatar menu. Navigation lives in the
  /// shell's bottom tab bar, so there is no hamburger.
  final bool compact;
  /// Current page name, shown in the [compact] layout.
  final String? title;
  /// Called with the tapped notification, or null for "View all".
  final ValueChanged<AppNotification?>? onOpenNotification;
  /// Called with the tapped global-search result.
  final ValueChanged<SearchResult>? onOpenSearchResult;

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
  // Overlay portal controller + layer link for anchored dropdown
  final _overlayController = OverlayPortalController();
  final _layerLink          = LayerLink();

  List<AppNotification> _notifications        = [];
  bool                  _loadingNotifications = false;

  // ── Global search ────────────────────────────────────────────────────────
  final _searchOverlayController = OverlayPortalController();
  final _searchLayerLink          = LayerLink();
  final _searchCtrl               = TextEditingController();
  final _searchFocus               = FocusNode();
  List<SearchResult> _searchResults = [];
  bool                _searching    = false;
  String?             _searchError;
  Timer?              _searchDebounce;

  // Matching menu pages show at once; records follow from the server.
  List<SearchResult> _pageResults = [];
  int _selected = 0;
  bool _isMobileLayout = false;

  List<SearchResult> get _allResults => [..._pageResults, ..._searchResults];

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    final query = q.trim();
    _pageResults = matchSearchPages(query, widget.canOpenPage);
    _selected = 0;
    if (query.length < 2) {
      setState(() { _searchResults = []; _searching = false; _searchError = null; });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final results = await SearchService.instance.search(query);
        if (mounted && _searchCtrl.text.trim() == query) {
          setState(() { _searchResults = results; _searching = false; _searchError = null; _selected = 0; });
        }
      } catch (_) {
        if (mounted) setState(() { _searching = false; _searchError = 'Search failed. Check your connection and try again.'; });
      }
    });
  }

  void _moveSelection(int by) {
    final n = groupSearchResults(_allResults).length;
    if (n == 0) return;
    setState(() => _selected = (_selected + by) % n < 0 ? n - 1 : (_selected + by) % n);
  }

  void _openSelected() {
    final ordered = groupSearchResults(_allResults);
    if (ordered.isEmpty) return;
    _openSearchResult(ordered[_selected.clamp(0, ordered.length - 1)]);
  }

  void _closeSearch() {
    _searchOverlayController.hide();
    _searchFocus.unfocus();
  }

  // Ctrl+K / ⌘K: jump to search from anywhere.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.keyK) return false;
    final kb = HardwareKeyboard.instance;
    if (!kb.isControlPressed && !kb.isMetaPressed) return false;
    if (!mounted) return false;
    if (_isMobileLayout) {
      _openFullScreenSearch();
    } else {
      _searchFocus.requestFocus();
      _searchCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _searchCtrl.text.length);
      _searchOverlayController.show();
    }
    return true;
  }

  void _openSearchResult(SearchResult r) {
    _searchOverlayController.hide();
    _searchCtrl.clear();
    setState(() { _searchResults = []; _pageResults = []; _selected = 0; });
    _searchFocus.unfocus();
    widget.onOpenSearchResult?.call(r);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (_loadingNotifications) return;
    setState(() => _loadingNotifications = true);
    try {
      final data = await NotificationService.instance.list();
      if (mounted) {
        setState(() { _notifications = data; _loadingNotifications = false; });
        notificationCountNotifier.value = _unreadCount;
      }
    } catch (_) {
      if (mounted) setState(() => _loadingNotifications = false);
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

  Future<void> _markRead(int id) async {
    setState(() {
      _notifications = _notifications.map((n) => n.id == id
          ? AppNotification(
              id: n.id, type: n.type, title: n.title, body: n.body,
              entityType: n.entityType, entityId: n.entityId,
              isRead: true, createdAt: n.createdAt)
          : n).toList();
    });
    notificationCountNotifier.value = _unreadCount;
    try { await NotificationService.instance.markRead(id); } catch (_) {}
  }

  Future<void> _logout() async {
    final token = authTokenNotifier.value;
    if (token != null) await AuthService.instance.logout(token);
    authTokenNotifier.value = null;
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: Text('Log Out', style: AppTheme.bodyStrong),
        content: Text('You are about to log out. Continue?', style: AppTheme.bodySm),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Log Out', style: TextStyle(color: AppColors.coral)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _logout();
  }

  // Quick-toggle steps through every theme, in the Settings picker's order.
  static void _cycleTheme() {
    final order = AppTheme.pickerOrder.map((t) => t.$1).toList();
    themeNotifier.value = order[(order.indexOf(themeNotifier.value) + 1) % order.length];
  }


  static IconData _themeIcon(AppThemeMode mode) => switch (mode) {
    AppThemeMode.aurora  => Symbols.wb_twilight,
    AppThemeMode.dark    => Symbols.light_mode,
    AppThemeMode.light   => Symbols.tonality,
    AppThemeMode.neutral => Symbols.eco,
    _                    => Symbols.palette,
  };

  /// Phones and tablets: global search as its own full-screen page, since
  /// there's no room for the desktop's inline field + dropdown.
  Future<void> _openFullScreenSearch() async {
    final r = await Navigator.of(context, rootNavigator: true).push<SearchResult>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _FullScreenSearchPage(canOpenPage: widget.canOpenPage)),
    );
    if (r != null && mounted) widget.onOpenSearchResult?.call(r);
  }

  @override
  Widget build(BuildContext context) {
    final compact  = widget.compact;
    final isMobile = widget.onMenuPressed != null || compact;
    _isMobileLayout = isMobile;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: context.pal.topbarBg,
        border: Border(bottom: BorderSide(color: context.pal.border)),
      ),
      padding: EdgeInsets.only(left: 16, right: compact ? 8 : 16),
      child: Row(
        children: [
          // ── Hamburger (tablet only) ─────────────────────────────────────────
          if (isMobile && !compact) ...[
            GestureDetector(
              onTap: widget.onMenuPressed,
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                child: Icon(Symbols.menu, size: 22, color: context.pal.textMute),
              ),
            ),
            const SizedBox(width: 10),
          ],

          // ── Brand mark ──────────────────────────────────────────────────────
          _BrandMark(),

          // ── Page title (phone) ──────────────────────────────────────────────
          if (compact) ...[
            const SizedBox(width: 10),
            Expanded(child: Text(widget.title ?? '',
                style: AppTheme.bodyStrong.copyWith(fontSize: 16),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],

          // ── Desktop extras ──────────────────────────────────────────────────
          if (!isMobile) ...[
            const SizedBox(width: 16),
            Container(width: 1, height: 24, color: context.pal.border),
            const SizedBox(width: 16),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WORKSPACE', style: AppTheme.monoXs),
                Text('Hypermed Health Care',
                    style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CompositedTransformTarget(
                link: _searchLayerLink,
                child: OverlayPortal(
                  controller: _searchOverlayController,
                  overlayChildBuilder: (ctx) => GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _searchOverlayController.hide,
                    child: Stack(children: [
                      Positioned.fill(child: const ColoredBox(color: Colors.transparent)),
                      CompositedTransformFollower(
                        link: _searchLayerLink,
                        showWhenUnlinked: false,
                        targetAnchor: Alignment.bottomLeft,
                        followerAnchor: Alignment.topLeft,
                        child: GestureDetector(
                          onTap: () {},
                          child: Material(
                            color: Colors.transparent,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: _SearchResultsPanel(
                                query: _searchCtrl.text.trim(),
                                loading: _searching,
                                error: _searchError,
                                results: _allResults,
                                selected: _selected,
                                onSelect: _openSearchResult,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  // The Settings text input (LabeledTextField), driven by this
                  // field's own FocusNode because the results overlay needs it.
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moveSelection(1),
                      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveSelection(-1),
                      const SingleActivator(LogicalKeyboardKey.enter): _openSelected,
                      const SingleActivator(LogicalKeyboardKey.numpadEnter): _openSelected,
                      const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
                    },
                    child: LabeledTextField(
                    label: '',
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    prefixIcon: Symbols.search,
                    hint: 'Search pages, records, people…',
                    onChanged: (v) {
                      _onSearchChanged(v);
                      if (v.trim().isNotEmpty && !_searchOverlayController.isShowing) {
                        _searchOverlayController.show();
                      } else if (v.trim().isEmpty) {
                        _searchOverlayController.hide();
                      }
                    },
                    onTap: () {
                      if (!_searchOverlayController.isShowing) _searchOverlayController.show();
                    },
                    suffix: _searchCtrl.text.isEmpty
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.pal.surface3,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: context.pal.border),
                            ),
                            child: Text(Theme.of(context).platform == TargetPlatform.macOS ? '⌘K' : 'Ctrl K', style: AppTheme.monoXs),
                          )
                        : GestureDetector(
                            onTap: () {
                              _searchCtrl.clear();
                              _onSearchChanged('');
                              _searchOverlayController.hide();
                            },
                            child: Icon(Symbols.close, size: 15, color: context.pal.textDim),
                          ),
                  ))),
                ),
              ),
            ),
            const Spacer(),
            _IconBtn(icon: Symbols.help_outline),
            const SizedBox(width: 4),
            ValueListenableBuilder<AppThemeMode>(
              valueListenable: themeNotifier,
              builder: (_, mode, _) => Tooltip(
                message: 'Theme: ${_themeNameOf(mode)} — click for the next one',
                child: GestureDetector(
                  onTap: _cycleTheme,
                  child: _IconBtn(icon: _themeIcon(mode)),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ] else ...[
            if (!compact) const Spacer(),
            _TapTarget(
              tooltip: 'Search',
              onTap: _openFullScreenSearch,
              child: const _IconBtn(icon: Symbols.search),
            ),
            if (!compact) const SizedBox(width: 4),
          ],

          // ── Chat (phone): full-screen chats; wider layouts have the
          //    floating chat button instead ─────────────────────────────────
          if (compact)
            ValueListenableBuilder<bool>(
              valueListenable: chatAvailableNotifier,
              builder: (_, available, _) => !available ? const SizedBox.shrink() : _TapTarget(
                tooltip: 'Chats',
                onTap: () => openChatFullScreen(context),
                child: Stack(clipBehavior: Clip.none, children: [
                  const _IconBtn(icon: Symbols.chat),
                  const Positioned(top: 0, right: -2, child: ChatUnreadBadge()),
                ]),
              ),
            ),

          // ── Notification bell — OverlayPortal dropdown ──────────────────────
          CompositedTransformTarget(
            link: _layerLink,
            child: OverlayPortal(
              controller: _overlayController,
              // The overlay renders above the entire widget tree — no layout impact
              overlayChildBuilder: (ctx) => GestureDetector(
                // Tap outside → close
                behavior: HitTestBehavior.translucent,
                onTap: _overlayController.hide,
                child: Stack(children: [
                  Positioned.fill(child: const ColoredBox(color: Colors.transparent)),
                  CompositedTransformFollower(
                    link: _layerLink,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.bottomRight,
                    followerAnchor: Alignment.topRight,
                    child: GestureDetector(
                      // Prevent taps inside panel from closing it
                      onTap: () {},
                      child: Material(
                        color: Colors.transparent,
                        child: SizedBox(
                          // Never wider than the screen (minus a gutter) on phones.
                          width: math.min(380, MediaQuery.sizeOf(ctx).width - 16),
                          child: _NotificationPanel(
                            notifications: _notifications,
                            unreadCount: _unreadCount,
                            onMarkAllRead: () {
                              _markAllRead();
                              setState(() {});
                            },
                            onOpenNotification: (n) {
                              if (!n.isRead) {
                                _markRead(n.id);
                                setState(() {});
                              }
                              _overlayController.hide();
                              widget.onOpenNotification?.call(n);
                            },
                            onClose: _overlayController.hide,
                            onViewAll: widget.onOpenNotification == null ? null : () {
                              _overlayController.hide();
                              widget.onOpenNotification!(null);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              child: GestureDetector(
                onTap: () => setState(() {
                  if (_overlayController.isShowing) {
                    _overlayController.hide();
                  } else {
                    _overlayController.show();
                  }
                }),
                child: Stack(children: [
                  _IconBtn(
                    icon: Symbols.notifications,
                    active: _overlayController.isShowing,
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: notificationCountNotifier,
                    builder: (_, count, _) => count > 0
                        ? Positioned(
                            top: 8, right: 8,
                            child: Container(
                              width: 7, height: 7,
                              decoration: BoxDecoration(
                                color: AppColors.coral,
                                shape: BoxShape.circle,
                                border: Border.all(color: context.pal.topbarBg, width: 1.5),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ]),
              ),
            ),
          ),

          if (compact)
            _AccountMenu(onCycleTheme: _cycleTheme, themeIcon: _themeIcon, onLogout: _confirmLogout,
                onOpenProfile: widget.onOpenProfile)
          else ...[
            const SizedBox(width: 8),
            Tooltip(message: 'My profile', child: InkWell(
              onTap: widget.onOpenProfile,
              customBorder: const CircleBorder(),
              child: const CurrentUserAvatar(size: 30),
            )),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _confirmLogout,
              child: _IconBtn(icon: Symbols.logout),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Notification Panel ─────────────────────────────────────────────────────────

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({
    required this.notifications,
    required this.unreadCount,
    required this.onMarkAllRead,
    required this.onOpenNotification,
    required this.onClose,
    this.onViewAll,
  });
  final List<AppNotification> notifications;
  final int unreadCount;
  final VoidCallback onMarkAllRead;
  final ValueChanged<AppNotification> onOpenNotification;
  final VoidCallback onClose;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 520),
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.pal.borderStrong),
        boxShadow: const [
          BoxShadow(color: Color(0x60000000), blurRadius: 40, offset: Offset(0, 12)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Text('Notifications', style: AppTheme.bodyStrong),
            const SizedBox(width: 8),
            if (unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.coralSoft, borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$unreadCount', style: AppTheme.bodySub.copyWith(
                  color: AppColors.coral, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            const Spacer(),
            if (unreadCount > 0) ...[
              GestureDetector(
                onTap: onMarkAllRead,
                child: Text('Mark all read', style: AppTheme.bodySub.copyWith(
                  color: AppColors.teal, fontSize: 12)),
              ),
              const SizedBox(width: 12),
            ],
            GestureDetector(
              onTap: onClose,
              child: Icon(Symbols.close, size: 16, color: context.pal.textDim),
            ),
          ]),
        ),
        // List
        Flexible(
          child: notifications.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Symbols.notifications_off, size: 32, color: context.pal.textDim),
                    const SizedBox(height: 8),
                    Text('No notifications', style: AppTheme.bodySub),
                  ])),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: notifications.length,
                  itemBuilder: (context, i) {
                    final n = notifications[i];
                    final color = n.type.color;
                    final action = n.type.actionLabel;
                    return GestureDetector(
                      onTap: () => onOpenNotification(n),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: n.isRead ? Colors.transparent : context.pal.surface2,
                          border: i < notifications.length - 1
                            ? Border(bottom: BorderSide(color: context.pal.divider))
                            : null,
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(n.type.icon, size: 16, color: color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(n.title, style: AppTheme.bodyStrong.copyWith(
                                fontSize: 12.5,
                                fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600,
                              ))),
                              if (!n.isRead)
                                Container(
                                  width: 7, height: 7,
                                  decoration: BoxDecoration(
                                    color: AppColors.teal, shape: BoxShape.circle),
                                ),
                            ]),
                            const SizedBox(height: 3),
                            Text(n.body,
                              style: AppTheme.bodySub.copyWith(fontSize: 11.5, height: 1.4),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Row(children: [
                              Text(n.createdAt, style: AppTheme.monoXs.copyWith(
                                color: context.pal.textDim, fontSize: 10.5)),
                              if (action != null) ...[
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => onOpenNotification(n),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(action, style: AppTheme.bodySub.copyWith(
                                        color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ],
                            ]),
                          ])),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        // Footer
        GestureDetector(
          onTap: onViewAll,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.pal.border)),
            ),
            child: Center(
              child: Text('View all notifications',
                style: AppTheme.bodySub.copyWith(
                  color: onViewAll != null ? AppColors.teal : context.pal.textDim,
                  fontSize: 12.5,
                )),
            ),
          ),
        ),
      ]),
    );
  }
}

class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/hypermed_icon.png',
    height: 28, fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
  );
}

// ── Global search results panel ──────────────────────────────────────────────

/// Menu pages whose name matches every word typed, best first (max 5).
List<SearchResult> matchSearchPages(String query, bool Function(String key)? canOpen) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [];
  final words = q.split(RegExp(r'\s+'));
  final scored = <(int, SearchResult)>[];
  for (final p in allNavPages()) {
    if (canOpen != null && !canOpen(p.key)) continue;
    final label = p.label.toLowerCase();
    final hay = '$label ${p.group.toLowerCase()}';
    if (!words.every(hay.contains)) continue;
    final score = label == q ? 0 : label.startsWith(q) ? 1 : label.contains(q) ? 2 : 3;
    scored.add((score, SearchResult.page(key: p.key, title: p.label, subtitle: p.group, icon: p.icon)));
  }
  scored.sort((x, y) => x.$1.compareTo(y.$1));
  return scored.take(5).map((e) => e.$2).toList();
}

/// Results in display order: grouped by type, groups in the order their best
/// match came in (the server sends best matches first), Pages on top.
List<SearchResult> groupSearchResults(List<SearchResult> results) {
  final groups = <String, List<SearchResult>>{};
  for (final r in results) {
    (groups[r.type] ??= []).add(r);
  }
  return [for (final g in groups.values) ...g];
}

class _SearchResultsPanel extends StatelessWidget {
  const _SearchResultsPanel({
    required this.query,
    required this.loading,
    required this.error,
    required this.results,
    required this.onSelect,
    this.selected = -1,
    this.bare = false,
  });
  final String query;
  final bool loading;
  final String? error;
  final List<SearchResult> results;
  final ValueChanged<SearchResult> onSelect;
  /// Keyboard-highlighted row (index into the grouped order), -1 for none.
  final int selected;
  /// Full-screen search: no card chrome, no height cap, roomier rows.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final ordered = groupSearchResults(results);
    return Container(
      constraints: bare ? null : const BoxConstraints(maxHeight: 480),
      margin: bare ? null : const EdgeInsets.only(top: 6),
      decoration: bare ? null : BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.pal.borderStrong),
        boxShadow: const [
          BoxShadow(color: Color(0x60000000), blurRadius: 40, offset: Offset(0, 12)),
        ],
      ),
      child: Builder(builder: (context) {
        Widget message(String text, {IconData? icon, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 24, color: context.pal.textDim), const SizedBox(height: 6)],
            Text(text, textAlign: TextAlign.center,
                style: AppTheme.bodySub.copyWith(fontSize: 12, color: color)),
          ])),
        );

        if (query.isEmpty) {
          return message('Search pages, stock items, customers, POs, invoices, quotations, '
              'shipments, tenders, people, meetings and letters.', icon: Symbols.search);
        }
        if (ordered.isEmpty) {
          if (query.length < 2) return message('Keep typing to search…');
          if (loading) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          if (error != null) return message(error!, color: AppColors.coral);
          return message('No results for "$query"', icon: Symbols.search_off);
        }

        // Flat list of headers + rows; `i` counts rows only, for the highlight.
        final children = <Widget>[];
        String? lastType;
        for (var i = 0; i < ordered.length; i++) {
          final r = ordered[i];
          if (r.type != lastType) {
            lastType = r.type;
            children.add(Padding(
              padding: EdgeInsets.fromLTRB(bare ? 16 : 14, children.isEmpty ? 6 : 12, 14, 4),
              child: Text(r.type.searchCategoryLabel.toUpperCase(),
                  style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textDim, letterSpacing: 0.6)),
            ));
          }
          children.add(_SearchRow(result: r, highlighted: i == selected, bare: bare, onTap: () => onSelect(r)));
        }
        if (loading || error != null) {
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Text(error ?? 'Searching records…',
                style: AppTheme.bodySub.copyWith(fontSize: 11, color: error != null ? AppColors.coral : null)),
          ));
        }
        return ListView(
          shrinkWrap: !bare,
          padding: const EdgeInsets.only(bottom: 6),
          children: children,
        );
      }),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.result, required this.highlighted, required this.bare, required this.onTap});
  final SearchResult result;
  final bool highlighted;
  final bool bare;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = result;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: highlighted ? AppColors.teal.withValues(alpha: 0.10) : null,
        padding: EdgeInsets.symmetric(horizontal: bare ? 16 : 14, vertical: bare ? 12 : 8),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(r.icon ?? r.type.searchIcon, size: 15, color: AppColors.teal),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.title, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (r.subtitle != null && r.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(r.subtitle!, style: AppTheme.bodySub.copyWith(fontSize: 11),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ])),
          if (highlighted) ...[
            const SizedBox(width: 8),
            Icon(Symbols.keyboard_return, size: 14, color: context.pal.textDim),
          ],
        ]),
      ),
    );
  }
}

/// 44×44 hit area around a smaller visual — the minimum comfortable touch
/// target on phones, without changing how the icon looks.
class _TapTarget extends StatelessWidget {
  const _TapTarget({required this.child, required this.onTap, this.tooltip});
  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final target = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(width: 44, height: 44, child: Center(child: child)),
    );
    return tooltip == null ? target : Tooltip(message: tooltip!, child: target);
  }
}

/// Phone top bar: the avatar opens a small account menu (theme, log out)
/// instead of spending two more icons of a 360 px-wide bar on them.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.onCycleTheme, required this.themeIcon, required this.onLogout, this.onOpenProfile});
  final VoidCallback? onOpenProfile;
  final VoidCallback onCycleTheme;
  final IconData Function(AppThemeMode) themeIcon;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Account',
    color: context.pal.surface1,
    position: PopupMenuPosition.under,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: context.pal.borderStrong),
    ),
    onSelected: (v) => switch (v) {
      'profile' => onOpenProfile?.call(),
      'theme' => onCycleTheme(),
      _ => onLogout(),
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        enabled: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([userNameNotifier, userRoleNotifier]),
          builder: (_, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(userNameNotifier.value.isNotEmpty ? userNameNotifier.value : 'User',
                style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
            Text(roleDisplayName(userRoleNotifier.value),
                style: AppTheme.bodySub.copyWith(fontSize: 11)),
          ]),
        ),
      ),
      const PopupMenuDivider(),
      if (onOpenProfile != null)
        PopupMenuItem(value: 'profile', child: Row(children: [
          Icon(Symbols.person, size: 18, color: context.pal.textMute),
          const SizedBox(width: 12),
          Text('My profile', style: AppTheme.bodySm),
        ])),
      PopupMenuItem(value: 'theme', child: Row(children: [
        Icon(themeIcon(themeNotifier.value), size: 18, color: context.pal.textMute),
        const SizedBox(width: 12),
        Text('Switch theme (${_themeNameOf(themeNotifier.value)})', style: AppTheme.bodySm),
      ])),
      PopupMenuItem(value: 'logout', child: Row(children: [
        Icon(Symbols.logout, size: 18, color: AppColors.coral),
        const SizedBox(width: 12),
        Text('Log out', style: AppTheme.bodySm.copyWith(color: AppColors.coral)),
      ])),
    ],
    child: const SizedBox(width: 44, height: 44,
        child: Center(child: CurrentUserAvatar(size: 30))),
  );
}

/// Global search as a full-screen page (phones/tablets). Pops with the
/// picked [SearchResult]; the top bar hands it to the shell to route.
class _FullScreenSearchPage extends StatefulWidget {
  const _FullScreenSearchPage({this.canOpenPage});
  final bool Function(String key)? canOpenPage;
  @override
  State<_FullScreenSearchPage> createState() => _FullScreenSearchPageState();
}

class _FullScreenSearchPageState extends State<_FullScreenSearchPage> {
  final _ctrl = TextEditingController();
  List<SearchResult> _results = [];
  List<SearchResult> _pages = [];
  bool    _loading = false;
  String? _error;
  Timer?  _debounce;

  void _onChanged(String q) {
    _debounce?.cancel();
    final query = q.trim();
    _pages = matchSearchPages(query, widget.canOpenPage);
    if (query.length < 2) {
      setState(() { _results = []; _loading = false; _error = null; });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final results = await SearchService.instance.search(query);
        if (mounted && _ctrl.text.trim() == query) {
          setState(() { _results = results; _loading = false; _error = null; });
        }
      } catch (_) {
        if (mounted) setState(() { _loading = false; _error = 'Search failed. Check your connection and try again.'; });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = [..._pages, ..._results];
    return Scaffold(
      backgroundColor: context.pal.bg,
      body: SafeArea(child: Column(children: [
        Container(
          height: 60,
          padding: const EdgeInsets.only(left: 4, right: 12),
          decoration: BoxDecoration(
            color: context.pal.topbarBg,
            border: Border(bottom: BorderSide(color: context.pal.border)),
          ),
          child: Row(children: [
            _TapTarget(
              tooltip: 'Back',
              onTap: () => Navigator.of(context).pop(),
              child: Icon(Symbols.arrow_back, size: 22, color: context.pal.text),
            ),
            Expanded(child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              style: AppTheme.fieldText.copyWith(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search pages, records, people…',
                hintStyle: AppTheme.fieldHint.copyWith(fontSize: 15),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
              ),
              onChanged: _onChanged,
              onSubmitted: (_) {
                final ordered = groupSearchResults(all);
                if (ordered.isNotEmpty) Navigator.of(context).pop(ordered.first);
              },
            )),
            if (_ctrl.text.isNotEmpty)
              _TapTarget(
                tooltip: 'Clear',
                onTap: () { _ctrl.clear(); _onChanged(''); },
                child: Icon(Symbols.close, size: 20, color: context.pal.textDim),
              ),
          ]),
        ),
        Expanded(child: Material(
          color: Colors.transparent,
          child: _SearchResultsPanel(
            bare: true,
            query: _ctrl.text.trim(),
            loading: _loading,
            error: _error,
            results: all,
            onSelect: (r) => Navigator.of(context).pop(r),
          ),
        )),
      ])),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, this.active = false});
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    width: 34, height: 34,
    decoration: BoxDecoration(
      color: active ? context.pal.surface2 : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, size: 20, color: active ? context.pal.text : context.pal.textMute),
  );
}

/// A theme's name as the Settings picker shows it.
String _themeNameOf(AppThemeMode mode) =>
    AppTheme.pickerOrder.firstWhere((t) => t.$1 == mode, orElse: () => (mode, mode.name)).$2;
