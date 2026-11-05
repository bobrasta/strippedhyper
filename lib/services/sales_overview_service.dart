import 'api_client.dart';

int _toInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? 0;
  return 0;
}

class SalesPeriod {
  const SalesPeriod({required this.key, required this.label, required this.daysLeft});
  final String key;   // month | quarter | year
  final String label; // "Q3 2026"
  final int daysLeft;

  factory SalesPeriod.fromJson(Map<String, dynamic> j) => SalesPeriod(
    key: j['key'] as String? ?? 'quarter',
    label: j['label'] as String? ?? '',
    daysLeft: _toInt(j['days_left']),
  );
}

class SalesMonth {
  const SalesMonth({required this.label, required this.actual, required this.target, required this.projected, required this.current});
  final String label;
  final int actual, target, projected;
  final bool current;

  bool get hitTarget => target > 0 && actual >= target;

  factory SalesMonth.fromJson(Map<String, dynamic> j) => SalesMonth(
    label: j['label'] as String? ?? '',
    actual: _toInt(j['actual']),
    target: _toInt(j['target']),
    projected: _toInt(j['projected']),
    current: j['current'] == true,
  );
}

class SalesForecast {
  const SalesForecast({required this.closed, required this.commit, required this.bestCase, required this.pipeline,
      required this.target, required this.openUndated, required this.openSlipped});
  final int closed, commit, bestCase, pipeline, target, openUndated, openSlipped;

  int get forecast => closed + commit;
  int get gap => target - forecast;

  factory SalesForecast.fromJson(Map<String, dynamic> j) => SalesForecast(
    closed: _toInt(j['closed']),
    commit: _toInt(j['commit']),
    bestCase: _toInt(j['best_case']),
    pipeline: _toInt(j['pipeline']),
    target: _toInt(j['target']),
    openUndated: _toInt(j['open_undated']),
    openSlipped: _toInt(j['open_slipped']),
  );
}

class RepCommit {
  const RepCommit({required this.id, required this.name, required this.initials, required this.closed, required this.commit, required this.target});
  final int id, closed, commit, target;
  final String name, initials;

  int get pct => target > 0 ? ((closed + commit) / target * 100).round() : 0;

  factory RepCommit.fromJson(Map<String, dynamic> j) => RepCommit(
    id: _toInt(j['id']),
    name: j['name'] as String? ?? '—',
    initials: j['initials'] as String? ?? '',
    closed: _toInt(j['closed']),
    commit: _toInt(j['commit']),
    target: _toInt(j['target']),
  );
}

class ClosingDeal {
  const ClosingDeal({required this.id, required this.client, required this.machineType, required this.closeDate,
      required this.category, required this.value, this.rep});
  final int id, value;
  final String client, machineType, category; // commit | best_case | pipeline
  final DateTime? closeDate;
  final String? rep;

  factory ClosingDeal.fromJson(Map<String, dynamic> j) => ClosingDeal(
    id: _toInt(j['id']),
    client: j['client'] as String? ?? '—',
    machineType: j['machine_type'] as String? ?? '—',
    closeDate: DateTime.tryParse(j['expected_close_date'] as String? ?? ''),
    category: j['forecast_category'] as String? ?? 'pipeline',
    value: _toInt(j['value']),
    rep: j['rep'] as String?,
  );
}

class SalesFeedItem {
  const SalesFeedItem({required this.kind, required this.title, this.client, this.by, required this.at,
      required this.upcoming, this.dateOnly = false});
  // call | visit | meeting | demo | email | whatsapp | quote | won | follow_up
  final String kind;
  final String title;
  final String? client, by;
  final DateTime at;
  final bool upcoming, dateOnly;

  factory SalesFeedItem.fromJson(Map<String, dynamic> j) => SalesFeedItem(
    kind: j['kind'] as String? ?? 'call',
    title: j['title'] as String? ?? '',
    client: j['client'] as String?,
    by: j['by'] as String?,
    at: (DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now()).toLocal(),
    upcoming: j['upcoming'] == true,
    dateOnly: j['date_only'] == true,
  );
}

