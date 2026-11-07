import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/email.dart';
import '../../main.dart' show emailBadgeNotifier;
import '../../models/email_account.dart';
import '../../services/email_account_service.dart';
import '../../services/email_outbox.dart';
import '../../services/email_service.dart';
import '../../services/local_db.dart' show OutboxEntry;
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/avatar_widget.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/email/compose_modal.dart';
import '../../widgets/email/email_attachments.dart';
import '../../theme/app_palette.dart';
import '../../widgets/common/phone_layout.dart';

class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key});

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  // Folder state
  String _folder      = 'inbox';

  // Email list
  List<Email> _emails    = [];
  // Paging: 100 at a time, the next page loads at the bottom of the list.
  int  _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;
  // Search: subject, sender, recipients and text, across the whole folder (server-side).
  String _search = '';
  Timer? _searchDebounce;
  bool        _loading   = true;
  bool        _syncing   = false;
  String?     _loadError;
  int         _selectedIdx = -1;
  int         _unread    = 0;

  // UI state
  int  _narrowPane   = 1; // 0=folders 1=list 2=reading

  // Account
  List<EmailAccount> _accounts = [];
  bool _checkingAccounts = true;

  Email? get _selected =>
      _selectedIdx >= 0 && _selectedIdx < _emails.length ? _emails[_selectedIdx] : null;

  // ── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Stale-while-revalidate: skip both the account-check spinner and the
    // email-list spinner on a return visit when we already know accounts
    // exist and have the current folder's emails cached — same reasoning
    // as InventoryItemsScreen.
    final cachedAccounts = EmailAccountService.cachedAccounts;
    if (cachedAccounts != null) {
      _accounts = cachedAccounts;
      _checkingAccounts = false;
    }
    final cachedEmails = EmailService.cachedByFolder[_folder];
    if (cachedEmails != null) {
      _emails = cachedEmails;
      _loading = false;
    }
    // 1. Check if any account is configured
    try {
      final accounts = await EmailAccountService.instance.list();
      if (!mounted) return;
      setState(() { _accounts = accounts; _checkingAccounts = false; });
      if (accounts.isEmpty) return; // Screen shows "set up account" prompt
    } catch (_) {
      if (mounted) setState(() => _checkingAccounts = false);
      return;
    }
    // 2. Load emails immediately — sync runs in background and doesn't block
    _sync(silent: true);   // fire-and-forget: IMAP failures won't delay inbox load
    await Future.wait([_loadUnread(), _loadEmails()]);
  }

  /// Pulls new mail in the background; when any arrives the list reloads.
  /// Failures keep the cached list — a manual refresh ([silent] false) also
  /// shows the mail server's reason.
  Future<void> _sync({bool silent = false}) async {
    if (!silent) setState(() => _syncing = true);
    try {
      final folder = _folder;
      // Flagged spans folders and drafts live only here: nothing to fetch.
      final server = switch (folder) { 'inbox' => 'INBOX', 'flagged' || 'drafts' => null, _ => folder };
      if (server == null) {
        if (mounted && !silent) setState(() => _syncing = false);
        return;
      }
      final n = await EmailService.instance.sync(folder: server);
      if (n > 0 && mounted && _folder == folder) {
        await Future.wait([_loadEmails(), _loadUnread()]);
      }
    } catch (e) {
      if (!silent && mounted) showErrorToast(context, e);
    }
    if (mounted && !silent) setState(() => _syncing = false);
  }

  Future<void> _loadUnread() async {
    try {
      final n = await EmailService.instance.unreadCount();
      _setUnread(n);
    } catch (_) {
      // Non-fatal — keeps the last known unread count.
    }
  }

  Future<void> _loadEmails() async {
    setState(() {
      if (_emails.isEmpty) _loading = true;
      _loadError = null;
      _selectedIdx = -1;
    });
    try {
      final r = await EmailService.instance.page(_folder, 1, search: _search);
      final list = r.emails;
      if (!mounted) return;
      setState(() { _emails = list; _page = 1; _hasMore = r.hasMore; _loading = false; });
      if (list.isNotEmpty) _selectAt(0, autoMark: false);
    } catch (e) {
      if (mounted) setState(() { _loadError = friendlyError(e); _loading = false; });
    }
  }

  /// Keeps the nav badge in step with what this screen shows.
  void _setUnread(int n) {
    if (mounted) setState(() => _unread = n);
    emailBadgeNotifier.value = (unread: n, failed: emailBadgeNotifier.value.failed);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearch(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || v.trim() == _search) return;
      setState(() => _search = v.trim());
      _loadEmails();
    });
  }

  Widget _searchBox() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
    child: SearchField(hint: 'Search ${_folderLabel(_folder).toLowerCase()} — subject, people, text…', onChanged: _onSearch),
  );

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final folder = _folder;
    setState(() => _loadingMore = true);
    try {
      final r = await EmailService.instance.page(folder, _page + 1, search: _search);
      if (!mounted || folder != _folder) return;
      final seen = {for (final e in _emails) e.id};
      setState(() {
        _emails = [..._emails, ...r.emails.where((e) => !seen.contains(e.id))];
        _page++;
        _hasMore = r.hasMore;
      });
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _syncing = true);
    await Future.wait([_loadEmails(), _loadUnread()]);
    await _sync();
  }

  Future<void> _switchFolder(String folder) async {
    // Switching folders is an identity change, same as
    // a detail screen's didUpdateWidget on a changed id — leaving the
    // OLD folder's emails showing under the NEW folder would be actively
    // wrong, so seed from that folder's own cache entry (or empty) rather
    // than carrying the previous folder's list over.
    final cached = EmailService.cachedByFolder[folder];
    setState(() {
      _folder = folder;
      _narrowPane = 1;
      _emails = cached ?? [];
      _page = 1;
      _hasMore = false;
      _selectedIdx = -1;
    });
    await _loadEmails();
  }

  /// [autoMark] false: the first email preselected after a load — on a
  /// phone the list stays in front.
  Future<void> _selectAt(int i, {bool autoMark = true}) async {
    setState(() { _selectedIdx = i; if (autoMark) _narrowPane = 2; });
    final email = _emails[i];
    if (autoMark && !email.isRead) {
      try {
        await EmailService.instance.toggleRead(email.id);
        if (mounted) {
          setState(() => _emails[i] = email.copyWith(isRead: true));
          if (_unread > 0) _setUnread(_unread - 1);
        }
      } catch (_) {}
    }
  }

  Future<void> _toggleFlag(int i) async {
    final email = _emails[i];
    try {
      await EmailService.instance.toggleFlag(email.id);
      if (mounted) {
        setState(() => _emails[i] = email.copyWith(isFlagged: !email.isFlagged));
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _toggleRead(int i) async {
    final email = _emails[i];
    try {
      await EmailService.instance.toggleRead(email.id);
      if (!mounted) return;
      setState(() => _emails[i] = email.copyWith(isRead: !email.isRead));
      if (email.folder.toUpperCase() == 'INBOX') {
        _setUnread(email.isRead ? _unread + 1 : (_unread > 0 ? _unread - 1 : 0));
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  /// Takes an email out of this list once it has moved; the next one opens.
  void _removeFromList(int id) {
    final i = _emails.indexWhere((e) => e.id == id);
    if (i < 0) return;
    setState(() {
      _emails.removeAt(i);
      _selectedIdx = _emails.isEmpty ? -1 : i.clamp(0, _emails.length - 1);
      _narrowPane = 1; // phone: back to the list
    });
  }

  /// Spam, Not spam, Archive, Move to Inbox, Delete (to Trash), Restore.
  Future<void> _move(int i, String to) async {
    final email = _emails[i];
    try {
      await EmailService.instance.move(email.id, to);
      if (!mounted) return;
      _removeFromList(email.id);
      showSuccessToast(context, switch (to) {
        'spam'    => 'Moved to Spam.',
        'trash'   => 'Moved to Trash.',
        'archive' => 'Archived.',
        'restore' => 'Restored.',
        _         => 'Moved to Inbox.',
      });
      _loadUnread();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  /// Delete moves to Trash; in Trash (and Spam) it removes the email for good.
  Future<void> _delete(int i) async {
    final email = _emails[i];
    if (!email.inTrash && !email.inSpam) return _move(i, 'trash');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.pal.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete forever?', style: AppTheme.bodyStrong),
        content: Text('"${email.subject}" is removed from the mail server too. This can\'t be undone.',
            style: AppTheme.bodySub),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text('Cancel', style: AppTheme.bodySm.copyWith(color: context.pal.textMute))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
              onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Delete forever')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await EmailService.instance.delete(email.id);
      EmailService.cachedByFolder.clear();
      if (!mounted) return;
      _removeFromList(email.id);
      showSuccessToast(context, 'Deleted.');
      _loadUnread();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  /// One place for the toolbar and the right-click menu.
  void _run(String action, int i) {
    switch (action) {
      case 'open':    _selectAt(i);
      case 'read':    _toggleRead(i);
      case 'flag':    _toggleFlag(i);
      case 'archive': _move(i, 'archive');
      case 'inbox':   _move(i, 'inbox');
      case 'spam':    _move(i, 'spam');
      case 'notspam': _move(i, 'inbox');
      case 'restore': _move(i, 'restore');
      case 'delete':  _delete(i);
      case 'copyfrom':
        final e = _emails[i];
        Clipboard.setData(ClipboardData(text: e.fromEmail.isNotEmpty ? e.fromEmail : e.from));
        showSuccessToast(context, 'Sender address copied.');
    }
  }

  /// Own mail (Sent, Drafts) can't be spam.
  bool get _ownFolder => _folder == 'sent' || _folder == 'drafts';

  List<PopupMenuEntry<String>> _menuItems(Email e) {
    PopupMenuItem<String> item(String v, IconData icon, String label) => PopupMenuItem(
      value: v,
      height: 36,
      child: Row(children: [
        Icon(icon, size: 16, color: context.pal.textMute),
        const SizedBox(width: 12),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySm.copyWith(fontSize: 13, color: context.pal.text))),
      ]),
    );
    return [
      item('open', Symbols.mail, 'Open'),
      item('read', e.isRead ? Symbols.mark_email_unread : Symbols.drafts, e.isRead ? 'Mark as unread' : 'Mark as read'),
      item('flag', Symbols.flag, e.isFlagged ? 'Remove flag' : 'Flag'),
      const PopupMenuDivider(),
      if (e.inSpam) ...[
        item('notspam', Symbols.report_off, 'Not spam'),
        item('delete', Symbols.delete_forever, 'Delete forever'),
      ] else if (e.inTrash) ...[
        item('restore', Symbols.restore_from_trash, 'Restore'),
        item('delete', Symbols.delete_forever, 'Delete forever'),
      ] else ...[
        e.inArchive
            ? item('inbox', Symbols.move_to_inbox, 'Move to Inbox')
            : item('archive', Symbols.archive, 'Archive'),
        if (!_ownFolder) item('spam', Symbols.report, 'Mark as spam'),
        item('delete', Symbols.delete, 'Delete'),
      ],
      const PopupMenuDivider(),
      item('copyfrom', Symbols.content_copy, 'Copy sender address'),
    ];
  }

  Future<void> _openRowMenu(int i, Offset global) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final id = _emails[i].id;
    final v = await showMenu<String>(
      context: context,
      color: context.pal.surface1,
      position: RelativeRect.fromRect(global & const Size(1, 1), Offset.zero & overlay.size),
      items: _menuItems(_emails[i]),
    );
    if (v == null || !mounted) return;
    final now = _emails.indexWhere((e) => e.id == id);
    if (now >= 0) _run(v, now);
  }

  // showDialog gives the modal the whole window as its route, not just this
  // screen's own content pane — stacking it as a bare Stack child (the old
  // approach) only got it the email screen's own bounds, which is why it
  // rendered cramped and undimmed instead of as a real full-screen overlay.
  void _openCompose({OutboxEntry? from}) {
    final p = from?.payload ?? const <String, dynamic>{};
    showDialog(
      context: context,
      builder: (dialogCtx) => ComposeModal(
        onClose: () => Navigator.of(dialogCtx).pop(),
        onSent: () { _loadUnread(); Navigator.of(dialogCtx).pop(); },
        // Edit from the failed-sends list: a reply/forward comes back as a
        // new message to the same people.
        initialTo: p['to'] as String?,
        initialCc: p['cc'] as String?,
        initialBcc: p['bcc'] as String?,
        initialSubject: p['subject'] as String?,
        initialBody: p['body'] as String?,
        initialAttachments: [
          for (final a in (p['attachments'] as List? ?? const [])) Map<String, dynamic>.from(a as Map),
        ],
        outboxId: from?.id,
      ),
    );
  }

  void _openOutbox() {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => _OutboxDialog(onEdit: (entry) {
        Navigator.of(dialogCtx).pop();
        _openCompose(from: entry);
      }),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_checkingAccounts) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_accounts.isEmpty) {
      return _AccountSetupPrompt(
        onAccountAdded: (acc) {
          setState(() { _accounts = [acc]; });
          _init();
        },
      );
    }

    return LayoutBuilder(builder: (ctx, cst) {
      final narrow = cst.maxWidth < 720;
      return Stack(children: [
        Column(children: [
          _FailedSendsBanner(onOpen: _openOutbox),
          Expanded(child: narrow ? _narrowLayout(context) : _wideLayout(context)),
        ]),
        if (_syncing)
          Positioned(
            top: 8, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.pal.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.pal.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 10, height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5)),
                const SizedBox(width: 6),
                Text('Syncing', style: AppTheme.bodySub.copyWith(fontSize: 11)),
              ]),
            ),
          ),
      ]);
    });
  }

  // ── 3-pane wide layout ─────────────────────────────────────────────────────

  Widget _wideLayout(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        width: 220,
        decoration: BoxDecoration(border: Border(right: BorderSide(color: context.pal.border))),
        padding: const EdgeInsets.all(10),
        child: _sidebar(context),
      ),
      Container(
        width: 360,
        decoration: BoxDecoration(border: Border(right: BorderSide(color: context.pal.border))),
        child: Column(children: [
          _ListHeader(
            label: _folderLabel(_folder),
            unread: _folder == 'inbox' ? _unread : null,
            onRefresh: _refresh,
          ),
          _searchBox(),
          Expanded(child: _emailList(context)),
        ]),
      ),
      Expanded(child: _readingPane(context)),
    ],
  );

  // ── Narrow layout ──────────────────────────────────────────────────────────

  Widget _narrowLayout(BuildContext context) {
    if (_narrowPane == 0) {
      return Column(children: [
        _NarrowBar(label: 'Folders',
          leading: GestureDetector(
            onTap: () => setState(() => _narrowPane = 1),
            child: Icon(Symbols.arrow_back, size: 18, color: context.pal.textMute),
          ),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(10), child: _sidebar(context))),
      ]);
    }
    if (_narrowPane == 2 && _selected != null) {
      return Column(children: [
        _NarrowBar(label: _folderLabel(_folder),
          leading: GestureDetector(
            onTap: () => setState(() => _narrowPane = 1),
            child: Icon(Symbols.arrow_back, size: 18, color: context.pal.textMute),
          ),
        ),
        Expanded(child: _readingPane(context)),
      ]);
    }
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() => _narrowPane = 0),
            child: Icon(Icons.menu, size: 20, color: context.pal.textMute),
          ),
          const SizedBox(width: 10),
          Text(_folderLabel(_folder), style: AppTheme.bodyStrong),
          if (_folder == 'inbox' && _unread > 0) ...[
            const SizedBox(width: 8),
            _CountBadge('$_unread'),
          ],
          const Spacer(),
          GestureDetector(
            onTap: _openCompose,
            child: Container(
              height: 28, padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(7)),
              child: Row(children: [
                const Icon(Symbols.edit_square, size: 13, color: Color(0xFF06120F)),
                const SizedBox(width: 4),
                Text('Compose', style: AppTheme.bodySub.copyWith(
                    color: const Color(0xFF06120F), fontSize: 11)),
              ]),
            ),
          ),
        ]),
      ),
      _searchBox(),
      Expanded(child: _emailList(context)),
    ]);
  }

  // ── Sidebar ────────────────────────────────────────────────────────────────

  Widget _sidebar(BuildContext context) {
    final staticFolders = [
      (Symbols.inbox,   'inbox',   'Inbox',   _unread),
      (Symbols.flag,    'flagged', 'Flagged', 0),
      (Symbols.send,    'sent',    'Sent',    0),
      (Symbols.drafts,  'drafts',  'Drafts',  0),
      (Symbols.archive, 'archive', 'Archive', 0),
      (Symbols.report,  'spam',    'Spam',    0),
      (Symbols.delete,  'trash',   'Trash',   0),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Compose button
      GestureDetector(
        onTap: _openCompose,
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.teal,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: AppColors.teal.withValues(alpha: 0.3), blurRadius: 12)],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Symbols.edit_square, size: 16, color: Color(0xFF06120F)),
            const SizedBox(width: 8),
            Text('Compose', style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F))),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      _SectionLabel('Mailboxes'),
      ...staticFolders.map((f) => _FolderItem(
        icon: f.$1, label: f.$3,
        count: f.$4 > 0 ? '${f.$4}' : null,
        active: _folder == f.$2,
        onTap: () => _switchFolder(f.$2),
      )),
      const SizedBox(height: 12),
      // Account settings link
      GestureDetector(
        onTap: () => _showAccountSettings(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            Icon(Symbols.settings, size: 15, color: context.pal.textDim),
            const SizedBox(width: 8),
            Flexible(child: Text('Account Settings', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySub.copyWith(fontSize: 12, color: context.pal.textDim))),
          ]),
        ),
      ),
    ]);
  }

  // ── Email list ─────────────────────────────────────────────────────────────

  Widget _emailList(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    // A background refresh failing while stale-but-valid cached emails
    // are already showing shouldn't blow that away.
    if (_loadError != null && _emails.isEmpty) return ErrorView(message: _loadError!, onRetry: _loadEmails);
    if (_emails.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Symbols.inbox, size: 36, color: context.pal.textDim),
        const SizedBox(height: 10),
        Text(_search.isNotEmpty ? 'Nothing matches "$_search"' : 'No messages in ${_folderLabel(_folder)}',
            style: AppTheme.bodySub.copyWith(fontSize: 13)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        itemCount: _emails.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _emails.length) {
            // Reaching the end loads the next 100.
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
            return Padding(padding: const EdgeInsets.all(14), child: Center(child: _loadingMore
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(onPressed: _loadMore, child: const Text('Load more'))));
          }
          final group = _emails[i].dateGroup;
          return _EmailListRow(
            email:    _emails[i],
            selected: _selectedIdx == i,
            // A section heading where the day/month changes.
            section:  i == 0 || _emails[i - 1].dateGroup != group ? group : null,
            onTap:    () => _selectAt(i),
            onMenu:   (pos) => _openRowMenu(i, pos),
          );
        },
      ),
    );
  }

  // ── Reading pane ───────────────────────────────────────────────────────────

  Widget _readingPane(BuildContext context) {
    final email = _selected;
    if (email == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Symbols.mark_email_unread, size: 40, color: context.pal.textDim),
        const SizedBox(height: 12),
        Text('Select an email to read', style: AppTheme.bodySub),
      ]));
    }
    return _ReadingPane(
      email:     email,
      canSpam:   !_ownFolder,
      onAction:  (a) => _run(a, _selectedIdx),
    );
  }

  // ── Account settings ───────────────────────────────────────────────────────

  void _showAccountSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _AccountDialog(
        existing: _accounts.isNotEmpty ? _accounts.first : null,
        onSaved: (acc) {
          setState(() {
            if (_accounts.isEmpty) {
              _accounts = [acc];
            } else {
              _accounts[0] = acc;
            }
          });
        },
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _folderLabel(String f) => switch (f.toLowerCase()) {
    'inbox'   => 'Inbox',
    'sent'    => 'Sent',
    'drafts'  => 'Drafts',
    'trash'   => 'Trash',
    'flagged' => 'Flagged',
    'archive' => 'Archive',
    'spam'    => 'Spam',
    _         => f,
  };
}

