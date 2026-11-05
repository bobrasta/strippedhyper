import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/chart_of_account.dart';
import '../../services/accounting_service.dart';
import '../../services/finance_report_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../utils/csv_export.dart';
import '../../utils/format.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/error_view.dart';

enum _Period { thisMonth, lastMonth, last7Days, thisQuarter, thisYear }

extension on _Period {
  String get label => switch (this) {
    _Period.thisMonth   => 'This Month',
    _Period.lastMonth   => 'Last Month',
    _Period.last7Days   => 'Last 7 Days',
    _Period.thisQuarter => 'This Quarter',
    _Period.thisYear    => 'This Year',
  };
}

(String?, String?) _dateRangeFor(_Period p) {
  final now = DateTime.now();
  String iso(DateTime d) => d.toIso8601String().substring(0, 10);
  switch (p) {
    case _Period.thisMonth:
      return (null, null); // let the backend default to the current month
    case _Period.lastMonth:
      final firstOfThisMonth = DateTime(now.year, now.month, 1);
      final lastMonthEnd     = firstOfThisMonth.subtract(const Duration(days: 1));
      final lastMonthStart   = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);
      return (iso(lastMonthStart), iso(lastMonthEnd));
    case _Period.last7Days:
      return (iso(now.subtract(const Duration(days: 7))), iso(now));
    case _Period.thisQuarter:
      final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
      return (iso(DateTime(now.year, qStartMonth, 1)), iso(now));
    case _Period.thisYear:
      return (iso(DateTime(now.year, 1, 1)), iso(now));
  }
}

/// One double-entry posting pair — the same [reference] links a debit row
/// and a credit row in the flat /accounting/journal feed; this groups them
/// back into the DR/CR pair an accountant actually reads.
class _JournalPair {
  const _JournalPair({required this.ref, required this.title, required this.when, required this.dr, required this.cr, required this.amount});
  final String ref;
  final String title;
  final DateTime? when;
  final String dr;
  final String cr;
  final int amount;
}

List<_JournalPair> _pairJournal(List<LedgerEntry> entries) {
  final byRef = <String, List<LedgerEntry>>{};
  for (final e in entries) {
    final key = e.reference?.isNotEmpty == true ? e.reference! : 'row-${e.id}';
    byRef.putIfAbsent(key, () => []).add(e);
  }
  final pairs = <_JournalPair>[];
  byRef.forEach((ref, rows) {
    final debit = rows.where((r) => r.isDebit).isNotEmpty ? rows.firstWhere((r) => r.isDebit) : rows.first;
    final credit = rows.where((r) => !r.isDebit).isNotEmpty ? rows.firstWhere((r) => !r.isDebit) : rows.last;
    final title = (debit.description?.isNotEmpty ?? false) ? debit.description! : ((credit.description?.isNotEmpty ?? false) ? credit.description! : ref);
    pairs.add(_JournalPair(
      ref: ref, title: title, when: debit.createdAt ?? credit.createdAt,
      dr: '${debit.accountCode} ${debit.accountName}', cr: '${credit.accountCode} ${credit.accountName}',
      amount: debit.amount,
    ));
  });
  pairs.sort((a, b) => (b.when ?? DateTime(0)).compareTo(a.when ?? DateTime(0)));
  return pairs;
}

