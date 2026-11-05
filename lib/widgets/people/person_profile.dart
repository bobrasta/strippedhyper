import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../main.dart' show roleDisplayName, userIdNotifier;
import '../../services/api_client.dart';
import '../../services/chat_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../common/app_button.dart';
import '../common/avatar_widget.dart';
import '../common/error_view.dart';
import '../common/phone_layout.dart';

/// A colleague's public profile (GET /people/{id}): photo, position,
/// department, who they report to, contact, bio and qualifications. The API
/// never sends sensitive data (IDs, bank, salary, next of kin).
class PersonProfile {
  const PersonProfile({
    required this.id, required this.name, this.avatarUrl, this.position, this.department, this.role,
    this.region, this.email, this.phone, this.joined, this.bio, this.qualifications = const [],
    this.reportsTo, this.reportsToPosition, this.isActive = true,
  });
  final int id;
  final String name;
  final String? avatarUrl, position, department, role, region, email, phone, bio, reportsTo, reportsToPosition;
  final DateTime? joined;
  final List<String> qualifications;
  final bool isActive;

  factory PersonProfile.fromJson(Map<String, dynamic> j) {
    final boss = j['reports_to'] is Map ? Map<String, dynamic>.from(j['reports_to'] as Map) : null;
    String? s(String k) => (j[k] as String?)?.trim().isEmpty ?? true ? null : (j[k] as String).trim();
    return PersonProfile(
      id: (j['id'] as num).toInt(), name: (j['name'] as String?) ?? '', avatarUrl: s('avatar_url'),
      position: s('position'), department: s('department'), role: s('role'), region: s('region'),
      email: s('email'), phone: s('phone'), bio: s('bio'),
      joined: j['joined'] is String ? DateTime.tryParse(j['joined'] as String) : null,
      qualifications: [for (final q in (j['qualifications'] as List? ?? const [])) if ('$q'.trim().isNotEmpty) '$q'.trim()],
      reportsTo: boss?['name'] as String?, reportsToPosition: boss?['position'] as String?,
      isActive: j['is_active'] != false,
    );
  }

  String get initials {
    final p = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    return p.length == 1 ? p.first[0].toUpperCase() : (p.first[0] + p.last[0]).toUpperCase();
  }
}

Future<PersonProfile> fetchPersonProfile(int userId) async {
  final res = await ApiClient.instance.dio.get('/people/$userId', options: ApiClient.noCache);
  return PersonProfile.fromJson(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
}

/// Opens [userId]'s profile as a card over the page (a bottom sheet on a
/// phone). [onMessage] replaces the default "Message" action (open a chat).
Future<void> showPersonProfile(BuildContext context, int userId) => showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dCtx) => _ProfileCard(userId: userId, onClose: () => Navigator.of(dCtx).pop()),
    );

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.userId, required this.onClose});
  final int userId;
  final VoidCallback onClose;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  PersonProfile? _p;
  String? _error;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await fetchPersonProfile(widget.userId);
      if (mounted) setState(() => _p = p);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _message() async {
    setState(() => _opening = true);
    try {
      final id = await ChatController.instance.startDirect(widget.userId);
      final c = ChatController.instance;
      c.openRequests.value = null;
      c.openRequests.value = id;
      widget.onClose();
    } catch (e) {
      if (mounted) {
        setState(() => _opening = false);
        showErrorToast(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          onTap: widget.onClose,
          child: Container(
            color: const Color(0xAA06070A),
            alignment: Alignment.center,
            child: PhoneModalBox(child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 440,
                decoration: BoxDecoration(
                  color: context.pal.surface1,
                  borderRadius: BorderRadius.circular(AppColors.rMd),
                  border: Border.all(color: context.pal.borderStrong),
                ),
                child: _body(context),
              ),
            )),
          ),
        ),
      );

  Widget _body(BuildContext context) {
    final p = _p;
    if (_error != null) {
      return Padding(padding: const EdgeInsets.all(16),
          child: ErrorView(message: _error!, onRetry: _load, compact: true));
    }
    if (p == null) {
      return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final me = userIdNotifier.value == p.id;
    final role = p.role == null ? null : roleDisplayName(p.role!);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Identity
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AvatarWidget(initials: p.initials, imageUrl: p.avatarUrl, size: 64, variant: AvatarVariant.teal),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: AppTheme.pageTitle.copyWith(fontSize: 18), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (p.position != null || role != null) ...[
              const SizedBox(height: 2),
              Text(p.position ?? role!, style: AppTheme.bodySm.copyWith(fontSize: 13, color: context.pal.textMute),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (p.department != null) _pill(context, p.department!, AppColors.tealSoft, AppColors.teal),
              if (!p.isActive) _pill(context, 'No longer with Hypermed', AppColors.coralSoft, AppColors.coral),
            ]),
          ])),
          IconButton(
            tooltip: 'Close',
            onPressed: widget.onClose,
            icon: Icon(Symbols.close, size: 18, color: context.pal.textDim),
          ),
        ]),
      ),
      Divider(height: 1, color: context.pal.divider),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (p.reportsTo != null)
            _row(context, Symbols.supervisor_account, 'Reports to',
                p.reportsToPosition != null ? '${p.reportsTo} · ${p.reportsToPosition}' : p.reportsTo!),
          if (p.region != null) _row(context, Symbols.location_on, 'Based in', p.region!),
          if (p.joined != null) _row(context, Symbols.calendar_month, 'Joined', formatDate(p.joined!)),
          if (p.email != null)
            _row(context, Symbols.mail, 'Email', p.email!, onTap: () => launchUrl(Uri(scheme: 'mailto', path: p.email))),
          if (p.phone != null)
            _row(context, Symbols.call, 'Phone', p.phone!, onTap: () => launchUrl(Uri(scheme: 'tel', path: p.phone))),
        ]),
      ),
      if (p.bio != null || p.qualifications.isNotEmpty)
        Flexible(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (p.bio != null) ...[
              Text('ABOUT', style: AppTheme.monoXs.copyWith(letterSpacing: 0.10)),
              const SizedBox(height: 4),
              Text(p.bio!, style: AppTheme.bodySm.copyWith(fontSize: 13, height: 1.45)),
              const SizedBox(height: 12),
            ],
            if (p.qualifications.isNotEmpty) ...[
              Text('QUALIFICATIONS', style: AppTheme.monoXs.copyWith(letterSpacing: 0.10)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final q in p.qualifications)
                  _pill(context, q, context.pal.surface2, context.pal.text, icon: Symbols.workspace_premium),
              ]),
            ],
          ]),
        )),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.border))),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          AppButton(label: 'Close', variant: BtnVariant.ghost, small: true, onPressed: widget.onClose),
          if (!me && p.isActive && chatAvailableNotifier.value) ...[
            const SizedBox(width: 8),
            AppButton(label: _opening ? 'Opening…' : 'Message', icon: Symbols.chat, small: true,
                variant: BtnVariant.primary, onPressed: _opening ? null : () => unawaited(_message())),
          ],
        ]),
      ),
    ]);
  }

  Widget _row(BuildContext context, IconData icon, String label, String value, {VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 15, color: context.pal.textDim),
          const SizedBox(width: 10),
          SizedBox(width: 78, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12))),
          Expanded(child: InkWell(
            onTap: onTap,
            child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySm.copyWith(fontSize: 13, color: onTap != null ? AppColors.teal : null)),
          )),
        ]),
      );

  Widget _pill(BuildContext context, String text, Color bg, Color fg, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: fg, fontWeight: FontWeight.w600))),
        ]),
      );
}