// ── Account setup prompt ─────────────────────────────────────────────────────

class _AccountSetupPrompt extends StatelessWidget {
  const _AccountSetupPrompt({required this.onAccountAdded});
  final void Function(EmailAccount) onAccountAdded;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Symbols.mail_outline, size: 48, color: context.pal.textDim),
      const SizedBox(height: 16),
      Text('No email account configured',
          style: AppTheme.bodyStrong.copyWith(fontSize: 16)),
      const SizedBox(height: 8),
      Text('Connect your IMAP/SMTP account to use this screen.',
          style: AppTheme.bodySub),
      const SizedBox(height: 24),
      GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _AccountDialog(
            onSaved: onAccountAdded,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.teal, borderRadius: BorderRadius.circular(10),
          ),
          child: Text('Connect Email Account', style: AppTheme.bodyStrong.copyWith(
              color: const Color(0xFF06120F))),
        ),
      ),
    ]),
  );
}

// ── Account dialog ───────────────────────────────────────────────────────────

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({this.existing, required this.onSaved});
  final EmailAccount?                       existing;
  final void Function(EmailAccount account) onSaved;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final _labelCtrl    = TextEditingController(text: widget.existing?.label    ?? '');
  late final _nameCtrl     = TextEditingController(text: widget.existing?.fromName ?? '');
  late final _emailCtrl    = TextEditingController(text: widget.existing?.fromEmail ?? '');
  late final _userCtrl     = TextEditingController(text: widget.existing?.username  ?? '');
  late final _passCtrl     = TextEditingController();
  late final _imapHostCtrl = TextEditingController(text: widget.existing?.imapHost ?? _mailHost);
  late final _smtpHostCtrl = TextEditingController(text: widget.existing?.smtpHost ?? _mailHost);
  late int    _imapPort    = widget.existing?.imapPort ?? 993;
  late int    _smtpPort    = widget.existing?.smtpPort ?? 465;

  bool    _saving   = false;
  bool    _testing  = false;
  String? _error;
  String? _testMsg;

  // Company mail server on the VPS (IMAP 993 SSL, SMTP 465 SSL) — the
  // only provider offered; Gmail/Outlook/Yahoo presets were removed.
  static const _mailHost = 'mail.hypermed.co.tz';

  @override
  void dispose() {
    for (final c in [_labelCtrl,_nameCtrl,_emailCtrl,_userCtrl,_passCtrl,
                     _imapHostCtrl,_smtpHostCtrl]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final data = {
        'label':           _labelCtrl.text.trim(),
        'from_name':       _nameCtrl.text.trim(),
        'from_email':      _emailCtrl.text.trim(),
        'username':        _userCtrl.text.trim(),
        if (_passCtrl.text.isNotEmpty) 'password': _passCtrl.text,
        'imap_host':       _imapHostCtrl.text.trim(),
        'imap_port':       _imapPort,
        'imap_encryption': 'ssl',
        'smtp_host':       _smtpHostCtrl.text.trim(),
        'smtp_port':       _smtpPort,
        'smtp_encryption': _smtpPort == 587 ? 'tls' : 'ssl',
        'is_default':      true,
      };
      final acc = widget.existing != null
          ? await EmailAccountService.instance.update(widget.existing!.id, data)
          : await EmailAccountService.instance.create(data);
      if (mounted) { widget.onSaved(acc); Navigator.of(context).pop(); }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e); });
    }
  }

  Future<void> _test() async {
    if (widget.existing == null) {
      setState(() => _testMsg = 'Save the account first, then test.');
      return;
    }
    setState(() { _testing = true; _testMsg = null; });
    try {
      final folders = await EmailAccountService.instance.test(widget.existing!.id);
      if (mounted) {
        setState(() {
          _testing = false;
          _testMsg = folders.isNotEmpty
              ? '✓ Connected. Folders: ${folders.take(5).join(', ')}'
              : '✓ Connected successfully.';
        });
      }
    } catch (e) {
      if (mounted) {
        // e is an Exception whose message is the server's specific error
        final msg = e.toString().replaceFirst('Exception: ', '');
        setState(() { _testing = false; _testMsg = '✗ $msg'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.88;
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        color: const Color(0xAA06070A),
        alignment: Alignment.center,
        child: PhoneModalBox(scroll: false, child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520, maxHeight: maxH),
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: context.pal.surface1,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.pal.borderStrong),
                  boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60)],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(children: [
                      Icon(Symbols.mail, size: 18, color: AppColors.teal),
                      const SizedBox(width: 10),
                      Text(widget.existing != null ? 'Email Account' : 'Connect Email Account',
                          style: AppTheme.bodyStrong),
                      const Spacer(),
                      GestureDetector(onTap: () => Navigator.of(context).pop(),
                          child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
                    ]),
                  ),
                  // Form
                  Flexible(child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(children: [
                      Row(children: [
                        Expanded(child: _aField('Label',      _labelCtrl,    'My Work Email')),
                        const SizedBox(width: 12),
                        Expanded(child: _aField('From name',  _nameCtrl,     'Edmund Salaho')),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _aField('From email', _emailCtrl, 'info@hypermed.co.tz')),
                        const SizedBox(width: 12),
                        Expanded(child: _aField('Username',   _userCtrl,  'info@hypermed.co.tz')),
                      ]),
                      const SizedBox(height: 10),
                      _aField('Password', _passCtrl, '••••••••••••••••',
                          obscure: true),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _aField('IMAP host', _imapHostCtrl, _mailHost)),
                        const SizedBox(width: 12),
                        SizedBox(width: 80, child: _aField('Port', TextEditingController(text: '$_imapPort'), '993',
                            onChanged: (v) => setState(() => _imapPort = int.tryParse(v) ?? _imapPort))),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _aField('SMTP host', _smtpHostCtrl, _mailHost)),
                        const SizedBox(width: 12),
                        SizedBox(width: 80, child: _aField('Port', TextEditingController(text: '$_smtpPort'), '465',
                            onChanged: (v) => setState(() => _smtpPort = int.tryParse(v) ?? _smtpPort))),
                      ]),
                      if (_testMsg != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _testMsg!.startsWith('✓')
                                ? AppColors.tealSoft : AppColors.coral.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(_testMsg!, style: AppTheme.bodySub.copyWith(
                            fontSize: 12,
                            color: _testMsg!.startsWith('✓') ? AppColors.teal : AppColors.coral)),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
                      ],
                      const SizedBox(height: 20),
                    ]),
                  )),
                  // Footer
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(children: [
                      GestureDetector(
                        onTap: _testing ? null : _test,
                        child: Container(
                          height: 36, padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: context.pal.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(child: _testing
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Text('Test', style: AppTheme.bodySm)),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          height: 36, padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: context.pal.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(child: Text('Cancel', style: AppTheme.bodySm)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _saving ? null : _save,
                        child: Container(
                          height: 36, padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                          child: Center(child: _saving
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(color: Color(0xFF06120F), strokeWidth: 2))
                            : Text('Save', style: AppTheme.bodyStrong.copyWith(
                                color: const Color(0xFF06120F)))),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        )),
      ),
    );
  }

  Widget _aField(String label, TextEditingController ctrl, String hint,
      {bool obscure = false, void Function(String)? onChanged}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabeledTextField(label: label, controller: ctrl, obscure: obscure, onChanged: onChanged, hint: hint),
    ]);
}

