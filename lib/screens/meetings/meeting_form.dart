import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/meeting.dart';
import '../../services/meeting_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/procurement/proc_widgets.dart';
import '../procurement/tender_forms.dart' show ProcDialog, formRow, formHeading;

// Schedule a meeting, or edit its details and who's invited. Attendance,
// minutes and action items are recorded on the meeting page itself.

Future<Meeting?> showMeetingForm(BuildContext context, {required MeetingList list, Meeting? meeting}) =>
    showDialog<Meeting>(context: context, builder: (_) => _MeetingForm(list: list, meeting: meeting));

/// 06:00 to 21:45 in quarter hours.
final _times = [
  for (var h = 6; h < 22; h++)
    for (final m in const [0, 15, 30, 45]) '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
];

String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${(d.minute - d.minute % 15).toString().padLeft(2, '0')}';

class _MeetingForm extends StatefulWidget {
  const _MeetingForm({required this.list, this.meeting});
  final MeetingList list;
  final Meeting? meeting;
  @override
  State<_MeetingForm> createState() => _MeetingFormState();
}

class _MeetingFormState extends State<_MeetingForm> {
  late final Meeting? m = widget.meeting;
  late final _title = TextEditingController(text: m?.title ?? '');
  late final _location = TextEditingController(text: m?.location ?? '');
  late final _link = TextEditingController(text: m?.onlineLink ?? '');
  late final _agenda = TextEditingController(text: m?.agenda ?? '');
  final _guestName = TextEditingController();
  final _guestOrg = TextEditingController();
  late String _category = m?.category ?? 'management';
  late int? _departmentId = m?.departmentId;
  late int? _chairId = m?.chairedBy;
  late DateTime _date = m?.startsAt ?? DateTime.now().add(const Duration(days: 1));
  late String _start = m?.startsAt == null ? '09:00' : _hhmm(m!.startsAt!);
  late String? _end = m?.endsAt == null ? (m == null ? '10:00' : null) : _hhmm(m!.endsAt!);
  late final List<MeetingAttendee> _attendees = [...?m?.attendees];
  List<StaffMember> _staff = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    StaffService.instance.list().then((s) {
      if (mounted) setState(() => _staff = [...s]..sort((a, b) => a.name.compareTo(b.name)));
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_title, _location, _link, _agenda, _guestName, _guestOrg]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _categories {
    final c = widget.list.categories.isEmpty ? const ['management', 'department', 'staff', 'board', 'client', 'supplier', 'general'] : widget.list.categories;
    return c.contains(_category) ? c : [...c, _category];
  }

  DateTime _at(String hhmm) {
    final p = hhmm.split(':');
    return DateTime(_date.year, _date.month, _date.day, int.parse(p[0]), int.parse(p[1]));
  }

  void _addStaff(StaffMember s) {
    if (_attendees.any((a) => a.userId == s.id)) return;
    setState(() => _attendees.add(MeetingAttendee(userId: s.id, name: s.name)));
  }

  void _addGuest() {
    final name = _guestName.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _attendees.add(MeetingAttendee(name: name, guestOrganisation: _guestOrg.text.trim().isEmpty ? null : _guestOrg.text.trim()));
      _guestName.clear();
      _guestOrg.clear();
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showErrorToast(context, 'Give the meeting a title.');
      return;
    }
    setState(() => _saving = true);
    final data = {
      'title': _title.text.trim(),
      'category': _category,
      'department_id': _departmentId,
      'starts_at': _at(_start).toUtc().toIso8601String(),
      'ends_at': _end == null ? null : _at(_end!).toUtc().toIso8601String(),
      'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
      'online_link': _link.text.trim().isEmpty ? null : _link.text.trim(),
      'chaired_by': _chairId,
      'agenda': _agenda.text.trim().isEmpty ? null : _agenda.text.trim(),
      'attendees': [for (final a in _attendees) a.toJson()],
    };
    try {
      final saved = m == null
          ? await MeetingService.instance.create(data)
          : await MeetingService.instance.update(m!.id, data);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorToast(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final staffNotAdded = _staff.where((s) => !_attendees.any((a) => a.userId == s.id)).toList();
    return ProcDialog(
      title: m == null ? 'New meeting' : 'Edit meeting',
      icon: Symbols.groups,
      width: 640,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LabeledTextField(label: 'Title', controller: _title, hint: 'e.g. Monthly management meeting', autofocus: m == null),
        const SizedBox(height: 12),
        formRow([
          LabeledDropdown<String>(label: 'Kind of meeting', value: _category, items: _categories,
              displayBuilder: meetingCategoryLabel, onChanged: (v) => setState(() => _category = v)),
          LabeledDropdown<int?>(label: 'Department', value: _departmentId,
              items: [null, ...widget.list.departments.map((d) => d.$1)],
              displayBuilder: (id) => id == null ? 'Company-wide' : widget.list.departments.firstWhere((d) => d.$1 == id).$2,
              onChanged: (v) => setState(() => _departmentId = v)),
        ]),
        formRow([
          LabeledDateField(label: 'Date', date: _date, onTap: () async {
            final now = DateTime.now();
            final d = await showDatePicker(context: context, initialDate: _date,
                firstDate: DateTime(now.year - 3), lastDate: DateTime(now.year + 3));
            if (d != null) setState(() => _date = d);
          }),
          LabeledDropdown<String>(label: 'Starts', value: _times.contains(_start) ? _start : '09:00', items: _times,
              displayBuilder: (t) => t, onChanged: (v) => setState(() => _start = v)),
          LabeledDropdown<String?>(label: 'Ends', value: _end != null && _times.contains(_end) ? _end : null,
              items: [null, ..._times], displayBuilder: (t) => t ?? '—', onChanged: (v) => setState(() => _end = v)),
        ]),
        formRow([
          LabeledTextField(label: 'Venue', controller: _location, hint: 'e.g. Board room'),
          LabeledTextField(label: 'Online link', controller: _link, hint: 'Meet / Zoom link, if any'),
        ]),
        LabeledDropdown<int?>(label: 'Chair', value: _staff.any((s) => s.id == _chairId) ? _chairId : null,
            items: [null, ..._staff.map((s) => s.id)],
            displayBuilder: (id) => id == null ? 'Not set' : _staff.firstWhere((s) => s.id == id).name,
            onChanged: (v) => setState(() => _chairId = v)),
        const SizedBox(height: 12),
        LabeledTextField(label: 'Agenda', controller: _agenda, maxLines: 5, hint: 'One item per line'),
        formHeading('Attendees · ${_attendees.length}'),
        if (_attendees.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final a in _attendees)
              InputChip(
                label: Text(a.isGuest && (a.guestOrganisation ?? '').isNotEmpty ? '${a.name} (${a.guestOrganisation})' : a.name,
                    style: AppTheme.bodySub.copyWith(fontSize: 12, color: pal.text)),
                avatar: Icon(a.isGuest ? Symbols.person_outline : Symbols.badge, size: 14, color: a.isGuest ? AppColors.violet : AppColors.teal),
                onDeleted: () => setState(() => _attendees.remove(a)),
                deleteIconColor: pal.textDim,
                backgroundColor: pal.surface2,
                side: BorderSide(color: pal.border),
              ),
          ]),
        const SizedBox(height: 10),
        LabeledDropdown<int?>(label: 'Add staff', value: null,
            items: [null, ...staffNotAdded.map((s) => s.id)],
            displayBuilder: (id) => id == null ? (_staff.isEmpty ? 'Loading staff…' : 'Choose a staff member') : _staff.firstWhere((s) => s.id == id).name,
            onChanged: (id) { if (id != null) _addStaff(_staff.firstWhere((s) => s.id == id)); }),
        const SizedBox(height: 12),
        formRow([
          LabeledTextField(label: 'Guest name', controller: _guestName, hint: 'Someone from outside Hypermed'),
          LabeledTextField(label: 'Guest organisation', controller: _guestOrg, onSubmitted: (_) => _addGuest()),
        ]),
        Align(alignment: Alignment.centerLeft,
            child: ProcButton(label: 'Add guest', icon: Symbols.person_add, onPressed: _addGuest)),
      ]),
      actions: [
        ProcButton(label: 'Cancel', onPressed: _saving ? null : () => Navigator.of(context).pop()),
        ProcButton(label: _saving ? 'Saving…' : (m == null ? 'Schedule meeting' : 'Save'), icon: Symbols.check,
            tone: ProcTone.green, onPressed: _saving ? null : _save),
      ],
    );
  }
}
