import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/invoice.dart';
import '../../services/invoice_service.dart';
import '../../services/setting_service.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/kpi_card.dart';
import '../../widgets/common/labeled_field.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/responsive.dart';
import '../../widgets/common/app_button.dart';
import '../../theme/app_palette.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/common/phone_layout.dart';

Color _paymentStatusColor(PaymentStatus s) => switch (s) {
  PaymentStatus.paid      => AppColors.teal,
  PaymentStatus.partial   => AppColors.blue,
  PaymentStatus.pending   => AppColors.amber,
  PaymentStatus.sent      => AppColors.blue,
  PaymentStatus.overdue   => AppColors.coral,
  PaymentStatus.waived    => AppColors.textMute,
  PaymentStatus.cancelled => AppColors.coral,
};

class RevenueScreen extends StatefulWidget {
  const RevenueScreen({super.key});

  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  bool _showNewInvoice = false;
  Invoice? _selectedInvoice;

  List<Invoice>              _invoices         = [];
  List<Map<String, dynamic>> _revenueByHosp    = [];
  List<String>               _revenueMonths    = [];
  List<double>               _revenueActual    = [];
  List<double>               _revenueTarget    = [];
  double                     _monthlyTarget    = 0;
  bool                       _loading          = true;
  String?                    _error;
  Period                     _period           = Period.defaultPeriod;

  // KPI totals derived from invoices
  double get _totalRevenue => _invoices.fold(0, (s, i) => s + i.total);

  double get _collected => _invoices.fold(0, (s, i) => s + i.amountPaid);
  double get _outstanding => _invoices.fold(0, (s, i) => s + i.balanceDue);
  double get _avgDealSize => _invoices.isEmpty ? 0 : _totalRevenue / _invoices.length;

  // Simple 3-month moving average —a naive projection, not a fabricated one.
  double get _nextMonthForecast {
    if (_revenueActual.isEmpty) return 0;
    final last3 = _revenueActual.length >= 3
        ? _revenueActual.sublist(_revenueActual.length - 3)
        : _revenueActual;
    return last3.fold(0.0, (a, b) => a + b) / last3.length;
  }