// ── Shared widgets ───────────────────────────────────────────────────────────

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.label, this.unread, this.onRefresh});
  final String label; final int? unread; final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
    child: Row(children: [
      Text(label, style: AppTheme.bodyStrong),
      if ((unread ?? 0) > 0) ...[const SizedBox(width: 8), _CountBadge('$unread')],
      const Spacer(),
      if (onRefresh != null)
        GestureDetector(onTap: onRefresh,
            child: Icon(Symbols.refresh, size: 16, color: context.pal.textDim)),
    ]),
  );
}

class _NarrowBar extends StatelessWidget {
  const _NarrowBar({required this.label, this.leading});
  final String label; final Widget? leading;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
    child: Row(children: [
      if (leading != null) ...[leading!, const SizedBox(width: 10)],
      Text(label, style: AppTheme.bodyStrong),
    ]),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: AppTheme.bodySub.copyWith(color: AppColors.teal, fontSize: 11)),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
    child: Text(text.toUpperCase(), style: AppTheme.monoXs.copyWith(letterSpacing: 0.10)),
  );
}

class _FolderItem extends StatelessWidget {
  const _FolderItem({required this.icon, required this.label, this.count,
      required this.active, required this.onTap});
  final IconData icon; final String label; final String? count;
  final bool active; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active ? context.pal.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(children: [
        Icon(icon, size: 17, color: active ? context.pal.text : context.pal.textMute),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: AppTheme.bodySm.copyWith(
          color: active ? context.pal.text : context.pal.textMute, fontSize: 13))),
        if (count != null)
          Text(count!, style: AppTheme.bodySub.copyWith(
            color: active ? AppColors.teal : context.pal.textDim, fontSize: 11)),
      ]),
    ),
  );
}

