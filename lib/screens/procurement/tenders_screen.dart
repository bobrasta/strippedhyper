// Section 19 · Tenders & Contracts list (design 1a). Sorted by the deadline
// that could hurt us first; an overdue performance security or missed
// contract signing is a red row + red KPI. Everything shown is computed by
// the API (TenderDeadlineService), not by this screen.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/tender.dart';
import '../../services/tender_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/procurement/proc_widgets.dart';
import 'tender_detail_screen.dart';
import 'tender_forms.dart';

String tshShort(int? v) {
  if (v == null) return '—';
  if (v == 0) return 'TSh 0';
  if (v >= 1000000000) return 'TSh ${(v / 1e9).toStringAsFixed(2)}B';
  if (v >= 1000000) return 'TSh ${(v / 1e6).toStringAsFixed(v >= 10000000 ? 0 : 1)}M';
  return 'TSh ${(v / 1000).round()}K';
}

Color deadlineColor(BuildContext c, DeadlineState s) => switch (s) {
  DeadlineState.overdue => AppColors.coral,
  DeadlineState.dueToday || DeadlineState.soon => AppColors.amber,
  DeadlineState.ok => c.pal.textMute,
  _ => c.pal.textDim,
};

class TendersScreen extends StatefulWidget {
  const TendersScreen({super.key, this.initialTenderId});
  /// Opened from a deadline notification — jumps straight to that tender.
  final int? initialTenderId;
  @override
  State<TendersScreen> createState() => _TendersScreenState();
}