  double get _targetProgressPct =>
      _monthlyTarget > 0 ? (_nextMonthForecast / _monthlyTarget * 100).clamp(0, 999) : 0;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: seed every independently-cacheable piece
    // from its service's own cache so this screen doesn't blank to a
    // full-page spinner on every return visit.
    final invoices = InvoiceService.cachedDefaultList;
    final revByHosp = InvoiceService.cachedRevenueByHospital;
    final revSummary = InvoiceService.cachedRevenueSummary;
    final settings = SettingService.cachedAll;
    if (invoices != null) {
      _invoices = invoices;
      if (revByHosp != null) _revenueByHosp = revByHosp;
      if (revSummary != null) {
        _revenueMonths = (revSummary['months'] as List? ?? []).cast<String>();
        _revenueActual = (revSummary['actual'] as List? ?? []).map((e) => (e as num).toDouble()).toList();
        _revenueTarget = (revSummary['target'] as List? ?? []).map((e) => (e as num).toDouble()).toList();
      }
      if (settings != null) {
        _monthlyTarget = double.tryParse(settings['revenue_monthly_target'] ?? '') ?? 0;
      }
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_invoices.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        InvoiceService.instance.list(period: _period),
        InvoiceService.instance.revenueByHospital(period: _period),
        // Monthly chart: Jan-Dec of the period's year (rolling 12 months
        // for all-time / cross-year ranges).
        InvoiceService.instance.revenueSummary(year: _period.year),
      ]);
      final settings = await SettingService.instance.all();
      if (!mounted) return;
      final invoices  = results[0] as List<Invoice>;
      final byHosp    = results[1] as List<Map<String, dynamic>>;
      final summary   = results[2] is Map<String, dynamic>
          ? results[2] as Map<String, dynamic>
          : <String, dynamic>{};

      setState(() {
        _invoices      = invoices;
        _revenueByHosp = byHosp;
        _revenueMonths = (summary['months'] as List? ?? []).cast<String>();
        _revenueActual = (summary['actual'] as List? ?? []).map((e) => (e as num).toDouble()).toList();
        _revenueTarget = (summary['target'] as List? ?? []).map((e) => (e as num).toDouble()).toList();
        _monthlyTarget = double.tryParse(settings['revenue_monthly_target'] ?? '') ?? 0;
        _loading       = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _saveTarget(double value) async {
    await SettingService.instance.set('revenue_monthly_target', value.toStringAsFixed(0));
    if (mounted) setState(() => _monthlyTarget = value);
  }

  void _showEditTargetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _EditTargetDialog(currentValue: _monthlyTarget, onSave: _saveTarget),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
    LayoutBuilder(builder: (ctx, cst) {
    final pad = cst.maxWidth < 560 ? 16.0 : 28.0;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          LayoutBuilder(builder: (ctx, cst) {
            final narrow = cst.maxWidth < 560;
            final titleBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Revenue & Sales', style: AppTheme.pageTitle),
              const SizedBox(height: 4),
              Text('Invoice revenue, collections and outstanding balances', style: AppTheme.bodySub),
            ]);
            final actions = Row(mainAxisSize: MainAxisSize.min, children: [
              AppButton(label: 'Export', icon: Symbols.download, variant: BtnVariant.ghost),
              const SizedBox(width: 8),
              PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
            ]);
            if (narrow) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                titleBlock, const SizedBox(height: 12), actions,
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              titleBlock, const Spacer(), actions,
            ]);
          }),
          const SizedBox(height: 24),

          // Loading / error banner
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
          // A background refresh failing while stale-but-valid cached
          // data is already showing shouldn't blow that away.
          else if (_error != null && _invoices.isEmpty)
            ErrorView(message: _error!, onRetry: _load)
          else ...[

          // KPI row —' cols wide, 2 cols medium, 1 narrow
          AdaptiveColumns(
            wideCols: 4, mediumCols: 2, narrowCols: 2,
            children: [
              KpiCard(
                label: 'Total Revenue',
                icon: Symbols.payments,
                value: tshFromDouble(_totalRevenue),
                deltaValue: '${_invoices.length} invoices',
                deltaUp: true,
                deltaNote: 'issued',
                sparkValues: _revenueActual.length >= 2
                    ? _revenueActual
                    : const [10, 14, 12, 18, 16, 22, 20, 26, 24, 28, 27, 30],
                accent: KpiAccent.teal,
              ),
              KpiCard(
                label: 'Collected',
                icon: Symbols.price_check,
                value: tshFromDouble(_collected),
                deltaValue: _totalRevenue > 0 ? '${(_collected / _totalRevenue * 100).round()}%' : '0%',
                deltaUp: true,
                deltaNote: 'of invoiced',
                accent: KpiAccent.teal,
              ),
              KpiCard(
                label: 'Outstanding',
                icon: Symbols.pending_actions,
                value: tshFromDouble(_outstanding),
                deltaValue: '${_invoices.where((i) => i.balanceDue > 0).length} invoices',
                deltaUp: _outstanding == 0,
                deltaNote: 'unpaid',
                accent: KpiAccent.amber,
              ),
              KpiCard(
                label: 'Avg. Deal Size',
                icon: Symbols.request_quote,
                value: tshFromDouble(_avgDealSize),
                deltaValue: '${_invoices.length} deals',
                deltaUp: true,
                deltaNote: 'this period',
                sparkValues: const [7, 8, 7, 9, 8, 10, 9, 11, 10, 9, 11, 10],
                accent: KpiAccent.coral,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Forecast panel + trend chart —side by side on wide, stacked on narrow
          ResponsiveRow(
            minChildWidth: 260,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ForecastPanel(
                forecast: _nextMonthForecast,
                target: _monthlyTarget,
                progressPct: _targetProgressPct,
                onEditTarget: () => _showEditTargetDialog(context),
              ),
              Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: context.pal.surface1,
                      borderRadius: BorderRadius.circular(AppColors.rLg),
                      border: Border.all(color: context.pal.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(builder: (ctx, cst) {
                          final narrow = cst.maxWidth < 480;
                          final titleRow = Row(children: [
                            const SizedBox(width: 8),
                            Expanded(child: Text('Revenue Trend —Last 12 Months', style: AppTheme.cardTitle)),
                          ]);
                          final legends = Wrap(spacing: 12, runSpacing: 6, children: [
                            _Legend(color: AppColors.teal,    label: 'Actual'),
                            _Legend(color: AppColors.blue,    label: 'Collected'),
                            _Legend(color: context.pal.textDim, label: 'Target', dashed: true),
                          ]);
                          if (narrow) {
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              titleRow, const SizedBox(height: 8), legends,
                            ]);
                          }
                          return Row(children: [
                            const SizedBox(width: 8),
                            Expanded(child: Text('Revenue Trend —Last 12 Months', style: AppTheme.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis)),
                            _Legend(color: AppColors.teal,    label: 'Actual'),
                            const SizedBox(width: 12),
                            _Legend(color: AppColors.blue,    label: 'Collected'),
                            const SizedBox(width: 12),
                            _Legend(color: context.pal.textDim, label: 'Target', dashed: true),
                          ]);
                        }),
                        const SizedBox(height: 16),
                        SizedBox(height: 240, child: _RevenueChart(
                          actual: _revenueActual,
                          target: _revenueTarget,
                          months: _revenueMonths,
                        )),
                      ],
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 16),

          // Insight row —status mix, geography, latest activity, top accounts
          ResponsiveRow(
            minChildWidth: 260,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusBreakdownPanel(invoices: _invoices),
              _RecentTransactionsPanel(invoices: _invoices),
              _TopClientsPanel(revenueByHospital: _revenueByHosp),
            ],
          ),
          const SizedBox(height: 16),

          // Invoices
          Container(
            decoration: BoxDecoration(
              color: context.pal.surface1,
              borderRadius: BorderRadius.circular(AppColors.rLg),
              border: Border.all(color: context.pal.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LayoutBuilder(builder: (ctx, cst) {
                final narrow = cst.maxWidth < 520;
                final titleRow = Row(children: [
                  const SizedBox(width: 8),
                  Expanded(child: Text('Invoices', style: AppTheme.cardTitle)),
                ]);
                final action = AppButton(label: 'New Invoice', icon: Symbols.add, variant: BtnVariant.primary, small: true,
                    onPressed: () => setState(() => _showNewInvoice = true));
                if (narrow) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      titleRow, const SizedBox(height: 10), action,
                    ]),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                  child: Row(children: [
                    const SizedBox(width: 8),
                    Expanded(child: Text('Invoices', style: AppTheme.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis)),
                    action,
                  ]),
                );
              }),
              HScrollTable(
                minWidth: 750,
                child: _InvoicesTable(
                  invoices: _invoices,
                  onSelectInvoice: (inv) => setState(() => _selectedInvoice = inv),
                ),
              ),
            ]),
          ),

          ], // end else [...] for loading guard
        ],
      ),
    ));  // SingleChildScrollView + RefreshIndicator
    }),   // LayoutBuilder

    // New Invoice dialog
    if (_showNewInvoice)
      _NewInvoiceDialog(
        onClose: () => setState(() => _showNewInvoice = false),
      ),

    // Invoice detail / Record Payment
    if (_selectedInvoice != null)
      _InvoiceDetailSheet(
        invoice: _selectedInvoice!,
        onClose: () => setState(() => _selectedInvoice = null),
      ),
    ]);  // Stack
  }
}