// ── Email list row ───────────────────────────────────────────────────────────

class _EmailListRow extends StatelessWidget {
  const _EmailListRow({required this.email, required this.selected, required this.onTap,
      required this.onMenu, this.section});
  final Email email; final bool selected; final VoidCallback onTap;
  /// Right-click / long-press: the row's actions at that point.
  final ValueChanged<Offset> onMenu;
  /// "Today", "Yesterday", "This week", a month — shown above the first row of each.
  final String? section;

  @override
  Widget build(BuildContext context) {
    final unread = !email.isRead;
    final row = GestureDetector(
      onSecondaryTapDown: (d) => onMenu(d.globalPosition),
      onLongPressStart: (d) => onMenu(d.globalPosition),
      child: Material(
        color: selected ? context.pal.surface2 : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 10, 16, 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.pal.divider),
                // Unread mail carries a teal edge.
                left: BorderSide(color: unread ? AppColors.teal : Colors.transparent, width: 3),
              ),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AvatarWidget(initials: email.initials, size: 30, variant: AvatarVariant.teal),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(email.from, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStrong.copyWith(fontSize: 13,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          color: unread ? context.pal.text : context.pal.textMute))),
                  if (email.hasAttachments) ...[
                    const SizedBox(width: 4),
                    Icon(Symbols.attach_file, size: 13, color: context.pal.textDim),
                  ],
                  if (email.isFlagged) ...[
                    const SizedBox(width: 4),
                    Icon(Symbols.flag, size: 13, color: AppColors.amber, fill: 1),
                  ],
                  const SizedBox(width: 6),
                  Text(email.timeLabel, style: AppTheme.bodySub.copyWith(fontSize: 11,
                      color: unread ? AppColors.teal : null)),
                ]),
                const SizedBox(height: 2),
                Text(email.subject, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySm.copyWith(
                      color: unread ? context.pal.text : context.pal.textMute,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    )),
                const SizedBox(height: 2),
                Text(email.preview, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ])),
            ]),
          ),
        ),
      ),
    );
    if (section == null) return row;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        decoration: BoxDecoration(
          color: context.pal.surface1,
          border: Border(bottom: BorderSide(color: context.pal.divider)),
        ),
        child: Text(section!.toUpperCase(), style: AppTheme.monoXs.copyWith(letterSpacing: 0.10)),
      ),
      row,
    ]);
  }
}

