import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/per_diem_request.dart';
import '../../services/per_diem_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/phone_layout.dart';

// Section 15.4: one travel plan laid out like the paper WORKPLAN template,
// in its order — header, day table, totals, summary, payment, signatures —
// then the status timeline. Every number comes from the API (summary and
// signature block are computed server-side), the same figures the PDF and
// XLSX exports print.

/// Opens the viewer as a full page. [plan] shows at once; the latest copy
/// is fetched behind it.
Future<void> openTravelPlanViewer(BuildContext context, PerDiemRequest plan) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TravelPlanViewerScreen(plan: plan)));

class TravelPlanViewerScreen extends StatefulWidget {
  const TravelPlanViewerScreen({super.key, required this.plan});
  final PerDiemRequest plan;

  @override
  State<TravelPlanViewerScreen> createState() => _TravelPlanViewerScreenState();
}

String _money(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
String _money2(num v) => '${_money(v.truncate())}.${((v.abs() * 100).round() % 100).toString().padLeft(2, '0')}';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// "Monday, September 21, 2026" — the template's long date.
String _longDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${_days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// "21/09/2026"
String _shortDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// "21 Sep 2026, 14:05" in local time.
String? _stamp(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  return '${d.day} ${_months[d.month - 1].substring(0, 3)} ${d.year}, '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Color _statusColor(PerDiemRequest p) => switch (p.status) {
  PerDiemStatus.rejected => AppColors.coral,
  PerDiemStatus.cancelled => AppColors.textMute,
  PerDiemStatus.paid => AppColors.green,
  PerDiemStatus.pendingTeamLead => AppColors.amber,
  PerDiemStatus.pendingCto => AppColors.blue,
  PerDiemStatus.pendingPayment => AppColors.violet,
  _ => AppColors.teal,
};

class _TravelPlanViewerScreenState extends State<TravelPlanViewerScreen> {
  late PerDiemRequest _p = widget.plan;

  @override
  void initState() {
    super.initState();
    PerDiemService.instance.show(widget.plan.id).then((p) {
      if (mounted) setState(() => _p = p);
    }).catchError((_) {});
  }

  Future<void> _pdf() => downloadPdf(context, () => PerDiemService.instance.pdfBytes(_p.id), 'travel-plan-${_p.id}.pdf');
  Future<void> _xlsx() => downloadPdf(context, () => PerDiemService.instance.xlsxBytes(_p.id), 'travel-plan-${_p.id}.xlsx');

  @override
  Widget build(BuildContext context) {
    final phone = isPhoneWidth(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: context.pal.bg,
      appBar: AppBar(
        backgroundColor: context.pal.surface1, foregroundColor: context.pal.text, elevation: 0,
        surfaceTintColor: Colors.transparent, titleSpacing: 4,
        title: Text('Travel plan #${_p.id}', style: AppTheme.bodyStrong.copyWith(fontSize: 15), overflow: TextOverflow.ellipsis),
        actions: [
          if (phone) ...[
            IconButton(onPressed: _pdf, tooltip: 'Download PDF', icon: const Icon(Symbols.picture_as_pdf, size: 18)),
            IconButton(onPressed: _xlsx, tooltip: 'Download XLSX', icon: const Icon(Symbols.table_chart, size: 18)),
          ] else ...[
            OutlinedButton.icon(onPressed: _pdf, icon: const Icon(Symbols.picture_as_pdf, size: 15), label: const Text('PDF')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _xlsx, icon: const Icon(Symbols.table_chart, size: 15), label: const Text('XLSX')),
          ],
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(builder: (ctx, cst) {
        final narrow = isPhoneWidth(cst.maxWidth);
        return SingleChildScrollView(
          padding: EdgeInsets.all(narrow ? 12 : 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _sheet(context, narrow),
                const SizedBox(height: 16),
                _timeline(context),
                if (_p.adjustments.isNotEmpty) ...[const SizedBox(height: 16), _adjustments(context)],
                if (_p.revisions.isNotEmpty) ...[const SizedBox(height: 16), _revisions(context)],
              ]),
            ),
          ),
        );
      }),
    );
  }

  BoxDecoration _card(BuildContext context) => BoxDecoration(
      color: context.pal.surface1, borderRadius: BorderRadius.circular(AppColors.rLg), border: Border.all(color: context.pal.border));

  Widget _label(String t) => Text(t.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10));

  // ── The template sheet: header → day table → totals → summary → payment → sign-off
  Widget _sheet(BuildContext context, bool narrow) {
    final s = _p.summary;
    final color = _statusColor(_p);
    return Container(
      padding: EdgeInsets.all(narrow ? 14 : 22),
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Row 1: company + "Work Plan"
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text('Hypermed Healthcare Ltd',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTheme.pageTitle.copyWith(fontSize: narrow ? 18 : 22, fontStyle: FontStyle.italic))),
          const SizedBox(width: 12),
          Text('Work Plan', style: AppTheme.pageTitle.copyWith(fontSize: narrow ? 18 : 22, fontStyle: FontStyle.italic)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          PhonePill(_p.status.label, color),
          if (_p.wasEdited) PhonePill('Edited by CTO', AppColors.amber),
        ]),
        const SizedBox(height: 14),
        // Rows 2–5: the info box
        _infoBox(context, narrow, [
          ('Description of the Trip', _p.purpose?.isNotEmpty == true ? _p.purpose! : _p.destination),
          ('Trip coverage date', '${_shortDate(_p.startDate)} – ${_shortDate(_p.endDate)}'),
          ('Name', _p.staffNameSnapshot ?? _p.userName ?? '—'),
          ('Designation', _p.staffDesignationSnapshot ?? '—'),
        ]),
        const SizedBox(height: 18),
        // Row 6 onward: day table + Total row
        if (_p.lines.isEmpty)
          Text('No day-by-day lines recorded — single-total request of TSh ${_money(_p.amount)}.', style: AppTheme.bodySub)
        else if (narrow)
          ..._dayCards(context)
        else
          _dayTable(context),
        const SizedBox(height: 18),
        // Summary block, then the grand total
        if (s != null)
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(children: [
                _sumRow(context, 'Number of sites visited', '${s.sitesVisited}'),
                _sumRow(context, 'Total number of days spent', '${s.daysSpent}'),
                _sumRow(context, 'Average number of days / site', s.avgDaysPerSite?.toStringAsFixed(1) ?? '-'),
                _sumRow(context, 'Average cost per site', s.avgCostPerSite != null ? _money2(s.avgCostPerSite!) : '-'),
                _sumRow(context, 'Grand total', 'TSh ${_money2(s.grandTotal)}', grand: true),
              ]),
            ),
          ),
        // Payment row
        if (_p.paymentSnapshot != null) ...[
          const SizedBox(height: 16),
          _payment(context, _p.paymentSnapshot!),
        ],
        // Signature block
        if (_p.signatureBlock.isNotEmpty) ...[
          const SizedBox(height: 20),
          _label('Sign-off'),
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 12, children: [
            for (final (i, l) in _p.signatureBlock.indexed)
              SizedBox(width: narrow ? double.infinity : 320, child: _signature(context, l, first: i == 0)),
          ]),
        ],
      ]),
    );
  }

  Widget _infoBox(BuildContext context, bool narrow, List<(String, String)> rows) => Container(
    decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, r) in rows.indexed)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: context.pal.divider))),
          child: narrow
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.$1, style: AppTheme.bodySub.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 2),
                  Text(r.$2, style: AppTheme.bodyStrong.copyWith(fontSize: 13, fontStyle: FontStyle.italic)),
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 200, child: Text(r.$1, style: AppTheme.bodyStrong.copyWith(fontSize: 13, fontStyle: FontStyle.italic))),
                  Expanded(child: Text(r.$2, style: AppTheme.bodyStrong.copyWith(fontSize: 13, fontStyle: FontStyle.italic))),
                ]),
        ),
    ]),
  );

  Widget _dayTable(BuildContext context) {
    final head = AppTheme.bodyStrong.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic);
    final cell = AppTheme.bodySm.copyWith(fontSize: 12, color: context.pal.text);
    Widget c(String t, {TextStyle? style, bool right = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(t, style: style ?? cell, textAlign: right ? TextAlign.right : TextAlign.left),
    );
    final s = _p.summary;
    final border = BorderSide(color: context.pal.border);
    return Table(
      border: TableBorder(horizontalInside: border, verticalInside: border, top: border, bottom: border, left: border, right: border),
      columnWidths: const {
        0: FixedColumnWidth(40), 1: FlexColumnWidth(2.2), 2: FlexColumnWidth(1.1), 3: FlexColumnWidth(1.1),
        4: FlexColumnWidth(1.5), 5: FlexColumnWidth(2.2), 6: FlexColumnWidth(1.1), 7: FlexColumnWidth(1.2), 8: FlexColumnWidth(1.3),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: context.pal.surface2),
          children: [
            for (final (i, h) in ['No.', 'Date', 'Region', 'District', 'Site name', 'Activity', 'Labor', 'Per diem', 'Transportation fare'].indexed)
              c(h, style: head, right: i >= 6),
          ],
        ),
        for (final l in _p.lines)
          TableRow(children: [
            c('${l.seqNo}'),
            c(_longDate(l.date), style: cell.copyWith(fontWeight: FontWeight.w600, fontStyle: FontStyle.italic)),
            c(l.region ?? '—'), c(l.district ?? '—'), c(l.siteName ?? '—'), c(l.activity ?? '—'),
            c(_money2(l.laborCost), right: true), c(_money2(l.perDiemCost), right: true), c(_money2(l.transportFare), right: true),
          ]),
        TableRow(children: [
          for (var i = 0; i < 5; i++) const SizedBox.shrink(),
          c('Total', style: AppTheme.bodyStrong.copyWith(fontSize: 12)),
          c(_money2(s?.totalLabor ?? 0), style: AppTheme.bodyStrong.copyWith(fontSize: 12), right: true),
          c(_money2(s?.totalPerDiem ?? 0), style: AppTheme.bodyStrong.copyWith(fontSize: 12), right: true),
          c(_money2(s?.totalTransport ?? 0), style: AppTheme.bodyStrong.copyWith(fontSize: 12), right: true),
        ]),
      ],
    );
  }

  List<Widget> _dayCards(BuildContext context) {
    final s = _p.summary;
    return [
      for (final l in _p.lines)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${l.seqNo}.', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              const SizedBox(width: 6),
              Expanded(child: Text(_longDate(l.date), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStrong.copyWith(fontSize: 12.5, fontStyle: FontStyle.italic))),
            ]),
            const SizedBox(height: 4),
            Text([l.region, l.district, l.siteName].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
                style: AppTheme.bodySm.copyWith(fontSize: 12)),
            if (l.activity?.isNotEmpty == true) Text(l.activity!, style: AppTheme.bodySub.copyWith(fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 14, runSpacing: 2, children: [
              Text('Labor ${_money(l.laborCost)}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
              Text('Per diem ${_money(l.perDiemCost)}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
              Text('Transport ${_money(l.transportFare)}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
            ]),
          ]),
        ),
      if (s != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 14, runSpacing: 2, children: [
            Text('Total', style: AppTheme.bodyStrong.copyWith(fontSize: 12)),
            Text('Labor ${_money(s.totalLabor)}', style: AppTheme.bodyStrong.copyWith(fontSize: 12)),
            Text('Per diem ${_money(s.totalPerDiem)}', style: AppTheme.bodyStrong.copyWith(fontSize: 12)),
            Text('Transport ${_money(s.totalTransport)}', style: AppTheme.bodyStrong.copyWith(fontSize: 12)),
          ]),
        ),
    ];
  }

  Widget _sumRow(BuildContext context, String k, String v, {bool grand = false}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(border: Border(
        top: grand ? BorderSide(color: context.pal.text, width: 1.5) : BorderSide.none,
        bottom: grand ? BorderSide.none : BorderSide(color: context.pal.divider))),
    child: Row(children: [
      Expanded(child: Text(k, style: grand ? AppTheme.bodyStrong.copyWith(fontSize: 13) : AppTheme.bodySm.copyWith(fontSize: 12.5))),
      Text(v, style: AppTheme.bodyStrong.copyWith(fontSize: grand ? 15 : 12.5, color: grand ? AppColors.teal : null)),
    ]),
  );

  Widget _payment(BuildContext context, PerDiemPaymentSnapshot p) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.pal.border)),
    child: Wrap(spacing: 18, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(p.provider ?? '—', style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
      Text(p.accountNumber ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 13, color: context.pal.text)),
      Text('ACCOUNT NAME: ${p.accountName ?? '—'}', style: AppTheme.bodySm.copyWith(fontSize: 12.5, color: context.pal.text)),
    ]),
  );

  Widget _signature(BuildContext context, PerDiemSignatureLine l, {required bool first}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${l.roleLabel}: ${l.personName ?? '—'}', style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
      const SizedBox(height: 4),
      if (first)
        Text(l.actedAtDisplay ?? '', style: AppTheme.bodySub.copyWith(fontSize: 11.5))
      else if (l.pending)
        Text('Signature: ……………………………', style: AppTheme.bodySub.copyWith(fontSize: 11.5))
      else
        Row(children: [
          Icon(Symbols.verified, size: 14, color: AppColors.green),
          const SizedBox(width: 4),
          Flexible(child: Text('Approved electronically on ${l.actedAtDisplay ?? ''}',
              style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.green))),
        ]),
    ],
  );

  // ── Status timeline: one step per approval stage ───────────────────────────
  Widget _timeline(BuildContext context) {
    final p = _p;
    final rejected = p.status == PerDiemStatus.rejected;
    final teamLeadRejected = rejected && p.teamLeadRejectionReason != null;
    final ctoRejected = rejected && !teamLeadRejected;
    const order = [PerDiemStatus.pendingTeamLead, PerDiemStatus.pendingCto, PerDiemStatus.pendingPayment, PerDiemStatus.pendingDirector];
    final at = order.indexOf(p.status);

    _Step stage(int i, String title, String? who, String? when, {String? note}) {
      final _StepState state = when != null
          ? _StepState.done
          : (at == i ? _StepState.current : _StepState.todo);
      return _Step(title, who, _stamp(when), state, note: note);
    }

    final steps = <_Step>[
      _Step('Submitted', p.staffNameSnapshot ?? p.userName, _stamp(p.createdAt), _StepState.done),
      teamLeadRejected
          ? _Step('Rejected by team lead', p.teamLeadReviewerName, _stamp(p.teamLeadReviewedAt), _StepState.stopped, note: p.teamLeadRejectionReason)
          : stage(0, 'Team lead approval', p.teamLeadReviewerName, p.teamLeadReviewedAt),
      if (!teamLeadRejected)
        ctoRejected
            ? _Step('Rejected', p.reviewerName, _stamp(p.reviewedAt), _StepState.stopped, note: p.rejectionReason)
            : stage(1, 'CTO approval', p.reviewerName, p.reviewedAt),
      if (!rejected) ...[
        stage(2, 'Payment initiated', p.paymentInitiatedByName, p.paymentInitiatedAt,
            note: [p.paymentMethod?.replaceAll('_', ' '), p.paymentReference].whereType<String>().where((x) => x.isNotEmpty).join(' · ')),
        stage(3, 'Money is out', p.paidByName, p.paidAt),
      ],
      if (p.status == PerDiemStatus.cancelled)
        _Step('Cancelled', p.cancelledByName, _stamp(p.cancelledAt), _StepState.stopped, note: p.cancellationReason),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('Status timeline'),
        const SizedBox(height: 12),
        for (final (i, s) in steps.indexed) _stepRow(context, s, last: i == steps.length - 1),
      ]),
    );
  }

  Widget _stepRow(BuildContext context, _Step s, {required bool last}) {
    final color = switch (s.state) {
      _StepState.done => AppColors.green,
      _StepState.current => AppColors.amber,
      _StepState.stopped => AppColors.coral,
      _StepState.todo => context.pal.textMute,
    };
    final icon = switch (s.state) {
      _StepState.done => Symbols.check_circle,
      _StepState.current => Symbols.schedule,
      _StepState.stopped => Symbols.cancel,
      _StepState.todo => Symbols.radio_button_unchecked,
    };
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          Icon(icon, size: 18, color: color, fill: s.state == _StepState.todo ? 0 : 1),
          if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: context.pal.divider)),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.title + (s.state == _StepState.current ? ' — waiting' : ''),
                  style: AppTheme.bodyStrong.copyWith(fontSize: 12.5, color: s.state == _StepState.todo ? context.pal.textMute : null)),
              if (s.who != null || s.when != null)
                Text([s.who, s.when].whereType<String>().join(' · '), style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
              if (s.note?.isNotEmpty == true)
                Text(s.note!, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: s.state == _StepState.stopped ? AppColors.coral : null)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _adjustments(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _card(context),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Payment adjustments'),
      const SizedBox(height: 8),
      for (final a in _p.adjustments)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text('${a.reason}${a.createdByName != null ? ' · ${a.createdByName}' : ''}${a.createdAt != null ? ' · ${_stamp(a.createdAt)}' : ''}',
                style: AppTheme.bodySm.copyWith(fontSize: 12))),
            const SizedBox(width: 12),
            Text('${a.amount >= 0 ? '+' : '−'}TSh ${_money(a.amount.abs())}',
                style: AppTheme.bodyStrong.copyWith(fontSize: 12, color: a.amount >= 0 ? AppColors.green : AppColors.coral)),
          ]),
        ),
    ]),
  );

  Widget _revisions(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _card(context),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Revision history'),
      const SizedBox(height: 8),
      for (final r in _p.revisions)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${_stamp(r.createdAt) ?? ''} · ${r.editedByName ?? 'Someone'} (${r.editorRole}) · ${r.reason}'
            '${r.isPendingReview ? ' · awaiting CTO review' : r.status == 'rejected' ? ' · rejected' : ''}',
            style: AppTheme.bodySm.copyWith(fontSize: 12),
          ),
        ),
    ]),
  );
}

enum _StepState { done, current, todo, stopped }

class _Step {
  const _Step(this.title, this.who, this.when, this.state, {this.note});
  final String title;
  final String? who;
  final String? when;
  final _StepState state;
  final String? note;
}
