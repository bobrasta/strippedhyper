import '../models/location.dart';
import 'api_client.dart';

class LocationService {
  LocationService._();
  static final instance = LocationService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. Only covers the unfiltered/default query.
  static List<Location>? cachedDefaultList;

  Future<List<Location>> list({String? search, String? type, bool includeInactive = false}) async {
    final res = await _dio.get('/locations', queryParameters: {
      'search':           ?search,
      'type':             ?type,
      if (includeInactive) 'include_inactive': 'true',
    });
    final (data, _) = ApiClient.unwrapList(res);
    final locations = data.map((j) => Location.fromJson(j as Map<String, dynamic>)).toList();
    if (search == null && type == null && includeInactive == false) cachedDefaultList = locations;
    return locations;
  }

  Future<Location> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/locations', data: data);
    return Location.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Location> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/locations/$id', data: data);
    return Location.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> deactivate(int id) => _dio.delete('/locations/$id');
}
