import '../models/quotation.dart';
import '../models/sales_order.dart';
import 'api_client.dart';

int _toInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? 0;
  return 0;
}

class SalesPipelineStage {
  const SalesPipelineStage({required this.stage, required this.count, required this.value});
  final String stage;
  final int count;
  final int value;

  factory SalesPipelineStage.fromJson(Map<String, dynamic> j) => SalesPipelineStage(
    stage: j['stage'] as String? ?? '—',
    count: _toInt(j['count']),
    value: _toInt(j['value']),
  );

  String get stageLabel => const {
    'lead':           'Lead',
    'qualified':      'Qualified',
    'demo_scheduled': 'Demo Scheduled',
    'proposal_sent':  'Proposal Sent',
    'negotiation':    'Negotiation',
  }[stage] ?? stage;
}

class SalesRep {
  const SalesRep({required this.repId, required this.repName, required this.dealCount, required this.totalValue});
  final int repId;
  final String repName;
  final int dealCount;
  final int totalValue;

  factory SalesRep.fromJson(Map<String, dynamic> j) => SalesRep(
    repId: _toInt(j['rep_id']),
    repName: j['rep_name'] as String? ?? '—',
    dealCount: _toInt(j['deal_count']),
    totalValue: _toInt(j['total_value']),
  );
}

class SalesDashboardData {
  const SalesDashboardData({
    required this.pipelineValue,
    required this.openLeads,
    required this.wonThisMonth,
    required this.wonValueThisMonth,
    required this.winRateThisMonth,
    required this.quotationsPendingApproval,
    required this.quotationsAwaitingResponse,
    required this.salesOrdersThisMonth,
    required this.revenueThisMonth,
    required this.pipelineByStage,
    required this.topReps,
    required this.recentQuotations,
    required this.recentOrders,
    this.scope = 'team',
  });

  // 'team' (sales.view_full_numbers — sales_manager+) shows exact,
  // company-wide figures and the rep leaderboard. 'own' (plain 'sales' role)
  // scopes every figure to this user's own leads/quotations/orders and
  // rounds currency KPIs to the nearest 100K — topReps arrives empty in
  // that case, never masked, since a rep isn't shown teammates' numbers at
  // any resolution.
  final String scope;
  bool get isMasked => scope == 'own';

  final int pipelineValue;
  final int openLeads;
  final int wonThisMonth;
  final int wonValueThisMonth;
  final double winRateThisMonth;
  final int quotationsPendingApproval;
  final int quotationsAwaitingResponse;
  final int salesOrdersThisMonth;
  final int revenueThisMonth;
  final List<SalesPipelineStage> pipelineByStage;
  final List<SalesRep> topReps;
  final List<Quotation> recentQuotations;
  final List<SalesOrder> recentOrders;

  factory SalesDashboardData.fromJson(Map<String, dynamic> j) {
    final kpi = j['kpi'] as Map<String, dynamic>? ?? {};
    return SalesDashboardData(
      pipelineValue:              _toInt(kpi['pipeline_value']),
      openLeads:                  _toInt(kpi['open_leads']),
      wonThisMonth:               _toInt(kpi['won_this_month']),
      wonValueThisMonth:          _toInt(kpi['won_value_this_month']),
      winRateThisMonth:           (kpi['win_rate_this_month'] as num? ?? 0).toDouble(),
      quotationsPendingApproval:  _toInt(kpi['quotations_pending_approval']),
      quotationsAwaitingResponse: _toInt(kpi['quotations_awaiting_response']),
      salesOrdersThisMonth:       _toInt(kpi['sales_orders_this_month']),
      revenueThisMonth:           _toInt(kpi['revenue_this_month']),
      pipelineByStage: (j['pipeline_by_stage'] as List? ?? [])
          .map((e) => SalesPipelineStage.fromJson(e as Map<String, dynamic>)).toList(),
      topReps: (j['top_reps'] as List? ?? [])
          .map((e) => SalesRep.fromJson(e as Map<String, dynamic>)).toList(),
      recentQuotations: (j['recent_quotations'] as List? ?? [])
          .map((e) => Quotation.fromJson(e as Map<String, dynamic>)).toList(),
      recentOrders: (j['recent_orders'] as List? ?? [])
          .map((e) => SalesOrder.fromJson(e as Map<String, dynamic>)).toList(),
      scope: j['scope'] as String? ?? 'team',
    );
  }
}

class SalesDashboardService {
  SalesDashboardService._();
  static final instance = SalesDashboardService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. A single-object fetch, so one cached instance (no by-id map
  // needed), mirroring InvoiceService.cachedRevenueSummary.
  static SalesDashboardData? cachedData;

  Future<SalesDashboardData> load() async {
    final res = await _dio.get('/dashboard/sales');
    final data = SalesDashboardData.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedData = data;
    return data;
  }
}