// ── Reading pane ─────────────────────────────────────────────────────────────

/// One email: actions on top, then subject, who/when, the message as sent
/// (formatted, every word selectable and copyable), attachments and a reply box.
class _ReadingPane extends StatefulWidget {
  const _ReadingPane({required this.email, required this.onAction, this.canSpam = true});
  final Email email;
  /// The screen's actions: read, flag, archive, inbox, spam, notspam, restore, delete.
  final ValueChanged<String> onAction;
  /// False in Sent/Drafts.
  final bool canSpam;

  @override
  State<_ReadingPane> createState() => _ReadingPaneState();
}

class _ReadingPaneState extends State<_ReadingPane> {
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  final _scroll = ScrollController();
  bool _sending    = false;
  bool _replyAll   = false;
  String? _replyError;
  int? _outboxId; // this reply's failed-send entry, if it failed before
  final _replyFiles = <Map<String, dynamic>>[];
  // The list rows don't carry attachments; the single email does.
  Future<List<EmailAttachment>>? _attachments;
  /// Pictures load from the sender's server (and tell it the email was
  /// opened), so they wait for a click; Spam never shows them.
  bool _showImages = false;
  /// Formatted (HTML) or plain text.
  bool _plain = false;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _replyFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ReadingPane old) {
    super.didUpdateWidget(old);
    if (old.email.id != widget.email.id) {
      _replyError = null;
      _outboxId = null;
      _replyFiles.clear();
      _showImages = false;
      _plain = false;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _loadAttachments();
    }
  }

  void _loadAttachments() {
    final email = widget.email;
    _attachments = email.hasAttachments
        ? EmailService.instance.get(email.id, markRead: false).then((e) => e.attachments)
        : null;
  }

  /// Toolbar Reply / Reply all: down to the reply box, ready to type.
  void _startReply(bool all) {
    setState(() => _replyAll = all);
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
    _replyFocus.requestFocus();
  }

  void _copyText() {
    final e = widget.email;
    Clipboard.setData(ClipboardData(text: e.body.isNotEmpty ? e.body : e.preview));
    showSuccessToast(context, 'Email text copied.');
  }

  bool get _hasImages => RegExp(r'<img\b', caseSensitive: false).hasMatch(widget.email.bodyHtml ?? '');

  Future<void> _attachToReply() async {
    final picked = await pickEmailFiles(context);
    if (mounted && addPickedFiles(context, _replyFiles, picked)) setState(() {});
  }

  Future<void> _sendReply() async {
    final body = _replyCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    final email = widget.email;
    setState(() { _sending = true; _replyError = null; });
    final payload = <String, dynamic>{
      'email_id': email.id,
      'body': body,
      'reply_all': _replyAll,
      // For the failed-sends list and its Edit.
      'to': email.fromEmail.isNotEmpty ? email.fromEmail : email.from,
      'subject': email.subject.toLowerCase().startsWith('re:') ? email.subject : 'Re: ${email.subject}',
      if (_replyFiles.isNotEmpty) 'attachments': _replyFiles,
    };
    try {
      await EmailOutbox.send('reply', payload);
      EmailOutbox.instance.remove(_outboxId);
      _outboxId = null;
      if (mounted) { _replyCtrl.clear(); setState(() { _sending = false; _replyFiles.clear(); }); }
    } catch (e) {
      final error = friendlyError(e);
      _outboxId = EmailOutbox.instance.record(id: _outboxId, kind: 'reply', payload: payload, error: error);
      if (mounted) setState(() { _sending = false; _replyError = error; });
    }
  }

  void _showForward(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _ForwardDialog(emailId: widget.email.id,
          originalSubject: widget.email.subject, hasAttachments: widget.email.hasAttachments),
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────────────

  Widget _toolbar(BuildContext context) => LayoutBuilder(builder: (context, c) => _toolbarFor(context, isPhoneWidth(c.maxWidth)));

  /// Phone: Reply keeps its label, the rest are icons with tooltips.
  Widget _toolbarFor(BuildContext context, bool phone) {
    final e = widget.email;
    final act = widget.onAction;
    Widget icon(IconData i, String tip, VoidCallback onTap, {Color? color, bool fill = false}) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(i, size: phone ? 20 : 18, color: color ?? context.pal.textMute, fill: fill ? 1 : 0),
    );
    if (phone) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
        child: Row(children: [
          if (e.inSpam)
            AppButton(small: true, icon: Symbols.report_off, label: 'Not spam', onPressed: () => act('notspam'))
          else if (e.inTrash)
            AppButton(small: true, icon: Symbols.restore_from_trash, label: 'Restore', onPressed: () => act('restore'))
          else
            AppButton(small: true, variant: BtnVariant.primary, icon: Symbols.reply, label: 'Reply', onPressed: () => _startReply(false)),
          const Spacer(),
          if (!e.inSpam && !e.inTrash) ...[
            icon(Symbols.reply_all, 'Reply all', () => _startReply(true)),
            icon(Symbols.forward, 'Forward', () => _showForward(context)),
            e.inArchive
                ? icon(Symbols.move_to_inbox, 'Move to Inbox', () => act('inbox'))
                : icon(Symbols.archive, 'Archive', () => act('archive')),
            if (widget.canSpam) icon(Symbols.report, 'Mark as spam', () => act('spam')),
          ],
          icon(e.inSpam || e.inTrash ? Symbols.delete_forever : Symbols.delete,
              e.inSpam || e.inTrash ? 'Delete forever' : 'Delete', () => act('delete')),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            color: context.pal.surface1,
            icon: Icon(Symbols.more_vert, size: 20, color: context.pal.textMute),
            onSelected: (v) => v == 'copy' ? _copyText() : act(v),
            itemBuilder: (_) => [
              for (final (v, ic, label) in [
                ('read', e.isRead ? Symbols.mark_email_unread : Symbols.drafts, e.isRead ? 'Mark as unread' : 'Mark as read'),
                ('flag', Symbols.flag, e.isFlagged ? 'Remove flag' : 'Flag'),
                ('copy', Symbols.content_copy, 'Copy email text'),
              ])
                PopupMenuItem(value: v, height: 36, child: Row(children: [
                  Icon(ic, size: 16, color: context.pal.textMute),
                  const SizedBox(width: 12),
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySm.copyWith(fontSize: 13, color: context.pal.text))),
                ])),
            ],
          ),
        ]),
      );
    }
    final moves = <Widget>[
      if (e.inSpam) ...[
        AppButton(small: true, icon: Symbols.report_off, label: 'Not spam', onPressed: () => act('notspam')),
        AppButton(small: true, icon: Symbols.delete_forever, label: 'Delete forever', variant: BtnVariant.danger, onPressed: () => act('delete')),
      ] else if (e.inTrash) ...[
        AppButton(small: true, icon: Symbols.restore_from_trash, label: 'Restore', onPressed: () => act('restore')),
        AppButton(small: true, icon: Symbols.delete_forever, label: 'Delete forever', variant: BtnVariant.danger, onPressed: () => act('delete')),
      ] else ...[
        e.inArchive
            ? AppButton(small: true, variant: BtnVariant.ghost, icon: Symbols.move_to_inbox, label: 'Move to Inbox', onPressed: () => act('inbox'))
            : AppButton(small: true, variant: BtnVariant.ghost, icon: Symbols.archive, label: 'Archive', onPressed: () => act('archive')),
        if (widget.canSpam)
          AppButton(small: true, variant: BtnVariant.ghost, icon: Symbols.report, label: 'Spam', onPressed: () => act('spam')),
        AppButton(small: true, variant: BtnVariant.ghost, icon: Symbols.delete, label: 'Delete', onPressed: () => act('delete')),
      ],
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
      child: Row(children: [
        Expanded(child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (!e.inSpam && !e.inTrash) ...[
            AppButton(small: true, variant: BtnVariant.primary, icon: Symbols.reply, label: 'Reply', onPressed: () => _startReply(false)),
            AppButton(small: true, icon: Symbols.reply_all, label: 'Reply all', onPressed: () => _startReply(true)),
            AppButton(small: true, icon: Symbols.forward, label: 'Forward', onPressed: () => _showForward(context)),
            Container(width: 1, height: 20, color: context.pal.border),
          ],
          ...moves,
        ])),
        icon(e.isRead ? Symbols.mark_email_unread : Symbols.drafts, e.isRead ? 'Mark as unread' : 'Mark as read', () => act('read')),
        icon(Symbols.flag, e.isFlagged ? 'Remove flag' : 'Flag', () => act('flag'),
            color: e.isFlagged ? AppColors.amber : null, fill: e.isFlagged),
        icon(Symbols.content_copy, 'Copy email text', _copyText),
      ]),
    );
  }

  // ── Who / when ─────────────────────────────────────────────────────────────

  Widget _header(BuildContext context) {
    final e = widget.email;
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 38, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12, color: context.pal.textDim))),
        Expanded(child: Text(value, style: AppTheme.bodySub.copyWith(fontSize: 12, color: context.pal.textMute))),
      ]),
    );
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AvatarWidget(initials: e.initials, size: 38, variant: AvatarVariant.teal),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
            Text(e.from, style: AppTheme.bodyStrong.copyWith(color: context.pal.text)),
            if (e.fromEmail.isNotEmpty && e.fromEmail != e.from)
              Text('<${e.fromEmail}>', style: AppTheme.bodySub.copyWith(fontSize: 12)),
          ]),
          const SizedBox(height: 2),
          if (e.to.isNotEmpty) line('To', e.to),
          if (e.cc != null) line('Cc', e.cc!),
          line('Date', e.fullDateLabel),
        ])),
      ]),
    );
  }

  // ── Message ────────────────────────────────────────────────────────────────

  Widget _body(BuildContext context) {
    final e = widget.email;
    final html = e.bodyHtml;
    final plainStyle = AppTheme.bodySm.copyWith(height: 1.65, color: context.pal.text);
    if (html == null || _plain) {
      return Text(e.body.isNotEmpty ? e.body : e.preview, style: plainStyle);
    }
    final images = _showImages && !e.inSpam;
    // Mail is written for a white page (dark text, its own colours), so it
    // sits on one in both themes.
    const ink = Color(0xFF1F2328);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.pal.border),
      ),
      child: HtmlWidget(
        html,
        textStyle: AppTheme.bodySm.copyWith(height: 1.55, color: ink, fontSize: 13.5),
        onTapUrl: (url) async {
          final uri = Uri.tryParse(url);
          if (uri == null || !(uri.isScheme('http') || uri.isScheme('https') || uri.isScheme('mailto'))) return true;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return true;
        },
        customWidgetBuilder: (el) => el.localName == 'img' && !images ? const SizedBox.shrink() : null,
        onErrorBuilder: (_, _, _) => Text(e.body, style: plainStyle.copyWith(color: ink)),
      ),
    );
  }

  /// "Pictures are hidden · Show pictures" and "Show as plain text", above the message.
  Widget _viewOptions(BuildContext context) {
    final e = widget.email;
    if (e.bodyHtml == null) return const SizedBox.shrink();
    final linkStyle = AppTheme.bodySub.copyWith(fontSize: 12, color: AppColors.teal, fontWeight: FontWeight.w600);
    Widget link(String label, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Text(label, style: linkStyle)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (_hasImages && !_plain && !e.inSpam && !_showImages) ...[
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Symbols.hide_image, size: 14, color: context.pal.textDim),
            const SizedBox(width: 6),
            Text('Pictures are hidden.', style: AppTheme.bodySub.copyWith(fontSize: 12)),
          ]),
          link('Show pictures', () => setState(() => _showImages = true)),
        ],
        link(_plain ? 'Show formatted' : 'Show as plain text', () => setState(() => _plain = !_plain)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.email;
    return Column(children: [
      _toolbar(context),
      Expanded(child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (email.inSpam) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Symbols.report, size: 16, color: AppColors.coral),
                const SizedBox(width: 8),
                Expanded(child: Text('This email is in Spam. Pictures stay hidden; mark it Not spam to move it back to your Inbox.',
                    style: AppTheme.bodySub.copyWith(fontSize: 12, color: AppColors.coral))),
              ]),
            ),
            const SizedBox(height: 14),
          ],
          // Subject, people, date and message: drag to select, right-click
          // or Ctrl+C to copy, Ctrl+A for everything.
          SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(email.subject, style: AppTheme.pageTitle.copyWith(fontSize: 18, color: context.pal.text)),
            const SizedBox(height: 14),
            _header(context),
            const SizedBox(height: 14),
            _viewOptions(context),
            _body(context),
          ])),
          if (_attachments != null) ...[
            const SizedBox(height: 20),
            FutureBuilder<List<EmailAttachment>>(
              future: _attachments,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Row(children: [
                    Expanded(child: Text('Couldn\'t load the attachments: ${friendlyError(snap.error!)}',
                        style: AppTheme.bodySub.copyWith(fontSize: 12, color: AppColors.coral))),
                    TextButton(onPressed: () => setState(_loadAttachments), child: const Text('Retry')),
                  ]);
                }
                if (!snap.hasData) {
                  return Row(children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text('Loading attachments…', style: AppTheme.bodySub.copyWith(fontSize: 12)),
                  ]);
                }
                return snap.data!.isEmpty
                    ? const SizedBox.shrink()
                    : EmailAttachmentList(emailId: email.id, attachments: snap.data!);
              },
            ),
          ],
          if (!email.inSpam && !email.inTrash) ...[
            const SizedBox(height: 28),
            _replyBox(context),
          ],
        ]),
      )),
    ]);
  }

  Widget _replyBox(BuildContext context) {
    final email = widget.email;
    return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.pal.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LabeledTextField(label: '', controller: _replyCtrl, focusNode: _replyFocus, maxLines: 4,
                hint: _replyAll ? 'Reply to everyone…' : 'Reply to ${email.from}…'),
            if (_replyFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutgoingAttachmentChips(files: _replyFiles, onRemove: (i) => setState(() => _replyFiles.removeAt(i))),
            ],
            if (_replyError != null) ...[
              const SizedBox(height: 8),
              Text("Couldn't send: $_replyError",
                  style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
            ],
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.pal.divider))),
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                // Reply / Reply All toggle
                GestureDetector(
                  onTap: () => setState(() => _replyAll = !_replyAll),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _replyAll ? AppColors.tealSoft : context.pal.surface2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _replyAll ? AppColors.teal : context.pal.border),
                    ),
                    child: Text(_replyAll ? 'Reply All' : 'Reply',
                      style: AppTheme.bodySub.copyWith(
                        fontSize: 12,
                        color: _replyAll ? AppColors.teal : context.pal.textMute)),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Attach files',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _attachToReply,
                  icon: Icon(Symbols.attach_file, size: 18, color: context.pal.textMute),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _sendReply,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                        color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: _sending
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(color: Color(0xFF06120F), strokeWidth: 2))
                      : Text('Send', style: AppTheme.bodyStrong.copyWith(
                          color: const Color(0xFF06120F), fontSize: 13)),
                  ),
                ),
              ]),
            ),
          ]),
        );
  }
}