class _TendersScreenState extends State<TendersScreen> {
  int _tab = 0; // open · bidding · won · closed/lost
  String _q = '';
  TenderList? _data = TenderService.cachedList;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialTenderId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openId(widget.initialTenderId!));
    }
  }

  Future<void> _load() async {
    try {
      final d = await TenderService.instance.list();
      if (mounted) setState(() { _data = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  bool _inTab(Tender t) => switch (_tab) {
    1 => t.step <= 4 && !t.isClosedOrLost,
    2 => t.step >= 5 && !t.isClosedOrLost,
    3 => t.isClosedOrLost,
    _ => !t.isClosedOrLost,
  };

  List<Tender> _rows(List<Tender> all) {
    final q = _q.toLowerCase();
    final list = all.where((t) => _inTab(t) && (q.isEmpty ||
        t.tenderNumber.toLowerCase().contains(q) || (t.contractNumber ?? '').toLowerCase().contains(q) ||
        (t.entity?.name ?? '').toLowerCase().contains(q) || t.title.toLowerCase().contains(q))).toList();
    list.sort((a, b) {
      if (a.flagged != b.flagged) return a.flagged ? -1 : 1;
      final da = a.nextDeadline?.due, db = b.nextDeadline?.due;
      if (da == null) return db == null ? b.id.compareTo(a.id) : 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return list;
  }

  Future<void> _openId(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TenderDetailScreen(tenderId: id)));
    _load();
  }

  Future<void> _new() async {
    final t = await showTenderForm(context);
    if (t != null) _openId(t.id);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final data = _data;
    if (data == null) {
      return _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    final all = data.tenders;
    final open = all.where((t) => !t.isClosedOrLost).toList();
    final flagged = all.where((t) => t.flagged).toList();
    final week = open.where((t) {
      final d = t.nextDeadline;
      return d != null && d.daysLeft != null && d.daysLeft! >= 0 && d.daysLeft! <= 7;
    }).toList();
    final bidsOut = open.where((t) => t.status == 'bid_submitted' || t.status == 'awaiting_award').toList();
    final underContract = open.where((t) => t.step >= 8).toList();
    int sum(List<Tender> l) => l.fold(0, (s, t) => s + (t.value ?? 0));
    final counts = [open.length, all.where((t) => t.step <= 4 && !t.isClosedOrLost).length,
      all.where((t) => t.step >= 5 && !t.isClosedOrLost).length, all.where((t) => t.isClosedOrLost).length];

    return Container(
      color: pal.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ProcPageHeader(
          title: 'Tenders & contracts',
          subtitle: '${all.length} tender${all.length == 1 ? '' : 's'} · ${open.length} open · ${flagged.length} flagged · ${week.length} deadline${week.length == 1 ? '' : 's'} this week',
          actions: [
            ProcButton(label: 'Company details', icon: Symbols.domain,
                onPressed: () => showCompanyProfileDialog(context, canManage: data.canManage)),
            ProcButton(label: 'Board resolutions', icon: Symbols.format_list_numbered,
                onPressed: () => showResolutionsDialog(context, canManage: data.canManage)),
            if (data.canManage) ProcButton(label: 'New tender', icon: Symbols.add, tone: ProcTone.green, onPressed: _new),
          ],
        ),
        Expanded(child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 14, 24, 24), children: [
            KpiStrip([
              KpiStripItem(Symbols.report, ProcTone.coral, 'Flagged', '${flagged.length}',
                  flagged.isEmpty ? 'nothing overdue' : flagged.map((t) => t.entity?.shortCode ?? t.tenderNumber).take(2).join(' · '),
                  alarm: flagged.isNotEmpty),
              KpiStripItem(Symbols.alarm, ProcTone.amber, 'Due in 7 days', '${week.length}',
                  week.isEmpty ? 'no deadlines' : week.map((t) => t.nextDeadline!.label.toLowerCase()).toSet().take(2).join(' · ')),
              KpiStripItem(Symbols.gavel, ProcTone.teal, 'Bids out', '${bidsOut.length}', '${tshShort(sum(bidsOut))} awaiting award'),
              KpiStripItem(Symbols.signature, ProcTone.green, 'Under contract', tshShort(sum(underContract)), '${underContract.length} tenders'),
            ]),
            if (data.needsAction.isNotEmpty) ...[
              const SizedBox(height: 14),
              NeedsActionPanel(subtitle: 'most urgent first', [
                for (final t in data.needsAction.take(6)) _needsAction(t),
              ]),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ProcSegmented(options: ['Open · ${counts[0]}', 'Bidding · ${counts[1]}', 'Won · ${counts[2]}', 'Closed / lost · ${counts[3]}'],
                  selected: _tab, onChanged: (i) => setState(() => _tab = i)),
              ProcSearchField(hint: 'Tender no., contract no., entity…', onChanged: (v) => setState(() => _q = v)),
            ]),
            const SizedBox(height: 14),
            _TenderTable(rows: _rows(all), onTap: (t) => _openId(t.id)),
          ]),
        )),
      ]),
    );
  }

  NeedsActionItem _needsAction(Tender t) {
    final d = t.nextDeadline;
    final flaggedDeadline = t.flagged ? 'Performance security or contract signing is overdue — disqualification risk.' : null;
    final when = d == null ? '' : d.relative.replaceAll(' overdue', ' over');
    final cta = d?.kind == 'performance_security' ? 'Upload signed copy'
        : d?.kind == 'bid_submission' ? 'Generate docs' : 'Open tender';
    return NeedsActionItem(
      when: when,
      ref: t.tenderNumber,
      tone: t.flagged || d?.state == DeadlineState.overdue ? ProcTone.coral : ProcTone.amber,
      cta: cta,
      onTap: () => _openId(t.id),
      text: flaggedDeadline ?? (d == null ? t.title
          : '${d.label} ${d.due == null ? '' : 'due ${formatDate(d.due!)}'} — ${t.title}${t.entity == null ? '' : ' (${t.entity!.name})'}.'),
    );
  }
}

class _TenderTable extends StatelessWidget {
  const _TenderTable({required this.rows, required this.onTap});
  final List<Tender> rows;
  final ValueChanged<Tender> onTap;

  (Color, String) _status(BuildContext c, Tender t) {
    if (t.flagged) return (AppColors.coral, '${t.statusLabel} · overdue');
    if (t.status == 'delivered') return (AppColors.green, 'Delivered · awaiting close');
    if (t.status == 'preparing_bid') return (AppColors.amber, t.statusLabel);
    if (t.isClosedOrLost) return (c.pal.textDim, t.statusLabel);
    return (c.pal.text, t.statusLabel);
  }

