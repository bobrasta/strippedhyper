import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/chat.dart';
import '../../services/chat_controller.dart';
import '../../services/chat_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../common/app_button.dart';
import '../common/avatar_widget.dart';
import '../common/error_view.dart';
import '../common/labeled_field.dart';
import '../people/person_profile.dart';

/// The whole chat experience: the chat list, starting a chat, and one open
/// chat. The desktop dock and the phone's full-screen page show it as one
/// pane; [onClose] hides it (minimise on desktop, back on phone). The Chats
/// menu screen shows it with [workspace]: the list beside the open chat
/// when there is room, one pane at a time on a phone, and no close button.
class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, this.onClose, this.closeIcon = Symbols.remove, this.workspace = false});
  final VoidCallback? onClose;
  final IconData closeIcon;
  final bool workspace;

  /// Below this content width the workspace shows one pane at a time.
  static const twoPaneWidth = 720.0;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

enum _View { list, people, chat }

class _ChatPanelState extends State<ChatPanel> {
  final _c = ChatController.instance;
  _View _view = _View.list;

  @override
  void initState() {
    super.initState();
    _c.attachView();
    if (_c.openId != null) _view = _View.chat;
    _c.openRequests.addListener(_onOpenRequest);
    // After the first frame: these update the unread badges, which other
    // widgets (top bar, dock) listen to — not allowed mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onOpenRequest();
      unawaited(_c.markOpenRead());
    });
  }

  @override
  void dispose() {
    _c.detachView();
    _c.openRequests.removeListener(_onOpenRequest);
    super.dispose();
  }

  void _onOpenRequest() {
    final id = _c.openRequests.value;
    if (id == null || !mounted) return;
    _c.openRequests.value = null;
    if (id > 0) {
      _open(id);
    } else {
      setState(() => _view = _View.list);
    }
  }

  void _open(int id) {
    unawaited(_c.openChat(id));
    setState(() => _view = _View.chat);
  }

  void _back() {
    _c.closeChat();
    setState(() => _view = _View.list);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) => !widget.workspace
            ? _single()
            : LayoutBuilder(builder: (context, box) => box.maxWidth < ChatPanel.twoPaneWidth
                ? _single()
                : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(
                      width: 340,
                      child: _view == _View.people
                          ? _PeoplePicker(onBack: () => setState(() => _view = _View.list), onOpened: _open)
                          : _ChatList(onOpen: _open, onNew: () => setState(() => _view = _View.people),
                              onClose: null, closeIcon: widget.closeIcon, selectedId: _c.openId),
                    ),
                    VerticalDivider(width: 1, color: context.pal.border),
                    Expanded(child: _c.openId == null
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Symbols.forum, size: 40, color: context.pal.textDim),
                            const SizedBox(height: 12),
                            Text('Select a chat to read', style: AppTheme.bodySub),
                          ]))
                        : _ChatView(key: ValueKey(_c.openId), onBack: _back, onClose: null, closeIcon: widget.closeIcon)),
                  ])),
      );

  Widget _single() => switch (_view) {
          _View.list => _ChatList(onOpen: _open, onNew: () => setState(() => _view = _View.people),
              onClose: widget.onClose, closeIcon: widget.closeIcon),
          _View.people => _PeoplePicker(onBack: () => setState(() => _view = _View.list), onOpened: _open),
          _View.chat => _c.openId == null
              ? _ChatList(onOpen: _open, onNew: () => setState(() => _view = _View.people),
                  onClose: widget.onClose, closeIcon: widget.closeIcon)
              : _ChatView(onBack: _back, onClose: widget.onClose, closeIcon: widget.closeIcon),
      };
}

// ── Shared bits ──────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
        child: Row(children: children),
      );
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 18, color: context.pal.textMute)),
        ),
      );
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.n);
  final int n;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 18),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(999)),
        child: Text(n > 99 ? '99+' : '$n', textAlign: TextAlign.center,
            style: AppTheme.bodySub.copyWith(color: const Color(0xFF06120F), fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// "Chats may be reviewed" — shown while the Director has chat review on.
class ChatReviewNotice extends StatelessWidget {
  const ChatReviewNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: AppColors.amberSoft,
        child: Row(children: [
          Icon(Symbols.visibility, size: 14, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text('Chat review is on: management may read chats. Every read is logged.',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.amber))),
        ]),
      );
}