// ── Forward dialog ───────────────────────────────────────────────────────────

class _ForwardDialog extends StatefulWidget {
  const _ForwardDialog({required this.emailId, required this.originalSubject, this.hasAttachments = false});
  final int emailId; final String originalSubject;
  /// The original's attachments go along (the API adds them).
  final bool hasAttachments;

  @override
  State<_ForwardDialog> createState() => _ForwardDialogState();
}

class _ForwardDialogState extends State<_ForwardDialog> {
  final _toCtrl   = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool    _sending = false;
  String? _error;
  int?    _outboxId;
  final _files = <Map<String, dynamic>>[];

  @override
  void dispose() { _toCtrl.dispose(); _bodyCtrl.dispose(); super.dispose(); }

  Future<void> _attach() async {
    final picked = await pickEmailFiles(context);
    if (mounted && addPickedFiles(context, _files, picked)) setState(() {});
  }

  Future<void> _send() async {
    if (_toCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Recipient is required.');
      return;
    }
    setState(() { _sending = true; _error = null; });
    final payload = <String, dynamic>{
      'email_id': widget.emailId,
      'to': _toCtrl.text.trim(),
      'body': _bodyCtrl.text.trim(),
      'subject': 'Fwd: ${widget.originalSubject}',
      if (_files.isNotEmpty) 'attachments': _files,
    };
    try {
      await EmailOutbox.send('forward', payload);
      EmailOutbox.instance.remove(_outboxId);
      _outboxId = null;
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      final error = friendlyError(e);
      _outboxId = EmailOutbox.instance.record(id: _outboxId, kind: 'forward', payload: payload, error: error);
      if (mounted) setState(() { _sending = false; _error = error; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
    contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
    actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
    title: Row(children: [
      Icon(Symbols.forward_to_inbox, size: 18, color: AppColors.teal),
      const SizedBox(width: 10),
      Expanded(child: Text('Forward: ${widget.originalSubject}',
          style: AppTheme.bodyStrong, overflow: TextOverflow.ellipsis)),
    ]),
    content: SizedBox(
      width: 440,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _fField('To', _toCtrl, 'recipient@example.com', context),
        const SizedBox(height: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LabeledTextField(label: 'Note', controller: _bodyCtrl, maxLines: 3, hint: 'Add a note (optional)…'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text(widget.hasAttachments ? 'The original attachments are included.' : 'Add files if needed.',
              style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textDim))),
          TextButton.icon(onPressed: _sending ? null : _attach,
              icon: const Icon(Symbols.attach_file, size: 16), label: const Text('Attach')),
        ]),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft,
              child: OutgoingAttachmentChips(files: _files, onRemove: (i) => setState(() => _files.removeAt(i)))),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
        ],
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppTheme.bodySm.copyWith(color: context.pal.textMute))),
      GestureDetector(
        onTap: _sending ? null : _send,
        child: Container(
          height: 36, padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
          child: Center(child: _sending
            ? const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(color: Color(0xFF06120F), strokeWidth: 2))
            : Text('Forward', style: AppTheme.bodyStrong.copyWith(
                color: const Color(0xFF06120F), fontSize: 13))),
        ),
      ),
    ],
  );

  Widget _fField(String label, TextEditingController ctrl, String hint, BuildContext ctx) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabeledTextField(label: label, controller: ctrl, hint: hint),
    ]);
}

