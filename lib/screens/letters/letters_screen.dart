// Letters on the Hypermed letterhead. Each letter gets the next reference
// number (HHL/2026/0001…); the signatory's own signature goes on only when
// they press Sign; the company stamp is a tick box. Everyone writes letters
// and sees their own and the ones they sign (admins see all).
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/letter.dart';
import '../../services/letter_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/phone_layout.dart';

class LettersScreen extends StatefulWidget {
  const LettersScreen({super.key});
  @override
  State<LettersScreen> createState() => _LettersScreenState();
}

class _LettersScreenState extends State<LettersScreen> {
  LettersPage? _page;
  Object? _error;
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await LetterService.instance.list();
      if (mounted) setState(() { _page = p; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<Letter> get _shown {
    final q = _query.trim().toLowerCase();
    final all = _page?.letters ?? const <Letter>[];
    if (q.isEmpty) return all;
    return all.where((l) => '${l.referenceNumber} ${l.subject} ${l.recipient} ${l.signatoryName ?? ''}'.toLowerCase().contains(q)).toList();
  }

  Future<void> _newLetter() async {
    if (await showLetterForm(context) != null) _load();
  }

  Future<void> _open(Letter l) async {
    if (await showDialog<bool>(context: context, builder: (_) => _LetterDialog(letter: l)) == true) _load();
  }

  Future<String?> _pickImage() async {
    final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg']);
    final f = r?.files.firstOrNull;
    return f?.path;
  }

  Future<void> _mySignature() async {
    final has = _page?.mySignature ?? false;
    final choice = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: Text('My signature', style: AppTheme.bodyStrong),
      content: Text(has
          ? 'Your signature is on file. It is added to a letter only when you, as its signatory, press Sign.'
          : 'Upload a picture of your signature (a PNG with a transparent background looks best). '
            'It is added to a letter only when you, as its signatory, press Sign.',
          style: AppTheme.bodySub),
      actions: [
        if (has) TextButton(onPressed: () => Navigator.pop(ctx, 'remove'), child: Text('Remove', style: TextStyle(color: AppColors.coral))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'upload'), child: Text(has ? 'Replace' : 'Upload')),
      ],
    ));
    if (!mounted || choice == null) return;
    try {
      if (choice == 'remove') {
        await LetterService.instance.removeSignature();
      } else {
        final path = await _pickImage();
        if (path == null) return;
        await LetterService.instance.uploadSignature(path, path.split(RegExp(r'[\\/]')).last);
      }
      if (mounted) showSuccessToast(context, choice == 'remove' ? 'Signature removed' : 'Signature saved');
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _stamp() async {
    final path = await _pickImage();
    if (path == null) return;
    try {
      await LetterService.instance.uploadStamp(path, path.split(RegExp(r'[\\/]')).last);
      if (mounted) showSuccessToast(context, 'Company stamp saved');
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, cst) {
    final phone = isPhoneWidth(cst.maxWidth);
    final page = _page;
    final search = LabeledTextField(label: '', hint: 'Search reference, subject, recipient…', controller: _search,
        onChanged: (v) => setState(() => _query = v));
    final actions = <Widget>[
      AppButton(label: 'My signature', icon: Symbols.signature, onPressed: _mySignature),
      if (page?.canManageStamp ?? false)
        AppButton(label: (page?.hasStamp ?? false) ? 'Replace stamp' : 'Company stamp', icon: Symbols.approval, onPressed: _stamp),
      AppButton(label: phone ? 'New' : 'New letter', icon: Symbols.add, variant: BtnVariant.primary, onPressed: _newLetter),
    ];
    return Padding(
      padding: EdgeInsets.all(phone ? 12 : 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TitleWithActions(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Letters', style: AppTheme.pageTitle),
            Text('On the Hypermed letterhead · reference numbers run in order', style: AppTheme.bodySub),
          ]),
          actions: actions,
        ),
        const SizedBox(height: 14),
        search,
        const SizedBox(height: 12),
        Expanded(child: _error != null
            ? ErrorView(message: friendlyError(_error!), onRetry: _load)
            : page == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _shown.isEmpty
                    ? Center(child: Text(page.letters.isEmpty ? 'No letters yet — press New letter.' : 'Nothing matches.',
                        style: AppTheme.bodySub))
                    : ListView.separated(
                        itemCount: _shown.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: context.pal.divider),
                        itemBuilder: (_, i) => _LetterRow(letter: _shown[i], phone: phone, onTap: () => _open(_shown[i])),
                      )),
      ]),
    );
  });
}

