import 'package:dio/dio.dart';
import 'api_client.dart';

class PayrollItem {
  final int id;
  final int payrollRunId;
  final int userId;
  final String? userName;
  final int baseSalary;
  final int allowancesTotal;
  final int overtimeAmount;
  final int payeAmount;
  final int nssfAmount;
  final int? nssfEmployerAmount;
  /// Company-paid health insurance premium — an employer cost, not deducted.
  final int healthInsuranceEmployer;
  final int heslbAmount;
  final int otherDeductions;
  final int grossPay;
  final int netPay;
  final String? notes;

  const PayrollItem({
    required this.id, required this.payrollRunId, required this.userId, this.userName,
    required this.baseSalary, required this.allowancesTotal, required this.overtimeAmount,
    required this.payeAmount, required this.nssfAmount, this.nssfEmployerAmount, this.healthInsuranceEmployer = 0, required this.heslbAmount,
    required this.otherDeductions, required this.grossPay, required this.netPay, this.notes,
  });

  factory PayrollItem.fromJson(Map<String, dynamic> j) => PayrollItem(
    id: (j['id'] as num).toInt(),
    payrollRunId: (j['payroll_run_id'] as num).toInt(),
    userId: (j['user_id'] as num).toInt(),
    userName: j['user_name'] as String?,
    baseSalary: (j['base_salary'] as num).toInt(),
    allowancesTotal: (j['allowances_total'] as num).toInt(),
    overtimeAmount: (j['overtime_amount'] as num).toInt(),
    payeAmount: (j['paye_amount'] as num).toInt(),
    nssfAmount: (j['nssf_amount'] as num).toInt(),
    nssfEmployerAmount: (j['nssf_employer_amount'] as num?)?.toInt(),
    healthInsuranceEmployer: (j['health_insurance_employer'] as num?)?.toInt() ?? 0,
    heslbAmount: (j['heslb_amount'] as num).toInt(),
    otherDeductions: (j['other_deductions'] as num).toInt(),
    grossPay: (j['gross_pay'] as num).toInt(),
    netPay: (j['net_pay'] as num).toInt(),
    notes: j['notes'] as String?,
  );
}

class PayrollRun {
  final int id;
  final int periodMonth;
  final int periodYear;
  final String status;
  final int grossTotal;
  final int deductionsTotal;
  final int netTotal;
  final int? itemsCount;
  final List<PayrollItem> items;
  final String? createdByName;
  final String? approvedByName;
  final String? approvedAt;
  final String? paidAt;

  const PayrollRun({
    required this.id, required this.periodMonth, required this.periodYear, required this.status,
    required this.grossTotal, required this.deductionsTotal, required this.netTotal,
    this.itemsCount, this.items = const [], this.createdByName, this.approvedByName,
    this.approvedAt, this.paidAt, this.healthInsuranceTotal = 0, this.staffWithoutSalary = const [],
    this.placeholderSalaries = 0,
  });
  /// Lines whose salary is still the flat placeholder, to be set before paying.
  final int placeholderSalaries;
  /// Company-paid health insurance for the run (set on approval).
  final int healthInsuranceTotal;
  /// Active staff with no salary on record — not on the run until their pay is imported.
  final List<({int id, String name})> staffWithoutSalary;

  factory PayrollRun.fromJson(Map<String, dynamic> j) => PayrollRun(
    id: (j['id'] as num).toInt(),
    periodMonth: (j['period_month'] as num).toInt(),
    periodYear: (j['period_year'] as num).toInt(),
    status: j['status'] as String,
    grossTotal: (j['gross_total'] as num?)?.toInt() ?? 0,
    deductionsTotal: (j['deductions_total'] as num?)?.toInt() ?? 0,
    netTotal: (j['net_total'] as num?)?.toInt() ?? 0,
    itemsCount: (j['items_count'] as num?)?.toInt(),
    items: (j['items'] as List<dynamic>? ?? []).map((i) => PayrollItem.fromJson(i as Map<String, dynamic>)).toList(),
    createdByName: j['created_by_name'] as String?,
    approvedByName: j['approved_by_name'] as String?,
    approvedAt: j['approved_at'] as String?,
    paidAt: j['paid_at'] as String?,
    healthInsuranceTotal: (j['health_insurance_total'] as num?)?.toInt() ?? 0,
    placeholderSalaries: (j['placeholder_salaries'] as num?)?.toInt() ?? 0,
    staffWithoutSalary: [
      for (final s in (j['staff_without_salary'] as List? ?? []))
        (id: ((s as Map)['id'] as num).toInt(), name: s['name'] as String? ?? '—'),
    ],
  );
}