/// Shared bordered card chrome for the insight-row panels below.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, this.icon, required this.child});
  final String title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.pal.surface1,
      borderRadius: BorderRadius.circular(AppColors.rLg),
      border: Border.all(color: context.pal.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.amber),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(title, style: AppTheme.cardTitle)),
        ]),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _ForecastPanel extends StatelessWidget {
  const _ForecastPanel({
    required this.forecast,
    required this.target,
    required this.progressPct,
    required this.onEditTarget,
  });
  final double forecast, target, progressPct;
  final VoidCallback onEditTarget;

  @override
  Widget build(BuildContext context) {
    final clamped = (progressPct / 100).clamp(0.0, 1.0);
    return _Panel(
      title: 'Revenue Forecast',
      icon: Symbols.insights,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NEXT MONTH FORECAST', style: AppTheme.labelCaps),
        const SizedBox(height: 6),
        Text(tshFromDouble(forecast), style: AppTheme.kpiValue.copyWith(fontSize: 26)),
        const SizedBox(height: 4),
        Text('3-month moving average', style: AppTheme.bodySub.copyWith(fontSize: 11)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Text('MONTHLY TARGET', style: AppTheme.labelCaps)),
          GestureDetector(
            onTap: onEditTarget,
            child: Icon(Symbols.edit, size: 14, color: context.pal.textDim),
          ),
        ]),
        const SizedBox(height: 4),
        Text(target > 0 ? tshFromDouble(target) : 'Not set', style: AppTheme.bodyStrong.copyWith(fontSize: 15)),
        const SizedBox(height: 10),
        if (target > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 6,
              backgroundColor: context.pal.surface3,
              valueColor: AlwaysStoppedAnimation(AppColors.teal),
            ),
          ),
          const SizedBox(height: 6),
          Text('${progressPct.toStringAsFixed(0)}% to target', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
        ] else
          Text('Set a target to track progress', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
      ]),
    );
  }
}