String _listTime(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  if (t.year == now.year && t.month == now.month && t.day == now.day) return formatTime(t);
  if (now.difference(t).inDays < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
  return formatDate(t);
}

Widget _avatar(ChatUser? u, {double size = 34, bool group = false}) => AvatarWidget(
      initials: group ? '#' : (u?.initials ?? '?'),
      imageUrl: group ? null : u?.avatarUrl,
      size: size,
      variant: group ? AvatarVariant.violet : AvatarVariant.teal,
    );

// ── Chat list ────────────────────────────────────────────────────────────────

class _ChatList extends StatefulWidget {
  const _ChatList({required this.onOpen, required this.onNew, required this.onClose, required this.closeIcon, this.selectedId});
  final ValueChanged<int> onOpen;
  final VoidCallback onNew;
  final VoidCallback? onClose;
  final IconData closeIcon;
  /// The chat open beside the list (Chats screen), highlighted.
  final int? selectedId;

  @override
  State<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<_ChatList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ChatController.instance;
    final q = _search.text.trim().toLowerCase();
    final rows = q.isEmpty ? c.conversations
        : c.conversations.where((x) => x.displayName(c.me).toLowerCase().contains(q)).toList();
    final unread = chatUnreadNotifier.value;
    return Column(children: [
      _Header(children: [
        const SizedBox(width: 4),
        Text('Chats', style: AppTheme.bodyStrong),
        if (unread > 0) ...[const SizedBox(width: 8), _CountPill(unread)],
        if (!c.live && c.settings.hasRealtime) ...[
          const SizedBox(width: 8),
          Tooltip(message: 'Reconnecting: new messages may take a few seconds',
              child: Icon(Symbols.cloud_off, size: 14, color: context.pal.textDim)),
        ],
        const Spacer(),
        _HeaderIcon(icon: Symbols.edit_square, tooltip: 'New chat', onTap: widget.onNew),
        if (widget.onClose != null) _HeaderIcon(icon: widget.closeIcon, tooltip: 'Hide chats', onTap: widget.onClose!),
      ]),
      if (c.settings.auditEnabled) const ChatReviewNotice(),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: LabeledTextField(label: '', controller: _search, hint: 'Search chats', prefixIcon: Symbols.search,
            onChanged: (_) => setState(() {})),
      ),
      Expanded(child: _body(context, c, rows, q)),
    ]);
  }

  Widget _body(BuildContext context, ChatController c, List<Conversation> rows, String q) {
    if (c.loadingList && c.conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (c.listError != null && c.conversations.isEmpty) {
      return ErrorView(message: 'Could not load your chats.', onRetry: c.refreshList, compact: true);
    }
    if (rows.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.forum, size: 34, color: context.pal.textDim),
          const SizedBox(height: 10),
          Text(q.isNotEmpty ? 'No chat matches "$q"' : 'No chats yet', style: AppTheme.bodySub.copyWith(fontSize: 13)),
          if (q.isEmpty) ...[
            const SizedBox(height: 12),
            AppButton(label: 'Start a chat', icon: Symbols.edit_square, variant: BtnVariant.primary, small: true,
                onPressed: widget.onNew),
          ],
        ]),
      ));
    }
    return RefreshIndicator(
      onRefresh: c.refreshList,
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (_, i) => _ChatRow(conversation: rows[i], selected: rows[i].id == widget.selectedId,
            onTap: () => widget.onOpen(rows[i].id)),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.conversation, required this.onTap, this.selected = false});
  final Conversation conversation;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = ChatController.instance;
    final conv = conversation;
    final unread = conv.unreadCount > 0;
    final last = conv.lastMessage;
    final mine = last != null && last.senderId == c.me;
    final preview = last == null ? 'No messages yet'
        : (mine ? 'You: ${last.preview}'
            : (!conv.isDirect && last.sender != null && !last.isSystem
                ? '${last.sender!.name.split(' ').first}: ${last.preview}' : last.preview));
    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: (d) => _rowMenu(context, d.globalPosition),
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) _rowMenu(context, box.localToGlobal(box.size.center(Offset.zero)));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? context.pal.surface2 : null,
          border: Border(left: BorderSide(color: unread || selected ? AppColors.teal : Colors.transparent, width: 3)),
        ),
        child: Row(children: [
          _avatar(conv.isDirect ? conv.other(c.me) : null, group: !conv.isDirect),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(conv.displayName(c.me), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStrong.copyWith(fontSize: 13, fontWeight: unread ? FontWeight.w700 : FontWeight.w500))),
              if (conv.isMuted) ...[
                Icon(Symbols.notifications_off, size: 12, color: context.pal.textDim),
                const SizedBox(width: 4),
              ],
              Text(_listTime(conv.lastActivityAt), style: AppTheme.bodySub.copyWith(fontSize: 11,
                  color: unread ? AppColors.teal : null)),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              Expanded(child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySub.copyWith(fontSize: 12,
                      color: unread ? context.pal.text : null))),
              if (unread) ...[const SizedBox(width: 6), _CountPill(conv.unreadCount)],
            ]),
          ])),
        ]),
      ),
    );
  }

  Future<void> _rowMenu(BuildContext context, Offset at) async {
    final c = ChatController.instance;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    PopupMenuItem<String> item(String v, IconData i, String l) => PopupMenuItem(value: v, height: 36,
        child: Row(children: [Icon(i, size: 16, color: context.pal.textMute), const SizedBox(width: 10),
          Text(l, style: AppTheme.bodySm.copyWith(fontSize: 13))]));
    final v = await showMenu<String>(
      context: context,
      color: context.pal.surface1,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        conversation.isMuted
            ? item('unmute', Symbols.notifications, 'Unmute')
            : item('mute', Symbols.notifications_off, 'Mute'),
        if (!conversation.isDirect) item('leave', Symbols.logout, 'Leave group'),
      ],
    );
    if (v == null || !context.mounted) return;
    try {
      switch (v) {
        case 'mute' || 'unmute':
          await c.setMuted(conversation.id, v == 'mute');
        case 'leave':
          await c.leave(conversation.id);
      }
    } catch (e) {
      if (context.mounted) showErrorToast(context, e);
    }
  }
}