class SalaryAdjustment {
  final int id;
  final int userId;
  final int? previousSalary;
  final int newSalary;
  final String? reason;
  final String effectiveDate;
  final String status;
  final String? approvedByName;
  final String? approvedAt;
  final String? createdByName;

  const SalaryAdjustment({
    required this.id, required this.userId, this.previousSalary, required this.newSalary,
    this.reason, required this.effectiveDate, this.status = 'pending',
    this.approvedByName, this.approvedAt, this.createdByName,
  });

  factory SalaryAdjustment.fromJson(Map<String, dynamic> j) => SalaryAdjustment(
    id: (j['id'] as num).toInt(),
    userId: (j['user_id'] as num).toInt(),
    previousSalary: (j['previous_salary'] as num?)?.toInt(),
    newSalary: (j['new_salary'] as num).toInt(),
    reason: j['reason'] as String?,
    effectiveDate: j['effective_date'] as String,
    status: j['status'] as String? ?? 'pending',
    approvedByName: j['approved_by_name'] as String?,
    approvedAt: j['approved_at'] as String?,
    createdByName: j['created_by_name'] as String?,
  );
}

class PayrollHistoryItem {
  final int id;
  final int periodMonth;
  final int periodYear;
  final String status;
  final int baseSalary;
  final int allowancesTotal;
  final int overtimeAmount;
  final int payeAmount;
  final int nssfAmount;
  final int heslbAmount;
  final int otherDeductions;
  final int grossPay;
  final int netPay;
  final String? paidAt;
  // Employer-side NSSF contribution — new field, may not exist in every
  // backend deployment yet; null (not fabricated) when the server omits it.
  final int? nssfEmployerAmount;

  const PayrollHistoryItem({
    required this.id, required this.periodMonth, required this.periodYear, required this.status,
    required this.baseSalary, required this.allowancesTotal, required this.overtimeAmount,
    required this.payeAmount, required this.nssfAmount, required this.heslbAmount,
    required this.otherDeductions, required this.grossPay, required this.netPay, this.paidAt,
    this.nssfEmployerAmount,
  });

  factory PayrollHistoryItem.fromJson(Map<String, dynamic> j) => PayrollHistoryItem(
    id: (j['id'] as num).toInt(),
    periodMonth: (j['period_month'] as num).toInt(),
    periodYear: (j['period_year'] as num).toInt(),
    status: j['status'] as String,
    baseSalary: (j['base_salary'] as num).toInt(),
    allowancesTotal: (j['allowances_total'] as num).toInt(),
    overtimeAmount: (j['overtime_amount'] as num).toInt(),
    payeAmount: (j['paye_amount'] as num).toInt(),
    nssfAmount: (j['nssf_amount'] as num).toInt(),
    heslbAmount: (j['heslb_amount'] as num).toInt(),
    otherDeductions: (j['other_deductions'] as num).toInt(),
    grossPay: (j['gross_pay'] as num).toInt(),
    netPay: (j['net_pay'] as num).toInt(),
    paidAt: j['paid_at'] as String?,
    nssfEmployerAmount: (j['nssf_employer_amount'] as num?)?.toInt(),
  );
}

class EligibleStaffOption {
  final int id;
  final String name;
  // Prefill data from the staff member's active Contract, when they have
  // one — null when no contract is on file yet (falls back to manual entry).
  final int? baseSalary;
  final int? allowancesTotal;
  final int? nssfAmount;
  final int? nssfEmployerAmount;
  final int? payeAmount;
  const EligibleStaffOption({
    required this.id,
    required this.name,
    this.baseSalary,
    this.allowancesTotal,
    this.nssfAmount,
    this.nssfEmployerAmount,
    this.payeAmount,
  });
  factory EligibleStaffOption.fromJson(Map<String, dynamic> j) => EligibleStaffOption(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String,
    baseSalary: (j['base_salary'] as num?)?.toInt(),
    allowancesTotal: (j['allowances_total'] as num?)?.toInt(),
    nssfAmount: (j['nssf_amount'] as num?)?.toInt(),
    nssfEmployerAmount: (j['nssf_employer_amount'] as num?)?.toInt(),
    payeAmount: (j['paye_amount'] as num?)?.toInt(),
  );
}

