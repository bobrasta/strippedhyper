import '../models/position.dart';
import 'api_client.dart';

export '../models/position.dart';

class PositionService {
  PositionService._();
  static final instance = PositionService._();
  final _dio = ApiClient.instance.dio;

  List<Position>? _cache;
  Future<List<Position>>? _inflight;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. Public (unlike the private _cache above, which only helps
  // *within* this service) so a screen can seed itself synchronously in
  // initState, before the first frame, the same way MachineListScreen does.
  static List<Position>? cachedList;

  Future<List<Position>> list({bool force = false}) async {
    if (!force && _cache != null) return _cache!;
    if (!force && _inflight != null) return _inflight!;

    final future = _fetch();
    _inflight = future;
    try {
      final result = await future;
      _cache     = result;
      cachedList = result;
      _inflight  = null;
      return result;
    } catch (_) {
      _inflight = null;
      rethrow;
    }
  }

  Future<List<Position>> _fetch() async {
    final res = await _dio.get('/positions');
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((j) => Position.fromJson(j as Map<String, dynamic>)).toList();
  }

  void invalidateCache() { _cache = null; _inflight = null; }

  Future<Position> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/positions', data: data);
    invalidateCache();
    return Position.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Position> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/positions/$id', data: data);
    invalidateCache();
    return Position.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> delete(int id) async {
    await _dio.delete('/positions/$id');
    invalidateCache();
  }
}