// ── New chat / new group ─────────────────────────────────────────────────────

class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({required this.onBack, required this.onOpened, this.addTo});
  final VoidCallback onBack;
  final ValueChanged<int> onOpened;
  /// Adding people to this group instead of starting a chat.
  final Conversation? addTo;

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  final _search = TextEditingController();
  final _title = TextEditingController();
  List<ChatUser> _people = [];
  bool _loading = true;
  String? _error;
  late bool _group = widget.addTo != null;
  final _picked = <int, ChatUser>{};
  bool _busy = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await ChatService.instance.people(_search.text, limit: 50);
      if (!mounted) return;
      final already = widget.addTo?.participants.map((p) => p.id).toSet() ?? const <int>{};
      setState(() => _people = rows.where((u) => !already.contains(u.id)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _tap(ChatUser u) async {
    if (_group) {
      setState(() => _picked.containsKey(u.id) ? _picked.remove(u.id) : _picked[u.id] = u);
      return;
    }
    setState(() => _busy = true);
    try {
      widget.onOpened(await ChatController.instance.startDirect(u.id));
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createGroup() async {
    final c = ChatController.instance;
    setState(() => _busy = true);
    try {
      if (widget.addTo != null) {
        await c.addMembers(widget.addTo!.id, _picked.keys.toList());
        widget.onOpened(widget.addTo!.id);
      } else {
        widget.onOpened(await c.startGroup(_title.text.trim(), _picked.keys.toList()));
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.addTo != null;
    final canCreate = _picked.isNotEmpty && (adding || _title.text.trim().isNotEmpty) && !_busy;
    return Column(children: [
      _Header(children: [
        _HeaderIcon(icon: Symbols.arrow_back, tooltip: 'Back', onTap: widget.onBack),
        const SizedBox(width: 4),
        Expanded(child: Text(adding ? 'Add people' : (_group ? 'New group' : 'New chat'),
            style: AppTheme.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (!adding)
          AppButton(small: true, variant: BtnVariant.ghost, icon: _group ? Symbols.person : Symbols.group,
              label: _group ? 'One person' : 'New group',
              onPressed: () => setState(() { _group = !_group; _picked.clear(); })),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: Column(children: [
          if (_group && !adding) ...[
            LabeledTextField(label: 'Group name', controller: _title, hint: 'e.g. Sales team',
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 8),
          ],
          LabeledTextField(label: '', controller: _search, hint: 'Search people', prefixIcon: Symbols.search,
              autofocus: !_group, onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _load);
              }),
        ]),
      ),
      if (_group && _picked.isNotEmpty)
        SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            for (final u in _picked.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InputChip(
                  label: Text(u.name, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.text)),
                  onDeleted: () => setState(() => _picked.remove(u.id)),
                  backgroundColor: context.pal.surface2,
                  side: BorderSide(color: context.pal.border),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ]),
        ),
      Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load, compact: true)
              : _people.isEmpty
                  ? Center(child: Text('Nobody matches', style: AppTheme.bodySub.copyWith(fontSize: 13)))
                  : ListView.builder(
                      itemCount: _people.length,
                      itemBuilder: (_, i) {
                        final u = _people[i];
                        final on = _picked.containsKey(u.id);
                        return InkWell(
                          onTap: _busy ? null : () => _tap(u),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(children: [
                              _avatar(u, size: 30),
                              const SizedBox(width: 10),
                              Expanded(child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: AppTheme.bodySm.copyWith(fontSize: 13))),
                              _HeaderIcon(icon: Symbols.info, tooltip: 'View profile',
                                  onTap: () => showPersonProfile(context, u.id)),
                              if (_group)
                                Icon(on ? Symbols.check_circle : Symbols.radio_button_unchecked, size: 18,
                                    fill: on ? 1 : 0, color: on ? AppColors.teal : context.pal.textDim),
                            ]),
                          ),
                        );
                      },
                    )),
      if (_group)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.border))),
          child: Row(children: [
            Expanded(child: Text(_picked.isEmpty ? 'Pick people' : '${_picked.length} picked',
                style: AppTheme.bodySub.copyWith(fontSize: 12))),
            AppButton(variant: BtnVariant.primary, small: true, icon: adding ? Symbols.person_add : Symbols.group_add,
                label: adding ? 'Add' : 'Create group', onPressed: canCreate ? _createGroup : null),
          ]),
        ),
    ]);
  }
}

