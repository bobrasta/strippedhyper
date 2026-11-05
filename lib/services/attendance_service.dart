import 'package:dio/dio.dart';
import 'api_client.dart';

class AttendanceRecord {
  final int id;
  final int userId;
  final String? userName;
  final String date;
  final String? clockIn;
  final String? clockOut;
  final String status;
  final double? overtimeHours;
  final String source;

  const AttendanceRecord({
    required this.id, required this.userId, this.userName, required this.date,
    this.clockIn, this.clockOut, required this.status, this.overtimeHours, required this.source,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
    id: (j['id'] as num).toInt(),
    userId: (j['user_id'] as num).toInt(),
    userName: j['user_name'] as String?,
    date: j['date'] as String,
    clockIn: j['clock_in'] as String?,
    clockOut: j['clock_out'] as String?,
    status: j['status'] as String,
    overtimeHours: (j['overtime_hours'] as num?)?.toDouble(),
    source: j['source'] as String,
  );
}

class AttendanceImportResult {
  final int id;
  final String filename;
  final int rowCount;
  final int matchedCount;
  final List<Map<String, dynamic>> unmatchedRows;

  const AttendanceImportResult({
    required this.id, required this.filename, required this.rowCount,
    required this.matchedCount, required this.unmatchedRows,
  });

  factory AttendanceImportResult.fromJson(Map<String, dynamic> j) => AttendanceImportResult(
    id: (j['id'] as num).toInt(),
    filename: j['filename'] as String,
    rowCount: (j['row_count'] as num).toInt(),
    matchedCount: (j['matched_count'] as num).toInt(),
    unmatchedRows: (j['unmatched_rows'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
  );
}

class AttendanceService {
  AttendanceService._();
  static final instance = AttendanceService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. list() has no "default" query (start/end are always
  // required), so it's cached by its own exact query key instead.
  static final Map<String, List<AttendanceRecord>> cachedByQuery = {};
  static List<AttendanceImportResult>? cachedImports;

  Future<List<AttendanceRecord>> list({required String start, required String end, int? userId}) async {
    final res = await _dio.get('/attendance', queryParameters: {'start': start, 'end': end, 'user_id': ?userId});
    final (data, _) = ApiClient.unwrapList(res);
    final records = data.map((j) => AttendanceRecord.fromJson(j as Map<String, dynamic>)).toList();
    cachedByQuery['$start|$end|${userId ?? ''}'] = records;
    return records;
  }

  Future<AttendanceRecord> mark(Map<String, dynamic> data) async {
    final res = await _dio.post('/attendance/mark', data: data);
    return AttendanceRecord.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> bulkMark({required List<int> userIds, required String date, required String status}) =>
      _dio.post('/attendance/bulk-mark', data: {'user_ids': userIds, 'date': date, 'status': status});

  Future<AttendanceImportResult> import(String filePath, String fileName) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final res = await _dio.post('/attendance/import', data: formData);
    return AttendanceImportResult.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<List<AttendanceImportResult>> imports() async {
    final res = await _dio.get('/attendance/imports');
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => AttendanceImportResult.fromJson(j as Map<String, dynamic>)).toList();
    cachedImports = list;
    return list;
  }
}
