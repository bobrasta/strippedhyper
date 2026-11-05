import '../models/late_arrival.dart';
import 'api_client.dart';

class LateArrivalService {
  LateArrivalService._();
  static final instance = LateArrivalService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. Scoped to only the default/unfiltered list, same as
  // MachineService.cachedDefaultList.
  static List<LateArrival>? cachedDefaultList;

  Future<List<LateArrival>> list({int? userId, String? dateFrom, String? dateTo}) async {
    final res = await _dio.get('/late-arrivals', queryParameters: {
      'user_id':   ?userId,
      'date_from': ?dateFrom,
      'date_to':   ?dateTo,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => LateArrival.fromJson(j as Map<String, dynamic>)).toList();
    if (userId == null && dateFrom == null && dateTo == null) cachedDefaultList = list;
    return list;
  }

  Future<LateArrival> report({String? expectedTime, String? reason}) async {
    final res = await _dio.post('/late-arrivals', data: {
      'expected_time': expectedTime,
      'reason': reason,
    });
    return LateArrival.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
