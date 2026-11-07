import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io' show HandshakeException, TlsException;
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
}

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const _baseUrl  = ApiClient.baseUrl;
  static const _tokenKey = 'hypermed_token';
  static const _storage  = FlutterSecureStorage(
    wOptions: WindowsOptions(),
  );

  late final Dio _dio = _buildDio();

  Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
    ));
    dio.httpClientAdapter = ApiClient.createHttpAdapter();
    dio.interceptors.add(LogInterceptor(
      requestHeader:  true,
      requestBody:    true,
      responseHeader: false,
      responseBody:   true,
      error:          true,
      logPrint: (o) => dev.log(o.toString(), name: 'HTTP'),
    ));
    return dio;
  }

  static const _userKey = 'hypermed_user_name';
  static const _roleKey = 'hypermed_user_role';
  static const _idKey   = 'hypermed_user_id';

  Future<String?> getStoredToken()    => _storage.read(key: _tokenKey);
  Future<String?> getStoredUserName() => _storage.read(key: _userKey);
  Future<String?> getStoredRole()     => _storage.read(key: _roleKey);
  Future<int?> getStoredUserId() async {
    final raw = await _storage.read(key: _idKey);
    return raw != null ? int.tryParse(raw) : null;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await _dio.post(
        '/auth/login',
        data: jsonEncode({'email': email, 'password': password}),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final payload = res.data['data'] as Map;
      final token    = payload['token'] as String;
      final user     = payload['user'] as Map?;
      final userName = user?['name'] as String? ?? 'User';
      final userRole = user?['role'] as String? ?? 'staff';
      final userId   = user?['id'];
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _userKey,  value: userName);
      await _storage.write(key: _roleKey,  value: userRole);
      if (userId != null) await _storage.write(key: _idKey, value: userId.toString());
      return Map<String, dynamic>.from(payload);
    } on DioException catch (e) {
      dev.log('LOGIN ${e.response?.statusCode} | ${e.type} | ${e.response?.data}', name: 'AUTH');
      if (e.response?.statusCode == 401 || e.response?.statusCode == 422) {
        throw const AuthException('Invalid email or password.');
      }
      // A failed secure handshake: almost always this PC's date/time, or a
      // network/antivirus that intercepts secure connections.
      final err = e.error;
      if (e.type == DioExceptionType.badCertificate || err is HandshakeException || err is TlsException) {
        throw const AuthException('Secure connection to the server failed. Check that this computer\'s date and time '
            'are correct (set automatically), and that no antivirus or office network is blocking app.hypermed.co.tz, then try again.');
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw const AuthException('Cannot reach the server. Check your connection.');
      }
      // Say what came back, so a firewall page or a server fault can be told apart.
      final code = e.response?.statusCode;
      throw AuthException('Login failed${code != null ? ' (server answered $code)' : ' (${e.type.name}: ${err ?? e.message ?? 'no detail'})'}. Please try again later.');
    } catch (e) {
      dev.log('LOGIN unexpected: $e', name: 'AUTH');
      throw const AuthException('Something went wrong. Please try again.');
    }
  }

  // Stale-while-revalidate screen cache — see InventoryService for the full
  // reasoning.
  static Map<String, dynamic>? cachedProfile;

  Future<Map<String, dynamic>?> getProfile() async {
    try {
      final res  = await ApiClient.instance.dio.get('/auth/me');
      final data = ApiClient.unwrap(res);
      if (data is! Map<String, dynamic>) return null;
      // Keep storage in sync so role/name/id survive app restarts.
      final name = data['name'] as String?;
      final role = data['role'] as String?;
      final id   = data['id'];
      if (name != null) await _storage.write(key: _userKey, value: name);
      if (role != null) await _storage.write(key: _roleKey, value: role);
      if (id != null) await _storage.write(key: _idKey, value: id.toString());
      cachedProfile = data;
      return data;
    } catch (_) { return null; }
  }

  Future<void> updateStoredName(String name) =>
      _storage.write(key: _userKey, value: name);

  Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _roleKey);
    await _storage.delete(key: _idKey);
  }

  Future<void> logout(String token) async {
    try {
      await _dio.post(
        '/auth/logout',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {}
    await _storage.delete(key: _tokenKey);
  }

  Dio get dio => _dio;
}
