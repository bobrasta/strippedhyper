// Meetings register. The Administrator (secretary to every meeting), the
// Director and the CTO see every meeting and run them; everyone else sees
// the meetings they attend, and the minutes once circulated.

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
import 'meeting_detail_screen.dart';
import 'meeting_form.dart';
import 'meetings_report_view.dart';

ProcTone meetingStatusTone(String status) => switch (status) {
  'scheduled' => ProcTone.teal,
  'held' || 'minutes_final' => ProcTone.amber,
  'circulated' => ProcTone.green,
  _ => ProcTone.neutral,
};

String meetingWhen(Meeting m) {
  final s = m.startsAt;
  if (s == null) return '—';
  final e = m.endsAt;
  return '${formatDate(s)} · ${formatTime(s)}${e == null ? '' : '–${formatTime(e)}'}';
}

class MeetingsScreen extends StatefulWidget {
  const MeetingsScreen({super.key, this.initialMeetingId});
  /// Opened from a meeting notification — jumps straight to that meeting.
  final int? initialMeetingId;
  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  int _tab = 0; // upcoming · past · report
  String _q = '';
  Period _period = Period.defaultPeriod;
  MeetingList? _data = MeetingService.cachedList;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialMeetingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openId(widget.initialMeetingId!));
    }
  }

  Future<void> _load() async {
    try {
      final d = await MeetingService.instance.list(query: _period.query);
      if (_period.preset == Period.defaultPeriod.preset) MeetingService.cachedList = d;
      if (mounted) setState(() { _data = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _openId(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MeetingDetailScreen(meetingId: id)));
    _load();
  }

  Future<void> _new() async {
    final data = _data;
    if (data == null) return;
    final m = await showMeetingForm(context, list: data);
    if (m != null) _openId(m.id);
  }

  List<Meeting> _rows(List<Meeting> all) {
    final q = _q.toLowerCase();
    final list = all.where((m) {
      final upcoming = m.isUpcoming;
      if (_tab == 0 && !upcoming) return false;
      if (_tab == 1 && upcoming) return false;
      return q.isEmpty || m.title.toLowerCase().contains(q) || (m.department ?? '').toLowerCase().contains(q)
          || (m.chair ?? '').toLowerCase().contains(q) || m.category.toLowerCase().contains(q);
    }).toList();
    // Upcoming soonest first; past most recent first.
    list.sort((a, b) {
      final da = a.startsAt ?? DateTime(0), db = b.startsAt ?? DateTime(0);
      return _tab == 0 ? da.compareTo(db) : db.compareTo(da);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final data = _data;
    if (data == null) {
      return _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    final all = data.meetings;
    final upcoming = all.where((m) => m.isUpcoming).toList();
    final awaiting = all.where((m) => m.awaitingMinutes).toList();
    final circulated = all.where((m) => m.status == 'circulated').toList();
    final thisWeek = upcoming.where((m) => m.startsAt!.isBefore(DateTime.now().add(const Duration(days: 7)))).toList();
    final tabs = ['Upcoming · ${upcoming.length}', 'Past · ${all.length - upcoming.length}', if (data.canManage) 'Report'];
    if (_tab >= tabs.length) _tab = 0;

    return Container(
      color: pal.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ProcPageHeader(
          title: 'Meetings',
          subtitle: data.canManage
              ? '${all.length} meeting${all.length == 1 ? '' : 's'} in ${_period.label.toLowerCase()} · ${awaiting.length} awaiting minutes'
              : 'Meetings you attend, and their minutes once circulated',
          actions: [
            if (data.canManage) ProcButton(label: 'New meeting', icon: Symbols.add, tone: ProcTone.green, onPressed: _new),
          ],
        ),
        Expanded(child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 14, 24, 24), children: [
            if (data.canManage) ...[
              KpiStrip([
                KpiStripItem(Symbols.event_upcoming, ProcTone.teal, 'Upcoming', '${upcoming.length}',
                    thisWeek.isEmpty ? 'none this week' : '${thisWeek.length} this week'),
                KpiStripItem(Symbols.edit_note, ProcTone.amber, 'Awaiting minutes', '${awaiting.length}',
                    awaiting.isEmpty ? 'all written up' : awaiting.map((m) => m.title).take(2).join(' · '),
                    alarm: awaiting.isNotEmpty),
                KpiStripItem(Symbols.mark_email_read, ProcTone.green, 'Minutes circulated', '${circulated.length}',
                    _period.label.toLowerCase()),
              ]),
              const SizedBox(height: 14),
            ],
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ProcSegmented(options: tabs, selected: _tab, onChanged: (i) => setState(() => _tab = i)),
              PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
              if (_tab != 2) ProcSearchField(hint: 'Title, department, chair…', onChanged: (v) => setState(() => _q = v)),
            ]),
            const SizedBox(height: 14),
            if (_tab == 2)
              MeetingsReportView(period: _period, onOpenMeeting: _openId)
            else
              _MeetingTable(rows: _rows(all), upcoming: _tab == 0, onTap: (m) => _openId(m.id)),
          ]),
        )),
      ]),
    );
  }
}