// ── One chat ─────────────────────────────────────────────────────────────────

class _ChatView extends StatefulWidget {
  const _ChatView({super.key, required this.onBack, required this.onClose, required this.closeIcon});
  final VoidCallback onBack;
  final VoidCallback? onClose;
  final IconData closeIcon;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _c = ChatController.instance;
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  ChatMessage? _editing;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // The list is reversed: the top (older messages) is the max extent.
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) unawaited(_c.loadOlder());
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text;
    if (t.trim().isEmpty) return;
    final editing = _editing;
    _text.clear();
    setState(() => _editing = null);
    _focus.requestFocus();
    if (editing != null) {
      try {
        await _c.edit(editing, t);
      } catch (e) {
        if (mounted) showErrorToast(context, e);
      }
      return;
    }
    await _c.sendText(t);
  }

  Future<void> _attach() async {
    final r = await FilePicker.pickFiles(allowMultiple: false, withData: false);
    final path = r?.files.single.path;
    if (path == null) return;
    final caption = _text.text.trim();
    _text.clear();
    await _c.sendFile(path, caption: caption.isEmpty ? null : caption);
  }

  Future<void> _messageMenu(ChatMessage m, Offset at) async {
    final mine = m.senderId == _c.me;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    PopupMenuItem<String> item(String v, IconData i, String l, {Color? color}) => PopupMenuItem(value: v, height: 36,
        child: Row(children: [Icon(i, size: 16, color: color ?? context.pal.textMute), const SizedBox(width: 10),
          Text(l, style: AppTheme.bodySm.copyWith(fontSize: 13, color: color))]));
    final v = await showMenu<String>(
      context: context,
      color: context.pal.surface1,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        if ((m.body ?? '').isNotEmpty) item('copy', Symbols.content_copy, 'Copy text'),
        if (mine && m.type == 'text') item('edit', Symbols.edit, 'Edit'),
        if (mine) item('delete', Symbols.delete, 'Delete', color: AppColors.coral),
      ],
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body ?? ''));
      case 'edit':
        setState(() => _editing = m);
        _text.text = m.body ?? '';
        _focus.requestFocus();
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (dCtx) => AlertDialog(
            backgroundColor: dCtx.pal.surface1,
            title: Text('Delete this message?', style: AppTheme.bodyStrong),
            content: Text('Everyone in the chat will see "Message deleted" instead.', style: AppTheme.bodySub),
            actions: [
              AppButton(label: 'Cancel', small: true, variant: BtnVariant.ghost, onPressed: () => Navigator.of(dCtx).pop(false)),
              AppButton(label: 'Delete', small: true, variant: BtnVariant.danger, onPressed: () => Navigator.of(dCtx).pop(true)),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        try {
          await _c.delete(m);
        } catch (e) {
          if (mounted) showErrorToast(context, e);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final conv = _c.open;
    if (_adding && conv != null) {
      return _PeoplePicker(addTo: conv, onBack: () => setState(() => _adding = false),
          onOpened: (_) => setState(() => _adding = false));
    }
    final me = _c.me;
    final name = conv?.displayName(me) ?? '';
    final sub = conv == null ? '' : conv.isDirect ? '' : '${conv.participantCount} people';
    return Column(children: [
      _Header(children: [
        _HeaderIcon(icon: Symbols.arrow_back, tooltip: 'All chats', onTap: widget.onBack),
        const SizedBox(width: 4),
        // The person (or the group's members): tap for their profile.
        Expanded(child: Tooltip(
          message: conv == null ? '' : (conv.isDirect ? 'View profile' : 'Members'),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: conv == null ? null : () {
              final other = conv.other(me);
              if (conv.isDirect && other != null) {
                unawaited(showPersonProfile(context, other.id));
              } else if (!conv.isDirect) {
                unawaited(_showMembers(context, conv.id));
              }
            },
            child: Row(children: [
              if (conv != null) _avatar(conv.isDirect ? conv.other(me) : null, size: 28, group: !conv.isDirect),
              const SizedBox(width: 8),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
                if (sub.isNotEmpty) Text(sub, style: AppTheme.bodySub.copyWith(fontSize: 11)),
              ])),
            ]),
          ),
        )),
        if (conv != null && !conv.isDirect && conv.myRole == 'admin')
          _HeaderIcon(icon: Symbols.person_add, tooltip: 'Add people', onTap: () => setState(() => _adding = true)),
        if (widget.onClose != null) _HeaderIcon(icon: widget.closeIcon, tooltip: 'Hide chats', onTap: widget.onClose!),
      ]),
      if (_c.settings.auditEnabled) const ChatReviewNotice(),
      Expanded(child: _messages(context)),
      _composer(context),
    ]);
  }

  Widget _messages(BuildContext context) {
    if (_c.loadingMessages && _c.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_c.messagesError != null && _c.messages.isEmpty) {
      return ErrorView(message: 'Could not load this chat.', compact: true,
          onRetry: () => _c.openId == null ? null : _c.openChat(_c.openId!));
    }
    if (_c.messages.isEmpty) {
      return Center(child: Text('Say hello 👋', style: AppTheme.bodySub.copyWith(fontSize: 13)));
    }
    final msgs = _c.messages;
    final group = !(_c.open?.isDirect ?? true);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: msgs.length + (_c.hasOlder ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == msgs.length) {
          return const Padding(padding: EdgeInsets.all(10),
              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))));
        }
        final idx = msgs.length - 1 - i; // reversed list
        final m = msgs[idx];
        final prev = idx > 0 ? msgs[idx - 1] : null;
        final newDay = prev == null || !_sameDay(prev.createdAt, m.createdAt);
        final showName = group && m.senderId != _c.me && !m.isSystem &&
            (prev == null || prev.senderId != m.senderId || newDay);
        return Column(children: [
          if (newDay) _DaySeparator(m.createdAt),
          MessageBubble(
            message: m,
            mine: m.senderId == _c.me,
            showName: showName,
            state: m.senderId == _c.me ? _c.stateOf(m) : null,
            onMenu: m.isPending || m.isDeleted || m.isSystem ? null : (at) => _messageMenu(m, at),
            onRetry: m.localState == SendState.failed ? () => _c.retry(m) : null,
            onDiscard: m.localState == SendState.failed ? () => _c.discard(m) : null,
            onSenderTap: m.senderId == null ? null : () => showPersonProfile(context, m.senderId!),
          ),
        ]);
      },
    );
  }

  Widget _composer(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.border))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_editing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Row(children: [
                Icon(Symbols.edit, size: 13, color: AppColors.teal),
                const SizedBox(width: 6),
                Expanded(child: Text('Editing message', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.teal))),
                InkWell(
                  onTap: () => setState(() { _editing = null; _text.clear(); }),
                  child: Icon(Symbols.close, size: 14, color: context.pal.textDim),
                ),
              ]),
            ),
          Row(children: [
            if (_editing == null) _HeaderIcon(icon: Symbols.attach_file, tooltip: 'Send a file', onTap: _attach),
            const SizedBox(width: 4),
            Expanded(child: LabeledTextField(
              label: '',
              controller: _text,
              focusNode: _focus,
              hint: 'Write a message…',
              autofocus: true,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            )),
            const SizedBox(width: 6),
            ListenableBuilder(
              listenable: _text,
              builder: (_, _) => AppButton(
                small: true,
                variant: BtnVariant.primary,
                icon: _editing != null ? Symbols.check : Symbols.send,
                label: _editing != null ? 'Save' : 'Send',
                onPressed: _text.text.trim().isEmpty ? null : _send,
              ),
            ),
          ]),
        ]),
      );
}

