import '../models/leave_request.dart';
import 'api_client.dart';

class LeaveService {
  LeaveService._();
  static final instance = LeaveService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. list()/balances()/types() each have several distinct call
  // "shapes" across the HR screens — each shape gets its own cache slot so
  // a filtered/scoped view never shows another view's stale data.
  static List<LeaveRequest>? cachedDefaultList;       // list() — no filters
  static List<LeaveRequest>? cachedMineList;          // list(mine: true)
  static final Map<int, List<LeaveRequest>> cachedByUserId = {}; // list(userId: ...)

  static List<LeaveBalanceEntry>? cachedDefaultBalances;                    // balances() — no filters
  static final Map<int, List<LeaveBalanceEntry>> cachedBalancesByYear = {}; // balances(year: ...)
  static final Map<int, List<LeaveBalanceEntry>> cachedBalancesByUserId = {}; // balances(userId: ...)

  static List<LeaveTypeCatalogEntry>? cachedTypes; // types() — activeOnly: false

  Future<List<LeaveRequest>> list({int? userId, String? status, String? type, bool mine = false}) async {
    final res = await _dio.get('/leave-requests', queryParameters: {
      'user_id': ?userId,
      'status':  ?status,
      'type':    ?type,
      if (mine) 'mine': 1,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => LeaveRequest.fromJson(j as Map<String, dynamic>)).toList();
    if (userId == null && status == null && type == null && !mine) {
      cachedDefaultList = list;
    } else if (mine && userId == null && status == null && type == null) {
      cachedMineList = list;
    } else if (userId != null) {
      cachedByUserId[userId] = list;
    }
    return list;
  }

  Future<LeaveRequest> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/leave-requests', data: data);
    return LeaveRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  /// [daysCountOverride] is required by the backend when the leave type's
  /// `requires_manual_days` is true (Compassionate) — the approver sets
  /// the final day count rather than trusting the requester's date range.
  Future<LeaveRequest> approve(int id, {int? daysCountOverride}) async {
    final res = await _dio.post('/leave-requests/$id/approve', data: {
      'days_count': ?daysCountOverride,
    });
    return LeaveRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<LeaveRequest> reject(int id, {String? reason}) async {
    final res = await _dio.post('/leave-requests/$id/reject', data: {'rejection_reason': reason});
    return LeaveRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<LeaveRequest> cancel(int id) async {
    final res = await _dio.post('/leave-requests/$id/cancel');
    return LeaveRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<List<LeaveTypeCatalogEntry>> types({bool activeOnly = false}) async {
    final res = await _dio.get('/leave-types', queryParameters: {
      if (activeOnly) 'active_only': 'true',
    });
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => LeaveTypeCatalogEntry.fromJson(j as Map<String, dynamic>)).toList();
    if (!activeOnly) cachedTypes = list;
    return list;
  }

  Future<LeaveTypeCatalogEntry> updateType(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/leave-types/$id', data: data);
    return LeaveTypeCatalogEntry.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<List<LeaveBalanceEntry>> balances({int? userId, int? year}) async {
    final res = await _dio.get('/leave-balances', queryParameters: {
      'user_id': ?userId,
      'year':    ?year,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => LeaveBalanceEntry.fromJson(j as Map<String, dynamic>)).toList();
    if (userId != null) {
      cachedBalancesByUserId[userId] = list;
    } else if (year != null) {
      cachedBalancesByYear[year] = list;
    } else {
      cachedDefaultBalances = list;
    }
    return list;
  }
}
