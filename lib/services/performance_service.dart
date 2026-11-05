import 'api_client.dart';

class TaskStats {
  const TaskStats({required this.completed, required this.pending, required this.overdue});
  final int completed;
  final int pending;
  final int overdue;

  factory TaskStats.fromJson(Map<String, dynamic> j) => TaskStats(
    completed: (j['completed'] as num? ?? 0).toInt(),
    pending: (j['pending'] as num? ?? 0).toInt(),
    overdue: (j['overdue'] as num? ?? 0).toInt(),
  );
}

class LeadStageBand {
  const LeadStageBand({required this.stage, required this.count, required this.value, required this.pct});
  final String stage;
  final int count;
  final int value;
  final int pct;

  factory LeadStageBand.fromJson(Map<String, dynamic> j) => LeadStageBand(
    stage: j['stage'] as String? ?? '',
    count: (j['count'] as num? ?? 0).toInt(),
    value: (j['value'] as num? ?? 0).toInt(),
    pct: (j['pct'] as num? ?? 0).toInt(),
  );
}

class QuoteMonth {
  const QuoteMonth({required this.name, required this.sent, required this.accepted});
  final String name;
  final int sent;
  final int accepted;

  factory QuoteMonth.fromJson(Map<String, dynamic> j) => QuoteMonth(
    name: j['name'] as String? ?? '',
    sent: (j['sent'] as num? ?? 0).toInt(),
    accepted: (j['accepted'] as num? ?? 0).toInt(),
  );
}

class MySalesPerformance {
  const MySalesPerformance({
    required this.pipelineValue, required this.openLeads, required this.leadsByStage,
    required this.quotationsSentThisMonth, required this.quotationsAcceptedThisMonth,
    required this.monthlyChart, required this.acceptRate, required this.commissionMtd,
    this.dealsWonAllTime = 0, this.accountsServed = 0,
  });
  final int pipelineValue;
  final int openLeads;
  final List<LeadStageBand> leadsByStage;
  final int quotationsSentThisMonth;
  final int quotationsAcceptedThisMonth;
  final List<QuoteMonth> monthlyChart;
  final int acceptRate;
  final int commissionMtd;
  // Career totals — used by the profile page's header stat strip.
  final int dealsWonAllTime;
  final int accountsServed;

  factory MySalesPerformance.fromJson(Map<String, dynamic> j) => MySalesPerformance(
    pipelineValue: (j['pipeline_value'] as num? ?? 0).toInt(),
    openLeads: (j['open_leads'] as num? ?? 0).toInt(),
    leadsByStage: (j['leads_by_stage'] as List? ?? []).map((e) => LeadStageBand.fromJson(e as Map<String, dynamic>)).toList(),
    quotationsSentThisMonth: (j['quotations_sent_this_month'] as num? ?? 0).toInt(),
    quotationsAcceptedThisMonth: (j['quotations_accepted_this_month'] as num? ?? 0).toInt(),
    monthlyChart: (j['monthly_chart'] as List? ?? []).map((e) => QuoteMonth.fromJson(e as Map<String, dynamic>)).toList(),
    acceptRate: (j['accept_rate'] as num? ?? 0).toInt(),
    commissionMtd: (j['commission_mtd'] as num? ?? 0).toInt(),
    dealsWonAllTime: (j['deals_won_all_time'] as num? ?? 0).toInt(),
    accountsServed: (j['accounts_served'] as num? ?? 0).toInt(),
  );
}

/// One tile of the profile header's role-specific stat strip.
class ProfileStat {
  const ProfileStat({required this.value, required this.label, this.isMoney = false, this.highlight = false});
  final int value;
  final String label;
  final bool isMoney;
  final bool highlight;

  factory ProfileStat.fromJson(Map<String, dynamic> j) => ProfileStat(
    value: (j['value'] as num? ?? 0).toInt(),
    label: j['label'] as String? ?? '',
    isMoney: j['format'] == 'money',
    highlight: j['highlight'] == true,
  );
}

class MyPerformance {
  const MyPerformance({required this.period, required this.tasks, this.sales, this.profileStats});
  final String period;
  final TaskStats tasks;
  final MySalesPerformance? sales;
  // Null on a backend that predates role-based profile stats.
  final List<ProfileStat>? profileStats;