class _MeetingTable extends StatelessWidget {
  const _MeetingTable({required this.rows, required this.upcoming, required this.onTap});
  final List<Meeting> rows;
  final bool upcoming;
  final ValueChanged<Meeting> onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
        child: Text(upcoming ? 'No upcoming meetings.' : 'No past meetings in this period.',
            textAlign: TextAlign.center, style: AppTheme.bodySub.copyWith(color: pal.textDim)),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 860) return Column(children: [for (final m in rows) _card(context, m)]);
        Widget h(String s, {int flex = 0, double? w, TextAlign a = TextAlign.left}) {
          final x = Text(s.toUpperCase(), style: procCaps(context), textAlign: a);
          return w != null ? SizedBox(width: w, child: x) : Expanded(flex: flex, child: x);
        }
        const gap = SizedBox(width: 14);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border))),
            child: Row(children: [
              h('When', w: 170), gap, h('Meeting', flex: 24), gap, h('Venue', flex: 12), gap,
              h('Chair', w: 130), gap, h('People', w: 56, a: TextAlign.right), gap, h('Actions', w: 56, a: TextAlign.right), gap,
              h('Status', w: 140),
            ]),
          ),
          for (final m in rows) InkWell(
            onTap: () => onTap(m),
            hoverColor: pal.surface2.withValues(alpha: 0.5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
              child: Row(children: [
                SizedBox(width: 170, child: Text(meetingWhen(m), style: procMono(context, color: pal.text), overflow: TextOverflow.ellipsis)),
                gap,
                Expanded(flex: 24, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.title, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text([meetingCategoryLabel(m.category), if (m.department != null) m.department!].join(' · '),
                      style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                gap,
                Expanded(flex: 12, child: Text(m.venue.isEmpty ? '—' : m.venue,
                    style: AppTheme.bodySub.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                gap,
                SizedBox(width: 130, child: Text(m.chair ?? '—', style: AppTheme.bodySub.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                gap,
                SizedBox(width: 56, child: Text('${m.attendeesCount}', textAlign: TextAlign.right, style: procMono(context, color: pal.textMute))),
                gap,
                SizedBox(width: 56, child: Text('${m.actionItemsCount}', textAlign: TextAlign.right, style: procMono(context, color: pal.textMute))),
                gap,
                SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft,
                    child: ProcTag(m.statusLabel, tone: meetingStatusTone(m.status), small: true))),
              ]),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _card(BuildContext context, Meeting m) {
    final pal = context.pal;
    return InkWell(
      onTap: () => onTap(m),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(meetingWhen(m), style: procMono(context, color: pal.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            ProcTag(m.statusLabel, tone: meetingStatusTone(m.status), small: true),
          ]),
          const SizedBox(height: 6),
          Text(m.title, style: AppTheme.bodySm, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text([meetingCategoryLabel(m.category), if (m.venue.isNotEmpty) m.venue, if (m.chair != null) 'Chair: ${m.chair}'].join(' · '),
              style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim), maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