class FinanceDashboardScreen extends StatefulWidget {
  const FinanceDashboardScreen({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;

  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen> {
  Map<String, dynamic> _profitLoss = {};
  Map<String, dynamic> _balance    = {};
  Map<String, dynamic> _arAging    = {};
  Map<String, dynamic> _cashFlow   = {};
  List<LedgerEntry>    _journal    = [];
  List<Map<String, dynamic>> _trend = [];
  // App-wide rule: show this year's figures unless the user picks otherwise.
  _Period _period  = _Period.thisYear;
  bool    _loading = true;
  bool    _dismissedInsight = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — same reasoning as MachineListScreen's own
    // fix: show the last-known bundle instantly on a fresh mount (this
    // widget isn't kept alive across navigation), then quietly refresh.
    // Only seeds when cachedProfitLoss is set, which only happens on a
    // default (dateFrom/dateTo both null) call — exactly what _period's
    // default value of thisMonth resolves to below, so this is always the
    // right data to seed with on a fresh mount.
    // (The P&L cache holds the backend's current-MONTH default, so it only
    // seeds while this screen is on This Month — otherwise the year view
    // would briefly show month figures under a "This Year" label.)
    final cachedPL = FinanceReportService.cachedProfitLoss;
    if (cachedPL != null && _period == _Period.thisMonth) {
      _profitLoss = cachedPL;
      _cashFlow   = FinanceReportService.cachedCashFlow ?? {};
      _balance    = FinanceReportService.cachedBalanceSheet ?? {};
      _arAging    = FinanceReportService.cachedArAging ?? {};
      _journal    = AccountingService.cachedJournal ?? [];
      _trend      = FinanceReportService.cachedMonthlyTrend ?? [];
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      // Only show the blank/shimmer state when there's genuinely nothing
      // to show yet — a background refresh of an already-populated bundle
      // (or a return visit seeded from the cache above) updates silently.
      if (_profitLoss.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final (from, to) = _dateRangeFor(_period);
      final results = await Future.wait([
        FinanceReportService.instance.profitLoss(dateFrom: from, dateTo: to),
        FinanceReportService.instance.cashFlow(dateFrom: from, dateTo: to),
        FinanceReportService.instance.balanceSheet(),
        FinanceReportService.instance.arAging(),
      ]);
      final journal = await AccountingService.instance.journal();
      final trend   = await FinanceReportService.instance.monthlyTrend();

      if (!mounted) return;
      setState(() {
        _profitLoss = results[0]; _cashFlow = results[1];
        _balance    = results[2]; _arAging  = results[3];
        _journal    = journal;
        _trend      = trend;
        _dismissedInsight = false;
        _loading    = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _export() async {
    try {
      final path = await CsvExport.financeSummary(
        periodLabel:  _period.label,
        revenue:          ((_profitLoss['revenue'] as num?) ?? 0).toInt(),
        totalExpenses:    ((_profitLoss['total_expenses'] as num?) ?? 0).toInt(),
        netProfit:        ((_profitLoss['net_profit'] as num?) ?? 0).toInt(),
        netCashFlow:      ((_cashFlow['net_cash_flow'] as num?) ?? 0).toInt(),
        totalOutstanding: ((_arAging['total_outstanding'] as num?) ?? 0).toInt(),
        totalAssets:      ((_balance['total_assets'] as num?) ?? 0).toInt(),
        totalLiabilities: ((_balance['total_liabilities'] as num?) ?? 0).toInt(),
        totalEquity:      ((_balance['total_equity'] as num?) ?? 0).toInt(),
        expensesByCategory: ((_profitLoss['expenses_by_category'] as List?) ?? const [])
            .cast<Map<String, dynamic>>(),
        recentActivity: _journal,
      );
      if (path != null && mounted) showSuccessToast(context, 'Finance report exported to CSV');
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    // A background refresh failing while stale-but-valid cached data is
    // already showing shouldn't blow that away — only "genuinely nothing to
    // show" surfaces the error screen.
    if (_error != null && _profitLoss.isEmpty) return ErrorView(message: _error!, onRetry: _load);

    return LayoutBuilder(builder: (ctx, cst) {
      final pad  = cst.maxWidth < 560 ? 16.0 : 26.0;
      final wide = cst.maxWidth >= 1100;

      final revenue        = ((_profitLoss['revenue'] as num?) ?? 0).toDouble();
      final netProfit      = ((_profitLoss['net_profit'] as num?) ?? 0).toDouble();
      final totalExpenses  = ((_profitLoss['total_expenses'] as num?) ?? 0).toDouble();
      final netMarginPct   = revenue > 0 ? (netProfit / revenue * 100) : 0.0;
      final netCashFlow    = ((_cashFlow['net_cash_flow'] as num?) ?? 0).toDouble();
      final totalOutstanding = ((_arAging['total_outstanding'] as num?) ?? 0).toDouble();
      final overdueCount = ((_arAging['invoices'] as List?) ?? const [])
          .where((i) => (i as Map<String, dynamic>)['bucket'] != 'current').length;
      final totalAssets      = ((_balance['total_assets'] as num?) ?? 0).toDouble();
      final totalLiabilities = ((_balance['total_liabilities'] as num?) ?? 0).toDouble();
      final totalEquity      = ((_balance['total_equity'] as num?) ?? 0).toDouble();
      final balanced          = _balance['balanced'] == true;
      final expensesByCategory = ((_profitLoss['expenses_by_category'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      final expenseRatio = revenue > 0 ? (totalExpenses / revenue) : 0.0;
      final pairs = _pairJournal(_journal).take(4).toList();
      final lastPosting = _journal.isEmpty ? null
          : _journal.map((e) => e.createdAt).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TitleWithActions(
              leading: Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2))),
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Finance Overview', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                const SizedBox(height: 3),
                Text(
                  '${_period.label} · TZS · ${balanced ? "books balanced" : "books out of balance"}'
                  '${lastPosting != null ? " · last posting ${timeAgo(lastPosting)}" : ""}',
                  style: AppTheme.bodySub.copyWith(fontSize: 12),
                ),
              ]),
              actions: [
                _PeriodSelector(period: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
                _ExportButton(onTap: _export),
              ],
            ),
            const SizedBox(height: 18),

            Container(
              decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
              // Phones: the five figures two to a row (five columns broke
              // every amount one character per line).
              child: LayoutBuilder(builder: (context, cst) => statStrip(isPhoneWidth(cst.maxWidth), [
                Expanded(child: _kpiTile('Revenue', Symbols.payments, AppColors.cyan, tshFromDouble(revenue), '${netMarginPct.toStringAsFixed(0)}%', 'net margin')),
                Expanded(child: _kpiTile('Expenses', Symbols.receipt_long, AppColors.coral, tshFromDouble(totalExpenses), expenseRatio > 1 ? '${expenseRatio.toStringAsFixed(1)}× revenue' : '${(expenseRatio * 100).toStringAsFixed(0)}% of revenue', '${expensesByCategory.length} categories', border: true)),
                Expanded(child: _kpiTile('Net result', Symbols.balance, netProfit >= 0 ? AppColors.green : AppColors.coral, tshSigned(netProfit), netProfit >= 0 ? 'profit' : 'loss', 'margin ${netMarginPct.toStringAsFixed(0)}%', border: true)),
                Expanded(child: _kpiTile('Cash flow', Symbols.account_balance_wallet, netCashFlow >= 0 ? AppColors.green : AppColors.coral, tshSigned(netCashFlow), netCashFlow >= 0 ? 'positive' : 'negative', _period.label.toLowerCase(), border: true)),
                Expanded(child: _kpiTile('AR outstanding', Symbols.hourglass_top, AppColors.green, tshFromDouble(totalOutstanding), overdueCount == 0 ? 'none overdue' : '$overdueCount overdue', 'receivables', border: true)),
              ])),
            ),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: (balanced ? AppColors.green : AppColors.coral).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (balanced ? AppColors.green : AppColors.coral).withValues(alpha: 0.24)),
              ),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 14, runSpacing: 6, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(balanced ? Symbols.verified : Symbols.error, size: 15, color: balanced ? AppColors.green : AppColors.coral),
                  const SizedBox(width: 8),
                  Text(balanced ? 'Trial balance ties' : 'Trial balance is off', style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                ]),
                Text('Assets = Liabilities + Equity', style: AppTheme.bodySub.copyWith(fontSize: 12)),
                Container(width: 1, height: 14, color: context.pal.divider),
                Text('ASSETS ${tshSigned(totalAssets)}', style: AppTheme.monoXs.copyWith(fontSize: 11)),
                Text('LIABILITIES ${tshSigned(totalLiabilities)}', style: AppTheme.monoXs.copyWith(fontSize: 11)),
                Text('EQUITY ${tshSigned(totalEquity)}', style: AppTheme.monoXs.copyWith(fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 14),

            wide
                ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(flex: 17, child: Column(children: [
                      _chartCard(context),
                      const SizedBox(height: 14),
                      // Fits five category rows (220 cut the fifth off).
                      SizedBox(height: 270, child: _categoryCard(context, expensesByCategory, totalExpenses)),
                    ])),
                    const SizedBox(width: 16),
                    Expanded(flex: 7, child: Column(children: [
                      _insightCard(context, expenseRatio, expensesByCategory),
                      const SizedBox(height: 14),
                      Expanded(child: _journalCard(context, pairs)),
                    ])),
                  ]))
                : Column(children: [
                    _chartCard(context),
                    const SizedBox(height: 14),
                    // Taller when stacked: five category rows at phone text size.
                    SizedBox(height: 280, child: _categoryCard(context, expensesByCategory, totalExpenses)),
                    const SizedBox(height: 14),
                    _insightCard(context, expenseRatio, expensesByCategory),
                    const SizedBox(height: 14),
                    SizedBox(height: 320, child: _journalCard(context, pairs)),
                  ]),
          ]),
        ),
      );
    });
  }

  Widget _kpiTile(String label, IconData icon, Color color, String value, String chip, String note, {bool border = false}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: border ? BoxDecoration(border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.06)))) : null,
    child: Builder(builder: (context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 7),
        Expanded(child: Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: 9),
      Text(value, style: AppTheme.kpiValue.copyWith(fontSize: 22)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
          child: Text(chip, style: AppTheme.monoXs.copyWith(fontSize: 10, color: color)),
        ),
        Text(note, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
      ]),
    ])),
  );

  Widget _sectionHeader(BuildContext context, IconData icon, Color color, String title, {Widget? trailing}) => Row(children: [
    Icon(icon, size: 13, color: color),
    const SizedBox(width: 8),
    Flexible(flex: 3, child: Text(title.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5),
        maxLines: 1, overflow: TextOverflow.ellipsis)),
    const SizedBox(width: 8),
    Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
    if (trailing != null) ...[const SizedBox(width: 8), trailing],
  ]);

  Widget _card(BuildContext context, {required Widget child, double? height}) => Container(
    height: height,
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
    child: child,
  );

  Widget _chartCard(BuildContext context) {
    final revenue  = _trend.map((m) => ((m['revenue'] as num?) ?? 0).toDouble()).toList();
    final expenses = _trend.map((m) => ((m['expenses'] as num?) ?? 0).toDouble()).toList();
    final labels   = _trend.map((m) => m['label'] as String? ?? '').toList();
    final maxVal   = [...revenue, ...expenses].fold(1.0, (a, b) => b > a ? b : a);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(context, Symbols.bar_chart, AppColors.cyan, 'Revenue vs expenses · 12 months', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5), Text('Revenue', style: AppTheme.bodySub.copyWith(fontSize: 11)),
        const SizedBox(width: 12),
        Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5), Text('Expenses', style: AppTheme.bodySub.copyWith(fontSize: 11)),
      ])),
      const SizedBox(height: 9),
      _card(context, height: 230, child: _trend.isEmpty
          ? Center(child: Text('No trend data yet', style: AppTheme.bodySub))
          : Column(children: [
              Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(_trend.length, (i) => Expanded(
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Expanded(child: Container(height: (revenue[i] / maxVal * 160).clamp(2, 160).toDouble(), decoration: BoxDecoration(color: AppColors.cyan, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))))),
                  const SizedBox(width: 3),
                  Expanded(child: Container(height: (expenses[i] / maxVal * 160).clamp(2, 160).toDouble(), decoration: BoxDecoration(color: AppColors.coral, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))))),
                ])),
              )))),
              const SizedBox(height: 8),
              Row(children: List.generate(labels.length, (i) => Expanded(child: Text(labels[i], textAlign: TextAlign.center, style: AppTheme.monoXs.copyWith(fontSize: 10, color: i == labels.length - 1 ? context.pal.text : context.pal.textDim))))),
            ])),
    ]);
  }

  Widget _categoryCard(BuildContext context, List<Map<String, dynamic>> categories, double total) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(context, Symbols.receipt, AppColors.coral, 'Where the money went · ${_period.label}', trailing: Text(tshFromDouble(total), style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.text))),
      const SizedBox(height: 9),
      Expanded(child: _card(context, child: categories.isEmpty
          ? Center(child: Text('No expenses recorded', style: AppTheme.bodySub))
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: categories.take(5).map((c) {
              final catTotal = ((c['total'] as num?) ?? 0).toDouble();
              final pct = total > 0 ? (catTotal / total) : 0.0;
              final color = [AppColors.coral, AppColors.amber, AppColors.violet, AppColors.cyan, AppColors.textMute][categories.indexOf(c) % 5];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 130, child: Text(c['category'] as String? ?? '—', style: AppTheme.bodySub.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct.clamp(0, 1), minHeight: 8, backgroundColor: context.pal.surface3, valueColor: AlwaysStoppedAnimation(color)))),
                  const SizedBox(width: 10),
                  SizedBox(width: 62, child: Text(tshFromDouble(catTotal), textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.text))),
                  SizedBox(width: 40, child: Text('${(pct * 100).toStringAsFixed(0)}%', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim))),
                ]),
              );
            }).toList()))),
    ]);
  }

  Widget _insightCard(BuildContext context, double expenseRatio, List<Map<String, dynamic>> categories) {
    final overRevenue = expenseRatio > 1.2;
    if (!overRevenue || _dismissedInsight) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.green.withValues(alpha: 0.24))),
        child: Row(children: [
          Icon(Symbols.check_circle, size: 16, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(child: Text('Expenses are within a healthy range of revenue this period.', style: AppTheme.bodySm.copyWith(fontSize: 12))),
        ]),
      );
    }
    final topCat = categories.isNotEmpty ? categories.first : null;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.amber.withValues(alpha: 0.24))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Expenses ran ${expenseRatio.toStringAsFixed(1)}× revenue', style: AppTheme.cardTitle.copyWith(fontSize: 15)),
        const SizedBox(height: 6),
        Text(
          topCat != null
              ? '${topCat['category']} of ${tshFromDouble((topCat['total'] as num?) ?? 0)} is the largest cost this period. Review postings before you close.'
              : 'Review postings before you close the period.',
          style: AppTheme.bodySub.copyWith(fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton(
            onPressed: () => widget.onNavigateTo?.call('finance_reports'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.amber, side: BorderSide(color: AppColors.amber.withValues(alpha: 0.5))),
            child: const Text('Review postings'),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: () => setState(() => _dismissedInsight = true), child: const Text('Dismiss')),
        ]),
      ]),
    );
  }

  Widget _journalCard(BuildContext context, List<_JournalPair> pairs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(context, Symbols.list_alt, AppColors.violet, 'Latest journal entries', trailing: Text('Dr / Cr', style: AppTheme.bodySub.copyWith(fontSize: 11))),
      const SizedBox(height: 9),
      Expanded(child: Container(
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        clipBehavior: Clip.antiAlias,
        child: pairs.isEmpty
            ? Center(child: Text('No postings yet', style: AppTheme.bodySub))
            : Column(children: [
                ...pairs.map((p) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(p.ref, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p.title, style: AppTheme.bodySm.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(p.when != null ? timeAgo(p.when!) : '', style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Text('DR', style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: AppColors.cyan)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(p.dr, style: AppTheme.bodySub.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(tshFromDouble(p.amount), style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.text)),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      Text('CR', style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: AppColors.amber)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(p.cr, style: AppTheme.bodySub.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(tshFromDouble(p.amount), style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.textDim)),
                    ]),
                  ]),
                )),
                const Spacer(),
                InkWell(
                  onTap: () => widget.onNavigateTo?.call('finance_ledger'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.divider))),
                    alignment: Alignment.center,
                    child: Text('Open journal', style: AppTheme.bodySm.copyWith(fontSize: 12, color: AppColors.green)),
                  ),
                ),
              ]),
      )),
    ]);
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.period, required this.onChanged});
  final _Period period;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_Period>(
    onSelected: onChanged,
    itemBuilder: (_) => _Period.values.map((p) => PopupMenuItem(value: p, child: Text(p.label))).toList(),
    color: context.pal.surface2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.rMd), side: BorderSide(color: context.pal.border)),
    child: Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(9), border: Border.all(color: context.pal.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Symbols.calendar_today, size: 13, color: context.pal.textDim),
        const SizedBox(width: 7),
        Text(period.label, style: AppTheme.bodySm.copyWith(fontSize: 12)),
        const SizedBox(width: 5),
        Icon(Symbols.expand_more, size: 15, color: context.pal.textDim),
      ]),
    ),
  );
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: AppColors.green)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Symbols.file_download, size: 14, color: AppColors.green),
        const SizedBox(width: 7),
        Text('Export report', style: AppTheme.bodySm.copyWith(color: AppColors.green, fontSize: 12)),
      ]),
    ),
  );
}
