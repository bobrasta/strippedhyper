import '../models/public_holiday.dart';
import 'api_client.dart';

export '../models/public_holiday.dart';

class PublicHolidayService {
  PublicHolidayService._();
  static final instance = PublicHolidayService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. list() with no year is the "default" call (HR Settings);
  // a specific year (Leave Calendar) gets its own slot.
  static List<PublicHoliday>? cachedDefaultList;
  static final Map<int, List<PublicHoliday>> cachedByYear = {};

  Future<List<PublicHoliday>> list({int? year}) async {
    final res = await _dio.get('/public-holidays', queryParameters: {'year': ?year});
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => PublicHoliday.fromJson(j as Map<String, dynamic>)).toList();
    if (year == null) {
      cachedDefaultList = list;
    } else {
      cachedByYear[year] = list;
    }
    return list;
  }

  Future<PublicHoliday> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/public-holidays', data: data);
    return PublicHoliday.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _dio.delete('/public-holidays/$id');
}
