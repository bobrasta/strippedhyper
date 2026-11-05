import 'dart:developer' as dev;
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import '../main.dart';
import 'auth_service.dart';
import 'disk_cache.dart';
import 'host_address_cache.dart';
import 'local_db.dart';

/// Authenticated Dio instance — automatically attaches Bearer token
/// and signs the user out on 401.
class ApiClient {
  ApiClient._();
  static final instance = ApiClient._();

  // Default points at the production backend on the company VPS so every
  // device reaches the same real data without extra build flags. Override
  // for local dev with:
  //   flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8002/api/v1
  /// How long a multipart upload may take to send and be answered.
  static const uploadTimeout = Duration(minutes: 5);

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.hypermed.co.tz/api/v1',
  );

  // In-memory cache store shared across all requests — 10 MB cap.
  static final _cacheStore = MemCacheStore(maxSize: 10 * 1024 * 1024);

  static final _globalCacheOptions = CacheOptions(
    store: _cacheStore,
    policy: CachePolicy.request,
    hitCacheOnErrorExcept: [401, 403],
    maxStale: const Duration(minutes: 5),
    priority: CachePriority.normal,
  );

  /// Returns `Options` that cache the response for [ttl].
  /// Pass to a specific `_dio.get(...)` call to override the global 5-min default.
  static Options cachingOptions(Duration ttl) => CacheOptions(
        store: _cacheStore,
        policy: CachePolicy.request,
        hitCacheOnErrorExcept: [401, 403],
        maxStale: ttl,
        priority: CachePriority.normal,
      ).toOptions();

  /// Bypass cache entirely — use for polling / realtime endpoints.
  static Options get noCache => CacheOptions(
        store: _cacheStore,
        policy: CachePolicy.noCache,
      ).toOptions();

  late final Dio dio = _build();

  /// Persistent response cache — the app shell listens to its events.
  late final DiskCacheInterceptor diskCache = DiskCacheInterceptor(
    dio: () => dio,
    db: () => LocalDb.instance,
    userId: () => userIdNotifier.value,
    // The background revalidation must reach the network, and refresh the
    // memory cache while it's at it.
    revalidateExtra: CacheOptions(
      store: _cacheStore,
      policy: CachePolicy.refresh,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(minutes: 5),
    ).toExtra(),
  );

  /// Connections stay open for 90 s (Dart's default 15 s made every 20 s
  /// poll reconnect) and go straight to the remembered server IP — see
  /// [HostAddressCache].
  static HttpClientAdapter createHttpAdapter() => IOHttpClientAdapter(
        createHttpClient: () => HttpClient()
          ..idleTimeout = const Duration(seconds: 90)
          ..connectionFactory = HostAddressCache.instance.connect,
      );

  Dio _build() {
    final d = Dio(BaseOptions(
      // 10s was too tight against Railway's hobby-tier deployment — a cold
      // start or a brief proxy blip alone could burn the whole budget, and
      // since screens fire several requests concurrently (e.g. Settings
      // loading roles/staff/expense-categories/permissions together), one
      // blip took the whole batch down at once. 20s plus the retry below
      // absorbs that instead of surfacing it as a wall of errors.
      baseUrl:        baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout:    const Duration(seconds: 20),
      headers: {
        'Accept':          'application/json',
        'Accept-Encoding': 'gzip',
        'Connection':      'keep-alive',
      },
    ));
    d.httpClientAdapter = createHttpAdapter();
    // Keeps JSON GET bodies' raw bytes for the disk cache.
    d.transformer = RawBytesTransformer();

    // Disk first: answers a screen's first request this session from the
    // last copy on disk while the network catches up.
    d.interceptors.add(diskCache);
    d.interceptors.add(DioCacheInterceptor(options: _globalCacheOptions));

    // Log only in debug mode — responseBody/requestBody serialise the entire
    // payload to a String on the UI thread; disable them to avoid blocking renders.
    assert(() {
      d.interceptors.add(LogInterceptor(
        requestHeader:  false,
        requestBody:    false,  // too slow for large payloads
        responseHeader: false,
        responseBody:   false,  // too slow for large payloads
        error:          true,
        logPrint: (o) => dev.log(o.toString(), name: 'API'),
      ));
      return true;
    }());

    // Inject auth token on every request
    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = authTokenNotifier.value;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        // File uploads get minutes, not the 20 s meant for JSON: a scanned
        // contract of a few MB on an office line took longer than that and
        // was cut off mid-send.
        if (options.data is FormData) {
          Duration? atLeast(Duration? t) => t != null && t < uploadTimeout ? uploadTimeout : t;
          options.sendTimeout = atLeast(options.sendTimeout);
          options.receiveTimeout = atLeast(options.receiveTimeout);
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final status  = error.response?.statusCode;
        final path    = error.requestOptions.path;
        final body    = error.response?.data;
        dev.log('API $status $path — ${error.type}: ${error.message}', name: 'API');
        if (body != null) dev.log('  body: $body', name: 'API');
        // Only force-logout when the token used for THIS request is still the
        // active token. A stale in-flight request arriving after a fresh login
        // will have a different (old) Authorization header — don't wipe the
        // new token in that case.
        if (status == 401) {
          final usedBearer    = error.requestOptions.headers['Authorization'] as String?;
          final currentToken  = authTokenNotifier.value;
          if (currentToken != null && usedBearer == 'Bearer $currentToken') {
            AuthService.instance.clearToken();
            authTokenNotifier.value = null;
          }
        }

        // Retry once on a transient network failure (timeout / connection
        // error) — the failure mode actually seen in practice is a whole
        // burst of concurrent requests timing out together against Railway,
        // which reads as "the app froze" even though every individual
        // screen's error handling is fine — it's just a wall of near-
        // simultaneous failures. GET-only (retrying a POST/PUT/DELETE could
        // double-submit if the first attempt actually landed server-side
        // before the client-side timeout fired) and only once, via a flag
        // stashed on the request so this can't loop.
        final isRetryable = error.type == DioExceptionType.connectionTimeout
            || error.type == DioExceptionType.receiveTimeout
            || error.type == DioExceptionType.connectionError;
        final alreadyRetried = error.requestOptions.extra['retried'] == true;
        if (isRetryable && !alreadyRetried && error.requestOptions.method == 'GET') {
          try {
            error.requestOptions.extra['retried'] = true;
            final response = await d.fetch(error.requestOptions);
            return handler.resolve(response);
          } catch (_) {
            // Fall through — surface the original error below.
          }
        }

        handler.next(error);
      },
    ));

    return d;
  }

  /// Unwraps the standard Laravel `{ "data": ... }` envelope.
  /// Falls back to the raw body if it isn't a map with a "data" key.
  static dynamic unwrap(Response res) {
    final body = res.data;
    if (body is Map && body.containsKey('data')) return body['data'];
    return body;
  }

  /// GETs every page of a paginated list endpoint and returns all rows.
  /// The API caps `per_page`, so one big request silently truncates a large
  /// list (e.g. "All time" invoices); this keeps asking until `last_page`.
  static Future<List<dynamic>> getAllPages(
    Dio dio,
    String path, {
    Map<String, dynamic> query = const {},
    int perPage = 1000,
  }) async {
    final all = <dynamic>[];
    var page = 1;
    while (true) {
      final res = await dio.get(path, queryParameters: {...query, 'per_page': perPage, 'page': page});
      final (data, meta) = unwrapList(res);
      all.addAll(data);
      final last = (meta?['last_page'] as num?)?.toInt() ?? 1;
      if (page >= last || data.isEmpty) return all;
      page++;
    }
  }

  /// Unwraps a paginated response and returns the list + meta.
  /// Handles three server shapes:
  ///   {"data": [...], "meta": {...}}  — standard Laravel resource collection
  ///   {"data": [...]}                 — resource collection, no meta
  ///   [...]                           — raw JSON array (no envelope)
  static (List<dynamic>, Map<String, dynamic>?) unwrapList(Response res) {
    final body = res.data;

    // Raw JSON array — server skipped the envelope
    if (body is List) return (body, null);

    if (body is! Map) {
      dev.log('unwrapList: unexpected body type ${body.runtimeType}', name: 'API');
      return (<dynamic>[], null);
    }

    final raw  = body['data'];
    if (raw is List) {
      final meta = body['meta'] as Map<String, dynamic>?;
      return (raw, meta);
    }

    // data field is a Map or null — single resource or empty
    if (raw != null) {
      dev.log('unwrapList: data is ${raw.runtimeType}, wrapping as single-item list', name: 'API');
      return ([raw], null);
    }

    return (<dynamic>[], null);
  }
}