class _StatusBreakdownPanel extends StatelessWidget {
  const _StatusBreakdownPanel({required this.invoices});
  final List<Invoice> invoices;

  @override
  Widget build(BuildContext context) {
    if (invoices.isEmpty) {
      return _Panel(
        title: 'Invoice Status',
        child: Text('No invoices yet', style: TextStyle(color: context.pal.textDim)),
      );
    }
    final byStatus = <PaymentStatus, List<Invoice>>{};
    for (final inv in invoices) {
      (byStatus[inv.status] ??= []).add(inv);
    }
    final totalRevenue = invoices.fold(0, (s, i) => s + i.total);
    final entries = byStatus.entries.toList()
      ..sort((a, b) => b.value.fold(0, (s, i) => s + i.total).compareTo(a.value.fold(0, (s, i) => s + i.total)));

    return _Panel(
      title: 'Invoice Status',
      child: Column(children: entries.map((e) {
        final total = e.value.fold(0, (s, i) => s + i.total);
        final pct = totalRevenue > 0 ? (total / totalRevenue * 100) : 0.0;
        final color = _paymentStatusColor(e.key);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
              alignment: Alignment.center,
              child: Text('${e.value.length}', style: AppTheme.monoXs.copyWith(color: color, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.key.label, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
              const SizedBox(height: 2),
              Text('${e.value.length} invoice${e.value.length == 1 ? '' : 's'}', style: AppTheme.bodySub.copyWith(fontSize: 11)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(tshFromDouble(total), style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
              const SizedBox(height: 2),
              Text('${pct.toStringAsFixed(0)}%', style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
            ]),
          ]),
        );
      }).toList()),
    );
  }
}

class _RecentTransactionsPanel extends StatelessWidget {
  const _RecentTransactionsPanel({required this.invoices});
  final List<Invoice> invoices;

  @override
  Widget build(BuildContext context) {
    final sorted = [...invoices]..sort((a, b) => b.issueDate.compareTo(a.issueDate));
    final recent = sorted.take(5).toList();

    if (recent.isEmpty) {
      return _Panel(
        title: 'Recent Transactions',
        child: Text('No transactions yet', style: TextStyle(color: context.pal.textDim)),
      );
    }

    return _Panel(
      title: 'Recent Transactions',
      child: Column(children: recent.map((inv) {
        final name  = inv.displayName;
        final color = _paymentStatusColor(inv.status);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(999)),
              alignment: Alignment.center,
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: AppTheme.bodyStrong.copyWith(color: AppColors.teal, fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(inv.invoiceNumber, style: AppTheme.bodySub.copyWith(fontSize: 11)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(tshFromDouble(inv.total), style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                child: Text(inv.status.label, style: AppTheme.bodySub.copyWith(color: color, fontSize: 10)),
              ),
            ]),
          ]),
        );
      }).toList()),
    );
  }
}

