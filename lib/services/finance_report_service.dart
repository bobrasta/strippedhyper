import 'package:dio/dio.dart';
import 'api_client.dart';

class FinanceReportService {
  FinanceReportService._();
  static final instance = FinanceReportService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. The date-range reports only cache the call with no explicit
  // range (dateFrom/dateTo both null — the caller let the backend default
  // to the current period, which is what FinanceDashboardScreen's default
  // "This Month" period resolves to); a caller-supplied range is a genuine
  // filter, same as a machine list's filtered query, so it isn't cached.
  // The reports below that take no date range at all always cache.
  static Map<String, dynamic>? cachedProfitLoss;
  static Map<String, dynamic>? cachedCashFlow;
  static Map<String, dynamic>? cachedVat;
  static Map<String, dynamic>? cachedTrialBalance;
  static Map<String, dynamic>? cachedBalanceSheet;
  static Map<String, dynamic>? cachedArAging;
  static Map<String, dynamic>? cachedApAging;
  static Map<String, dynamic>? cachedStockValuation;
  static List<Map<String, dynamic>>? cachedMonthlyTrend;

  Future<Map<String, dynamic>> _get(String path, {String? dateFrom, String? dateTo}) async {
    final res = await _dio.get(path, queryParameters: {
      'date_from': ?dateFrom,
      'date_to':   ?dateTo,
    });
    final raw = ApiClient.unwrap(res);
    return raw is Map<String, dynamic> ? raw : {};
  }

  Future<Map<String, dynamic>> vat({String? dateFrom, String? dateTo}) async {
    final r = await _get('/finance-reports/vat', dateFrom: dateFrom, dateTo: dateTo);
    if (dateFrom == null && dateTo == null) cachedVat = r;
    return r;
  }

  Future<Map<String, dynamic>> profitLoss({String? dateFrom, String? dateTo}) async {
    final r = await _get('/finance-reports/profit-loss', dateFrom: dateFrom, dateTo: dateTo);
    if (dateFrom == null && dateTo == null) cachedProfitLoss = r;
    return r;
  }

  Future<Map<String, dynamic>> trialBalance() async {
    final r = await _get('/finance-reports/trial-balance');
    cachedTrialBalance = r;
    return r;
  }

  Future<Map<String, dynamic>> balanceSheet() async {
    final r = await _get('/finance-reports/balance-sheet');
    cachedBalanceSheet = r;
    return r;
  }

  Future<Map<String, dynamic>> arAging() async {
    final r = await _get('/finance-reports/ar-aging');
    cachedArAging = r;
    return r;
  }

  Future<Map<String, dynamic>> apAging() async {
    final r = await _get('/finance-reports/ap-aging');
    cachedApAging = r;
    return r;
  }

  Future<Map<String, dynamic>> stockValuation() async {
    final r = await _get('/finance-reports/stock-valuation');
    cachedStockValuation = r;
    return r;
  }

  Future<Map<String, dynamic>> cashFlow({String? dateFrom, String? dateTo}) async {
    final r = await _get('/finance-reports/cash-flow', dateFrom: dateFrom, dateTo: dateTo);
    if (dateFrom == null && dateTo == null) cachedCashFlow = r;
    return r;
  }

  Future<List<Map<String, dynamic>>> monthlyTrend() async {
    final res = await _dio.get('/finance-reports/monthly-trend');
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.cast<Map<String, dynamic>>();
    cachedMonthlyTrend = list;
    return list;
  }

  // Annual financial statements (FinancialStatementsController). The
  // profile is the narrative around the ledger figures — directors,
  // auditor, policies — edited from the export dialog.
  Future<Map<String, dynamic>> statementsProfile() => _get('/finance-reports/financial-statements/profile');

  Future<Map<String, dynamic>> saveStatementsProfile(Map<String, dynamic> profile) async {
    final res = await _dio.put('/finance-reports/financial-statements/profile', data: profile);
    final raw = ApiClient.unwrap(res);
    return raw is Map<String, dynamic> ? raw : {};
  }

  Future<List<int>> statementsPdf({required int year, required bool audited, required String signDate}) async {
    final res = await _dio.get<List<int>>(
      '/finance-reports/financial-statements/pdf',
      queryParameters: {'year': year, 'audited': audited ? 1 : 0, 'sign_date': signDate},
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data!;
  }
}
