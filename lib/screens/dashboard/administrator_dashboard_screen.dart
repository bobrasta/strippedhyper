// The Administrator's home (head of the Administrative Wing): what's waiting
// on HR, this month's sales, and the meetings she keeps — upcoming, awaiting
// minutes, and action items running late. Each source loads on its own, so
// one failing request leaves the rest of the page working.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userNameNotifier;
import '../../models/leave_request.dart';
import '../../models/meeting.dart';
import '../../services/hr_report_service.dart';
import '../../services/invoice_service.dart';
import '../../services/leave_service.dart';
import '../../services/meeting_service.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/procurement/proc_widgets.dart';
import '../meetings/meeting_detail_screen.dart';
import '../meetings/meetings_screen.dart' show meetingWhen;

class AdministratorDashboardScreen extends StatefulWidget {
  const AdministratorDashboardScreen({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;
  @override
  State<AdministratorDashboardScreen> createState() => _AdministratorDashboardScreenState();
}

class _AdministratorDashboardScreenState extends State<AdministratorDashboardScreen> {
  List<Meeting>? _meetings = MeetingService.cachedList?.meetings;
  List<Map<String, dynamic>> _overdueItems = [];
  int _openItems = 0;
  List<LeaveRequest>? _pendingLeave;
  int? _openVacancies;
  (int, int)? _salesMonth; // count, total TSh

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final year = Period.defaultPeriod;
    final month = Period.of(PeriodPreset.thisMonth);
    await Future.wait([
      MeetingService.instance.list(query: year.query).then((l) {
        MeetingService.cachedList = l;
        if (mounted) setState(() => _meetings = l.meetings);
      }).catchError((_) {}),
      MeetingService.instance.report(year.query).then((r) {
        final items = r['action_items'] as Map? ?? {};
        if (mounted) {
          setState(() {
            _overdueItems = [for (final o in (r['overdue'] as List? ?? [])) Map<String, dynamic>.from(o as Map)];
            _openItems = (items['open'] as num?)?.toInt() ?? 0;
          });
        }
      }).catchError((_) {}),
      LeaveService.instance.list(status: 'pending').then((l) {
        if (mounted) setState(() => _pendingLeave = l);
      }).catchError((_) {}),
      HrReportService.instance.recruitmentSummary().then((r) {
        if (mounted) setState(() => _openVacancies = r.openVacancies);
      }).catchError((_) {}),
      InvoiceService.instance.list(period: month).then((l) {
        if (mounted) setState(() => _salesMonth = (l.length, l.fold<int>(0, (s, i) => s + i.total)));
      }).catchError((_) {}),
    ]);
  }

  void _go(String key) => widget.onNavigateTo?.call(key);

  Future<void> _openMeeting(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MeetingDetailScreen(meetingId: id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final now = DateTime.now();
    final meetings = _meetings ?? const <Meeting>[];
    final upcoming = meetings.where((m) => m.isUpcoming).toList()
      ..sort((a, b) => (a.startsAt ?? now).compareTo(b.startsAt ?? now));
    final week = upcoming.where((m) => m.startsAt!.isBefore(now.add(const Duration(days: 7)))).toList();
    final awaiting = meetings.where((m) => m.awaitingMinutes).toList();
    final leave = _pendingLeave;
    final sales = _salesMonth;
    final first = userNameNotifier.value.trim().split(' ').first;

    Widget empty(String s) => Padding(padding: const EdgeInsets.all(16),
        child: Text(s, style: AppTheme.bodySub.copyWith(color: pal.textDim)));
    Widget row({required String title, required String sub, Widget? trailing, VoidCallback? onTap}) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(sub, style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ]),
      ),
    );

