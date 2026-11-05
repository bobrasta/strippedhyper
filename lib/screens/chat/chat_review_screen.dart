import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/chat.dart';
import '../../services/chat_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/chat/chat_panel.dart' show MessageBubble;
import '../../widgets/common/avatar_widget.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/phone_layout.dart';

/// Read-only chat review: pick a person, one of their chats, read it —
/// deleted messages and earlier versions of edited ones included. Works
/// only while the Director has chat review on and the reader holds the
/// "Review Staff Chats" permission; every list and chat opened here is
/// written to the Activity Log by the API.
class ChatReviewScreen extends StatefulWidget {
  const ChatReviewScreen({super.key});

  @override
  State<ChatReviewScreen> createState() => _ChatReviewScreenState();
}

class _ChatReviewScreenState extends State<ChatReviewScreen> {
  final _api = ChatService.instance;
  final _search = TextEditingController();
  Timer? _debounce;

  List<ChatUser> _people = [];
  bool _loadingPeople = true;
  String? _peopleError;

  ChatUser? _person;
  List<Conversation> _chats = [];
  bool _loadingChats = false;
  String? _chatsError;

  Conversation? _chat;
  List<ChatMessage> _messages = []; // oldest first
  bool _loadingMessages = false;
  bool _hasOlder = false;
  String? _messagesError;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    setState(() { _loadingPeople = true; _peopleError = null; });
    try {
      final rows = await _api.people(_search.text, limit: 100);
      if (mounted) setState(() => _people = rows);
    } catch (e) {
      if (mounted) setState(() => _peopleError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loadingPeople = false);
    }
  }

  Future<void> _pickPerson(ChatUser u) async {
    setState(() {
      _person = u; _chats = []; _chat = null; _messages = [];
      _loadingChats = true; _chatsError = null;
    });
    try {
      final (rows, _) = await _api.reviewConversations(u.id);
      if (mounted && _person?.id == u.id) setState(() => _chats = rows);
    } catch (e) {
      if (mounted) setState(() => _chatsError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loadingChats = false);
    }
  }

  Future<void> _pickChat(Conversation c, {bool older = false}) async {
    if (!older) {
      setState(() { _chat = c; _messages = []; _hasOlder = false; _messagesError = null; });
    }
    setState(() => _loadingMessages = true);
    try {
      final before = older && _messages.isNotEmpty ? _messages.first.id : null;
      final (rows, more) = await _api.reviewMessages(c.id, before: before);
      if (!mounted || _chat?.id != c.id) return;
      setState(() {
        _messages = [...rows.reversed, if (older) ..._messages];
        _hasOlder = more;
      });
    } catch (e) {
      if (mounted) setState(() => _messagesError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  // Names in review are always from the reviewed person's side.
  String _chatName(Conversation c) => c.displayName(_person?.id);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final phone = isPhoneWidth(box.maxWidth);
        return PopScope(
          // Phone: back steps out of the chat, then the person, then the screen.
          canPop: !phone || (_chat == null && _person == null),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            setState(() => _chat != null ? _chat = null : _person = null);
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(context),
            _notice(context),
            Expanded(child: phone ? _phone(context) : _wide(context)),
          ]),
        );
      });

  Widget _header(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
        child: Row(children: [
          IconButton(
            tooltip: 'Back',
            icon: Icon(Symbols.arrow_back, size: 20, color: context.pal.textMute),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text('Chat review', style: AppTheme.pageTitle.copyWith(fontSize: 18),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      );

  Widget _notice(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppColors.amberSoft,
        child: Row(children: [
          Icon(Symbols.policy, size: 15, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Read-only. Every chat list and chat you open here goes into the Activity Log under your name.',
            style: AppTheme.bodySub.copyWith(fontSize: 12, color: AppColors.amber))),
        ]),
      );

  Widget _wide(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 260, child: _peoplePane(context)),
        VerticalDivider(width: 1, color: context.pal.border),
        SizedBox(width: 300, child: _chatsPane(context)),
        VerticalDivider(width: 1, color: context.pal.border),
        Expanded(child: _messagesPane(context)),
      ]);

  Widget _phone(BuildContext context) {
    if (_chat != null) return _messagesPane(context);
    if (_person != null) return _chatsPane(context);
    return _peoplePane(context);
  }

  Widget _paneTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Text(text.toUpperCase(), style: AppTheme.monoXs.copyWith(letterSpacing: 0.10)),
      );

  Widget _peoplePane(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _paneTitle(context, 'Staff'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: LabeledTextField(label: '', controller: _search, hint: 'Search staff', prefixIcon: Symbols.search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _loadPeople);
              }),
        ),
        const SizedBox(height: 6),
        Expanded(child: _loadingPeople
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _peopleError != null
                ? ErrorView(message: _peopleError!, onRetry: _loadPeople, compact: true)
                : ListView.builder(
                    itemCount: _people.length,
                    itemBuilder: (_, i) {
                      final u = _people[i];
                      final on = _person?.id == u.id;
                      return InkWell(
                        onTap: () => _pickPerson(u),
                        child: Container(
                          color: on ? context.pal.surface2 : null,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(children: [
                            AvatarWidget(initials: u.initials, imageUrl: u.avatarUrl, size: 28, variant: AvatarVariant.teal),
                            const SizedBox(width: 10),
                            Expanded(child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: AppTheme.bodySm.copyWith(fontSize: 13))),
                          ]),
                        ),
                      );
                    },
                  )),
      ]);

  Widget _chatsPane(BuildContext context) {
    final p = _person;
    if (p == null) {
      return Center(child: Text('Pick a person', style: AppTheme.bodySub.copyWith(fontSize: 13)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _paneTitle(context, "${p.name}'s chats"),
      Expanded(child: _loadingChats
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _chatsError != null
              ? ErrorView(message: _chatsError!, onRetry: () => _pickPerson(p), compact: true)
              : _chats.isEmpty
                  ? Center(child: Text('No chats', style: AppTheme.bodySub.copyWith(fontSize: 13)))
                  : ListView.builder(
                      itemCount: _chats.length,
                      itemBuilder: (_, i) {
                        final c = _chats[i];
                        final on = _chat?.id == c.id;
                        return InkWell(
                          onTap: () => _pickChat(c),
                          child: Container(
                            color: on ? context.pal.surface2 : null,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            child: Row(children: [
                              Icon(c.isDirect ? Symbols.person : Symbols.group, size: 16, color: context.pal.textDim),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_chatName(c), maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
                                Text(c.lastMessage?.preview ?? 'No messages', maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: AppTheme.bodySub.copyWith(fontSize: 12)),
                              ])),
                              if (c.lastActivityAt != null)
                                Text(formatDate(c.lastActivityAt!), style: AppTheme.bodySub.copyWith(fontSize: 11)),
                            ]),
                          ),
                        );
                      },
                    )),
    ]);
  }

  Widget _messagesPane(BuildContext context) {
    final c = _chat;
    if (c == null) {
      return Center(child: Text('Pick a chat to read', style: AppTheme.bodySub.copyWith(fontSize: 13)));
    }
    final names = c.participants.map((p) => p.name).join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_chatName(c), style: AppTheme.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (names.isNotEmpty)
            Text(names, style: AppTheme.bodySub.copyWith(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
      Divider(height: 1, color: context.pal.border),
      Expanded(child: _loadingMessages && _messages.isEmpty
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _messagesError != null && _messages.isEmpty
              ? ErrorView(message: _messagesError!, onRetry: () => _pickChat(c), compact: true)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_hasOlder)
                      Center(child: TextButton(
                        onPressed: _loadingMessages ? null : () => _pickChat(c, older: true),
                        child: const Text('Show earlier messages'),
                      )),
                    for (var i = 0; i < _messages.length; i++) ...[
                      if (i == 0 || !_sameDay(_messages[i - 1].createdAt, _messages[i].createdAt))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: Text(formatDate(_messages[i].createdAt).toUpperCase(),
                              style: AppTheme.monoXs.copyWith(letterSpacing: 0.10))),
                        ),
                      MessageBubble(
                        message: _messages[i],
                        // The reviewed person's messages on the right.
                        mine: _messages[i].senderId == _person?.id,
                        showName: true,
                        review: true,
                      ),
                    ],
                  ],
                )),
    ]);
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

}