/// A group's members; tap one for their profile.
Future<void> _showMembers(BuildContext context, int conversationId) async {
  Conversation conv;
  try {
    conv = await ChatService.instance.conversation(conversationId); // every member, not the 5 in the list
  } catch (e) {
    if (context.mounted) showErrorToast(context, e);
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dCtx) => AlertDialog(
      backgroundColor: dCtx.pal.surface1,
      title: Text('${conv.displayName(ChatController.instance.me)} · ${conv.participants.length} people',
          style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 360,
        child: ListView(shrinkWrap: true, children: [
          for (final p in conv.participants)
            InkWell(
              onTap: () => showPersonProfile(dCtx, p.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(children: [
                  _avatar(p, size: 30),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySm.copyWith(fontSize: 13))),
                  if (p.role == 'admin') Text('Admin', style: AppTheme.bodySub.copyWith(fontSize: 11)),
                ]),
              ),
            ),
        ]),
      ),
      actions: [AppButton(label: 'Close', small: true, variant: BtnVariant.ghost, onPressed: () => Navigator.of(dCtx).pop())],
    ),
  );
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class _DaySeparator extends StatelessWidget {
  const _DaySeparator(this.day);
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = _sameDay(day, now) ? 'Today'
        : _sameDay(day, now.subtract(const Duration(days: 1))) ? 'Yesterday' : formatDate(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(child: Divider(color: context.pal.divider, height: 1)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(label.toUpperCase(), style: AppTheme.monoXs.copyWith(letterSpacing: 0.10))),
        Expanded(child: Divider(color: context.pal.divider, height: 1)),
      ]),
    );
  }
}

