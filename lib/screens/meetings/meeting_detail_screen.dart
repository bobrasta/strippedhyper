// One meeting: details, attendance, agenda, minutes and decisions, action
// items (each a task on the owner's board — its status comes from the task)
// and attachments. The secretary circulates the minutes from here.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/meeting.dart';
import '../../services/meeting_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/pdf_preview_dialog.dart';
import '../../widgets/procurement/proc_widgets.dart';
import '../procurement/tender_forms.dart' show ProcDialog, OptionalDateField;
import 'meeting_form.dart';
import 'meetings_screen.dart' show meetingStatusTone, meetingWhen;

class MeetingDetailScreen extends StatefulWidget {
  const MeetingDetailScreen({super.key, required this.meetingId});
  final int meetingId;
  @override
  State<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  Meeting? _m;
  String? _error;
  final _agenda = TextEditingController();
  final _minutes = TextEditingController();
  final _decisions = TextEditingController();
  bool _notesDirty = false;
  bool _busy = false;
  List<StaffMember> _staff = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _agenda.dispose();
    _minutes.dispose();
    _decisions.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await MeetingService.instance.get(widget.meetingId);
      if (!mounted) return;
      setState(() { _set(m); _error = null; });
      if (m.canManage && _staff.isEmpty) {
        StaffService.instance.list().then((s) {
          if (mounted) setState(() => _staff = [...s]..sort((a, b) => a.name.compareTo(b.name)));
        }).catchError((_) {});
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _set(Meeting m) {
    _m = m;
    _agenda.text = m.agenda ?? '';
    _minutes.text = m.minutes ?? '';
    _decisions.text = m.decisions ?? '';
    _notesDirty = false;
  }

  Future<void> _run(Future<Meeting?> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final m = await action();
      if (!mounted) return;
      if (m != null) {
        setState(() => _set(m));
      } else {
        await _load();
      }
      if (done != null && mounted) showSuccessToast(context, done);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> get _notes => {
    'agenda': _agenda.text.trim().isEmpty ? null : _agenda.text.trim(),
    'minutes': _minutes.text.trim().isEmpty ? null : _minutes.text.trim(),
    'decisions': _decisions.text.trim().isEmpty ? null : _decisions.text.trim(),
  };

  Future<void> _saveNotes() => _run(() => MeetingService.instance.update(_m!.id, _notes), done: 'Minutes saved.');

  Future<void> _setStatus(String status, String done) =>
      _run(() => MeetingService.instance.update(_m!.id, {..._notes, 'status': status}), done: done);

  Future<void> _circulate() async {
    final ok = await _confirm('Circulate the minutes?',
        'Every staff attendee is notified (and emailed) and can read the minutes from now on.', 'Circulate');
    if (!ok) return;
    await _run(() async {
      if (_notesDirty) await MeetingService.instance.update(_m!.id, _notes);
      return MeetingService.instance.circulate(_m!.id);
    }, done: 'Minutes circulated.');
  }

  Future<void> _delete() async {
    final ok = await _confirm('Delete this meeting?',
        'Its minutes, attendance and attachments are removed, and unfinished action-item tasks are deleted.', 'Delete');
    if (!ok) return;
    try {
      await MeetingService.instance.delete(_m!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _edit() async {
    final m = _m!;
    final list = MeetingService.cachedList ?? await MeetingService.instance.list();
    if (!mounted) return;
    final saved = await showMeetingForm(context, list: list, meeting: m);
    if (saved != null && mounted) setState(() => _set(saved));
  }

  Future<void> _setAttendance(MeetingAttendee a, String attendance) {
    final m = _m!;
    final rows = [
      for (final x in m.attendees) (x.id == a.id ? (MeetingAttendee(userId: x.userId, name: x.name,
          guestOrganisation: x.guestOrganisation, guestEmail: x.guestEmail, attendance: attendance)) : x).toJson(),
    ];
    return _run(() => MeetingService.instance.update(m.id, {'attendees': rows}));
  }

  Future<void> _pdf() => showPdfPreview(context, () => MeetingService.instance.pdf(_m!.id),
      'Minutes - ${_m!.title} - ${_m!.startsAt == null ? '' : formatDate(_m!.startsAt!)}.pdf');

  Future<void> _addActionItem() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ActionItemDialog(meeting: _m!, staff: _staff));
    if (ok == true) _load();
  }

  Future<void> _toggleDone(MeetingActionItem i) =>
      _run(() async { await MeetingService.instance.updateActionItem(_m!.id, i.id, {'done': !i.isDone}); return null; });

  Future<void> _deleteItem(MeetingActionItem i) async {
    final ok = await _confirm('Remove this action item?', 'Its task is removed from ${i.owner ?? 'the owner'}\'s board too, unless already done.', 'Remove');
    if (ok) await _run(() async { await MeetingService.instance.deleteActionItem(_m!.id, i.id); return null; });
  }

  Future<void> _upload() async {
    final r = await FilePicker.pickFiles(allowMultiple: false, withData: false);
    final f = r?.files.single;
    if (f?.path == null) return;
    await _run(() async { await MeetingService.instance.uploadAttachment(_m!.id, f!.path!, f.name); return null; }, done: 'Attached.');
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(context: context, builder: (dCtx) => ProcDialog(
      title: title, icon: Symbols.help, width: 440,
      body: Text(body, style: AppTheme.bodySub),
      actions: [
        ProcButton(label: 'Cancel', onPressed: () => Navigator.of(dCtx).pop(false)),
        ProcButton(label: action, tone: action == 'Delete' || action == 'Remove' ? ProcTone.coral : ProcTone.green,
            onPressed: () => Navigator.of(dCtx).pop(true)),
      ],
    ));
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final m = _m;
    if (m == null) {
      return Scaffold(backgroundColor: pal.bg, appBar: AppBar(backgroundColor: pal.bg),
          body: _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final manage = m.canManage;
    final hasMinutes = (m.minutes ?? '').isNotEmpty || (m.decisions ?? '').isNotEmpty || _minutes.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(left: 8, top: 6), child: Align(alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Symbols.arrow_back, size: 16), label: const Text('Meetings')))),
        ProcPageHeader(
          title: m.title,
          breadcrumb: ['Meetings', meetingCategoryLabel(m.category)],
          accent: meetingStatusTone(m.status) == ProcTone.green ? AppColors.green : AppColors.cyan,
          tags: [
            ProcTag(m.statusLabel, tone: meetingStatusTone(m.status)),
            Text([meetingWhen(m), if (m.venue.isNotEmpty) m.venue].join(' · '),
                style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
          ],
          actions: [
            if (manage || m.status == 'circulated') ProcButton(label: 'Minutes PDF', icon: Symbols.picture_as_pdf, onPressed: _pdf),
            if (manage) ...[
              ProcButton(label: 'Edit details', icon: Symbols.edit, onPressed: _busy ? null : _edit),
              if (m.status == 'scheduled')
                ProcButton(label: 'Mark held', icon: Symbols.event_available, tone: ProcTone.teal,
                    onPressed: _busy ? null : () => _setStatus('held', 'Marked as held.')),
              if (m.status != 'cancelled' && m.status != 'circulated')
                ProcButton(label: 'Circulate minutes', icon: Symbols.send, tone: ProcTone.green,
                    onPressed: _busy || !hasMinutes ? null : _circulate),
              if (m.status == 'scheduled')
                ProcButton(label: 'Cancel meeting', icon: Symbols.event_busy,
                    onPressed: _busy ? null : () => _setStatus('cancelled', 'Meeting cancelled.')),
              ProcButton(label: 'Delete', icon: Symbols.delete, tone: ProcTone.coral, onPressed: _busy ? null : _delete),
            ],
          ],
        ),
        Expanded(child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 14, 24, 24), children: [
            LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth >= 980;
              final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _notesPanel(m),
                const SizedBox(height: 12),
                _actionItemsPanel(m),
              ]);
              final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _detailsPanel(m),
                const SizedBox(height: 12),
                _attendeesPanel(m),
                const SizedBox(height: 12),
                _attachmentsPanel(m),
              ]);
              if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 12), right]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: left), const SizedBox(width: 12), Expanded(flex: 2, child: right),
              ]);
            }),
          ]),
        )),
      ])),
    );
  }

  Widget _notesPanel(Meeting m) {
    final pal = context.pal;
    if (!m.canManage) {
      Widget block(String label, String? text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: procCaps(context)),
          const SizedBox(height: 6),
          SelectableText((text ?? '').isEmpty ? '—' : text!, style: AppTheme.bodySm.copyWith(height: 1.5)),
        ]),
      );
      return ProcPanel(
        title: 'Agenda & minutes', icon: Symbols.description,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          block('Agenda', m.agenda),
          if (m.minutesVisible) ...[block('Minutes', m.minutes), block('Decisions', m.decisions)]
          else Padding(padding: const EdgeInsets.all(16),
              child: Text('The minutes will appear here once the secretary circulates them.',
                  style: AppTheme.bodySub.copyWith(color: pal.textDim))),
          const SizedBox(height: 10),
        ]),
      );
    }
    void dirty(_) { if (!_notesDirty) setState(() => _notesDirty = true); }
    return ProcPanel(
      title: 'Agenda & minutes', icon: Symbols.description,
      trailing: ProcButton(label: _notesDirty ? 'Save' : 'Saved', icon: Symbols.save, tone: _notesDirty ? ProcTone.green : ProcTone.neutral,
          onPressed: _notesDirty && !_busy ? _saveNotes : null),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LabeledTextField(label: 'Agenda', controller: _agenda, maxLines: 5, onChanged: dirty),
          const SizedBox(height: 12),
          LabeledTextField(label: 'Minutes', controller: _minutes, maxLines: 12, onChanged: dirty,
              hint: 'What was discussed, item by item'),
          const SizedBox(height: 12),
          LabeledTextField(label: 'Decisions', controller: _decisions, maxLines: 5, onChanged: dirty,
              hint: 'What was agreed'),
          if (m.status == 'circulated') Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Circulated ${m.circulatedAt == null ? '' : formatDate(m.circulatedAt!)} — later edits are visible to attendees straight away.',
                style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
          ),
        ]),
      ),
    );
  }

  Widget _detailsPanel(Meeting m) {
    Widget t(String? s) => Text((s ?? '').isEmpty ? '—' : s!, style: AppTheme.bodySm, maxLines: 2, overflow: TextOverflow.ellipsis);
    return ProcPanel(
      title: 'Details', icon: Symbols.info,
      child: KvGrid([
        ('When', t(meetingWhen(m))),
        ('Kind', t(meetingCategoryLabel(m.category))),
        ('Department', t(m.department ?? 'Company-wide')),
        ('Venue', t(m.location)),
        if ((m.onlineLink ?? '').isNotEmpty) ('Link', InkWell(
          onTap: () => launchUrl(Uri.parse(m.onlineLink!), mode: LaunchMode.externalApplication),
          child: Text(m.onlineLink!, style: AppTheme.bodySm.copyWith(color: AppColors.cyan), maxLines: 1, overflow: TextOverflow.ellipsis),
        )),
        ('Chair', t(m.chair)),
        ('Secretary', t(m.secretary)),
      ]),
    );
  }

  Widget _attendeesPanel(Meeting m) {
    final pal = context.pal;
    final a = m.attendees;
    final present = a.where((x) => x.attendance == 'present').length;
    return ProcPanel(
      title: 'Attendees · ${a.length}', icon: Symbols.group,
      trailing: a.isEmpty ? null : Text('$present present', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
      child: a.isEmpty
          ? Padding(padding: const EdgeInsets.all(16), child: Text('No one invited yet.', style: AppTheme.bodySub))
          : Column(children: [
              for (final x in a) Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(children: [
                  Icon(x.isGuest ? Symbols.person_outline : Symbols.badge, size: 15, color: x.isGuest ? AppColors.violet : AppColors.teal),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.name, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (x.isGuest) Text(x.guestOrganisation ?? 'Guest',
                        style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  const SizedBox(width: 8),
                  if (m.canManage && m.status != 'scheduled')
                    SizedBox(width: 130, child: DropdownFieldBox<String>(
                      value: x.attendance,
                      items: [
                        for (final e in attendanceLabels.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: _busy ? null : (v) { if (v != null) _setAttendance(x, v); },
                    ))
                  else
                    ProcTag(attendanceLabels[x.attendance] ?? x.attendance, small: true,
                        tone: x.attendance == 'present' ? ProcTone.green : x.attendance == 'invited' ? ProcTone.neutral : ProcTone.amber),
                ]),
              ),
              const SizedBox(height: 8),
            ]),
    );
  }

  Widget _actionItemsPanel(Meeting m) {
    final pal = context.pal;
    final items = m.actionItems;
    return ProcPanel(
      title: 'Action items · ${items.where((i) => i.isDone).length}/${items.length} done', icon: Symbols.task_alt,
      trailing: m.canManage ? ProcButton(label: 'Add', icon: Symbols.add, onPressed: _busy || _staff.isEmpty ? null : _addActionItem) : null,
      child: items.isEmpty
          ? Padding(padding: const EdgeInsets.all(16), child: Text(
              m.canManage ? 'Each action item goes onto its owner\'s task board.' : 'No action items.',
              style: AppTheme.bodySub))
          : Column(children: [
              for (final i in items) Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(children: [
                  Checkbox(value: i.isDone, onChanged: m.canManage && !_busy ? (_) => _toggleDone(i) : null),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i.description, style: AppTheme.bodySm.copyWith(
                        decoration: i.isDone ? TextDecoration.lineThrough : null,
                        color: i.isDone ? pal.textDim : null), maxLines: 3, overflow: TextOverflow.ellipsis),
                    Text([i.owner ?? '—', if (i.dueDate != null) 'due ${formatDate(i.dueDate!)}'].join(' · '),
                        style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  const SizedBox(width: 8),
                  ProcTag(actionItemStatusLabels[i.status] ?? i.status, small: true, tone: switch (i.status) {
                    'done' => ProcTone.green, 'overdue' => ProcTone.coral, 'in_progress' => ProcTone.teal, _ => ProcTone.neutral,
                  }),
                  if (m.canManage) IconButton(tooltip: 'Remove', onPressed: _busy ? null : () => _deleteItem(i),
                      icon: Icon(Symbols.close, size: 16, color: pal.textDim)),
                ]),
              ),
              const SizedBox(height: 6),
            ]),
    );
  }

  Widget _attachmentsPanel(Meeting m) {
    final pal = context.pal;
    final files = m.attachments;
    if (!m.canManage && files.isEmpty) return const SizedBox.shrink();
    return ProcPanel(
      title: 'Attachments · ${files.length}', icon: Symbols.attach_file,
      trailing: m.canManage ? ProcButton(label: 'Attach', icon: Symbols.upload, onPressed: _busy ? null : _upload) : null,
      child: files.isEmpty
          ? Padding(padding: const EdgeInsets.all(16), child: Text('Presentations, reports or signed minutes.', style: AppTheme.bodySub))
          : Column(children: [
              for (final f in files) InkWell(
                onTap: () => launchUrl(Uri.parse(f.url), mode: LaunchMode.externalApplication),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(children: [
                    Icon(Symbols.description, size: 15, color: pal.textMute),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f.name, style: AppTheme.bodySm.copyWith(color: AppColors.cyan), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (m.canManage) IconButton(tooltip: 'Remove', onPressed: _busy ? null : () => _run(() async {
                      await MeetingService.instance.deleteAttachment(m.id, f.id);
                      return null;
                    }), icon: Icon(Symbols.close, size: 16, color: pal.textDim)),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
            ]),
    );
  }
}

class _ActionItemDialog extends StatefulWidget {
  const _ActionItemDialog({required this.meeting, required this.staff});
  final Meeting meeting;
  final List<StaffMember> staff;
  @override
  State<_ActionItemDialog> createState() => _ActionItemDialogState();
}

class _ActionItemDialogState extends State<_ActionItemDialog> {
  final _desc = TextEditingController();
  int? _owner;
  DateTime? _due;
  bool _saving = false;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_desc.text.trim().isEmpty || _owner == null) {
      showErrorToast(context, 'Say what needs doing and who owns it.');
      return;
    }
    setState(() => _saving = true);
    try {
      await MeetingService.instance.addActionItem(widget.meeting.id, description: _desc.text.trim(), ownerId: _owner!, due: _due);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorToast(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Attendees first — they're the usual owners.
    final attendeeIds = widget.meeting.attendees.map((a) => a.userId).whereType<int>().toSet();
    final staff = [...widget.staff]..sort((a, b) {
      final x = attendeeIds.contains(a.id) ? 0 : 1, y = attendeeIds.contains(b.id) ? 0 : 1;
      return x != y ? x.compareTo(y) : a.name.compareTo(b.name);
    });
    return ProcDialog(
      title: 'New action item', icon: Symbols.task_alt, width: 520,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LabeledTextField(label: 'What needs doing', controller: _desc, maxLines: 3, autofocus: true),
        const SizedBox(height: 12),
        LabeledDropdown<int?>(label: 'Owner', value: _owner, items: [null, ...staff.map((s) => s.id)],
            displayBuilder: (id) => id == null ? 'Choose who owns it' : staff.firstWhere((s) => s.id == id).name,
            onChanged: (v) => setState(() => _owner = v)),
        const SizedBox(height: 12),
        OptionalDateField(label: 'Due', value: _due, onChanged: (d) => setState(() => _due = d),
            hint: 'It goes onto the owner\'s task board with this due date.'),
      ]),
      actions: [
        ProcButton(label: 'Cancel', onPressed: _saving ? null : () => Navigator.of(context).pop(false)),
        ProcButton(label: _saving ? 'Adding…' : 'Add action item', icon: Symbols.check, tone: ProcTone.green, onPressed: _saving ? null : _save),
      ],
    );
  }
}
