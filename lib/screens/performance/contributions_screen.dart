// Staff contributions — who did what per person in a period: quotations
// prepared (credited to whoever prepared them, engineers included), how many
// became invoices, installations, services and deals won. The Director's
// record for gauging bonuses: no formula and no amounts here, and every
// number opens the records behind it.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/contribution_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/procurement/proc_widgets.dart';
import '../procurement/tender_forms.dart' show ProcDialog;

String _tsh(int v) => 'TSh ${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
String _role(String r) => r.replaceAll('_', ' ').toUpperCase();

const _metricLabels = {
  'quotations': 'Quotations prepared',
  'quotations_invoiced': 'Quotations that became invoices',
  'installations': 'Installations',
  'services': 'Services',
  'deals_won': 'Deals won',
};

enum _Sort { name, quotations, invoiced, value, installations, services, deals }

class ContributionsScreen extends StatefulWidget {
  const ContributionsScreen({super.key});
  @override
  State<ContributionsScreen> createState() => _ContributionsScreenState();
}

class _ContributionsScreenState extends State<ContributionsScreen> {
  Period _period = Period.defaultPeriod;
  List<Contribution>? _rows;
  String? _error;
  String _q = '';
  _Sort _sort = _Sort.quotations;
  bool _asc = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ContributionService.instance.list(query: _period.query);
      if (mounted) setState(() { _rows = rows; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _sortBy(_Sort s) => setState(() {
    _asc = _sort == s ? !_asc : s == _Sort.name;
    _sort = s;
  });

  int _key(Contribution c) => switch (_sort) {
    _Sort.quotations => c.quotations,
    _Sort.invoiced => c.quotationsInvoiced,
    _Sort.value => c.invoicedValue,
    _Sort.installations => c.installations,
    _Sort.services => c.services,
    _Sort.deals => c.dealsWon,
    _Sort.name => 0,
  };

  List<Contribution> _shown(List<Contribution> all) {
    final q = _q.toLowerCase();
    final list = all.where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.role.toLowerCase().contains(q)).toList();
    list.sort((a, b) {
      final r = _sort == _Sort.name ? a.name.toLowerCase().compareTo(b.name.toLowerCase()) : _key(a).compareTo(_key(b));
      return _asc ? r : -r;
    });
    return list;
  }

  void _open(Contribution c, String metric) {
    if (c.metric(metric) == 0) return;
    showDialog<void>(context: context, builder: (_) => _ItemsDialog(person: c, metric: metric, period: _period));
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final all = _rows;
    if (all == null) {
      return _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    int sum(int Function(Contribution) f) => all.fold(0, (a, c) => a + f(c));
    final quotes = sum((c) => c.quotations), invoiced = sum((c) => c.quotationsInvoiced);

    return Container(
      color: pal.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ProcPageHeader(
          title: 'Staff Contributions',
          subtitle: 'Who did what in ${_period.label.toLowerCase()} · tap a number to see the records behind it',
        ),
        Expanded(child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 14, 24, 24), children: [
            KpiStrip([
              KpiStripItem(Symbols.request_quote, ProcTone.violet, 'Quotations prepared', '$quotes',
                  '$invoiced became invoices'),
              KpiStripItem(Symbols.build, ProcTone.teal, 'Installations', '${sum((c) => c.installations)}', 'machines installed'),
              KpiStripItem(Symbols.handyman, ProcTone.amber, 'Services', '${sum((c) => c.services)}', 'repair tickets resolved'),
              KpiStripItem(Symbols.handshake, ProcTone.green, 'Deals won', '${sum((c) => c.dealsWon)}', '${all.length} people with activity'),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              PeriodSelector(value: _period, onChanged: (p) { setState(() { _period = p; _rows = null; }); _load(); }),
              ProcSearchField(hint: 'Name or role…', onChanged: (v) => setState(() => _q = v)),
            ]),
            const SizedBox(height: 10),
            const ProcNote('Counts only what was recorded in the system: quotations credit whoever prepared them, '
                'installations the engineer who installed the machine, services the engineer assigned to the resolved ticket. '
                'Work done before it was logged here isn\'t counted.'),
            const SizedBox(height: 14),
            _table(context, _shown(all)),
          ]),
        )),
      ]),
    );
  }

  Widget _th(String label, {_Sort? sort, double? w, int flex = 0, bool right = false}) {
    final on = sort != null && _sort == sort;
    final text = Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
          style: procCaps(context).copyWith(color: on ? context.pal.text : null))),
      if (on) ...[const SizedBox(width: 3), Icon(_asc ? Symbols.arrow_upward : Symbols.arrow_downward, size: 12, color: context.pal.text)],
    ]);
    final cell = Align(alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        child: sort == null ? text : InkWell(onTap: () => _sortBy(sort), child: text));
    return w != null ? SizedBox(width: w, child: cell) : Expanded(flex: flex, child: cell);
  }

  /// A count that opens its records; a zero is plain.
  Widget _num(Contribution c, String metric, {String? text, double w = 90}) {
    final n = c.metric(metric);
    final label = Text(text ?? '$n', textAlign: TextAlign.right,
        style: procMono(context, color: n == 0 ? context.pal.textDim : AppColors.blue));
    return SizedBox(width: w, child: Align(alignment: Alignment.centerRight,
        child: n == 0 ? label : InkWell(onTap: () => _open(c, metric), child: label)));
  }

  String _pct(Contribution c) => c.quotations == 0 ? '' : ' · ${(c.quotationsInvoiced * 100 / c.quotations).round()}%';

  Widget _table(BuildContext context, List<Contribution> rows) {
    final pal = context.pal;
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
        child: Text('Nothing recorded for anyone in this period.', textAlign: TextAlign.center, style: AppTheme.bodySub.copyWith(color: pal.textDim)),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 860) return Column(children: [for (final c in rows) _card(context, c)]);
        const gap = SizedBox(width: 14);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border))),
            child: Row(children: [
              _th('Person', sort: _Sort.name, flex: 24), gap,
              _th('Quotations', sort: _Sort.quotations, w: 90, right: true), gap,
              _th('Became invoices', sort: _Sort.invoiced, w: 130, right: true), gap,
              _th('Invoiced value', sort: _Sort.value, w: 140, right: true), gap,
              _th('Installations', sort: _Sort.installations, w: 100, right: true), gap,
              _th('Services', sort: _Sort.services, w: 90, right: true), gap,
              _th('Deals won', sort: _Sort.deals, w: 90, right: true),
            ]),
          ),
          for (final c in rows) Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
            child: Row(children: [
              Expanded(flex: 24, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text('${_role(c.role)}${c.isActive ? '' : ' · inactive'}',
                    style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              gap,
              _num(c, 'quotations'),
              gap,
              _num(c, 'quotations_invoiced', text: '${c.quotationsInvoiced}${_pct(c)}', w: 130),
              gap,
              SizedBox(width: 140, child: Text(c.invoicedValue == 0 ? '—' : _tsh(c.invoicedValue), textAlign: TextAlign.right,
                  style: procMono(context, color: c.invoicedValue == 0 ? pal.textDim : pal.text))),
              gap,
              _num(c, 'installations', w: 100),
              gap,
              _num(c, 'services'),
              gap,
              _num(c, 'deals_won'),
            ]),
          ),
        ]);
      }),
    );
  }

  Widget _card(BuildContext context, Contribution c) {
    final pal = context.pal;
    Widget stat(String metric, String label, {String? text}) {
      final n = c.metric(metric);
      return InkWell(
        onTap: n == 0 ? null : () => _open(c, metric),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
          Expanded(child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute))),
          Text(text ?? '$n', style: procMono(context, color: n == 0 ? pal.textDim : AppColors.blue)),
        ])),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(c.name, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('${_role(c.role)}${c.isActive ? '' : ' · inactive'}', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
        const SizedBox(height: 6),
        stat('quotations', 'Quotations prepared'),
        stat('quotations_invoiced', 'Became invoices',
            text: '${c.quotationsInvoiced}${_pct(c)}${c.invoicedValue == 0 ? '' : ' · ${_tsh(c.invoicedValue)}'}'),
        stat('installations', 'Installations'),
        stat('services', 'Services'),
        stat('deals_won', 'Deals won'),
      ]),
    );
  }
}