/// One message. Own messages sit on the right in the accent tint; others on
/// the left. Used by the chat panel and (with [review]) by chat review,
/// which also shows deleted text and earlier versions.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.showName = false,
    this.state,
    this.onMenu,
    this.onRetry,
    this.onDiscard,
    this.onSenderTap,
    this.review = false,
  });
  final ChatMessage message;
  final bool mine;
  final bool showName;
  final SendState? state;
  final ValueChanged<Offset>? onMenu;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;
  /// Tap on the sender's name (group chats): their profile.
  final VoidCallback? onSenderTap;
  final bool review;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(child: Text(m.body ?? '', textAlign: TextAlign.center,
            style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textDim))),
      );
    }
    final deletedHidden = m.isDeleted && !review;
    final bg = mine ? AppColors.tealSoft : context.pal.surface2;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (showName && m.sender != null)
        Padding(padding: const EdgeInsets.only(bottom: 2),
            child: InkWell(
              onTap: onSenderTap,
              child: Text(m.sender!.name, style: AppTheme.bodySub.copyWith(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w600)),
            )),
      if (m.replyPreview != null)
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: context.pal.surface3,
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: AppColors.teal, width: 2)),
          ),
          child: Text('${m.replySender ?? ''}: ${m.replyPreview}', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySub.copyWith(fontSize: 11)),
        ),
      if (review && m.isDeleted)
        Padding(padding: const EdgeInsets.only(bottom: 2),
            child: Text('DELETED${m.deletedAt != null ? ' ${formatDate(m.deletedAt!)} ${formatTime(m.deletedAt!)}' : ''}',
                style: AppTheme.monoXs.copyWith(color: AppColors.coral))),
      if (deletedHidden)
        Text('Message deleted', style: AppTheme.bodySm.copyWith(fontStyle: FontStyle.italic, color: context.pal.textDim))
      else ...[
        for (final a in m.attachments) _AttachmentView(a),
        if ((m.body ?? '').isNotEmpty)
          SelectableText(m.body!, style: AppTheme.bodySm.copyWith(fontSize: 13, height: 1.4,
              decoration: review && m.isDeleted ? TextDecoration.lineThrough : null)),
      ],
      if (review && m.revisions.isNotEmpty) ...[
        const SizedBox(height: 4),
        for (final r in m.revisions)
          Text('Before edit${r.replacedAt != null ? ' (${formatTime(r.replacedAt!)})' : ''}: ${r.body ?? ''}',
              style: AppTheme.bodySub.copyWith(fontSize: 11, fontStyle: FontStyle.italic)),
      ],
      const SizedBox(height: 2),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (m.editedAt != null && !deletedHidden)
          Text('edited · ', style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: context.pal.textDim)),
        Text(formatTime(m.createdAt), style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: context.pal.textDim)),
        if (state != null) ...[const SizedBox(width: 4), _Tick(state!)],
      ]),
    ]);
    final bubble = GestureDetector(
      onSecondaryTapDown: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
      onLongPressStart: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
      onTap: onRetry,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppColors.rSm),
            topRight: const Radius.circular(AppColors.rSm),
            bottomLeft: Radius.circular(mine ? AppColors.rSm : 3),
            bottomRight: Radius.circular(mine ? 3 : AppColors.rSm),
          ),
          border: state == SendState.failed ? Border.all(color: AppColors.coral) : null,
        ),
        child: body,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: bubble),
        if (state == SendState.failed)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Not sent. ', style: AppTheme.bodySub.copyWith(fontSize: 11, color: AppColors.coral)),
              InkWell(onTap: onRetry, child: Text('Retry', style: AppTheme.bodySub.copyWith(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w600))),
              Text(' · ', style: AppTheme.bodySub.copyWith(fontSize: 11)),
              InkWell(onTap: onDiscard, child: Text('Discard', style: AppTheme.bodySub.copyWith(fontSize: 11))),
            ]),
          ),
      ]),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick(this.state);
  final SendState state;

  @override
  Widget build(BuildContext context) => switch (state) {
        SendState.sending => Icon(Symbols.schedule, size: 12, color: context.pal.textDim),
        SendState.failed => Icon(Symbols.error, size: 12, color: AppColors.coral),
        SendState.sent => Tooltip(message: 'Sent', child: Icon(Symbols.check, size: 13, color: context.pal.textDim)),
        SendState.delivered => Tooltip(message: 'Delivered', child: Icon(Symbols.done_all, size: 13, color: context.pal.textDim)),
        SendState.read => Tooltip(message: 'Read', child: Icon(Symbols.done_all, size: 13, color: AppColors.teal)),
      };
}

class _AttachmentView extends StatelessWidget {
  const _AttachmentView(this.a);
  final ChatAttachment a;

  @override
  Widget build(BuildContext context) {
    void open() {
      if (a.url.isNotEmpty) unawaited(launchUrl(Uri.parse(a.url), mode: LaunchMode.externalApplication));
    }
    if (a.isImage && (a.thumbUrl ?? a.url).isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: InkWell(
          onTap: open,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(a.thumbUrl ?? a.url, width: 220, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _chip(context, open)),
          ),
        ),
      );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: _chip(context, open));
  }

  Widget _chip(BuildContext context, VoidCallback open) => InkWell(
        onTap: a.url.isEmpty ? null : open,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: context.pal.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Symbols.description, size: 16, color: AppColors.teal),
            const SizedBox(width: 6),
            Flexible(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySm.copyWith(fontSize: 12))),
            if (a.size > 0) ...[
              const SizedBox(width: 6),
              Text(a.sizeLabel, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
            ],
          ]),
        ),
      );
}
