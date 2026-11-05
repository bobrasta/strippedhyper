import 'package:dio/dio.dart';

import '../models/email_account.dart';
import 'api_client.dart';

class EmailAccountService {
  EmailAccountService._();
  static final instance = EmailAccountService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. list() takes no filters, so it's always cached.
  static List<EmailAccount>? cachedAccounts;

  Future<List<EmailAccount>> list({bool noCache = false}) async {
    final res = await _dio.get('/email-accounts', options: noCache ? ApiClient.noCache : null);
    final (data, _) = ApiClient.unwrapList(res);
    final accounts = data.map((j) => EmailAccount.fromJson(j as Map<String, dynamic>)).toList();
    cachedAccounts = accounts;
    return accounts;
  }

  Future<EmailAccount> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/email-accounts', data: data);
    return EmailAccount.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<EmailAccount> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/email-accounts/$id', data: data);
    return EmailAccount.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _dio.delete('/email-accounts/$id');

  /// Verifies the IMAP connection and returns folder names on success.
  /// Throws an [Exception] with the server's error message on failure.
  Future<List<String>> test(int id) async {
    try {
      final res  = await _dio.post('/email-accounts/$id/test');
      final body = ApiClient.unwrap(res);
      if (body is Map) {
        if (body['connected'] == false) {
          throw Exception(body['error'] as String? ?? 'Connection failed.');
        }
        if (body['folders'] is List) {
          return (body['folders'] as List).map((f) => f.toString()).toList();
        }
      }
      return [];
    } on DioException catch (e) {
      // Server returns 422 with { data: { connected: false, error: "..." } }
      final raw = e.response?.data;
      String? msg;
      if (raw is Map) {
        final inner = raw['data'];
        if (inner is Map) msg = inner['error'] as String?;
        msg ??= raw['message'] as String?;
      }
      throw Exception(msg ?? 'Connection test failed (${e.response?.statusCode ?? 'no response'}).');
    }
  }
}
