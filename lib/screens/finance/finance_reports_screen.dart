import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show can;
import '../../services/accounting_service.dart';
import '../../services/download_manager.dart';
import '../../services/finance_report_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/error_view.dart';
import 'financial_statements_dialog.dart';

// Redesign ported from "Financial Reports Redesign.dc.html" — grouped tabs,
// a computed check-strip + insight card per report, and a real period
// picker/compare-prior toggle (feasible because profitLoss/vat/cashFlow
// already take date_from/date_to). Two things in that mockup were dropped
// rather than faked: the "period open, locks postings" badge (no real
// period-lock exists — closePeriod() is a one-shot GL sweep, not an
// enforcement gate) and the "period trail" activity feed (no event log
// produces those specific milestones). Everything else — every number,
// every check-strip message, every insight — is computed from the real
// finance-report endpoints, not hardcoded like the mockup's demo data.

const _tabDefs = [
  ('Statements', [('Profit & Loss', Symbols.trending_up), ('Balance Sheet', Symbols.balance), ('Cash Flow', Symbols.sync_alt)]),
  ('Ledger', [('Trial Balance', Symbols.list_alt), ('VAT Return', Symbols.receipt_long)]),
  ('Aging', [('AR Aging', Symbols.hourglass_top), ('AP Aging', Symbols.hourglass_bottom)]),
  ('Assets', [('Stock Valuation', Symbols.inventory_2)]),
];
// Flat index -> which tabs take a date range at all.
const _periodScoped = {0, 2, 4}; // P&L, Cash Flow, VAT

class FinanceReportsScreen extends StatefulWidget {
  const FinanceReportsScreen({super.key});

  @override
  State<FinanceReportsScreen> createState() => _FinanceReportsScreenState();
}

