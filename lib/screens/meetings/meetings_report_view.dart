// Meetings report for the selected period (GET /meetings/report): meetings
// held and written up, attendance, and how action items are getting done.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/meeting.dart';
import '../../services/meeting_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/procurement/proc_widgets.dart';

class MeetingsReportView extends StatefulWidget {
  const MeetingsReportView({super.key, required this.period, required this.onOpenMeeting});
  final Period period;
  final ValueChanged<int> onOpenMeeting;
  @override
  State<MeetingsReportView> createState() => _MeetingsReportViewState();
}

class _MeetingsReportViewState extends State<MeetingsReportView> {
  Map<String, dynamic>? _r;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MeetingsReportView old) {
    super.didUpdateWidget(old);
    if (old.period.from != widget.period.from || old.period.to != widget.period.to) _load();
  }

  Future<void> _load() async {
    try {
      final r = await MeetingService.instance.report(widget.period.query);
      if (mounted) setState(() { _r = r; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  int _i(Map? m, String k) => (m?[k] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final r = _r;
    if (r == null) {
      return _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    }
    final m = r['meetings'] as Map?;
    final att = r['attendance'] as Map?;
    final items = r['action_items'] as Map?;
    final rate = att?['rate'] as num?;
    final byCategory = Map<String, dynamic>.from(r['by_category'] as Map? ?? {});
    final byOwner = [for (final o in (r['by_owner'] as List? ?? [])) Map<String, dynamic>.from(o as Map)];
    final overdue = [for (final o in (r['overdue'] as List? ?? [])) Map<String, dynamic>.from(o as Map)];

    Widget line(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(children: [
        Expanded(child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text(value, style: procMono(context, size: 12, color: color ?? pal.text)),
      ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiStrip([
        KpiStripItem(Symbols.groups, ProcTone.teal, 'Meetings held', '${_i(m, 'held')}',
            '${_i(m, 'total')} in period · ${_i(m, 'cancelled')} cancelled'),
        KpiStripItem(Symbols.mark_email_read, ProcTone.green, 'Minutes circulated', '${_i(m, 'circulated')}',
            '${_i(m, 'awaiting_minutes')} awaiting minutes', alarm: _i(m, 'awaiting_minutes') > 0),
        KpiStripItem(Symbols.how_to_reg, ProcTone.violet, 'Attendance', rate == null ? '—' : '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%',
            '${_i(att, 'present')} present · ${_i(att, 'apologies')} apologies'),
        KpiStripItem(Symbols.task_alt, ProcTone.amber, 'Action items', '${_i(items, 'done')}/${_i(items, 'total')} done',
            '${_i(items, 'overdue')} overdue · ${_i(items, 'open')} open', alarm: _i(items, 'overdue') > 0),
      ]),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 760;
        final category = ProcPanel(
          title: 'By kind of meeting', icon: Symbols.category,
          child: byCategory.isEmpty
              ? Padding(padding: const EdgeInsets.all(16), child: Text('No meetings in this period.', style: AppTheme.bodySub))
              : Column(children: [
                  for (final e in byCategory.entries) line(meetingCategoryLabel(e.key), '${e.value}'),
                ]),
        );
        final owners = ProcPanel(
          title: 'Action items by owner', icon: Symbols.person_check,
          child: byOwner.isEmpty
              ? Padding(padding: const EdgeInsets.all(16), child: Text('No action items in this period.', style: AppTheme.bodySub))
              : Column(children: [
                  for (final o in byOwner)
                    line(o['owner'] as String? ?? '—', '${o['done']}/${o['total']} done${(o['overdue'] as num? ?? 0) > 0 ? ' · ${o['overdue']} overdue' : ''}',
                        color: (o['overdue'] as num? ?? 0) > 0 ? AppColors.coral : null),
                ]),
        );
        if (!wide) return Column(children: [category, const SizedBox(height: 12), owners]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: category), const SizedBox(width: 12), Expanded(child: owners),
        ]);
      }),
      const SizedBox(height: 12),
      ProcPanel(
        title: 'Overdue action items', icon: Symbols.alarm, iconColor: AppColors.coral,
        child: overdue.isEmpty
            ? Padding(padding: const EdgeInsets.all(16), child: Text('Nothing overdue.', style: AppTheme.bodySub))
            : Column(children: [
                for (final o in overdue) InkWell(
                  onTap: () => widget.onOpenMeeting(o['meeting_id'] as int),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o['description'] as String? ?? '', style: AppTheme.bodySm, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text([
                        o['owner'] as String? ?? '—',
                        if (o['due_date'] != null) 'due ${formatDate(DateTime.parse(o['due_date'] as String))}',
                        o['meeting_title'] as String? ?? '',
                      ].join(' · '), style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
              ]),
      ),
    ]);
  }
}
