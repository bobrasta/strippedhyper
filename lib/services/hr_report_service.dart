import 'package:dio/dio.dart';
import 'api_client.dart';

class HrTurnoverReport {
  final int year;
  final int departedCount;
  final int headcount;
  final double turnoverRate;

  const HrTurnoverReport({
    required this.year, required this.departedCount,
    required this.headcount, required this.turnoverRate,
  });

  factory HrTurnoverReport.fromJson(Map<String, dynamic> j) => HrTurnoverReport(
    year:          (j['year'] as num).toInt(),
    departedCount: (j['departed_count'] as num).toInt(),
    headcount:     (j['headcount'] as num).toInt(),
    turnoverRate:  (j['turnover_rate'] as num).toDouble(),
  );
}

class OrgChartEntry {
  final int id;
  final String name;
  final String role;
  final String? positionTitle;
  final int? managerId;
  final String? managerName;

  const OrgChartEntry({
    required this.id, required this.name, required this.role,
    this.positionTitle, this.managerId, this.managerName,
  });

  factory OrgChartEntry.fromJson(Map<String, dynamic> j) => OrgChartEntry(
    id:            (j['id'] as num).toInt(),
    name:          j['name'] as String,
    role:          j['role'] as String? ?? '—',
    positionTitle: j['position_title'] as String?,
    managerId:     (j['manager_id'] as num?)?.toInt(),
    managerName:   j['manager_name'] as String?,
  );
}

class HeadcountBreakdown {
  final int total;
  final Map<String, int> byDepartment;
  final Map<String, int> byPosition;
  final Map<String, int> byGender;
  final Map<String, int> byLocation;

  const HeadcountBreakdown({
    required this.total, required this.byDepartment, required this.byPosition,
    required this.byGender, required this.byLocation,
  });

  static Map<String, int> _m(dynamic raw) =>
      (raw as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt()));

  factory HeadcountBreakdown.fromJson(Map<String, dynamic> j) => HeadcountBreakdown(
    total:        (j['total'] as num).toInt(),
    byDepartment: _m(j['by_department']),
    byPosition:   _m(j['by_position']),
    byGender:     _m(j['by_gender']),
    byLocation:   _m(j['by_location']),
  );
}

class StaffDirectoryEntry {
  final String name;
  final String? email;
  final String? phone;
  final String role;
  final String? positionTitle;
  final String? gender;
  final String? hireDate;
  final String? zone;
  final String? nssfNumber;
  final String? tinNumber;
  final String? nidaNumber;

  const StaffDirectoryEntry({
    required this.name, this.email, this.phone, required this.role,
    this.positionTitle, this.gender, this.hireDate, this.zone,
    this.nssfNumber, this.tinNumber, this.nidaNumber,
  });

  factory StaffDirectoryEntry.fromJson(Map<String, dynamic> j) => StaffDirectoryEntry(
    name: j['name'] as String, email: j['email'] as String?, phone: j['phone'] as String?,
    role: j['role'] as String? ?? '—', positionTitle: j['position_title'] as String?,
    gender: j['gender'] as String?, hireDate: j['hire_date'] as String?, zone: j['zone'] as String?,
    nssfNumber: j['nssf_number'] as String?, tinNumber: j['tin_number'] as String?,
    nidaNumber: j['nida_number'] as String?,
  );
}

class HrLeaveBalanceRow {
  final String userName;
  final String leaveTypeLabel;
  final double allocatedDays;
  final double usedDays;
  final double remainingDays;
  final double utilizationPct;

  const HrLeaveBalanceRow({
    required this.userName, required this.leaveTypeLabel, required this.allocatedDays,
    required this.usedDays, required this.remainingDays, required this.utilizationPct,
  });

  factory HrLeaveBalanceRow.fromJson(Map<String, dynamic> j) => HrLeaveBalanceRow(
    userName:       j['user_name'] as String? ?? '—',
    leaveTypeLabel: j['leave_type_label'] as String? ?? '—',
    allocatedDays:  (j['allocated_days'] as num).toDouble(),
    usedDays:       (j['used_days'] as num).toDouble(),
    remainingDays:  (j['remaining_days'] as num).toDouble(),
    utilizationPct: (j['utilization_pct'] as num).toDouble(),
  );
}

class LeaveCalendarEntry {
  final String userName;
  final String leaveTypeLabel;
  final String startDate;
  final String endDate;

  const LeaveCalendarEntry({
    required this.userName, required this.leaveTypeLabel,
    required this.startDate, required this.endDate,
  });

