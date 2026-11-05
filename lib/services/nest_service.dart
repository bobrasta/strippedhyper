import 'package:dio/dio.dart';
import '../models/nest_tender.dart';
import 'api_client.dart';

/// NeST tender tracker — NestTenderController (/nest/*) in hypermed-api.
class NestService {
  NestService._();
  static final instance = NestService._();
  final _dio = ApiClient.instance.dio;

  Map<String, dynamic> _map(Response res) => Map<String, dynamic>.from(ApiClient.unwrap(res) as Map);

  // Stale-while-revalidate: the overview opens instantly on revisit.
  static NestDashboard? cachedDashboard;

  /// [peek] reads the counts without moving "new since my last visit".
  Future<NestDashboard> dashboard({bool peek = false}) async {
    final d = NestDashboard.fromJson(_map(await _dio.get('/nest/dashboard', queryParameters: {if (peek) 'peek': 1})));
    cachedDashboard = d;
    return d;
  }

  Future<NestPage> list(NestFilter f, {int page = 1}) async {
    final res = await _dio.get('/nest/tenders', queryParameters: f.toQuery(page: page));
    final body = Map<String, dynamic>.from(res.data as Map);
    final meta = Map<String, dynamic>.from(body['meta'] as Map? ?? const {});
    return NestPage(
      rows: [for (final r in (body['data'] as List? ?? const [])) NestTender.fromJson(Map<String, dynamic>.from(r as Map))],
      page: (meta['current_page'] as num?)?.toInt() ?? page,
      lastPage: (meta['last_page'] as num?)?.toInt() ?? page,
      total: (meta['total'] as num?)?.toInt() ?? 0,
      canManage: body['can_manage'] == true,
    );
  }

  Future<NestTenderDetail> get(int id) async {
    final body = Map<String, dynamic>.from((await _dio.get('/nest/tenders/$id')).data as Map);
    return NestTenderDetail.fromBody(body);
  }

  Future<NestTenderDetail> update(int id, Map<String, dynamic> data) async =>
      NestTenderDetail.fromBody(Map<String, dynamic>.from((await _dio.patch('/nest/tenders/$id', data: data)).data as Map));

  Future<NestTenderDetail> startBid(int id) async =>
      NestTenderDetail.fromBody(Map<String, dynamic>.from((await _dio.post('/nest/tenders/$id/start-bid')).data as Map));

  /// The tender document PDF, fetched from NeST by the server.
  Future<List<int>> document(int id, {bool refresh = false}) async {
    final res = await _dio.get<List<int>>('/nest/tenders/$id/document',
        queryParameters: {if (refresh) 'refresh': 1}, options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  /// Every document NeST shows a tenderer, plus clarifications and the addendum.
  Future<NestDocuments> documents(int id, {bool refresh = false}) async =>
      NestDocuments.fromJson(_map(await _dio.get('/nest/tenders/$id/documents', queryParameters: {if (refresh) 'refresh': 1})));

  /// One listed file's bytes and the server's suggested file name.
  Future<(List<int>, String?)> documentFile(int id, String fileId) async {
    final res = await _dio.get<List<int>>('/nest/tenders/$id/documents/$fileId', options: Options(responseType: ResponseType.bytes));
    final disp = res.headers.value('content-disposition') ?? '';
    final name = RegExp(r'filename="?([^";]+)"?').firstMatch(disp)?.group(1);
    return (res.data!, name);
  }

  Future<List<NestEntity>> entities({String? q}) async {
    final res = await _dio.get('/nest/procuring-entities', queryParameters: {'q': ?q});
    return [for (final e in (ApiClient.unwrap(res) as List)) NestEntity.fromJson(Map<String, dynamic>.from(e as Map))];
  }

  Future<(List<NestRule>, int threshold, int maybeMin, bool canManage)> rules() async {
    final m = _map(await _dio.get('/nest/relevance-rules'));
    return (
      [for (final r in (m['rules'] as List? ?? const [])) NestRule.fromJson(Map<String, dynamic>.from(r as Map))],
      (m['threshold'] as num?)?.toInt() ?? 10,
      (m['maybe_min'] as num?)?.toInt() ?? 5,
      m['can_manage'] == true,
    );
  }

  Future<NestRule> saveRule(Map<String, dynamic> data, {int? id}) async {
    final res = id == null ? await _dio.post('/nest/relevance-rules', data: data) : await _dio.put('/nest/relevance-rules/$id', data: data);
    return NestRule.fromJson(_map(res));
  }

  Future<void> deleteRule(int id) => _dio.delete('/nest/relevance-rules/$id');

  Future<void> recompute() => _dio.post('/nest/relevance-rules/recompute');

  Future<NestSettings> settings() async => NestSettings.fromJson(_map(await _dio.get('/nest/settings')));

  Future<NestSettings> saveSettings(Map<String, dynamic> data) async => NestSettings.fromJson(_map(await _dio.put('/nest/settings', data: data)));

  Future<NestSettings> testLogin() async => NestSettings.fromJson(_map(await _dio.post('/nest/settings/test-login')));

  /// Queues a NeST check now (counts towards the 3-a-day limit).
  Future<void> syncNow() => _dio.post('/nest/sync');
}

class NestPage {
  final List<NestTender> rows;
  final int page, lastPage, total;
  final bool canManage;
  const NestPage({required this.rows, required this.page, required this.lastPage, required this.total, required this.canManage});
  bool get hasMore => page < lastPage;
}

class NestTenderDetail {
  final NestTender tender;
  final bool canManage, documentAvailable, documentCached;
  const NestTenderDetail({required this.tender, required this.canManage, this.documentAvailable = false, this.documentCached = false});

  factory NestTenderDetail.fromBody(Map<String, dynamic> body) {
    final doc = Map<String, dynamic>.from(body['document'] as Map? ?? const {});
    return NestTenderDetail(
      tender: NestTender.fromJson(Map<String, dynamic>.from(body['data'] as Map)),
      canManage: body['can_manage'] == true,
      documentAvailable: doc['available'] == true,
      documentCached: doc['cached'] == true,
    );
  }
}
