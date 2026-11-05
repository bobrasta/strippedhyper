import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/email_outbox.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../common/labeled_field.dart';
import 'email_attachments.dart';

/// Full-screen overlay compose modal — renders its own semi-transparent
/// backdrop, so show it via `showDialog(builder: (_) => ComposeModal(...))`
/// like every other modal in the app, not as a bare Stack child. A Stack
/// only gives a non-Positioned child the bounds of whatever screen it's
/// embedded in (e.g. just the email content pane, not the whole window),
/// so the backdrop and centering broke when this was stacked directly.
///
/// Pass [initialTo] to pre-fill the recipient field (e.g. from a contact card).
///
/// A failed send is saved to the [EmailOutbox] (the inline error stays);
/// a later successful send from the same dialog removes it. [outboxId] ties
/// the dialog to an existing entry (Edit from the failed-sends list).
class ComposeModal extends StatefulWidget {
  const ComposeModal({
    super.key,
    required this.onClose,
    this.onSent,
    this.initialTo,
    this.initialSubject,
    this.initialCc,
    this.initialBcc,
    this.initialBody,
    this.initialAttachments,
    this.outboxId,
  });

  final VoidCallback  onClose;
  final VoidCallback? onSent;
  final String?       initialTo;
  final String?       initialSubject;
  final String?       initialCc;
  final String?       initialBcc;
  final String?       initialBody;
  /// `{path, name, size, token?}` maps (Edit from the failed-sends list).
  final List<Map<String, dynamic>>? initialAttachments;
  final int?          outboxId;

  @override
  State<ComposeModal> createState() => _ComposeModalState();
}

class _ComposeModalState extends State<ComposeModal> {
  late final _toCtrl      = TextEditingController(text: widget.initialTo ?? '');
  late final _ccCtrl      = TextEditingController(text: widget.initialCc ?? '');
  late final _bccCtrl     = TextEditingController(text: widget.initialBcc ?? '');
  late final _subjectCtrl = TextEditingController(text: widget.initialSubject ?? '');
  late final _bodyCtrl    = TextEditingController(text: widget.initialBody ?? '');
  bool    _sending = false;
  String? _error;
  late bool _showBcc = (widget.initialBcc ?? '').isNotEmpty;
  late int? _outboxId = widget.outboxId;
  late final _files = [for (final f in widget.initialAttachments ?? const []) Map<String, dynamic>.from(f)];

  Future<void> _attach() async {
    final picked = await pickEmailFiles(context);
    if (mounted && addPickedFiles(context, _files, picked)) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_toCtrl, _ccCtrl, _bccCtrl, _subjectCtrl, _bodyCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_toCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Recipient (To) is required.');
      return;
    }
    if (_subjectCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Subject is required.');
      return;
    }
    setState(() { _sending = true; _error = null; });
    final payload = <String, dynamic>{
      'to':      _toCtrl.text.trim(),
      'cc':      _ccCtrl.text.trim().isNotEmpty  ? _ccCtrl.text.trim()  : null,
      'bcc':     _bccCtrl.text.trim().isNotEmpty ? _bccCtrl.text.trim() : null,
      'subject': _subjectCtrl.text.trim(),
      'body':    _bodyCtrl.text.trim(),
      if (_files.isNotEmpty) 'attachments': _files,
    };
    try {
      await EmailOutbox.send('compose', payload);
      EmailOutbox.instance.remove(_outboxId);
      _outboxId = null;
      widget.onSent?.call();
    } catch (e) {
      final error = friendlyError(e);
      _outboxId = EmailOutbox.instance.record(
          id: _outboxId, kind: 'compose', payload: payload, error: error);
      if (mounted) setState(() { _sending = false; _error = error; });
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    // TextField needs a Material ancestor; showDialog's route content
    // doesn't provide one on its own, unlike being embedded directly in a
    // screen that already sits inside the app's own Material tree.
    type: MaterialType.transparency,
    child: Container(
    color: const Color(0xB306070A),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Container(
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.pal.borderStrong),
          boxShadow: const [BoxShadow(
            color: Color(0x80000000), blurRadius: 80, offset: Offset(0, 30))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Expanded(child: Text('New Message', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
              GestureDetector(
                onTap: () => setState(() => _showBcc = !_showBcc),
                child: Text('BCC', style: AppTheme.bodySub.copyWith(
                    color: _showBcc ? AppColors.teal : context.pal.textDim,
                    fontSize: 12)),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: widget.onClose,
                child: Icon(Symbols.close, size: 18, color: context.pal.textDim),
              ),
            ]),
          ),
          // Fields — the shared Settings inputs (LabeledTextField), in a
          // scroll area so the dialog never overflows short windows.
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              LabeledTextField(label: 'To', controller: _toCtrl, hint: 'recipient@example.com', keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),
              LabeledTextField(label: 'CC', controller: _ccCtrl),
              if (_showBcc) ...[
                const SizedBox(height: 10),
                LabeledTextField(label: 'BCC', controller: _bccCtrl),
              ],
              const SizedBox(height: 10),
              LabeledTextField(label: 'Subject', controller: _subjectCtrl),
              const SizedBox(height: 10),
              LabeledTextField(label: 'Message', controller: _bodyCtrl, maxLines: 8, hint: 'Compose your message…'),
              if (_files.isNotEmpty) ...[
                const SizedBox(height: 10),
                OutgoingAttachmentChips(files: _files, onRemove: (i) => setState(() => _files.removeAt(i))),
              ],
            ]),
          )),
          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x04FFFFFF),
              border: Border(top: BorderSide(color: context.pal.border)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!,
                      style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
                ),
              Row(children: [
                GestureDetector(
                  onTap: _sending ? null : _send,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                        color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: _sending
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                color: Color(0xFF06120F), strokeWidth: 2))
                        : Text('Send', style: AppTheme.bodyStrong.copyWith(
                            color: const Color(0xFF06120F))),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Attach files',
                  onPressed: _sending ? null : _attach,
                  icon: Icon(Symbols.attach_file, size: 20, color: context.pal.textMute),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Icon(Symbols.delete_outline, size: 20, color: context.pal.textDim),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    ),
  ));
}