class ExpiringWarranty {
  const ExpiringWarranty({required this.client, required this.model, required this.type, required this.serialNo,
      required this.daysLeft, required this.openDeal});
  final String client, model, type, serialNo;
  final int daysLeft;
  final bool openDeal;

  factory ExpiringWarranty.fromJson(Map<String, dynamic> j) => ExpiringWarranty(
    client: j['client'] as String? ?? '—',
    model: j['model'] as String? ?? '',
    type: j['type'] as String? ?? '',
    serialNo: j['serial_no'] as String? ?? '',
    daysLeft: _toInt(j['days_left']),
    openDeal: j['open_deal'] == true,
  );
}

class SalesOverview {
  const SalesOverview({required this.scope, required this.period, required this.targetsSet, required this.canSetTargets,
      required this.months, required this.forecast, required this.reps, required this.deals, required this.activity,
      required this.warranties});
  final String scope;
  final SalesPeriod period;
  final bool targetsSet, canSetTargets;
  final List<SalesMonth> months;
  final SalesForecast forecast;
  final List<RepCommit> reps;
  final List<ClosingDeal> deals;
  final List<SalesFeedItem> activity;
  final List<ExpiringWarranty> warranties;

  bool get isTeam => scope == 'team';
  bool get isMasked => scope == 'own';

  factory SalesOverview.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        (j[k] as List? ?? []).map((e) => f(e as Map<String, dynamic>)).toList();
    return SalesOverview(
      scope: j['scope'] as String? ?? 'own',
      period: SalesPeriod.fromJson(j['period'] as Map<String, dynamic>? ?? {}),
      targetsSet: j['targets_set'] == true,
      canSetTargets: j['can_set_targets'] == true,
      months: list('months', SalesMonth.fromJson),
      forecast: SalesForecast.fromJson(j['forecast'] as Map<String, dynamic>? ?? {}),
      reps: list('reps', RepCommit.fromJson),
      deals: list('deals', ClosingDeal.fromJson),
      activity: list('activity', SalesFeedItem.fromJson),
      warranties: list('warranties', ExpiringWarranty.fromJson),
    );
  }
}

class RepTargets {
  RepTargets({required this.id, required this.name, required this.role, required this.months});
  final int id;
  final String name, role;
  final List<int> months; // 12 entries, Jan..Dec

  factory RepTargets.fromJson(Map<String, dynamic> j) => RepTargets(
    id: _toInt(j['id']),
    name: j['name'] as String? ?? '—',
    role: j['role'] as String? ?? '',
    months: [for (final v in (j['months'] as List? ?? List.filled(12, 0))) _toInt(v)],
  );
}

class SalesOverviewService {
  SalesOverviewService._();
  static final instance = SalesOverviewService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate cache per period — see MachineService.
  static final Map<String, SalesOverview> cached = {};

  Future<SalesOverview> load({String period = 'quarter'}) async {
    final res = await _dio.get('/dashboard/sales/overview', queryParameters: {'period': period});
    final data = SalesOverview.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cached[period] = data;
    return data;
  }

  Future<({bool canManage, List<RepTargets> reps})> targets(int year) async {
    final res = await _dio.get('/sales-targets', queryParameters: {'year': year});
    final d = ApiClient.unwrap(res) as Map<String, dynamic>;
    return (
      canManage: d['can_manage'] == true,
      reps: (d['reps'] as List? ?? []).map((e) => RepTargets.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<void> saveTargets(int year, List<RepTargets> reps) async {
    await _dio.put('/sales-targets', data: {
      'year': year,
      'targets': [
        for (final r in reps)
          for (var m = 0; m < 12; m++) {'user_id': r.id, 'month': m + 1, 'amount': r.months[m]},
      ],
    });
  }

  Future<void> logActivity({
    required String type,
    required String subject,
    required DateTime occursAt,
    int? leadId,
    String? client,
    String? note,
  }) async {
    await _dio.post('/sales-activities', data: {
      'type': type,
      'subject': subject,
      'occurs_at': occursAt.toUtc().toIso8601String(),
      'sales_lead_id': ?leadId,
      if (leadId == null && client != null && client.isNotEmpty) 'hospital_name_raw': client,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }
}