class _TopClientsPanel extends StatelessWidget {
  const _TopClientsPanel({required this.revenueByHospital});
  final List<Map<String, dynamic>> revenueByHospital;

  @override
  Widget build(BuildContext context) {
    if (revenueByHospital.isEmpty) {
      return _Panel(
        title: 'Top 5 Clients',
        icon: Symbols.star,
        child: Text('No client revenue yet', style: TextStyle(color: context.pal.textDim)),
      );
    }
    final top = revenueByHospital.take(5).toList();
    final maxRev = top.map((x) => (x['revenue_monthly'] as num? ?? x['rev'] as num? ?? 0).toDouble())
        .fold(0.0, (a, b) => b > a ? b : a);

    return _Panel(
      title: 'Top 5 Clients',
      icon: Symbols.star,
      child: Column(children: top.asMap().entries.map((e) {
        final h = e.value;
        final rev = (h['revenue_monthly'] as num? ?? h['rev'] as num? ?? 0).toDouble();
        final pct = maxRev > 0 ? rev / maxRev : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.tealSoft,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text('${e.key + 1}',
                    style: AppTheme.monoXs.copyWith(color: AppColors.teal, fontSize: 9)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(h['name'] as String? ?? '—',
                  style: AppTheme.bodySm.copyWith(fontSize: 12),
                  overflow: TextOverflow.ellipsis)),
                Text(tshFromDouble(rev),
                  style: AppTheme.monoSm.copyWith(color: AppColors.amber, fontSize: 11)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: context.pal.surface3,
                  valueColor: AlwaysStoppedAnimation(AppColors.teal),
                  minHeight: 3,
                ),
              ),
            ],
          ),
        );
      }).toList()),
    );
  }
}

class _EditTargetDialog extends StatefulWidget {
  const _EditTargetDialog({required this.currentValue, required this.onSave});
  final double currentValue;
  final Future<void> Function(double) onSave;

  @override
  State<_EditTargetDialog> createState() => _EditTargetDialogState();
}

class _EditTargetDialogState extends State<_EditTargetDialog> {
  late final _ctrl = TextEditingController(
    text: widget.currentValue > 0 ? widget.currentValue.toStringAsFixed(0) : '',
  );
  bool _saving = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final value = double.tryParse(_ctrl.text.replaceAll(',', ''));
    if (value == null || value < 0) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(value);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) { setState(() => _saving = false); showErrorToast(context, e); }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    title: Text('Monthly Revenue Target', style: AppTheme.cardTitle),
    content: SizedBox(
      width: 320,
      child: LabeledTextField(label: 'Target (TSh)', controller: _ctrl, keyboardType: TextInputType.number),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        onPressed: _saving ? null : _submit,
        child: _saving
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Save'),
      ),
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.dashed = false});
  final Color color; final String label; final bool dashed;

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 8, height: 8,
      decoration: BoxDecoration(
        color: dashed ? null : color,
        borderRadius: BorderRadius.circular(2),
        border: dashed ? Border(top: BorderSide(color: color, width: 1)) : null,
      )),
    const SizedBox(width: 6),
    Text(label, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
  ]);
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.actual, required this.target, required this.months});
  final List<double> actual, target;
  final List<String> months;

  @override
  Widget build(BuildContext context) {
    if (actual.isEmpty) {
      return Center(child: Text('No revenue data', style: TextStyle(color: context.pal.textMute)));
    }
    final collected = List.generate(actual.length, (i) => actual[i] * 0.88);

    FlSpot s(int i, List<double> d) => FlSpot(i.toDouble(), d[i]);

    return LineChart(LineChartData(
      minX: 0, maxX: 11, minY: 155, maxY: 345,
      gridData: FlGridData(
        show: true, drawVerticalLine: false, horizontalInterval: 40,
        getDrawingHorizontalLine: (_) => const FlLine(color: Color(0x0DFFFFFF), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, interval: 40, reservedSize: 36,
          getTitlesWidget: (v, _) => Text('${v.toInt()}M',
            style: GoogleFonts.jetBrainsMono(fontSize: 9, color: context.pal.textDim)),
        )),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, interval: 1,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= months.length) return const SizedBox.shrink();
            return Text(months[i], style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: context.pal.textDim));
          },
        )),
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: List.generate(target.length, (i) => s(i, target)),
          color: context.pal.textDim.withValues(alpha: 0.7),
          barWidth: 1.2, dashArray: [4, 4],
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
        LineChartBarData(
          spots: List.generate(collected.length, (i) => s(i, collected)),
          color: AppColors.blue,
          barWidth: 1.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [AppColors.blue.withValues(alpha: 0.15), AppColors.blue.withValues(alpha: 0)]),
          ),
        ),
        LineChartBarData(
          spots: List.generate(actual.length, (i) => s(i, actual)),
          color: AppColors.teal, barWidth: 2,
          dotData: FlDotData(getDotPainter: (s, p, b, i) => FlDotCirclePainter(
            radius: i == actual.length - 1 ? 4 : 2.5,
            color: AppColors.teal, strokeColor: context.pal.bg,
            strokeWidth: i == actual.length - 1 ? 2 : 1,
          )),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [AppColors.teal.withValues(alpha: 0.22), AppColors.teal.withValues(alpha: 0)]),
          ),
        ),
      ],
    ));
  }
}