  List<Color> _segs(BuildContext c, Tender t) {
    final cur = t.flagged ? AppColors.coral
        : t.isClosedOrLost && t.status != 'closed' ? c.pal.textDim
        : t.status == 'preparing_bid' ? AppColors.amber
        : t.status == 'delivered' ? AppColors.green : AppColors.cyan;
    return StepBar.segments(c, total: tenderFlow.length, step: t.step, current: cur);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
        child: Text('No tenders here.', textAlign: TextAlign.center, style: AppTheme.bodySub.copyWith(color: pal.textDim)),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 900) return Column(children: [for (final t in rows) _card(context, t)]);
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
              h('Tender no.', w: 170), gap, h('Tender', flex: 22), gap, h('Status', flex: 15), gap,
              h('Next deadline', w: 150), gap, h('Docs', w: 62), gap, h('Value', w: 96, a: TextAlign.right), gap,
              h('Owner', w: 90, a: TextAlign.right),
            ]),
          ),
          for (final t in rows) Builder(builder: (context) {
            final (sc, st) = _status(context, t);
            final nd = t.nextDeadline;
            return InkWell(
              onTap: () => onTap(t),
              hoverColor: pal.surface2.withValues(alpha: 0.5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: t.flagged ? AppColors.coral.withValues(alpha: 0.05) : null,
                  border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
                child: Row(children: [
                  SizedBox(width: 170, child: Text(t.tenderNumber, style: procMono(context, color: pal.text), overflow: TextOverflow.ellipsis)),
                  gap,
                  Expanded(flex: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(t.entity?.name ?? '—', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  gap,
                  Expanded(flex: 15, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    StepBar(_segs(context, t)),
                    const SizedBox(height: 6),
                    Text(st, style: AppTheme.bodySub.copyWith(fontSize: 11, color: sc), overflow: TextOverflow.ellipsis),
                  ])),
                  gap,
                  SizedBox(width: 150, child: nd == null
                      ? Text('No open deadlines', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim))
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(nd.state == DeadlineState.overdue ? nd.relative
                              : '${nd.due == null ? '' : formatDate(nd.due!)} · ${nd.relative.replaceFirst('in ', '')}',
                              style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: deadlineColor(context, nd.state)), overflow: TextOverflow.ellipsis),
                          Text(nd.label, style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim), overflow: TextOverflow.ellipsis),
                        ])),
                  gap,
                  SizedBox(width: 62, child: Text('${t.documentsExecuted}/${t.documentsTotal}',
                      style: procMono(context, color: t.documentsExecuted < t.documentsTotal ? AppColors.amber : null))),
                  gap,
                  SizedBox(width: 96, child: Text(tshShort(t.value), textAlign: TextAlign.right, style: procMono(context, color: pal.textMute))),
                  gap,
                  SizedBox(width: 90, child: Text(t.ownerName ?? '—', textAlign: TextAlign.right, overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim))),
                ]),
              ),
            );
          }),
        ]);
      }),
    );
  }

  Widget _card(BuildContext context, Tender t) {
    final pal = context.pal;
    final (sc, st) = _status(context, t);
    final nd = t.nextDeadline;
    return InkWell(
      onTap: () => onTap(t),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: t.flagged ? AppColors.coral.withValues(alpha: 0.05) : null,
            border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(t.tenderNumber, style: procMono(context, color: pal.text), overflow: TextOverflow.ellipsis)),
            Text(tshShort(t.value), style: procMono(context, color: pal.textMute)),
          ]),
          const SizedBox(height: 6),
          Text(t.title, style: AppTheme.bodySm),
          Text(t.entity?.name ?? '—', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
          const SizedBox(height: 8),
          StepBar(_segs(context, t)),
          const SizedBox(height: 5),
          Text(st, style: AppTheme.bodySub.copyWith(fontSize: 11, color: sc)),
          if (nd != null) Text('${nd.label} · ${nd.relative}',
              style: AppTheme.bodySub.copyWith(fontSize: 11, color: deadlineColor(context, nd.state))),
        ]),
      ),
    );
  }
}