// ── Failed sends ─────────────────────────────────────────────────────────────

/// "N messages failed to send" — shown above the mailbox while the outbox
/// has entries.
class _FailedSendsBanner extends StatelessWidget {
  const _FailedSendsBanner({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<OutboxEntry>>(
    valueListenable: EmailOutbox.instance.entries,
    builder: (_, entries, _) {
      if (entries.isEmpty) return const SizedBox.shrink();
      final n = entries.length;
      return Material(
        color: AppColors.coralSoft,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
            child: Row(children: [
              Icon(Symbols.error, size: 16, color: AppColors.coral),
              const SizedBox(width: 8),
              Expanded(child: Text('$n message${n == 1 ? '' : 's'} failed to send',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySm.copyWith(color: AppColors.coral, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Text('Review', style: AppTheme.bodyStrong.copyWith(color: AppColors.coral, fontSize: 12.5)),
            ]),
          ),
        ),
      );
    },
  );
}

/// The failed sends, each with Retry / Edit / Discard.
class _OutboxDialog extends StatefulWidget {
  const _OutboxDialog({required this.onEdit});
  final ValueChanged<OutboxEntry> onEdit;

  @override
  State<_OutboxDialog> createState() => _OutboxDialogState();
}

class _OutboxDialogState extends State<_OutboxDialog> {
  final _retrying = <int>{};

  Future<void> _retry(OutboxEntry e) async {
    setState(() => _retrying.add(e.id));
    try {
      await EmailOutbox.instance.retry(e);
    } catch (_) {
      // The entry now carries the new error; the list shows it.
    }
    if (mounted) setState(() => _retrying.remove(e.id));
  }

  static String _kindLabel(String kind) => switch (kind) {
    'reply'   => 'Reply',
    'forward' => 'Forward',
    _         => 'New message',
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
    contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
    title: Text('Failed to send', style: AppTheme.bodyStrong),
    content: SizedBox(
      width: 480,
      child: ValueListenableBuilder<List<OutboxEntry>>(
        valueListenable: EmailOutbox.instance.entries,
        builder: (_, entries, _) {
          if (entries.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Nothing left to send.', style: AppTheme.bodySub),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            itemCount: entries.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: context.pal.divider),
            itemBuilder: (_, i) => _entry(context, entries[i]),
          );
        },
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: AppTheme.bodySm.copyWith(color: context.pal.textMute))),
    ],
  );

  Widget _entry(BuildContext context, OutboxEntry e) {
    final to = (e.payload['to'] as String?) ?? '';
    final subject = (e.payload['subject'] as String?) ?? '';
    final busy = _retrying.contains(e.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(subject.isNotEmpty ? subject : '(no subject)',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
        const SizedBox(height: 2),
        Text('${_kindLabel(e.kind)} · to $to',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySub.copyWith(fontSize: 12)),
        if (e.error != null) ...[
          const SizedBox(height: 2),
          Text(e.error!, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.coral, fontSize: 12)),
        ],
        const SizedBox(height: 6),
        Wrap(spacing: 4, children: [
          TextButton.icon(
            onPressed: busy ? null : () => _retry(e),
            icon: busy
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                : Icon(Symbols.send, size: 15, color: AppColors.teal),
            label: Text('Retry', style: AppTheme.bodySm.copyWith(color: AppColors.teal)),
          ),
          TextButton.icon(
            onPressed: busy ? null : () => widget.onEdit(e),
            icon: Icon(Symbols.edit, size: 15, color: context.pal.textMute),
            label: Text('Edit', style: AppTheme.bodySm.copyWith(color: context.pal.textMute)),
          ),
          TextButton.icon(
            onPressed: busy ? null : () => EmailOutbox.instance.remove(e.id),
            icon: Icon(Symbols.delete_outline, size: 15, color: AppColors.coral),
            label: Text('Discard', style: AppTheme.bodySm.copyWith(color: AppColors.coral)),
          ),
        ]),
      ]),
    );
  }
}

// ── Compose modal ────────────────────────────────────────────────────────────
