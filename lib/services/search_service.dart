import '../models/search_result.dart';
import 'api_client.dart';

class SearchService {
  SearchService._();
  static final instance = SearchService._();
  final _dio = ApiClient.instance.dio;

  Future<List<SearchResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final res = await _dio.get('/search',
      queryParameters: {'q': q},
      options: ApiClient.noCache,
    );
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((j) => SearchResult.fromJson(j as Map<String, dynamic>)).toList();
  }
}