class PayrollService {
  PayrollService._();
  static final instance = PayrollService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see InventoryService for the full
  // reasoning. Per-id maps keyed by the run/user id the fetch is scoped to.
  static List<PayrollRun>? cachedRuns;
  static final Map<int, PayrollRun> cachedRunById = {};
  static final Map<int, List<EligibleStaffOption>> cachedEligibleStaff = {};
  static final Map<int, List<SalaryAdjustment>> cachedSalaryAdjustments = {};
  static final Map<int, List<PayrollHistoryItem>> cachedHistoryForUser = {};

  Future<List<PayrollRun>> runs() async {
    final res = await _dio.get('/payroll-runs');
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => PayrollRun.fromJson(j as Map<String, dynamic>)).toList();
    cachedRuns = list;
    return list;
  }

  /// The run plus the top-level staff_without_salary list beside its data.
  PayrollRun _run(Response res) => PayrollRun.fromJson({
    ...ApiClient.unwrap(res) as Map<String, dynamic>,
    if (res.data is Map && (res.data as Map)['staff_without_salary'] != null)
      'staff_without_salary': (res.data as Map)['staff_without_salary'],
    if (res.data is Map && (res.data as Map)['placeholder_salaries'] != null)
      'placeholder_salaries': (res.data as Map)['placeholder_salaries'],
  });

  /// New runs come loaded with everyone who has a salary on record.
  Future<PayrollRun> createRun({required int month, required int year}) async =>
      _run(await _dio.post('/payroll-runs', data: {'period_month': month, 'period_year': year}));

  Future<PayrollRun> show(int runId) async {
    final run = _run(await _dio.get('/payroll-runs/$runId'));
    cachedRunById[runId] = run;
    return run;
  }

  /// Adds anyone with pay on record who isn't on this draft run yet.
  Future<({PayrollRun run, int added})> loadStaff(int runId) async {
    final res = await _dio.post('/payroll-runs/$runId/load-staff');
    return (run: _run(res), added: ((res.data as Map)['added'] as num?)?.toInt() ?? 0);
  }

  /// Import staff pay from a spreadsheet: [commit] false previews, true saves.
  Future<Map<String, dynamic>> importStaffPay(String path, String name, {required bool commit}) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: name), 'commit': commit ? 1 : 0});
    final res = await _dio.post('/payroll/staff-import', data: form);
    return Map<String, dynamic>.from(ApiClient.unwrap(res) as Map);
  }

  Future<List<EligibleStaffOption>> eligibleStaff(int runId) async {
    final res = await _dio.get('/payroll-runs/$runId/eligible-staff');
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => EligibleStaffOption.fromJson(j as Map<String, dynamic>)).toList();
    cachedEligibleStaff[runId] = list;
    return list;
  }

  Future<PayrollItem> upsertItem(int runId, Map<String, dynamic> data) async {
    final res = await _dio.post('/payroll-runs/$runId/items', data: data);
    return PayrollItem.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> deleteItem(int runId, int itemId) => _dio.delete('/payroll-runs/$runId/items/$itemId');

  Future<PayrollRun> review(int runId) async {
    final res = await _dio.post('/payroll-runs/$runId/review');
    return PayrollRun.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PayrollRun> approve(int runId) async {
    final res = await _dio.post('/payroll-runs/$runId/approve');
    return PayrollRun.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PayrollRun> markPaid(int runId) async {
    final res = await _dio.post('/payroll-runs/$runId/mark-paid');
    return PayrollRun.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<List<SalaryAdjustment>> salaryAdjustments(int userId) async {
    final res = await _dio.get('/staff/$userId/salary-adjustments');
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => SalaryAdjustment.fromJson(j as Map<String, dynamic>)).toList();
    cachedSalaryAdjustments[userId] = list;
    return list;
  }

  Future<SalaryAdjustment> addSalaryAdjustment(int userId, Map<String, dynamic> data) async {
    final res = await _dio.post('/staff/$userId/salary-adjustments', data: data);
    return SalaryAdjustment.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<SalaryAdjustment> approveSalaryAdjustment(int userId, int adjustmentId) async {
    final res = await _dio.post('/staff/$userId/salary-adjustments/$adjustmentId/approve');
    return SalaryAdjustment.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<List<PayrollHistoryItem>> historyForUser(int userId) async {
    final res = await _dio.get('/staff/$userId/payroll-history');
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => PayrollHistoryItem.fromJson(j as Map<String, dynamic>)).toList();
    cachedHistoryForUser[userId] = list;
    return list;
  }
}