  factory LeaveCalendarEntry.fromJson(Map<String, dynamic> j) => LeaveCalendarEntry(
    userName: j['user_name'] as String? ?? '—',
    leaveTypeLabel: j['leave_type_label'] as String? ?? '—',
    startDate: j['start_date'] as String? ?? '—',
    endDate: j['end_date'] as String? ?? '—',
  );
}

class VacancyPipelineEntry {
  final int vacancyId;
  final String? positionTitle;
  final int daysOpen;
  final int totalApplications;
  final Map<String, int> byStage;

  const VacancyPipelineEntry({
    required this.vacancyId, this.positionTitle, required this.daysOpen,
    required this.totalApplications, required this.byStage,
  });

  factory VacancyPipelineEntry.fromJson(Map<String, dynamic> j) => VacancyPipelineEntry(
    vacancyId: (j['vacancy_id'] as num).toInt(),
    positionTitle: j['position_title'] as String?,
    daysOpen: (j['days_open'] as num).toInt(),
    totalApplications: (j['total_applications'] as num).toInt(),
    byStage: (j['by_stage'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
  );
}

class RecruitmentSummary {
  final int openVacancies;
  final List<VacancyPipelineEntry> pipeline;
  final int talentPoolCount;
  final Map<String, int> hiresBySource;

  const RecruitmentSummary({
    required this.openVacancies, required this.pipeline,
    required this.talentPoolCount, required this.hiresBySource,
  });

  factory RecruitmentSummary.fromJson(Map<String, dynamic> j) => RecruitmentSummary(
    openVacancies: (j['open_vacancies'] as num).toInt(),
    pipeline: (j['pipeline'] as List<dynamic>? ?? [])
        .map((p) => VacancyPipelineEntry.fromJson(p as Map<String, dynamic>)).toList(),
    talentPoolCount: (j['talent_pool_count'] as num).toInt(),
    hiresBySource: (j['hires_by_source'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
  );
}

class ContractExpiringEntry {
  final String userName;
  final String contractType;
  final String endDate;
  final int daysRemaining;

  const ContractExpiringEntry({
    required this.userName, required this.contractType,
    required this.endDate, required this.daysRemaining,
  });

  factory ContractExpiringEntry.fromJson(Map<String, dynamic> j) => ContractExpiringEntry(
    userName: j['user_name'] as String? ?? '—',
    contractType: j['contract_type'] as String? ?? '—',
    endDate: j['end_date'] as String? ?? '—',
    daysRemaining: (j['days_remaining'] as num).toInt(),
  );
}

class RepeatOffenderEntry {
  final String userName;
  final int caseCount;
  const RepeatOffenderEntry({required this.userName, required this.caseCount});
  factory RepeatOffenderEntry.fromJson(Map<String, dynamic> j) => RepeatOffenderEntry(
    userName: j['user_name'] as String? ?? '—',
    caseCount: (j['case_count'] as num).toInt(),
  );
}

class DisciplinarySummary {
  final int activeCount;
  final Map<String, int> byStage;
  final List<RepeatOffenderEntry> repeatOffenders;

  const DisciplinarySummary({required this.activeCount, required this.byStage, required this.repeatOffenders});

  factory DisciplinarySummary.fromJson(Map<String, dynamic> j) => DisciplinarySummary(
    activeCount: (j['active_count'] as num).toInt(),
    byStage: (j['by_stage'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
    repeatOffenders: (j['repeat_offenders'] as List<dynamic>? ?? [])
        .map((r) => RepeatOffenderEntry.fromJson(r as Map<String, dynamic>)).toList(),
  );
}

class CareerProgressionEntry {
  final String? userName;
  final String? fromPosition;
  final String? toPosition;
  final String changeType;
  final String effectiveDate;

  const CareerProgressionEntry({
    this.userName, this.fromPosition, this.toPosition,
    required this.changeType, required this.effectiveDate,
  });

  factory CareerProgressionEntry.fromJson(Map<String, dynamic> j) => CareerProgressionEntry(
    userName: j['user_name'] as String?, fromPosition: j['from_position'] as String?,
    toPosition: j['to_position'] as String?, changeType: j['change_type'] as String? ?? '—',
    effectiveDate: j['effective_date'] as String? ?? '—',
  );
}

class ContractsSummary {
  final int activeCount;
  final Map<String, int> byType;
  const ContractsSummary({required this.activeCount, required this.byType});
  factory ContractsSummary.fromJson(Map<String, dynamic> j) => ContractsSummary(
    activeCount: (j['active_count'] as num).toInt(),
    byType: (j['by_type'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
  );
}

class HrReportService {
  HrReportService._();
  static final instance = HrReportService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see InventoryService for the full
  // reasoning. Each report is cached under the exact parameter shape the
  // HR dashboard/reports/leave-calendar screens actually call it with —
  // most of these reports take no filter at all, so a single slot per
  // report covers every caller.
  static HeadcountBreakdown? cachedHeadcount;
  static HrTurnoverReport? cachedTurnover; // turnover() — no year filter
  static List<HrLeaveBalanceRow>? cachedDefaultLeaveBalances; // leaveBalances() — no year
  static final Map<int, List<HrLeaveBalanceRow>> cachedLeaveBalancesByYear = {};
  static final Map<String, List<LeaveCalendarEntry>> cachedLeaveCalendarByRange = {}; // '$start|$end'
  static RecruitmentSummary? cachedRecruitmentSummary;
  static final Map<int, List<ContractExpiringEntry>> cachedContractsExpiringByDays = {};
  static ContractsSummary? cachedContractsSummary;
  static DisciplinarySummary? cachedDisciplinarySummary;
  static List<CareerProgressionEntry>? cachedCareerProgressions;

  Future<HrTurnoverReport> turnover({int? year}) async {
    final res = await _dio.get('/hr-reports/turnover', queryParameters: {'year': ?year});
    final report = HrTurnoverReport.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    if (year == null) cachedTurnover = report;
    return report;
  }

  Future<List<OrgChartEntry>> orgChart() async {
    final res = await _dio.get('/hr-reports/org-chart');
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((j) => OrgChartEntry.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<HeadcountBreakdown> headcount() async {
    final res = await _dio.get('/hr-reports/headcount');
    final breakdown = HeadcountBreakdown.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedHeadcount = breakdown;
    return breakdown;
  }

  Future<List<StaffDirectoryEntry>> staffDirectory() async {
    final res = await _dio.get('/hr-reports/staff-directory');
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((j) => StaffDirectoryEntry.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<List<HrLeaveBalanceRow>> leaveBalances({int? year}) async {
    final res = await _dio.get('/hr-reports/leave-balances', queryParameters: {'year': ?year});
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => HrLeaveBalanceRow.fromJson(j as Map<String, dynamic>)).toList();
    if (year == null) {
      cachedDefaultLeaveBalances = list;
    } else {
      cachedLeaveBalancesByYear[year] = list;
    }
    return list;
  }

  Future<List<LeaveCalendarEntry>> leaveCalendar({String? start, String? end}) async {
    final res = await _dio.get('/hr-reports/leave-calendar', queryParameters: {'start': ?start, 'end': ?end});
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => LeaveCalendarEntry.fromJson(j as Map<String, dynamic>)).toList();
    cachedLeaveCalendarByRange['${start ?? ''}|${end ?? ''}'] = list;
    return list;
  }

  Future<RecruitmentSummary> recruitmentSummary() async {
    final res = await _dio.get('/hr-reports/recruitment-summary');
    final summary = RecruitmentSummary.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedRecruitmentSummary = summary;
    return summary;
  }

  Future<List<ContractExpiringEntry>> contractsExpiring({int withinDays = 90}) async {
    final res = await _dio.get('/hr-reports/contracts-expiring', queryParameters: {'within_days': withinDays});
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => ContractExpiringEntry.fromJson(j as Map<String, dynamic>)).toList();
    cachedContractsExpiringByDays[withinDays] = list;
    return list;
  }

  Future<ContractsSummary> contractsSummary() async {
    final res = await _dio.get('/hr-reports/contracts-summary');
    final summary = ContractsSummary.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedContractsSummary = summary;
    return summary;
  }

  Future<DisciplinarySummary> disciplinarySummary() async {
    final res = await _dio.get('/hr-reports/disciplinary-summary');
    final summary = DisciplinarySummary.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedDisciplinarySummary = summary;
    return summary;
  }

  Future<List<CareerProgressionEntry>> careerProgressions() async {
    final res = await _dio.get('/hr-reports/career-progressions');
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => CareerProgressionEntry.fromJson(j as Map<String, dynamic>)).toList();
    cachedCareerProgressions = list;
    return list;
  }

  Future<String> exportPdfLink() async {
    final res = await _dio.get('/hr-reports/export-pdf-link');
    final data = ApiClient.unwrap(res) as Map<String, dynamic>;
    return data['url'] as String;
  }

  /// Fetches the report PDF through the signed link (no auth header
  /// needed) so it can be shown in the in-app preview.
  Future<List<int>> exportPdfBytes() async {
    final url = await exportPdfLink();
    final res = await Dio().get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }
}