class _FinanceReportsScreenState extends State<FinanceReportsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 8, vsync: this)..addListener(() => setState(() {}));

  // App-wide rule: this year unless the user picks otherwise.
  String _period = 'Year'; // This month | Quarter | Year | Custom
  DateTimeRange? _customRange;
  bool _compare = false;
  bool _hideNilTB = true;
  bool _hideNilBS = true;

  Map<String, dynamic> _pl = {}, _bs = {}, _cf = {}, _tb = {}, _vat = {}, _ar = {}, _ap = {}, _sv = {};
  Map<String, dynamic> _plPrior = {}, _cfPrior = {}, _vatPrior = {};
  bool    _loading = true;
  String? _error;
  bool    _closing = false;
  bool    _exporting = false;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — same reasoning as MachineListScreen's own
    // fix: show the last-known bundle instantly on a fresh mount (this
    // widget isn't kept alive across navigation), then quietly refresh.
    // _bs (balance sheet) is the anchor — it takes no date range at all,
    // so FinanceReportService always caches it regardless of caller,
    // making it a reliable "do we have anything to show" signal. The
    // period-scoped reports (_pl/_cf) only seed if their own cache is set,
    // which only happens on a default (null dateFrom/dateTo) call — the
    // same "This Month" period this screen also defaults to, so it's still
    // the right data when present; VAT (_vat) is never called with a null
    // range by either screen so it simply won't seed, same as before.
    final cachedBs = FinanceReportService.cachedBalanceSheet;
    if (cachedBs != null) {
      _bs  = cachedBs;
      // P&L / cash-flow caches hold the backend's current-month default —
      // only seed them while the screen is on This month.
      if (_period == 'This month') {
        _pl  = FinanceReportService.cachedProfitLoss ?? {};
        _cf  = FinanceReportService.cachedCashFlow ?? {};
      }
      _tb  = FinanceReportService.cachedTrialBalance ?? {};
      _vat = FinanceReportService.cachedVat ?? {};
      _ar  = FinanceReportService.cachedArAging ?? {};
      _ap  = FinanceReportService.cachedApAging ?? {};
      _sv  = FinanceReportService.cachedStockValuation ?? {};
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  (DateTime, DateTime) _rangeFor(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'Quarter':
        final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return (DateTime(now.year, qStartMonth, 1), DateTime(now.year, qStartMonth + 3, 0));
      case 'Year':
        return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31));
      case 'Custom':
        if (_customRange != null) return (_customRange!.start, _customRange!.end);
        return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0));
      default: // This month
        return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0));
    }
  }

  (DateTime, DateTime) _priorRangeFor((DateTime, DateTime) r) {
    final lengthDays = r.$2.difference(r.$1).inDays + 1;
    final priorEnd = r.$1.subtract(const Duration(days: 1));
    return (priorEnd.subtract(Duration(days: lengthDays - 1)), priorEnd);
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _periodLabel {
    final (s, e) = _rangeFor(_period);
    return '${formatDate(s)} → ${formatDate(e)}';
  }

  Future<void> _load() async {
    setState(() {
      // Only show the blank/shimmer state when there's genuinely nothing
      // to show yet — a background refresh of an already-populated bundle
      // (or a return visit seeded from the cache above) updates silently.
      if (_bs.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final (start, end) = _rangeFor(_period);
      final from = _iso(start), to = _iso(end);
      final futures = <Future>[
        FinanceReportService.instance.profitLoss(dateFrom: from, dateTo: to),
        FinanceReportService.instance.balanceSheet(),
        FinanceReportService.instance.cashFlow(dateFrom: from, dateTo: to),
        FinanceReportService.instance.trialBalance(),
        FinanceReportService.instance.vat(dateFrom: from, dateTo: to),
        FinanceReportService.instance.arAging(),
        FinanceReportService.instance.apAging(),
        FinanceReportService.instance.stockValuation(),
      ];
      if (_compare) {
        final (pStart, pEnd) = _priorRangeFor((start, end));
        final pFrom = _iso(pStart), pTo = _iso(pEnd);
        futures.addAll([
          FinanceReportService.instance.profitLoss(dateFrom: pFrom, dateTo: pTo),
          FinanceReportService.instance.cashFlow(dateFrom: pFrom, dateTo: pTo),
          FinanceReportService.instance.vat(dateFrom: pFrom, dateTo: pTo),
        ]);
      }
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _pl = results[0] as Map<String, dynamic>;
        _bs = results[1] as Map<String, dynamic>;
        _cf = results[2] as Map<String, dynamic>;
        _tb = results[3] as Map<String, dynamic>;
        _vat = results[4] as Map<String, dynamic>;
        _ar = results[5] as Map<String, dynamic>;
        _ap = results[6] as Map<String, dynamic>;
        _sv = results[7] as Map<String, dynamic>;
        if (_compare) {
          _plPrior = results[8] as Map<String, dynamic>;
          _cfPrior = results[9] as Map<String, dynamic>;
          _vatPrior = results[10] as Map<String, dynamic>;
        } else {
          _plPrior = {}; _cfPrior = {}; _vatPrior = {};
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _closePeriod() async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      final result = await AccountingService.instance.closePeriod();
      if (mounted) {
        showSuccessToast(context, 'Period closed — net income of ${tshFromDouble(result['net_income'] ?? 0)} swept to Retained Earnings.');
        _load();
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _onPeriodTap(String p) async {
    if (p == 'Custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 1),
        initialDateRange: _customRange ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      );
      if (picked == null) return;
      setState(() { _period = 'Custom'; _customRange = picked; });
    } else {
      setState(() => _period = p);
    }
    _load();
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final (filename, rows) = _exportRowsForActiveTab();
      final csv = rows.map((r) => r.map((c) => '"${c.replaceAll('"', '""')}"').join(',')).join('\n');
      final file = await DownloadManager.instance.save(utf8.encode(csv), filename);
      if (mounted) showSuccessToast(context, 'Saved to ${file.path}');
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  (String, List<List<String>>) _exportRowsForActiveTab() {
    final names = ['profit_loss', 'balance_sheet', 'cash_flow', 'trial_balance', 'vat_return', 'ar_aging', 'ap_aging', 'stock_valuation'];
    final filename = '${names[_tab.index]}_${_iso(DateTime.now())}.csv';
    switch (_tab.index) {
      case 0:
        final rows = <List<String>>[['Line', 'Amount']];
        rows.add(['Revenue', '${_n(_pl, 'revenue')}']);
        rows.add(['COGS', '${_n(_pl, 'cogs')}']);
        rows.add(['Gross profit', '${_n(_pl, 'gross_profit')}']);
        for (final c in (_pl['expenses_by_category'] as List? ?? [])) {
          rows.add(['Expense — ${c['category']}', '${c['total']}']);
        }
        rows.add(['Total expenses', '${_n(_pl, 'total_expenses')}']);
        rows.add(['Net profit', '${_n(_pl, 'net_profit')}']);
        return (filename, rows);
      case 1:
        final rows = <List<String>>[['Code', 'Account', 'Balance']];
        for (final section in ['assets', 'liabilities', 'equity']) {
          for (final a in (_bs[section] as List? ?? [])) {
            rows.add(['${a['code']}', '${a['name']}', '${a['balance']}']);
          }
        }
        rows.add(['', 'Total assets', '${_n(_bs, 'total_assets')}']);
        rows.add(['', 'Total liabilities', '${_n(_bs, 'total_liabilities')}']);
        rows.add(['', 'Total equity', '${_n(_bs, 'total_equity')}']);
        return (filename, rows);
      case 2:
        final rows = <List<String>>[['Line', 'Amount']];
        for (final m in (_cf['cash_in_by_method'] as List? ?? [])) {
          rows.add(['Cash in — ${m['method']}', '${m['total']}']);
        }
        rows.add(['Cash out — Expenses', '${_n(_cf, 'cash_out_expenses')}']);
        rows.add(['Cash out — Vendor bills', '${_n(_cf, 'cash_out_vendor_bills')}']);
        rows.add(['Net cash flow', '${_n(_cf, 'net_cash_flow')}']);
        return (filename, rows);
      case 3:
        final rows = <List<String>>[['Code', 'Account', 'Type', 'Debit', 'Credit']];
        for (final a in (_tb['accounts'] as List? ?? [])) {
          rows.add(['${a['code']}', '${a['name']}', '${a['type']}', '${a['debit']}', '${a['credit']}']);
        }
        rows.add(['', '', 'Total', '${_n(_tb, 'total_debit')}', '${_n(_tb, 'total_credit')}']);
        return (filename, rows);
      case 4:
        final rows = <List<String>>[['Line', 'Amount']];
        rows.add(['Output VAT', '${_n(_vat, 'output_vat')}']);
        rows.add(['Input VAT', '${_n(_vat, 'input_vat')}']);
        rows.add(['Net VAT payable', '${_n(_vat, 'net_vat_payable')}']);
        return (filename, rows);
      case 5:
        final rows = <List<String>>[['Invoice', 'Client', 'Due date', 'Days overdue', 'Balance due']];
        for (final i in (_ar['invoices'] as List? ?? [])) {
          rows.add(['${i['invoice_number']}', '${i['client_name']}', '${i['due_date']}', '${i['days_overdue']}', '${i['balance_due']}']);
        }
        return (filename, rows);
      case 6:
        final rows = <List<String>>[['Bill', 'Supplier', 'Due date', 'Days overdue', 'Balance due']];
        for (final b in (_ap['bills'] as List? ?? [])) {
          rows.add(['${b['bill_number']}', '${b['supplier_name']}', '${b['due_date']}', '${b['days_overdue']}', '${b['balance_due']}']);
        }
        return (filename, rows);
      default:
        final rows = <List<String>>[['SKU', 'Name', 'Category', 'Qty', 'Unit cost', 'Value']];
        for (final i in (_sv['items'] as List? ?? [])) {
          rows.add(['${i['sku']}', '${i['name']}', '${i['category']}', '${i['qty']}', '${i['unit_cost']}', '${i['stock_value']}']);
        }
        return (filename, rows);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      final wide = cst.maxWidth >= 1000;
      final periodRelevant = _periodScoped.contains(_tab.index);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: TitleWithActions(
            leading: Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2))),
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Financial Reports', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
              const SizedBox(height: 3),
              Text(periodRelevant ? _periodLabel : 'All-time position, updated on every load', style: AppTheme.bodySub.copyWith(fontSize: 12)),
            ]),
            actions: [
              if (can('finance.export_reports'))
                if (cst.maxWidth < 760)
                  IconButton.outlined(
                    tooltip: 'Financial statements',
                    onPressed: () => showFinancialStatementsDialog(context),
                    icon: const Icon(Symbols.picture_as_pdf, size: 16),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => showFinancialStatementsDialog(context),
                    icon: const Icon(Symbols.picture_as_pdf, size: 15),
                    label: const Text('Financial statements'),
                  ),
              OutlinedButton.icon(
                onPressed: _exporting ? null : _export,
                icon: _exporting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Symbols.download, size: 15),
                label: const Text('Export CSV'),
              ),
              FilledButton.icon(
                onPressed: _closing ? null : _closePeriod,
                icon: _closing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Symbols.event_repeat, size: 15),
                label: Text(_closing ? 'Closing…' : 'Close period'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: _GroupedTabBar(controller: _tab),
        ),
        if (periodRelevant) ...[
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            // Scrolls sideways on phones instead of overflowing.
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              Container(
                decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
                clipBehavior: Clip.antiAlias,
                child: Row(children: [
                  for (final p in ['This month', 'Quarter', 'Year', 'Custom'])
                    GestureDetector(
                      onTap: () => _onPeriodTap(p),
                      child: Container(
                        height: 28, padding: const EdgeInsets.symmetric(horizontal: 11), alignment: Alignment.center,
                        decoration: BoxDecoration(color: _period == p ? AppColors.blue.withValues(alpha: 0.16) : Colors.transparent),
                        child: Text(p, style: AppTheme.bodySub.copyWith(fontSize: 11, color: _period == p ? AppColors.blueStrong : context.pal.textMute)),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () { setState(() => _compare = !_compare); _load(); },
                child: Container(
                  height: 30, padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _compare ? AppColors.blue.withValues(alpha: 0.45) : context.pal.border),
                    color: _compare ? AppColors.blue.withValues(alpha: 0.10) : Colors.transparent,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_compare ? Symbols.check_box : Symbols.check_box_outline_blank, size: 15, color: _compare ? AppColors.blueStrong : context.pal.textMute),
                    const SizedBox(width: 6),
                    Text('Compare prior period', style: AppTheme.bodySub.copyWith(fontSize: 11, color: _compare ? AppColors.blueStrong : context.pal.textMute)),
                  ]),
                ),
              ),
            ])),
          ),
        ],
        const SizedBox(height: 14),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              // A background refresh failing while stale-but-valid cached
              // data is already showing shouldn't blow that away — only
              // "genuinely nothing to show" surfaces the error screen.
              : _error != null && _bs.isEmpty
                  ? ErrorView(message: _error!, onRetry: _load)
                  : TabBarView(controller: _tab, children: [
                      _tabScaffold(context, pad, wide, 0, _plView(context)),
                      _tabScaffold(context, pad, wide, 1, _bsView(context)),
                      _tabScaffold(context, pad, wide, 2, _cfView(context)),
                      _tabScaffold(context, pad, wide, 3, _tbView(context)),
                      _tabScaffold(context, pad, wide, 4, _vatView(context)),
                      _tabScaffold(context, pad, wide, 5, _agingView(context, isAr: true)),
                      _tabScaffold(context, pad, wide, 6, _agingView(context, isAr: false)),
                      _tabScaffold(context, pad, wide, 7, _stockView(context)),
                    ]),
        ),
      ]);
    });
  }

  // ── Shared scaffold: check strip + main report + insight aside ─────────────

  Widget _tabScaffold(BuildContext context, double pad, bool wide, int idx, Widget report) {
    final chk = _checkFor(idx);
    final insight = _insightFor(idx);
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CheckStrip(chk: chk),
        const SizedBox(height: 13),
        // Deliberately no IntrinsicHeight here — Balance Sheet / Stock
        // Valuation's report panel contains a LayoutBuilder further down
        // (for their own responsive two-column split), and IntrinsicHeight
        // forces an intrinsic-dimension layout pass LayoutBuilder can't
        // participate in — a real crash hit earlier in this codebase.
        // Both columns just size to their own natural height instead.
        wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 8, child: report),
                const SizedBox(width: 15),
                Expanded(flex: 3, child: _InsightCard(insight: insight)),
              ])
            : Column(children: [report, const SizedBox(height: 13), _InsightCard(insight: insight)]),
      ]),
    );
  }

  // ── Computed check-strip per tab (all real) ─────────────────────────────────

  _CheckData _checkFor(int idx) {
    switch (idx) {
      case 0:
        final rev = _n(_pl, 'revenue'), exp = _n(_pl, 'total_expenses'), net = _n(_pl, 'net_profit');
        final traded = rev != 0 || exp != 0;
        return _CheckData(
          ok: traded, title: traded ? 'Trading posted this period' : 'No trading posted this period',
          note: traded ? 'Revenue and expenses were recorded for $_period.' : 'Every revenue and expense account is nil for $_period.',
          stats: [('Revenue', tshFromDouble(rev)), ('Expenses', tshFromDouble(exp)), ('Net', tshSigned(net))],
        );
      case 1:
        final balanced = _bs['balanced'] == true;
        return _CheckData(
          ok: balanced, title: balanced ? 'Books balanced' : 'Balance sheet out of balance',
          note: balanced ? 'Assets equal liabilities plus equity to the shilling.' : 'Assets do not equal liabilities plus equity — this indicates a posting bug, not a business condition.',
          stats: [('Assets', tshFromDouble(_n(_bs, 'total_assets'))), ('Liabilities', tshFromDouble(_n(_bs, 'total_liabilities'))), ('Equity', tshFromDouble(_n(_bs, 'total_equity')))],
        );
      case 2:
        final cin = _n(_cf, 'cash_in'), cout = _n(_cf, 'cash_out');
        final moved = cin != 0 || cout != 0;
        return _CheckData(
          ok: moved, title: moved ? 'Cash moved this period' : 'No cash has moved this period',
          note: moved ? 'Receipts and payments recorded for $_period.' : 'No receipts or payments cleared during $_period.',
          stats: [('Cash in', tshFromDouble(cin)), ('Cash out', tshFromDouble(cout)), ('Net', tshSigned(_n(_cf, 'net_cash_flow')))],
        );
      case 3:
        final balanced = _tb['balanced'] == true;
        return _CheckData(
          ok: balanced, title: balanced ? 'Trial balance agrees' : 'Trial balance does not agree',
          note: balanced ? 'Debits equal credits across all accounts.' : 'Debits and credits differ — this indicates a posting bug.',
          stats: [('Debits', tshFromDouble(_n(_tb, 'total_debit'))), ('Credits', tshFromDouble(_n(_tb, 'total_credit')))],
        );
      case 4:
        final payable = _n(_vat, 'net_vat_payable');
        return _CheckData(
          ok: payable <= 0, title: payable > 0 ? 'VAT payable this period' : 'No VAT currently payable',
          note: payable > 0 ? 'Output VAT exceeds input VAT for $_period.' : 'Input VAT covers or exceeds output VAT for $_period.',
          stats: [('Output', tshFromDouble(_n(_vat, 'output_vat'))), ('Input', tshFromDouble(_n(_vat, 'input_vat'))), ('Payable', tshSigned(payable))],
        );
      case 5:
      case 6:
        final data = idx == 5 ? _ar : _ap;
        final total = _n(data, 'total_outstanding');
        final buckets = (data['buckets'] as Map?) ?? {};
        final overdue = (buckets.entries.where((e) => e.key != 'current').fold<num>(0, (s, e) => s + ((e.value as num?) ?? 0)));
        return _CheckData(
          ok: overdue == 0, title: total == 0 ? 'Nothing outstanding' : (overdue > 0 ? 'Overdue balance outstanding' : 'Outstanding but not yet overdue'),
          note: total == 0 ? (idx == 5 ? 'No outstanding receivables.' : 'No outstanding payables.') : '${tshFromDouble(overdue)} is overdue of ${tshFromDouble(total)} outstanding.',
          stats: [('Outstanding', tshFromDouble(total)), ('Overdue', tshFromDouble(overdue))],
        );
      default:
        final invAcc = ((_bs['assets'] as List? ?? [])).cast<Map>().where((a) => (a['name'] as String? ?? '').toLowerCase().contains('inventory')).toList();
        final invBal = invAcc.isNotEmpty ? ((invAcc.first['balance'] as num?) ?? 0) : 0;
        final stockVal = _n(_sv, 'total_value');
        final mismatch = stockVal > 0 && (stockVal - invBal).abs() > 0;
        return _CheckData(
          ok: !mismatch, title: mismatch ? 'Stock value not reflected on the balance sheet' : 'Stock reconciles with the ledger',
          note: mismatch
              ? '${tshFromDouble(stockVal)} of stock is held, but the ledger\'s Inventory account shows ${tshFromDouble(invBal)}.'
              : 'Stock valuation matches the ledger\'s Inventory account.',
          stats: [('Stock value', tshFromDouble(stockVal)), ('Inventory a/c', tshFromDouble(invBal)), ('Items', '${_n(_sv, 'item_count').toInt()}')],
        );
    }
  }

  // ── Computed insight card per tab (all real) ────────────────────────────────

  _InsightData _insightFor(int idx) {
    switch (idx) {
      case 0:
        final cats = (_pl['expenses_by_category'] as List? ?? []).cast<Map>();
        final totalExp = _n(_pl, 'total_expenses');
        if (cats.isEmpty || totalExp == 0) {
          return _InsightData(ok: true, kicker: 'Position', title: 'No expense breakdown yet', body: 'No expenses have been posted for $_period.');
        }
        final top = cats.reduce((a, b) => ((a['total'] as num?) ?? 0) > ((b['total'] as num?) ?? 0) ? a : b);
        final pct = totalExp == 0 ? 0 : (((top['total'] as num?) ?? 0) / totalExp * 100);
        return _InsightData(ok: pct < 50, kicker: 'Composition', title: '${top['category']} is the largest expense line',
            body: '${tshFromDouble((top['total'] as num?) ?? 0)} of ${tshFromDouble(totalExp)} total expenses (${pct.toStringAsFixed(0)}%) is ${top['category']} this period.');
      case 1:
        final assets = (_bs['assets'] as List? ?? []).cast<Map>();
        final totalAssets = _n(_bs, 'total_assets');
        if (assets.isEmpty || totalAssets == 0) return _InsightData(ok: true, kicker: 'Position', title: 'No assets recorded', body: 'No asset accounts carry a balance.');
        final top = assets.reduce((a, b) => ((a['balance'] as num?) ?? 0) > ((b['balance'] as num?) ?? 0) ? a : b);
        final pct = totalAssets == 0 ? 0 : (((top['balance'] as num?) ?? 0) / totalAssets * 100);
        return _InsightData(ok: pct < 70, kicker: 'Concentration', title: '${top['name']} holds most of total assets',
            body: '${tshFromDouble((top['balance'] as num?) ?? 0)} of ${tshFromDouble(totalAssets)} total assets (${pct.toStringAsFixed(0)}%) sits in ${top['name']}.');
      case 2:
        final net = _n(_cf, 'net_cash_flow');
        return _InsightData(ok: net >= 0, kicker: 'Liquidity', title: net >= 0 ? 'Cash position improved' : 'Cash position declined',
            body: '${tshFromDouble(_n(_cf, 'cash_in'))} in against ${tshFromDouble(_n(_cf, 'cash_out'))} out this period — a net ${net >= 0 ? 'increase' : 'decrease'} of ${tshFromDouble(net.abs())}.');
      case 3:
        final accounts = (_tb['accounts'] as List? ?? []).cast<Map>();
        final nil = accounts.where((a) => ((a['debit'] as num?) ?? 0) == 0 && ((a['credit'] as num?) ?? 0) == 0).length;
        return _InsightData(ok: true, kicker: 'Integrity', title: '$nil of ${accounts.length} accounts have never been used',
            body: 'Consider marking unused accounts inactive so reports and pickers stay short.');
      case 4:
        final expenses = (_vat['input_expenses'] as List? ?? []);
        final bills = (_vat['input_bills'] as List? ?? []);
        final inputVat = _n(_vat, 'input_vat');
        if (inputVat == 0 && (expenses.isNotEmpty || bills.isNotEmpty)) {
          return _InsightData(ok: false, kicker: 'Filing risk', title: 'No input VAT has been captured',
              body: '${expenses.length + bills.length} purchase entr${expenses.length + bills.length == 1 ? 'y carries' : 'ies carry'} a tax amount of zero — check they have a valid VAT rate before filing.');
        }
        return _InsightData(ok: true, kicker: 'Filing', title: 'VAT position for $_period',
            body: 'Output VAT ${tshFromDouble(_n(_vat, 'output_vat'))} less input VAT ${tshFromDouble(inputVat)} = ${tshSigned(_n(_vat, 'net_vat_payable'))} payable.');
      case 5:
      case 6:
        final rows = idx == 5 ? (_ar['invoices'] as List? ?? []) : (_ap['bills'] as List? ?? []);
        final nameKey = idx == 5 ? 'client_name' : 'supplier_name';
        final total = idx == 5 ? _n(_ar, 'total_outstanding') : _n(_ap, 'total_outstanding');
        if (rows.isEmpty || total == 0) {
          return _InsightData(ok: true, kicker: idx == 5 ? 'Collection' : 'Payables', title: idx == 5 ? 'Nothing owed to Hypermed' : 'Nothing owed to suppliers', body: 'No open balances in any aging bucket.');
        }
        final byParty = <String, num>{};
        for (final r in rows) { byParty[r[nameKey] as String? ?? '—'] = (byParty[r[nameKey] as String? ?? '—'] ?? 0) + ((r['balance_due'] as num?) ?? 0); }
        final topEntry = byParty.entries.reduce((a, b) => a.value > b.value ? a : b);
        final pct = total == 0 ? 0 : (topEntry.value / total * 100);
        return _InsightData(ok: pct < 60, kicker: 'Concentration', title: '${topEntry.key} holds most of the balance',
            body: '${tshFromDouble(topEntry.value)} of ${tshFromDouble(total)} outstanding (${pct.toStringAsFixed(0)}%) is with ${topEntry.key}.');
      default:
        final cats = (_sv['by_category'] as List? ?? []).cast<Map>();
        if (cats.isEmpty) return _InsightData(ok: true, kicker: 'Stock', title: 'No stock on hand', body: 'No active items carry quantity on hand.');
        final excluded = cats.length;
        return _InsightData(ok: true, kicker: 'Composition', title: '${cats.first['category']} is the largest stock category',
            body: '${cats.first['category']} accounts for the largest share of the ${tshFromDouble(_n(_sv, 'total_value'))} total stock value across $excluded categor${excluded == 1 ? 'y' : 'ies'} held.');
    }
  }

  // ── P&L ──────────────────────────────────────────────────────────────────

  Widget _plView(BuildContext context) {
    final cats = (_pl['expenses_by_category'] as List? ?? []).cast<Map>();
    final priorCats = { for (final c in (_plPrior['expenses_by_category'] as List? ?? []).cast<Map>()) c['category'] as String? ?? '': (c['total'] as num?) ?? 0 };
    num priorOf(String key) => (_plPrior[key] as num?) ?? 0;

    final rows = <_StRow>[
      _StRow.header('Revenue'),
      _StRow.line('Total revenue', v: _n(_pl, 'revenue'), prior: _compare ? priorOf('revenue') : null),
      _StRow.header('Cost of sales'),
      _StRow.line('Cost of goods sold', v: _n(_pl, 'cogs'), prior: _compare ? priorOf('cogs') : null, favorableUp: false),
      _StRow.subtotal('Gross profit', v: _n(_pl, 'gross_profit'), prior: _compare ? (priorOf('revenue') - priorOf('cogs')) : null),
      _StRow.header('Operating expenses'),
      for (final c in cats)
        _StRow.line(c['category'] as String? ?? '—', v: (c['total'] as num?) ?? 0, prior: _compare ? priorCats[c['category']] : null, favorableUp: false),
      if (cats.isEmpty) _StRow.line('No expenses posted', v: 0, muted: true),
      _StRow.subtotal('Total operating expenses', v: _n(_pl, 'total_expenses'), prior: _compare ? priorOf('total_expenses') : null, favorableUp: false),
      _StRow.total('Net profit', v: _n(_pl, 'net_profit'), prior: _compare ? priorOf('net_profit') : null),
    ];
    return _ReportCard(icon: Symbols.trending_up, title: 'Profit & Loss', sub: 'accrual basis · $_period',
        child: _StatementGrid(rows: rows, compare: _compare));
  }

  // ── Cash Flow ────────────────────────────────────────────────────────────

  Widget _cfView(BuildContext context) {
    final byMethod = (_cf['cash_in_by_method'] as List? ?? []).cast<Map>();
    num priorOf(String key) => (_cfPrior[key] as num?) ?? 0;
    final rows = <_StRow>[
      _StRow.header('Cash in'),
      for (final m in byMethod) _StRow.line('Cash in — ${m['method']}', v: (m['total'] as num?) ?? 0),
      if (byMethod.isEmpty) _StRow.line('No receipts this period', v: 0, muted: true),
      _StRow.subtotal('Total cash in', v: _n(_cf, 'cash_in'), prior: _compare ? priorOf('cash_in') : null),
      _StRow.header('Cash out'),
      _StRow.line('Expenses', v: _n(_cf, 'cash_out_expenses'), favorableUp: false),
      _StRow.line('Vendor bills', v: _n(_cf, 'cash_out_vendor_bills'), favorableUp: false),
      _StRow.subtotal('Total cash out', v: _n(_cf, 'cash_out'), prior: _compare ? priorOf('cash_out') : null, favorableUp: false),
      _StRow.total('Net cash flow', v: _n(_cf, 'net_cash_flow'), prior: _compare ? (priorOf('cash_in') - priorOf('cash_out')) : null),
    ];
    return _ReportCard(icon: Symbols.sync_alt, title: 'Cash Flow', sub: 'movement in cash and bank · $_period',
        child: _StatementGrid(rows: rows, compare: _compare));
  }

  // ── Trial Balance ────────────────────────────────────────────────────────

  Widget _tbView(BuildContext context) {
    final accounts = (_tb['accounts'] as List? ?? []).cast<Map>();
    const order = ['asset', 'liability', 'equity', 'revenue', 'expense'];
    const labels = {'asset': 'Assets', 'liability': 'Liabilities', 'equity': 'Equity', 'revenue': 'Revenue', 'expense': 'Expenses'};
    final byType = <String, List<Map>>{};
    for (final a in accounts) { (byType[a['type'] as String? ?? ''] ??= []).add(a); }

    final rows = <_StRow>[];
    for (final type in order) {
      final list = byType[type];
      if (list == null || list.isEmpty) continue;
      rows.add(_StRow.header(labels[type]!));
      var dr = 0, cr = 0;
      for (final a in list) {
        final d = (a['debit'] as num?) ?? 0, c = (a['credit'] as num?) ?? 0;
        dr += d.toInt(); cr += c.toInt();
        if (_hideNilTB && d == 0 && c == 0) continue;
        rows.add(_StRow.dc(a['name'] as String? ?? '—', code: a['code'] as String?, debit: d, credit: c, muted: d == 0 && c == 0));
      }
      rows.add(_StRow.subtotal('Subtotal', debit: dr, credit: cr));
    }
    rows.add(_StRow.total('Totals', debit: _n(_tb, 'total_debit').toInt(), credit: _n(_tb, 'total_credit').toInt()));

    return _ReportCard(icon: Symbols.list_alt, title: 'Trial Balance', sub: '${accounts.length} accounts',
        nilToggle: (_hideNilTB, () => setState(() => _hideNilTB = !_hideNilTB)),
        child: _StatementGrid(rows: rows, dcMode: true));
  }

  // ── VAT ──────────────────────────────────────────────────────────────────

  Widget _vatView(BuildContext context) {
    final outputs = (_vat['output_invoices'] as List? ?? []);
    final expenses = (_vat['input_expenses'] as List? ?? []);
    final bills = (_vat['input_bills'] as List? ?? []);
    num priorOf(String key) => (_vatPrior[key] as num?) ?? 0;

    final rows = <_StRow>[
      _StRow.header('Output tax — on sales'),
      _StRow.line('Output VAT charged', v: _n(_vat, 'output_vat'), hint: '${outputs.length} invoice(s)', prior: _compare ? priorOf('output_vat') : null),
      _StRow.subtotal('Total output VAT', v: _n(_vat, 'output_vat'), prior: _compare ? priorOf('output_vat') : null),
      _StRow.header('Input tax — on purchases'),
      _StRow.line('Expenses with VAT', v: expenses.fold<num>(0, (s, e) => s + ((e['tax_amount'] as num?) ?? 0)), hint: '${expenses.length} entries', muted: expenses.isEmpty),
      _StRow.line('Vendor bills with VAT', v: bills.fold<num>(0, (s, b) => s + ((b['tax_amount'] as num?) ?? 0)), hint: '${bills.length} entries', muted: bills.isEmpty),
      _StRow.subtotal('Total input VAT claimable', v: _n(_vat, 'input_vat'), prior: _compare ? priorOf('input_vat') : null, favorableUp: false),
      _StRow.total('Net VAT payable', v: _n(_vat, 'net_vat_payable'), prior: _compare ? priorOf('net_vat_payable') : null, favorableUp: false),
    ];
    return _ReportCard(icon: Symbols.receipt_long, title: 'VAT Return', sub: 'draft · $_period',
        child: _StatementGrid(rows: rows, compare: _compare));
  }

  // ── Balance Sheet ────────────────────────────────────────────────────────

  Widget _bsView(BuildContext context) {
    final assets = (_bs['assets'] as List? ?? []).cast<Map>();
    final liabilities = (_bs['liabilities'] as List? ?? []).cast<Map>();
    final equity = (_bs['equity'] as List? ?? []).cast<Map>();
    final balanced = _bs['balanced'] == true;

    List<_StRow> col(List<Map> items, {bool hideNil = false}) => [
      for (final a in items)
        if (!hideNil || ((a['balance'] as num?) ?? 0) != 0)
          _StRow.dc(a['name'] as String? ?? '—', code: a['code'] as String?, debit: (a['balance'] as num?)?.toInt() ?? 0, credit: 0, dcSingle: true, muted: ((a['balance'] as num?) ?? 0) == 0),
    ];

    return _ReportCard(icon: Symbols.balance, title: 'Balance Sheet', sub: 'as at ${formatDate(DateTime.now())}',
      nilToggle: (_hideNilBS, () => setState(() => _hideNilBS = !_hideNilBS)),
      trailing: _BalancedPill(balanced: balanced),
      child: LayoutBuilder(builder: (ctx, cst) {
        final twoCol = cst.maxWidth >= 560;
        final assetsPane = _StatementGrid(dcMode: true, dcSingle: true, rows: [
          _StRow.header('Assets'),
          ...col(assets, hideNil: _hideNilBS),
          _StRow.subtotal('Total assets', debit: _n(_bs, 'total_assets').toInt(), credit: 0, dcSingle: true),
        ]);
        final liabEquityPane = _StatementGrid(dcMode: true, dcSingle: true, rows: [
          _StRow.header('Liabilities'),
          if (liabilities.isEmpty) _StRow.line('No liabilities recorded', v: 0, muted: true),
          ...col(liabilities, hideNil: _hideNilBS),
          _StRow.subtotal('Total liabilities', debit: _n(_bs, 'total_liabilities').toInt(), credit: 0, dcSingle: true),
          _StRow.header('Equity'),
          ...col(equity, hideNil: _hideNilBS),
          _StRow.dc('Current period earnings (unclosed)', debit: _n(_bs, 'current_period_earnings').toInt(), credit: 0, dcSingle: true),
          _StRow.subtotal('Total liabilities & equity', debit: _n(_bs, 'total_equity').toInt() + _n(_bs, 'total_liabilities').toInt(), credit: 0, dcSingle: true),
        ]);
        return twoCol
            ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: assetsPane),
                VerticalDivider(width: 1, color: context.pal.divider),
                Expanded(child: liabEquityPane),
              ]))
            : Column(children: [assetsPane, Divider(height: 1, color: context.pal.divider), liabEquityPane]);
      }),
    );
  }

  // ── Aging (AR / AP) ──────────────────────────────────────────────────────

  Widget _agingView(BuildContext context, {required bool isAr}) {
    final data = isAr ? _ar : _ap;
    final rows = (isAr ? data['invoices'] : data['bills']) as List? ?? [];
    final buckets = (data['buckets'] as Map?) ?? {};
    const bucketOrder = ['current', 'days_1_30', 'days_31_60', 'days_61_90', 'days_90_plus'];
    const bucketLabels = {'current': 'Current', 'days_1_30': '1–30 d', 'days_31_60': '31–60 d', 'days_61_90': '61–90 d', 'days_90_plus': '90 d+'};
    final bucketColors = {'current': AppColors.teal, 'days_1_30': AppColors.amber, 'days_31_60': AppColors.coral, 'days_61_90': AppColors.violet, 'days_90_plus': AppColors.blueStrong};
    final total = _n(data, 'total_outstanding');

    return _ReportCard(icon: isAr ? Symbols.hourglass_top : Symbols.hourglass_bottom, title: isAr ? 'AR Aging' : 'AP Aging',
      sub: isAr ? 'money owed to Hypermed' : 'money Hypermed owes',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tshFromDouble(total), style: AppTheme.kpiValue.copyWith(fontSize: 26, color: total > 0 ? AppColors.amber : context.pal.text)),
            const SizedBox(height: 11),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(height: 8, child: Row(children: [
              for (final b in bucketOrder)
                if (((buckets[b] as num?) ?? 0) > 0)
                  Expanded(flex: (((buckets[b] as num?) ?? 0) * 1000 / (total == 0 ? 1 : total)).round().clamp(1, 1000), child: Container(color: bucketColors[b])),
              if (total == 0) Expanded(child: Container(color: context.pal.surface3)),
            ]))),
            const SizedBox(height: 11),
            Wrap(spacing: 16, runSpacing: 8, children: [
              for (final b in bucketOrder)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: bucketColors[b], borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 6),
                  Text('${bucketLabels[b]}  ', style: AppTheme.bodySub.copyWith(fontSize: 11)),
                  Text(tshFromDouble((buckets[b] as num?) ?? 0), style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.text)),
                ]),
            ]),
          ]),
        ),
        Divider(height: 1, color: context.pal.divider),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text(isAr ? 'No open invoices.' : 'No open vendor bills.', style: AppTheme.bodySub)))
        else
          Column(children: rows.map((r) {
            final bucketColor = bucketColors[r['bucket']] ?? context.pal.textMute;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
              child: Row(children: [
                Container(width: 3, height: 22, decoration: BoxDecoration(color: bucketColor, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${isAr ? r['invoice_number'] : r['bill_number']}', style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                  Text('${isAr ? r['client_name'] : r['supplier_name']}', style: AppTheme.bodySub.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                Text('${r['due_date']}', style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim)),
                const SizedBox(width: 14),
                SizedBox(width: 56, child: Text('${r['days_overdue']}d', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 11, color: bucketColor))),
                const SizedBox(width: 10),
                SizedBox(width: 96, child: Text(tshFromDouble((r['balance_due'] as num?) ?? 0), textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 12.5))),
              ]),
            );
          }).toList()),
      ]),
    );
  }

  // ── Stock Valuation ──────────────────────────────────────────────────────

  Widget _stockView(BuildContext context) {
    final items = (_sv['items'] as List? ?? []);
    final byCategory = (_sv['by_category'] as List? ?? []).cast<Map>();
    final totalValue = _n(_sv, 'total_value');
    final maxCat = byCategory.isEmpty ? 1.0 : byCategory.map((c) => ((c['total'] as num?) ?? 0).toDouble()).reduce((a, b) => a > b ? a : b);

    return _ReportCard(icon: Symbols.inventory_2, title: 'Stock Valuation', sub: 'as at ${formatDate(DateTime.now())}',
      child: LayoutBuilder(builder: (ctx, cst) {
        final wide = cst.maxWidth >= 640;
        final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TOTAL STOCK VALUE', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
                const SizedBox(height: 5),
                Text(tshFromDouble(totalValue), style: AppTheme.kpiValue.copyWith(fontSize: 24)),
              ]),
              const SizedBox(width: 24),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ITEMS', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
                const SizedBox(height: 5),
                Text('${_n(_sv, 'item_count').toInt()}', style: AppTheme.cardTitle.copyWith(fontSize: 16)),
              ]),
            ]),
          ),
          Divider(height: 1, color: context.pal.divider),
          if (items.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('No stock on hand.', style: AppTheme.bodySub)))
          else
            Column(children: items.map((i) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
              child: Row(children: [
                Expanded(child: Text('${i['name']}', style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                SizedBox(width: 100, child: Text('${i['sku']}', style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim), maxLines: 1, overflow: TextOverflow.ellipsis)),
                SizedBox(width: 50, child: Text('${i['qty']}', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 11))),
                SizedBox(width: 100, child: Text(tshFromDouble((i['stock_value'] as num?) ?? 0), textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 12))),
              ]),
            )).toList()),
        ]);

        final right = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 8),
            child: Text('BY CATEGORY', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Column(children: byCategory.map((c) {
              final v = ((c['total'] as num?) ?? 0).toDouble();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${c['category'] ?? 'Uncategorized'}', style: AppTheme.bodySub.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(tshFromDouble(v), style: AppTheme.monoXs.copyWith(fontSize: 11)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
                    value: maxCat == 0 ? 0 : v / maxCat, minHeight: 5, backgroundColor: context.pal.surface3,
                    valueColor: AlwaysStoppedAnimation(AppColors.blueStrong),
                  )),
                ]),
              );
            }).toList()),
          ),
        ]);

        return wide
            ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 2, child: left),
                VerticalDivider(width: 1, color: context.pal.divider),
                Expanded(child: right),
              ]))
            : Column(children: [left, Divider(height: 1, color: context.pal.divider), right]);
      }),
    );
  }
}

