import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/admin_overview.dart';
import '../../services/admin_overview_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/kpi_card.dart';

// Postgres COALESCE(SUM(...))/COUNT(...) columns come back through PDO as
// strings, not numbers, whenever they're forwarded to JSON raw (e.g.
// DashboardController::buildSales()'s pipeline_by_stage) instead of being
// explicitly (int)/(float) cast in PHP first — unlike this screen's KPI
// fields, which already get that cast server-side. Handles both shapes.
double _numField(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

String _humanizeStage(String stage) =>
    stage.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

/// Admin/Director-only "Command Centre": the cross-department exception
/// feed plus compact per-department panels (sales, finance, inventory,
/// people). Fed by GET /dashboard/admin-overview.
class AdminCommandCentreScreen extends StatefulWidget {
  const AdminCommandCentreScreen({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;

  @override
  State<AdminCommandCentreScreen> createState() => _AdminCommandCentreScreenState();
}

class _AdminCommandCentreScreenState extends State<AdminCommandCentreScreen> {
  AdminOverview? _overview;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final o = await AdminOverviewService.instance.load();
      if (mounted) setState(() => _overview = o);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Widget _mainRow(AdminOverview o) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Expanded(flex: 7, child: _AttentionPanel(items: o.attention)),
    const SizedBox(width: 12),
    Expanded(
      flex: 5,
      child: Column(children: [
        Expanded(child: _InventoryMiniPanel(inventory: o.inventory)),
        const SizedBox(height: 12),
        Expanded(child: _PeopleMiniPanel(people: o.people)),
      ]),
    ),
  ]);

  Widget _bottomRow(AdminOverview o) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Expanded(child: _SalesMiniPanel(sales: o.sales)),
    const SizedBox(width: 12),
    Expanded(child: _FinanceMiniPanel(finance: o.finance)),
  ]);

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final o = _overview;
    if (o == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));

    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 900 ? 16.0 : 28.0;
      final narrow = cst.maxWidth < 1100;
      final phone = cst.maxWidth < 600;

      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Header(greeting: o.greeting, onRefresh: _load),
            const SizedBox(height: 16),
            _kpiRow(o),
            const SizedBox(height: 16),
            if (narrow) ...[
              SizedBox(height: 340, child: _AttentionPanel(items: o.attention)),
              const SizedBox(height: 16),
              SizedBox(height: 170, child: _InventoryMiniPanel(inventory: o.inventory)),
              const SizedBox(height: 16),
              SizedBox(height: 170, child: _PeopleMiniPanel(people: o.people)),
            ] else
              SizedBox(height: 400, child: _mainRow(o)),
            const SizedBox(height: 16),
            // Phones: the department panels stacked, each full width.
            if (phone) ...[
              SizedBox(height: 300, child: _SalesMiniPanel(sales: o.sales)),
              const SizedBox(height: 16),
              SizedBox(height: 300, child: _FinanceMiniPanel(finance: o.finance)),
            ] else
              SizedBox(height: 340, child: _bottomRow(o)),
          ]),
        ),
      );
    });
  }
}