class _LetterRow extends StatelessWidget {
  const _LetterRow({required this.letter, required this.phone, required this.onTap});
  final Letter letter;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final status = PhonePill(letter.isSigned ? 'Signed' : 'Draft', letter.isSigned ? AppColors.teal : AppColors.amber);
    final ref = Text(letter.referenceNumber, style: AppTheme.monoXs.copyWith(fontSize: 12, color: AppColors.teal));
    final subject = Text(letter.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodyStrong.copyWith(fontSize: 13));
    final to = Text('To: ${letter.recipientFirstLine}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySub.copyWith(fontSize: 12));
    final meta = Text('${formatDate(letter.letterDate)} · ${letter.signatoryName ?? 'No signatory'}',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySub.copyWith(fontSize: 12, color: pal.textDim));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: phone
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: ref), status]),
                const SizedBox(height: 4), subject, to, meta,
              ])
            : Row(children: [
                SizedBox(width: 150, child: ref),
                Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [subject, to])),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: meta),
                const SizedBox(width: 12),
                status,
              ]),
      ),
    );
  }
}

// ── Letter panel: PDF, edit, sign ─────────────────────────────────────────────

class _LetterDialog extends StatefulWidget {
  const _LetterDialog({required this.letter});
  final Letter letter;
  @override
  State<_LetterDialog> createState() => _LetterDialogState();
}

class _LetterDialogState extends State<_LetterDialog> {
  late Letter _l = widget.letter;
  bool _changed = false, _busy = false;

  Future<void> _act(Future<Letter?> Function() fn, String msg) async {
    setState(() => _busy = true);
    try {
      final l = await fn();
      if (!mounted) return;
      setState(() { if (l != null) _l = l; _changed = true; _busy = false; });
      showSuccessToast(context, msg);
    } catch (e) {
      if (mounted) { setState(() => _busy = false); showErrorToast(context, e); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    final pal = context.pal;
    return Dialog(
      backgroundColor: pal.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(l.referenceNumber, style: AppTheme.monoXs.copyWith(fontSize: 13, color: AppColors.teal))),
              IconButton(onPressed: () => Navigator.pop(context, _changed), icon: Icon(Symbols.close, size: 18, color: pal.textDim)),
            ]),
            Text(l.subject, style: AppTheme.bodyStrong),
            const SizedBox(height: 4),
            Text('${formatDate(l.letterDate)} · ${l.isSigned ? 'Signed by ${l.signatoryName}' : 'Not signed yet'}'
                '${l.includeStamp ? ' · with stamp' : ''}', style: AppTheme.bodySub.copyWith(fontSize: 12)),
            const SizedBox(height: 12),
            Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.recipient, style: AppTheme.bodySm),
              const SizedBox(height: 10),
              Text(l.body, style: AppTheme.bodySm.copyWith(color: pal.textDim)),
            ]))),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
              AppButton(label: 'PDF', icon: Symbols.picture_as_pdf,
                  onPressed: () => downloadPdf(context, () => LetterService.instance.pdfBytes(l.id), '${l.referenceNumber.replaceAll('/', '-')}.pdf')),
              if (l.canEdit && !l.isSigned)
                AppButton(label: 'Delete', icon: Symbols.delete, variant: BtnVariant.danger, onPressed: _busy ? null : () async {
                  await _act(() async { await LetterService.instance.delete(l.id); return null; }, 'Letter deleted');
                  if (context.mounted) Navigator.pop(context, true);
                }),
              if (l.canEdit)
                AppButton(label: 'Edit', icon: Symbols.edit, onPressed: _busy ? null : () async {
                  final saved = await showLetterForm(context, editing: l);
                  if (saved != null && mounted) setState(() { _l = saved; _changed = true; });
                }),
              if (l.canSign && l.isSigned)
                AppButton(label: 'Remove signature', icon: Symbols.ink_eraser, onPressed: _busy ? null
                    : () => _act(() => LetterService.instance.unsign(l.id), 'Signature removed')),
              if (l.canSign && !l.isSigned)
                AppButton(label: 'Sign', icon: Symbols.signature, variant: BtnVariant.primary, onPressed: _busy ? null
                    : () => _act(() => LetterService.instance.sign(l.id), 'Letter signed')),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── New / edit letter ─────────────────────────────────────────────────────────

/// New letter, or [editing] one (editing a signed letter takes the signature off).
Future<Letter?> showLetterForm(BuildContext context, {Letter? editing}) =>
    showDialog<Letter>(context: context, builder: (_) => _LetterForm(editing: editing));

class _LetterForm extends StatefulWidget {
  const _LetterForm({this.editing});
  final Letter? editing;
  @override
  State<_LetterForm> createState() => _LetterFormState();
}