num _n(Map d, String k) => (d[k] as num?) ?? 0;

// ── Grouped tab bar ──────────────────────────────────────────────────────────

class _GroupedTabBar extends StatelessWidget {
  const _GroupedTabBar({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    var idx = 0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (groupLabel, tabs) in _tabDefs) ...[
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(groupLabel.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9)),
              const SizedBox(height: 6),
              Row(children: [
                for (final (label, icon) in tabs) () {
                  final myIdx = idx++;
                  return GestureDetector(
                    onTap: () => controller.animateTo(myIdx),
                    child: Container(
                      height: 32, padding: const EdgeInsets.symmetric(horizontal: 11),
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: controller.index == myIdx ? AppColors.blue.withValues(alpha: 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(children: [
                        Icon(icon, size: 14, color: controller.index == myIdx ? context.pal.text : context.pal.textMute),
                        const SizedBox(width: 7),
                        Text(label, style: AppTheme.bodySm.copyWith(fontSize: 12.5, color: controller.index == myIdx ? context.pal.text : context.pal.textMute)),
                      ]),
                    ),
                  );
                }(),
              ]),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Check strip ───────────────────────────────────────────────────────────────

class _CheckData {
  const _CheckData({required this.ok, required this.title, required this.note, required this.stats});
  final bool ok;
  final String title, note;
  final List<(String, String)> stats;
}

class _CheckStrip extends StatelessWidget {
  const _CheckStrip({required this.chk});
  final _CheckData chk;

  @override
  Widget build(BuildContext context) {
    final color = chk.ok ? AppColors.teal : AppColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), border: Border.all(color: color.withValues(alpha: 0.28)), borderRadius: BorderRadius.circular(11)),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
        // Wraps (rather than one long row) so it fits phone widths.
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 4, children: [
          Icon(chk.ok ? Symbols.check_circle : Symbols.warning, size: 16, color: color),
          Text(chk.title, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
          Text(chk.note, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
        ]),
        Wrap(runSpacing: 6, children: [
          for (final s in chk.stats) ...[
            Container(margin: const EdgeInsets.only(left: 15), padding: const EdgeInsets.only(left: 15), decoration: BoxDecoration(border: Border(left: BorderSide(color: context.pal.divider))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${s.$1}  ', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
                Text(s.$2, style: AppTheme.monoSm.copyWith(fontSize: 12)),
              ]),
            ),
          ],
        ]),
      ]),
    );
  }
}