Widget _kpiRow(AdminOverview o) => LayoutBuilder(builder: (ctx, cst) {
  final kpis = o.kpis;
  final openLeads = ((o.sales['kpi'] as Map?)?.cast<String, dynamic>()['open_leads'] as num? ?? 0).toInt();
  final lowStock = (o.inventory['low_stock_count'] as num? ?? 0).toInt();
  final pending = (o.people['pending_approvals'] as num? ?? 0).toInt();
  final cash = (kpis['cash_position'] as num? ?? 0).toDouble();

  final tiles = [
    KpiCard(
      label: 'Cash Position', icon: Symbols.account_balance_wallet,
      value: tshSigned(cash),
      accent: cash >= 0 ? KpiAccent.teal : KpiAccent.coral,
      deltaValue: cash >= 0 ? 'profit' : 'loss',
      deltaUp: cash >= 0, deltaNote: 'this month',
    ),
    KpiCard(
      label: 'Pipeline', icon: Symbols.trending_up, value: tshFromDouble((kpis['pipeline_value'] as num? ?? 0).toDouble()),
      deltaValue: '$openLeads open', deltaUp: true, deltaNote: 'active deals',
    ),
    KpiCard(
      label: 'Stock Value', icon: Symbols.inventory_2,
      value: tshFromDouble((o.inventory['total_stock_value'] as num? ?? 0).toDouble()),
      deltaValue: '${o.inventory['total_items'] ?? 0}', deltaUp: true, deltaNote: 'items',
    ),
    KpiCard(
      label: 'Low Stock', icon: Symbols.production_quantity_limits, value: '$lowStock',
      accent: lowStock > 0 ? KpiAccent.amber : KpiAccent.teal,
      deltaValue: '${o.inventory['open_purchase_orders'] ?? 0}', deltaUp: lowStock == 0, deltaNote: 'open POs',
    ),
    KpiCard(
      label: 'Pending Approvals', icon: Symbols.fact_check, value: '$pending',
      accent: pending > 0 ? KpiAccent.amber : KpiAccent.teal,
      deltaValue: pending > 0 ? 'waiting' : 'clear', deltaUp: pending == 0, deltaNote: 'across departments',
    ),
  ];
  final cols = cst.maxWidth < 480 ? 2 : (cst.maxWidth < 900 ? 3 : 5);
  return Wrap(
    spacing: 10, runSpacing: 10,
    children: tiles.map((t) => SizedBox(width: (cst.maxWidth - (cols - 1) * 10) / cols, child: t)).toList(),
  );
});

class _Header extends StatelessWidget {
  const _Header({required this.greeting, this.onRefresh});
  final AdminGreeting greeting;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final salutation = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Container(width: 2, height: 34, color: AppColors.teal),
      const SizedBox(width: 11),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$salutation, ${greeting.name}', style: AppTheme.pageTitle),
          const SizedBox(height: 3),
          Text(greeting.date, style: AppTheme.bodySub),
        ]),
      ),
      if (onRefresh != null)
        IconButton(
          icon: const Icon(Symbols.refresh, size: 18),
          tooltip: 'Refresh',
          onPressed: onRefresh,
        ),
    ]);
  }
}

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({required this.items});
  final List<AttentionItem> items;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      header: Row(children: [
        Icon(Symbols.warning, size: 15, color: AppColors.coral),
        const SizedBox(width: 8),
        Text('Needs You Today', style: AppTheme.cardTitle),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(5)),
          child: Text('${items.length}', style: AppTheme.monoXs.copyWith(color: AppColors.coral, fontSize: 10)),
        ),
      ]),
      expandChild: true,
      child: items.isEmpty
          ? Center(child: Text('Nothing needs attention right now.', style: TextStyle(color: context.pal.textMute, fontSize: 12)))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: context.pal.divider),
              itemBuilder: (_, i) {
                final a = items[i];
                final color = switch (a.severity) {
                  'critical' => AppColors.coral,
                  'warning'  => AppColors.amber,
                  _          => AppColors.violet,
                };
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 3, height: 26, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 9),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.title, style: AppTheme.bodySm.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(a.meta, style: AppTheme.bodySub.copyWith(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ])),
                    if (a.age != null) ...[
                      const SizedBox(width: 6),
                      Text(a.age!, style: AppTheme.monoXs.copyWith(color: color, fontSize: 10)),
                    ],
                    const SizedBox(width: 4),
                    Icon(Symbols.chevron_right, size: 14, color: context.pal.textDim),
                  ]),
                );
              },
            ),
    );
  }
}


class _SalesMiniPanel extends StatelessWidget {
  const _SalesMiniPanel({required this.sales});
  final Map<String, dynamic> sales;