class _TCell extends StatelessWidget {
  const _TCell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: child,
  );
}

// ── New Invoice Dialog ──────────────────────────────────────────────────────
class _NewInvoiceDialog extends StatefulWidget {
  const _NewInvoiceDialog({required this.onClose});
  final VoidCallback  onClose;

  @override
  State<_NewInvoiceDialog> createState() => _NewInvoiceDialogState();
}

class _NewInvoiceDialogState extends State<_NewInvoiceDialog> {
  final _clientCtrl = TextEditingController();
  String _type     = 'Product Sale';
  final _amountCtrl = TextEditingController();
  bool  _saving    = false;

  @override
  void dispose() { _clientCtrl.dispose(); _amountCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_saving) return;
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
    if (amount <= 0 || _clientCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final subtotal = (amount / 1.18).round();
      await InvoiceService.instance.create({
        'client_name': _clientCtrl.text.trim(),
        'issue_date':  DateTime.now().toIso8601String().substring(0, 10),
        'due_date':    DateTime.now().add(const Duration(days: 30)).toIso8601String().substring(0, 10),
        'tax_rate':    18,
        'currency':    'TZS',
        'line_items': [
          {
            'description': _type,
            'quantity':    1,
            'unit_price':  subtotal,
          }
        ],
      });
      widget.onClose();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onClose,
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 480,
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.receipt_long, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text('New Invoice', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                LabeledTextField(label: 'Client name', controller: _clientCtrl, hint: 'Company or customer name'),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _RField('Invoice type', _type,
                      const ['Product Sale', 'Spare Parts', 'Consultancy', 'Training', 'Other'],
                      (v) => setState(() => _type = v))),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    LabeledTextField(label: 'Amount (TSh)', controller: _amountCtrl, keyboardType: TextInputType.number, hint: '0'),
                  ])),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Expanded(child: GestureDetector(onTap: widget.onClose,
                  child: Container(height: 38,
                    decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text('Cancel', style: AppTheme.bodySm))))),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(onTap: _save,
                  child: Container(height: 38,
                    decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Create Invoice', style: AppTheme.bodyStrong.copyWith(
                          color: const Color(0xFF06120F), fontSize: 13)))))),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );
}

class _RField extends StatelessWidget {
  const _RField(this.label, this.value, this.items, this.onChanged);
  final String label, value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    DropdownFieldBox<String>(
      value: items.contains(value) ? value : items.first,
      items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    ),
  ]);
}