// ── Insight card ─────────────────────────────────────────────────────────────

class _InsightData {
  const _InsightData({required this.ok, required this.kicker, required this.title, required this.body});
  final bool ok;
  final String kicker, title, body;
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});
  final _InsightData insight;

  @override
  Widget build(BuildContext context) {
    final color = insight.ok ? AppColors.teal : AppColors.amber;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), border: Border.all(color: color.withValues(alpha: 0.22)), borderRadius: BorderRadius.circular(13)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(insight.ok ? Symbols.lightbulb : Symbols.warning_amber, size: 14, color: color),
          const SizedBox(width: 8),
          Text(insight.kicker.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10, color: color)),
        ]),
        const SizedBox(height: 9),
        Text(insight.title, style: AppTheme.cardTitle.copyWith(fontSize: 15)),
        const SizedBox(height: 7),
        Text(insight.body, style: AppTheme.bodySub.copyWith(fontSize: 12, height: 1.5)),
      ]),
    );
  }
}

class _BalancedPill extends StatelessWidget {
  const _BalancedPill({required this.balanced});
  final bool balanced;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: (balanced ? AppColors.teal : AppColors.coral).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(balanced ? Symbols.check_circle : Symbols.error, size: 13, color: balanced ? AppColors.teal : AppColors.coral),
      const SizedBox(width: 5),
      Text(balanced ? 'Balanced' : 'Out of balance', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: balanced ? AppColors.teal : AppColors.coral, fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Report card chrome ───────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.icon, required this.title, required this.sub, required this.child, this.nilToggle, this.trailing});
  final IconData icon;
  final String title, sub;
  final Widget child;
  final (bool, VoidCallback)? nilToggle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(13), border: Border.all(color: context.pal.border)),
    clipBehavior: Clip.antiAlias,
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        height: 44, padding: const EdgeInsets.symmetric(horizontal: 16), color: context.pal.surface2,
        child: Row(children: [
          Icon(icon, size: 15, color: AppColors.blueStrong),
          const SizedBox(width: 10),
          Text(title, style: AppTheme.cardTitle.copyWith(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(child: Text(sub, style: AppTheme.bodySub.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (trailing != null) ...[trailing!, const SizedBox(width: 10)],
          if (nilToggle != null)
            GestureDetector(
              onTap: nilToggle!.$2,
              child: Container(
                height: 26, padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(nilToggle!.$1 ? Symbols.visibility_off : Symbols.visibility, size: 13, color: context.pal.textMute),
                  const SizedBox(width: 6),
                  Text(nilToggle!.$1 ? 'Nil hidden' : 'Nil shown', style: AppTheme.bodySub.copyWith(fontSize: 11)),
                ]),
              ),
            ),
        ]),
      ),
      child,
    ]),
  );
}