  @override
  Widget build(BuildContext context) {
    final kpi = (sales['kpi'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawStages = (sales['pipeline_by_stage'] as List? ?? []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    // Backend groups by stage with no fixed order (Postgres GROUP BY order
    // is arbitrary) — sort into the real funnel sequence rather than
    // whatever order rows happened to come back in.
    const funnelOrder = ['lead', 'qualified', 'demo_scheduled', 'proposal_sent', 'negotiation'];
    final stages = [...rawStages]..sort((a, b) =>
        funnelOrder.indexOf(a['stage']).compareTo(funnelOrder.indexOf(b['stage'])));
    final maxVal = stages.isEmpty ? 1.0 : stages.map((s) => _numField(s['value'])).reduce((a, b) => a > b ? a : b);
    final quotesOpen = (kpi['quotes_open_value'] as num? ?? 0).toDouble();
    final collectedPct = (kpi['collected_pct'] as num? ?? 0).toInt();
    final stalled = (kpi['deals_stalled_90d'] as num? ?? 0).toInt();
    // Dropping the "TSh" prefix here specifically — at this card's actual
    // width the full "TSh 268.0M" pushed past the header and overflowed;
    // the bare figure plus the "pipeline" label next to it still reads fine.
    final pipelineValue = tshFromDouble((kpi['pipeline_value'] as num? ?? 0).toDouble()).replaceFirst('TSh ', '');
    return AppCard(
      header: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Icon(Symbols.trending_up, size: 14, color: AppColors.violet),
        const SizedBox(width: 8),
        Expanded(child: Text('Sales', style: AppTheme.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis)),
        Text(pipelineValue, style: AppTheme.monoXs.copyWith(fontSize: 12)),
        const SizedBox(width: 4),
        Text('pipeline', style: AppTheme.bodySub.copyWith(fontSize: 10)),
      ]),
      expandChild: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ListView(
            children: stages.map((s) {
              final v = _numField(s['value']);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 84, child: Text(_humanizeStage('${s['stage'] ?? ''}'), style: AppTheme.bodySub.copyWith(fontSize: 10.5), overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: v / maxVal, backgroundColor: context.pal.border,
                      valueColor: AlwaysStoppedAnimation(AppColors.violet), minHeight: 5, borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 56, child: Text(tshFromDouble(v), style: AppTheme.monoXs.copyWith(fontSize: 10.5), textAlign: TextAlign.right)),
                ]),
              );
            }).toList(),
          ),
        ),
        Divider(height: 16, color: context.pal.divider),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _miniStat('Quotes Open', tshFromDouble(quotesOpen)),
          _miniStat('Collected', '$collectedPct%', valueColor: AppColors.teal),
          if (stalled > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(6)),
              child: Text('$stalled deals stalled 90d+', style: AppTheme.monoXs.copyWith(color: AppColors.coral, fontSize: 9.5)),
            ),
        ]),
      ]),
    );
  }

  Widget _miniStat(String label, String value, {Color? valueColor}) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Builder(builder: (context) => Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
      const SizedBox(height: 2),
      Text(value, style: AppTheme.cardTitle.copyWith(fontSize: 16, color: valueColor)),
    ]),
  );
}

class _FinanceMiniPanel extends StatelessWidget {
  const _FinanceMiniPanel({required this.finance});
  final Map<String, dynamic> finance;