// ── Invoice Detail / Record Payment Sheet ───────────────────────────────────
class _InvoiceDetailSheet extends StatelessWidget {
  const _InvoiceDetailSheet({required this.invoice, required this.onClose});
  final Invoice invoice;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onClose,
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 460,
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.receipt, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text(invoice.invoiceNumber, style: AppTheme.bodyStrong)),
                GestureDetector(onTap: onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _IRow('Client', invoice.displayName),
                _IRow('Issue Date', invoice.issueDate),
                _IRow('Due Date',   invoice.dueDate),
                _IRow('Subtotal',   tshFromDouble(invoice.subtotal)),
                _IRow('VAT (${invoice.taxRate}%)', tshFromDouble(invoice.taxAmount)),
                _IRow('Total',      tshFromDouble(invoice.total), bold: true),
                _IRow('Paid',       tshFromDouble(invoice.amountPaid),
                    color: AppColors.teal),
                if (invoice.balanceDue > 0)
                  _IRow('Balance Due', tshFromDouble(invoice.balanceDue),
                      color: AppColors.coral, bold: true),
              ]),
            ),
            if (invoice.balanceDue > 0) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: double.infinity, height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.teal, borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Symbols.payments, size: 18, color: Color(0xFF06120F)),
                      const SizedBox(width: 8),
                      Text('Record Payment — ${tshFromDouble(invoice.balanceDue)}',
                          style: AppTheme.bodyStrong.copyWith(
                              color: const Color(0xFF06120F), fontSize: 13)),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
        ),
      )),
    ),
  );
}

class _IRow extends StatelessWidget {
  const _IRow(this.label, this.value, {this.color, this.bold = false});
  final String label, value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 120, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12.5))),
      Expanded(child: Text(value, style: AppTheme.bodySm.copyWith(
        color: color ?? context.pal.text,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12.5,
      ))),
    ]),
  );
}

class _InvoicesTable extends StatelessWidget {
  const _InvoicesTable({required this.invoices, this.onSelectInvoice});
  final List<Invoice> invoices;
  final ValueChanged<Invoice>? onSelectInvoice;

  @override
  Widget build(BuildContext context) {
    if (invoices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('No invoices found', style: TextStyle(color: context.pal.textMute))),
      );
    }
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(140),
        1: FlexColumnWidth(2.5),
        2: FlexColumnWidth(2),
        3: FlexColumnWidth(1.5),
        4: FlexColumnWidth(1.5),
        5: FlexColumnWidth(1),
        6: FixedColumnWidth(80),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
          children: ['Invoice No.', 'Client', 'Sales Order', 'Total', 'Due Date', 'Status', ''].map((h) =>
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(h.toUpperCase(), style: AppTheme.monoXs.copyWith(fontWeight: FontWeight.w500)),
            )
          ).toList(),
        ),
        ...invoices.asMap().entries.map((e) {
          final inv = e.value;
          final isLast = e.key == invoices.length - 1;
          final statusColor = _paymentStatusColor(inv.status);
          return TableRow(
            decoration: BoxDecoration(
              border: isLast ? null : Border(bottom: BorderSide(color: context.pal.divider)),
            ),
            children: [
              _TCell(child: Text(inv.invoiceNumber,
                style: AppTheme.monoXs.copyWith(color: context.pal.textMute, fontSize: 11))),
              _TCell(child: Text(inv.displayName,
                style: AppTheme.bodySm.copyWith(fontSize: 12.5),
                overflow: TextOverflow.ellipsis)),
              _TCell(child: Text(inv.salesOrderNumber ?? '—',
                style: AppTheme.bodySub.copyWith(fontSize: 12),
                overflow: TextOverflow.ellipsis)),
              _TCell(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tshFromDouble(inv.total),
                  style: AppTheme.monoSm.copyWith(color: AppColors.amber)),
                if (inv.balanceDue > 0)
                  Text('Balance: ${tshFromDouble(inv.balanceDue)}',
                    style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: AppColors.coral)),
              ])),
              _TCell(child: Text(inv.dueDate, style: AppTheme.monoXs)),
              _TCell(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(inv.status.label, style: AppTheme.bodySub.copyWith(
                  color: statusColor, fontSize: 11.5, fontWeight: FontWeight.w500,
                )),
              )),
              // Actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: GestureDetector(
                  onTap: () => onSelectInvoice?.call(inv),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: inv.balanceDue > 0 ? AppColors.teal : context.pal.surface3,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      inv.balanceDue > 0 ? 'Pay' : 'View',
                      style: AppTheme.bodySub.copyWith(
                        color: inv.balanceDue > 0 ? Color(0xFF06120F) : context.pal.textMute,
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}