// ── Statement row model + grid ───────────────────────────────────────────────

enum _RowKind { header, line, subtotal, total }

class _StRow {
  const _StRow(this.kind, this.label, {this.code, this.v = 0, this.prior, this.debit = 0, this.credit = 0,
      this.dcSingle = false, this.hint, this.muted = false, this.favorableUp = true});
  final _RowKind kind;
  final String label;
  final String? code;
  final num v;
  final num? prior;
  final num debit, credit;
  final bool dcSingle;
  final String? hint;
  final bool muted;
  final bool favorableUp; // does an increase read as good (green) or bad (red)?

  factory _StRow.header(String label) => _StRow(_RowKind.header, label);
  factory _StRow.line(String label, {num v = 0, num? prior, String? hint, bool muted = false, bool favorableUp = true}) =>
      _StRow(_RowKind.line, label, v: v, prior: prior, hint: hint, muted: muted, favorableUp: favorableUp);
  factory _StRow.subtotal(String label, {num v = 0, num? prior, bool favorableUp = true, num debit = 0, num credit = 0, bool dcSingle = false}) =>
      _StRow(_RowKind.subtotal, label, v: v, prior: prior, favorableUp: favorableUp, debit: debit, credit: credit, dcSingle: dcSingle);
  factory _StRow.total(String label, {num v = 0, num? prior, bool favorableUp = true, num debit = 0, num credit = 0}) =>
      _StRow(_RowKind.total, label, v: v, prior: prior, favorableUp: favorableUp, debit: debit, credit: credit);
  factory _StRow.dc(String label, {String? code, num debit = 0, num credit = 0, bool dcSingle = false, bool muted = false}) =>
      _StRow(_RowKind.line, label, code: code, debit: debit, credit: credit, dcSingle: dcSingle, muted: muted);
}