class _LetterFormState extends State<_LetterForm> {
  late final _recipient = TextEditingController(text: widget.editing?.recipient ?? '');
  late final _subject = TextEditingController(text: widget.editing?.subject ?? '');
  late final _body = TextEditingController(text: widget.editing?.body ?? 'Dear Sir/Madam,\n\n');
  late final _position = TextEditingController(text: widget.editing?.signatoryPosition ?? '');
  late DateTime _date = widget.editing?.letterDate ?? DateTime.now();
  late int? _signatoryId = widget.editing?.signatoryId;
  late bool _stamp = widget.editing?.includeStamp ?? false;
  List<LetterSignatory> _signatories = const [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    LetterService.instance.signatories().then((s) { if (mounted) setState(() => _signatories = s); }).catchError((_) {});
  }

  @override
  void dispose() {
    _recipient.dispose(); _subject.dispose(); _body.dispose(); _position.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = _recipient.text.trim().isEmpty ? 'Who is the letter to?'
        : _subject.text.trim().isEmpty ? 'Give the letter a subject.'
        : _body.text.trim().isEmpty ? 'Write the letter.'
        : null;
    if (problem != null) { setState(() => _error = problem); return; }
    setState(() { _saving = true; _error = null; });
    final data = {
      'letter_date': _date.toIso8601String().substring(0, 10),
      'recipient': _recipient.text.trim(), 'subject': _subject.text.trim(), 'body': _body.text.trim(),
      'signatory_id': _signatoryId, 'signatory_position': _position.text.trim().isEmpty ? null : _position.text.trim(),
      'include_stamp': _stamp,
    };
    try {
      final l = widget.editing == null
          ? await LetterService.instance.create(data)
          : await LetterService.instance.update(widget.editing!.id, data);
      if (mounted) Navigator.pop(context, l);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final signatory = _signatories.where((s) => s.id == _signatoryId).firstOrNull;
    return Dialog(
      backgroundColor: pal.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Symbols.mail, size: 18, color: AppColors.teal),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.editing == null ? 'New letter' : 'Edit ${widget.editing!.referenceNumber}', style: AppTheme.bodyStrong)),
              IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Symbols.close, size: 18, color: pal.textDim)),
            ]),
            Text(widget.editing == null
                ? 'Gets the next reference number when saved. The signatory adds their signature by pressing Sign.'
                : widget.editing!.isSigned ? 'Saving changes takes the signature off — the signatory signs again.' : 'Reference number stays the same.',
                style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
            const SizedBox(height: 14),
            Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              LayoutBuilder(builder: (context, c) => sideBySideOrStacked(isPhoneWidth(c.maxWidth), [
                Expanded(child: LabeledDateField(label: 'Date', date: _date, onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setState(() => _date = d);
                })),
                const SizedBox(width: 12, height: 12),
                Expanded(child: AppSearchableSelectField<int>(
                  label: 'Signatory',
                  hint: 'Who signs it…',
                  selectedLabel: signatory?.name,
                  items: [for (final s in _signatories)
                    AppSelectItem(value: s.id, label: s.name, subtitle: [s.position ?? '', s.hasSignature ? 'signature on file' : 'no signature yet']
                        .where((x) => x.isNotEmpty).join(' · '))],
                  onSelected: (sel) => setState(() {
                    _signatoryId = sel?.value;
                    final p = _signatories.where((s) => s.id == sel?.value).firstOrNull?.position;
                    if (p != null && _position.text.trim().isEmpty) _position.text = p;
                  }),
                )),
              ])),
              const SizedBox(height: 12),
              LabeledTextField(label: 'Signatory title', hint: 'e.g. Managing Director', controller: _position),
              const SizedBox(height: 12),
              LabeledTextField(label: 'To (recipient and address)', hint: 'The Executive Director\nMuhimbili National Hospital\nP.O. Box 65000\nDar es Salaam',
                  controller: _recipient, maxLines: 4),
              const SizedBox(height: 12),
              LabeledTextField(label: 'Subject', hint: 'Printed as RE: …', controller: _subject),
              const SizedBox(height: 12),
              LabeledTextField(label: 'Letter', hint: 'Dear Sir/Madam, … (leave a blank line between paragraphs)', controller: _body, maxLines: 12),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero, dense: true, controlAffinity: ListTileControlAffinity.leading,
                value: _stamp, onChanged: (v) => setState(() => _stamp = v ?? false),
                title: Text('Add the company stamp', style: AppTheme.bodySm),
              ),
            ]))),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5))),
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(onPressed: _saving ? null : _save, child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.editing == null ? 'Save letter' : 'Save changes')),
            ]),
          ]),
        ),
      ),
    );
  }
}