    final meetingsPanel = ProcPanel(
      title: 'Coming up', icon: Symbols.event_upcoming,
      trailing: ProcButton(label: 'Meetings', icon: Symbols.arrow_forward, onPressed: () => _go('meetings')),
      child: _meetings == null
          ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : upcoming.isEmpty
              ? empty('No meetings scheduled.')
              : Column(children: [
                  for (final m in upcoming.take(6))
                    row(title: m.title, sub: [meetingWhen(m), if (m.venue.isNotEmpty) m.venue].join(' · '),
                        onTap: () => _openMeeting(m.id)),
                  const SizedBox(height: 6),
                ]),
    );
    final minutesPanel = ProcPanel(
      title: 'Minutes to write up', icon: Symbols.edit_note,
      child: awaiting.isEmpty
          ? empty('Every meeting held has its minutes circulated.')
          : Column(children: [
              for (final m in awaiting.take(6))
                row(title: m.title, sub: meetingWhen(m),
                    trailing: ProcTag(m.statusLabel, tone: ProcTone.amber, small: true), onTap: () => _openMeeting(m.id)),
              const SizedBox(height: 6),
            ]),
    );
    final actionsPanel = ProcPanel(
      title: 'Action items running late', icon: Symbols.alarm,
      child: _overdueItems.isEmpty
          ? empty('Nothing overdue.')
          : Column(children: [
              for (final o in _overdueItems.take(6))
                row(title: o['description'] as String? ?? '',
                    sub: [o['owner'] as String? ?? '—',
                      if (o['due_date'] != null) 'due ${formatDate(DateTime.parse(o['due_date'] as String))}',
                      o['meeting_title'] as String? ?? ''].join(' · '),
                    onTap: () => _openMeeting(o['meeting_id'] as int)),
              const SizedBox(height: 6),
            ]),
    );
    final leavePanel = ProcPanel(
      title: 'Leave waiting for approval', icon: Symbols.event_busy,
      trailing: ProcButton(label: 'HR approvals', icon: Symbols.arrow_forward, onPressed: () => _go('hr_approvals')),
      child: leave == null
          ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : leave.isEmpty
              ? empty('No leave requests waiting.')
              : Column(children: [
                  for (final l in leave.take(6))
                    row(title: l.userName ?? 'Staff member',
                        sub: '${l.leaveTypeLabel ?? l.type.label} · ${l.daysCount} day${l.daysCount == 1 ? '' : 's'} from ${l.startDate}',
                        onTap: () => _go('hr_approvals')),
                  const SizedBox(height: 6),
                ]),
    );

    return Container(
      color: pal.bg,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 24), children: [
          Text(first.isEmpty ? 'Administration' : 'Hello, $first', style: AppTheme.pageTitle),
          const SizedBox(height: 4),
          Text('Administrative Wing · ${formatDate(now)}', style: AppTheme.bodySub),
          const SizedBox(height: 16),
          KpiStrip([
            KpiStripItem(Symbols.how_to_reg, ProcTone.amber, 'Leave to approve', leave == null ? '—' : '${leave.length}',
                'HR approvals', alarm: (leave?.length ?? 0) > 0),
            KpiStripItem(Symbols.groups_3, ProcTone.teal, 'Meetings this week', '${week.length}',
                '${awaiting.length} awaiting minutes', alarm: awaiting.isNotEmpty),
            KpiStripItem(Symbols.task_alt, ProcTone.coral, 'Action items late', '${_overdueItems.length}',
                '$_openItems still open', alarm: _overdueItems.isNotEmpty),
            KpiStripItem(Symbols.receipt_long, ProcTone.green, 'Sales this month', sales == null ? '—' : tshShort(sales.$2),
                sales == null ? '' : '${sales.$1} invoice${sales.$1 == 1 ? '' : 's'}'),
            KpiStripItem(Symbols.person_search, ProcTone.violet, 'Open vacancies', _openVacancies == null ? '—' : '$_openVacancies',
                'recruitment'),
          ]),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, box) {
            if (box.maxWidth < 900) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                meetingsPanel, const SizedBox(height: 12), leavePanel, const SizedBox(height: 12),
                minutesPanel, const SizedBox(height: 12), actionsPanel,
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                meetingsPanel, const SizedBox(height: 12), minutesPanel,
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                leavePanel, const SizedBox(height: 12), actionsPanel,
              ])),
            ]);
          }),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ProcButton(label: 'New invoice', icon: Symbols.add, onPressed: () => _go('sales_new')),
            ProcButton(label: 'All sales', icon: Symbols.receipt_long, onPressed: () => _go('sales_history')),
            ProcButton(label: 'Staff directory', icon: Symbols.badge, onPressed: () => _go('hr_directory')),
            ProcButton(label: 'Recruitment', icon: Symbols.person_search, onPressed: () => _go('hr_recruitment')),
            ProcButton(label: 'Payroll', icon: Symbols.payments, onPressed: () => _go('hr_payroll')),
          ]),
        ]),
      ),
    );
  }
}