class _StatementGrid extends StatelessWidget {
  const _StatementGrid({required this.rows, this.compare = false, this.dcMode = false, this.dcSingle = false});
  final List<_StRow> rows;
  final bool compare;
  final bool dcMode;   // debit/credit columns instead of value/prior
  final bool dcSingle; // single-amount dc rows (balance sheet account lists)

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      height: 30, padding: const EdgeInsets.symmetric(horizontal: 16), color: context.pal.surface2,
      child: Row(children: [
        Expanded(child: Text('ACCOUNT', style: AppTheme.labelCaps.copyWith(fontSize: 9))),
        if (dcMode && !dcSingle) ...[
          SizedBox(width: 96, child: Text('DEBIT', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9))),
          SizedBox(width: 96, child: Text('CREDIT', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9))),
        ] else if (dcMode && dcSingle) ...[
          SizedBox(width: 110, child: Text('BALANCE', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9))),
        ] else ...[
          SizedBox(width: 110, child: Text('AMOUNT', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9))),
          if (compare) SizedBox(width: 110, child: Text('CHANGE', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9))),
        ],
      ]),
    ),
    for (final r in rows) _rowWidget(context, r),
  ]);

  Widget _rowWidget(BuildContext context, _StRow r) {
    if (r.kind == _RowKind.header) {
      return Container(
        height: 30, padding: const EdgeInsets.symmetric(horizontal: 16), color: context.pal.surface2.withValues(alpha: 0.5),
        alignment: Alignment.centerLeft,
        child: Text(r.label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
      );
    }
    final isEmphasis = r.kind == _RowKind.subtotal || r.kind == _RowKind.total;
    final height = r.kind == _RowKind.total ? 48.0 : (r.kind == _RowKind.subtotal ? 38.0 : 34.0);
    final bg = r.kind == _RowKind.total ? AppColors.blue.withValues(alpha: 0.06) : (r.kind == _RowKind.subtotal ? context.pal.surface2.withValues(alpha: 0.35) : null);
    final labelStyle = isEmphasis ? AppTheme.bodyStrong.copyWith(fontSize: r.kind == _RowKind.total ? 13.5 : 12.5) : AppTheme.bodySm.copyWith(fontSize: 12.5, color: r.muted ? context.pal.textDim : context.pal.text);
    final numStyle = (isEmphasis ? AppTheme.bodyStrong : AppTheme.monoSm).copyWith(fontSize: r.kind == _RowKind.total ? 14.5 : 12.5, color: r.muted ? context.pal.textDim : context.pal.text);

    Widget amountCell(num v, {Color? color}) => Text(v == 0 && !isEmphasis ? '—' : tshFromDouble(v), style: numStyle.copyWith(color: color));

    return Container(
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(color: bg, border: Border(bottom: BorderSide(color: context.pal.divider))),
      child: Row(children: [
        Expanded(child: Row(children: [
          if (r.code != null) ...[Text(r.code!, style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)), const SizedBox(width: 9)],
          Flexible(child: Text(r.label, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (r.hint != null) ...[const SizedBox(width: 8), Text(r.hint!, style: AppTheme.bodySub.copyWith(fontSize: 10.5))],
        ])),
        if (dcMode && !dcSingle) ...[
          SizedBox(width: 96, child: Align(alignment: Alignment.centerRight, child: amountCell(r.debit))),
          SizedBox(width: 96, child: Align(alignment: Alignment.centerRight, child: amountCell(r.credit))),
        ] else if (dcMode && dcSingle) ...[
          SizedBox(width: 110, child: Align(alignment: Alignment.centerRight, child: amountCell(r.debit))),
        ] else ...[
          SizedBox(width: 110, child: Align(alignment: Alignment.centerRight, child: amountCell(r.v, color: r.kind == _RowKind.total ? (r.v >= 0 ? AppColors.teal : AppColors.coral) : null))),
          if (compare)
            SizedBox(width: 110, child: Align(alignment: Alignment.centerRight, child: r.prior == null
                ? Text('—', style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.textDim))
                : _delta(context, r.v, r.prior!, r.favorableUp))),
        ],
      ]),
    );
  }

  Widget _delta(BuildContext context, num v, num prior, bool favorableUp) {
    final diff = v - prior;
    final good = favorableUp ? diff >= 0 : diff <= 0;
    final color = diff == 0 ? context.pal.textDim : (good ? AppColors.teal : AppColors.coral);
    final pct = prior == 0 ? null : (diff / prior.abs() * 100);
    return Text(
      '${diff >= 0 ? '+' : ''}${tshFromDouble(diff)}${pct != null ? ' (${pct.toStringAsFixed(0)}%)' : ''}',
      style: AppTheme.monoXs.copyWith(fontSize: 11, color: color),
    );
  }
}