  factory MyPerformance.fromJson(Map<String, dynamic> j) => MyPerformance(
    period: j['period'] as String? ?? '',
    tasks: TaskStats.fromJson(j['tasks'] as Map<String, dynamic>? ?? {}),
    sales: j['sales'] != null ? MySalesPerformance.fromJson(j['sales'] as Map<String, dynamic>) : null,
    profileStats: (j['profile_stats'] as List?)
        ?.map((e) => ProfileStat.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class RevenueMonth {
  const RevenueMonth({required this.name, required this.actual});
  final String name;
  final int actual;

  factory RevenueMonth.fromJson(Map<String, dynamic> j) => RevenueMonth(
    name: j['name'] as String? ?? '',
    actual: (j['actual'] as num? ?? 0).toInt(),
  );
}

class HospitalRevenue {
  const HospitalRevenue({required this.name, required this.value, required this.pct});
  final String name;
  final int value;
  final int pct;

  factory HospitalRevenue.fromJson(Map<String, dynamic> j) => HospitalRevenue(
    name: j['name'] as String? ?? '',
    value: (j['value'] as num? ?? 0).toInt(),
    pct: (j['pct'] as num? ?? 0).toInt(),
  );
}

class LeaderboardRep {
  const LeaderboardRep({
    required this.id, required this.name, this.zone, required this.initials,
    required this.won, required this.revenue, required this.commissionOwed,
  });
  final int id;
  final String name;
  final String? zone;
  final String initials;
  final int won;
  final int revenue;
  final int commissionOwed;

  factory LeaderboardRep.fromJson(Map<String, dynamic> j) => LeaderboardRep(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String? ?? '—',
    zone: j['zone'] as String?,
    initials: j['initials'] as String? ?? '?',
    won: (j['won'] as num? ?? 0).toInt(),
    revenue: (j['revenue'] as num? ?? 0).toInt(),
    commissionOwed: (j['commission_owed'] as num? ?? 0).toInt(),
  );
}

class TeamPerformance {
  const TeamPerformance({
    required this.period, required this.repsCount, required this.revenueMtd,
    required this.teamPipeline, required this.awaitingMyApproval, required this.commissionOwed,
    required this.receivableOverdue, required this.revenueByMonth, required this.ytdActual,
    required this.revenueByHospital, required this.leaderboard,
  });
  final String period;
  final int repsCount;
  final int revenueMtd;
  final int teamPipeline;
  final int awaitingMyApproval;
  final int commissionOwed;
  final int receivableOverdue;
  final List<RevenueMonth> revenueByMonth;
  final int ytdActual;
  final List<HospitalRevenue> revenueByHospital;
  final List<LeaderboardRep> leaderboard;

  factory TeamPerformance.fromJson(Map<String, dynamic> j) {
    final kpi = j['kpis'] as Map<String, dynamic>? ?? {};
    return TeamPerformance(
      period: j['period'] as String? ?? '',
      repsCount: (j['reps_count'] as num? ?? 0).toInt(),
      revenueMtd: (kpi['revenue_mtd'] as num? ?? 0).toInt(),
      teamPipeline: (kpi['team_pipeline'] as num? ?? 0).toInt(),
      awaitingMyApproval: (kpi['awaiting_my_approval'] as num? ?? 0).toInt(),
      commissionOwed: (kpi['commission_owed'] as num? ?? 0).toInt(),
      receivableOverdue: (kpi['receivable_overdue'] as num? ?? 0).toInt(),
      revenueByMonth: (j['revenue_by_month'] as List? ?? []).map((e) => RevenueMonth.fromJson(e as Map<String, dynamic>)).toList(),
      ytdActual: (j['ytd_actual'] as num? ?? 0).toInt(),
      revenueByHospital: (j['revenue_by_hospital'] as List? ?? []).map((e) => HospitalRevenue.fromJson(e as Map<String, dynamic>)).toList(),
      leaderboard: (j['leaderboard'] as List? ?? []).map((e) => LeaderboardRep.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class PerformanceService {
  PerformanceService._();
  static final instance = PerformanceService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning.
  static MyPerformance? cachedMine;
  static TeamPerformance? cachedTeam;

  Future<MyPerformance> mine() async {
    final res = await _dio.get('/performance/mine');
    final perf = MyPerformance.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedMine = perf;
    return perf;
  }

  Future<TeamPerformance> team() async {
    final res = await _dio.get('/performance/team');
    final perf = TeamPerformance.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedTeam = perf;
    return perf;
  }
}