class _ItemsDialog extends StatefulWidget {
  const _ItemsDialog({required this.person, required this.metric, required this.period});
  final Contribution person;
  final String metric;
  final Period period;
  @override
  State<_ItemsDialog> createState() => _ItemsDialogState();
}

class _ItemsDialogState extends State<_ItemsDialog> {
  List<ContributionItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    ContributionService.instance.items(widget.person.id, widget.metric, query: widget.period.query).then((v) {
      if (mounted) setState(() => _items = v);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = friendlyError(e));
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final items = _items;
    return ProcDialog(
      title: '${widget.person.name} · ${_metricLabels[widget.metric]}',
      icon: Symbols.list_alt,
      width: 640,
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      body: _error != null
          ? Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: AppTheme.bodySub.copyWith(color: AppColors.coral)))
          : items == null
              ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${items.length} in ${widget.period.label.toLowerCase()}',
                      style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute)),
                  const SizedBox(height: 8),
                  for (final i in items) Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(i.reference, style: procMono(context, color: pal.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text([i.title, if (i.invoice != null) 'Invoice ${i.invoice}'].join(' · '),
                            style: AppTheme.bodySub.copyWith(fontSize: 11.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ])),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(i.date == null ? '—' : formatDate(i.date!), style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
                        if (i.value != null) Text(_tsh(i.value!), style: procMono(context, color: pal.textMute)),
                      ]),
                    ]),
                  ),
                ]),
    );
  }
}