  @override
  Widget build(BuildContext context) {
    final months = (finance['months'] as List? ?? []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    final last = months.isEmpty ? const {} : months.last;
    final maxVal = months.isEmpty ? 1.0 : months.expand((m) => [
      (m['revenue'] as num? ?? 0).toDouble(), (m['expenses'] as num? ?? 0).toDouble(),
    ]).fold(1.0, (a, b) => b > a ? b : a);
    final net = (last['net_profit'] as num? ?? 0).toDouble();
    return AppCard(
      header: Row(children: [
        Icon(Symbols.account_balance, size: 14, color: AppColors.cyan),
        const SizedBox(width: 8),
        Text('Finance', style: AppTheme.cardTitle),
      ]),
      expandChild: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _miniStat('Revenue MTD', tshFromDouble((last['revenue'] as num? ?? 0).toDouble())),
          _miniStat('Expenses', tshFromDouble((last['expenses'] as num? ?? 0).toDouble())),
          _miniStat('Net Result', tshSigned(net), valueColor: net < 0 ? AppColors.coral : null),
        ]),
        const SizedBox(height: 10),
        // Bars were hardcoded to a 34px cap regardless of how much room the
        // card actually had — LayoutBuilder lets them use the real space.
        Expanded(
          child: LayoutBuilder(builder: (ctx, cst) {
            final barMax = (cst.maxHeight - 16).clamp(8.0, double.infinity);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: months.map((m) {
                final rev = (m['revenue'] as num? ?? 0).toDouble();
                final exp = (m['expenses'] as num? ?? 0).toDouble();
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(children: [
                      Expanded(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(width: 5, height: (rev / maxVal * barMax).clamp(1, barMax), color: AppColors.cyan),
                          const SizedBox(width: 2),
                          Container(width: 5, height: (exp / maxVal * barMax).clamp(1, barMax), color: AppColors.coral),
                        ]),
                      ),
                      const SizedBox(height: 3),
                      Text('${m['label'] ?? ''}', style: AppTheme.monoXs.copyWith(fontSize: 8.5), textAlign: TextAlign.center),
                    ]),
                  ),
                );
              }).toList(),
            );
          }),
        ),
      ]),
    );
  }

  Widget _miniStat(String label, String value, {Color? valueColor}) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Builder(builder: (context) => Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
      const SizedBox(height: 2),
      Text(value, style: AppTheme.cardTitle.copyWith(fontSize: 18, color: valueColor)),
    ]),
  );
}

class _InventoryMiniPanel extends StatelessWidget {
  const _InventoryMiniPanel({required this.inventory});
  final Map<String, dynamic> inventory;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      header: Row(children: [
        Icon(Symbols.inventory_2, size: 14, color: AppColors.amber),
        const SizedBox(width: 8),
        Expanded(child: Text('Inventory', style: AppTheme.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis)),
        Text(tshFromDouble((inventory['total_stock_value'] as num? ?? 0).toDouble()), style: AppTheme.monoXs),
      ]),
      padding: const EdgeInsets.fromLTRB(13, 8, 13, 10),
      expandChild: true,
      child: Center(
        child: Row(children: [
          _stat('${inventory['total_items'] ?? 0}', 'Items'),
          _stat('${inventory['low_stock_count'] ?? 0}', 'Low Stock', color: AppColors.amber),
          _stat('${inventory['open_purchase_orders'] ?? 0}', 'Open POs'),
        ]),
      ),
    );
  }

  Widget _stat(String value, String label, {Color? color}) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: AppTheme.cardTitle.copyWith(fontSize: 26, color: color)),
      const SizedBox(height: 3),
      Builder(builder: (context) => Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5))),
    ]),
  );
}

class _PeopleMiniPanel extends StatelessWidget {
  const _PeopleMiniPanel({required this.people});
  final Map<String, dynamic> people;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      header: Row(children: [
        Icon(Symbols.badge, size: 14, color: AppColors.teal),
        const SizedBox(width: 8),
        Text('People', style: AppTheme.cardTitle),
      ]),
      padding: const EdgeInsets.fromLTRB(13, 8, 13, 10),
      expandChild: true,
      child: Center(
        child: Row(children: [
          _stat('${people['active_staff'] ?? 0}', 'Active Staff'),
          _stat('${people['on_leave_today'] ?? 0}', 'On Leave'),
          _stat('${people['pending_approvals'] ?? 0}', 'Approvals', color: AppColors.violet),
        ]),
      ),
    );
  }

  Widget _stat(String value, String label, {Color? color}) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: AppTheme.cardTitle.copyWith(fontSize: 26, color: color)),
      const SizedBox(height: 3),
      Builder(builder: (context) => Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5))),
    ]),
  );
}
