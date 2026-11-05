import 'dart:convert';
import 'dart:typed_data';

import 'package:bienhypermed/services/disk_cache.dart';
import 'package:bienhypermed/services/local_db.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with [body] (JSON) and records the paths it saw.
class _StubAdapter implements HttpClientAdapter {
  Object body = {'data': []};
  String contentType = Headers.jsonContentType;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options.uri.toString());
    return ResponseBody.fromString(
      contentType == Headers.jsonContentType ? jsonEncode(body) : '%PDF-1.4',
      200,
      headers: {Headers.contentTypeHeader: [contentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

Uint8List _bytes(Object json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

void main() {
  late LocalDb db;
  late Dio dio;
  late _StubAdapter adapter;
  late DiskCacheInterceptor cache;
  late DateTime now;
  late List<DiskCacheEvent> events;

  setUp(() {
    db = LocalDb.openInMemory();
    now = DateTime(2026, 10, 16, 9);
    adapter = _StubAdapter();
    dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))
      ..httpClientAdapter = adapter
      ..transformer = RawBytesTransformer();
    cache = DiskCacheInterceptor(
      dio: () => dio,
      db: () => db,
      userId: () => 7,
      revalidateExtra: const {},
      clock: () => now,
    );
    dio.interceptors.add(cache);
    events = [];
    cache.events.listen(events.add);
  });

  tearDown(() => db.close());

  // Waits for the background revalidation to report, rather than a fixed
  // delay — under a busy parallel test run 20 ms wasn't always enough.
  Future<void> settle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!events.any((e) => e is Revalidated)) {
      if (DateTime.now().isAfter(deadline)) fail('no revalidation within 5 s');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('first request is served from disk, revalidated, and reports the change', () async {
    db.putResponse(7, '/machines?page=1&status=active', _bytes({'data': ['old']}),
        fetchedAt: now.subtract(const Duration(days: 2)));
    adapter.body = {'data': ['new']};

    // Query order doesn't matter for the key.
    final first = await dio.get('/machines', queryParameters: {'status': 'active', 'page': 1});
    expect(first.data, {'data': ['old']});
    expect(first.requestOptions.extra[DiskCacheInterceptor.fromDiskKey], isTrue);
    await settle();

    expect(adapter.calls, hasLength(1)); // the background revalidation
    expect(events.map((e) => e.runtimeType), [ServedFromDisk, Revalidated]);
    expect((events.last as Revalidated).changed, isTrue);
    expect(utf8.decode(db.getResponse(7, '/machines?page=1&status=active')!.body), '{"data":["new"]}');

    // A remount right after the revalidation reads the fresh disk copy…
    now = now.add(const Duration(seconds: 5));
    final second = await dio.get('/machines', queryParameters: {'page': 1, 'status': 'active'});
    expect(second.data, {'data': ['new']});
    expect(adapter.calls, hasLength(1));

    // …and after that the key goes to the network as usual.
    now = now.add(const Duration(seconds: 30));
    adapter.body = {'data': ['newer']};
    final third = await dio.get('/machines', queryParameters: {'page': 1, 'status': 'active'});
    expect(third.data, {'data': ['newer']});
    expect(adapter.calls, hasLength(2));
    expect(events, hasLength(2));
  });

  test('an unchanged revalidation reports no change', () async {
    db.putResponse(7, '/hospitals', _bytes({'data': [1]}), fetchedAt: now);
    adapter.body = {'data': [1]};
    await dio.get('/hospitals');
    await settle();
    expect((events.last as Revalidated).changed, isFalse);
  });

  test('without a disk copy the request hits the network and is stored', () async {
    adapter.body = {'data': [42]};
    final res = await dio.get('/tickets');
    expect(res.data, {'data': [42]});
    expect(adapter.calls, hasLength(1));
    expect(events, isEmpty);
    expect(db.getResponse(7, '/tickets'), isNotNull);

    // Already fetched this session: the next one is a normal network call.
    await dio.get('/tickets');
    expect(adapter.calls, hasLength(2));
  });

  test('copies older than 14 days are ignored', () async {
    db.putResponse(7, '/tickets', _bytes({'data': ['ancient']}),
        fetchedAt: now.subtract(const Duration(days: 15)));
    final res = await dio.get('/tickets');
    expect(res.data, {'data': []});
    expect(events, isEmpty);
  });

  test('excluded paths and searches are neither served nor stored', () async {
    for (final key in ['/auth/me', '/license/check', '/updates/latest']) {
      db.putResponse(7, key, _bytes({'data': 'disk'}), fetchedAt: now);
      final res = await dio.get(key);
      expect(res.data, {'data': []}, reason: key);
    }
    await dio.get('/customers', queryParameters: {'search': 'kcmc'});
    expect(adapter.calls, hasLength(4));
    expect(events, isEmpty);
    expect(db.getResponse(7, '/customers?search=kcmc'), isNull);
    expect(DiskCacheInterceptor.keyFor(RequestOptions(path: '/customers', queryParameters: {'search': ''})),
        '/customers?search=');
  });

  test('noCache requests bypass the disk', () async {
    db.putResponse(7, '/notifications', _bytes({'data': ['disk']}), fetchedAt: now);
    final res = await dio.get('/notifications',
        options: CacheOptions(store: MemCacheStore(), policy: CachePolicy.noCache).toOptions());
    expect(res.data, {'data': []});
    expect(events, isEmpty);
    expect(utf8.decode(db.getResponse(7, '/notifications')!.body), '{"data":["disk"]}');
  });

  test('non-JSON, byte and mutation responses are not stored', () async {
    adapter.contentType = 'application/pdf';
    await dio.get('/invoices/1/pdf', options: Options(responseType: ResponseType.bytes));
    await dio.get('/invoices/2/pdf');
    adapter.contentType = Headers.jsonContentType;
    await dio.post('/tickets', data: {'a': 1});
    expect(db.getResponse(7, '/invoices/1/pdf'), isNull);
    expect(db.getResponse(7, '/invoices/2/pdf'), isNull);
    expect(db.getResponse(7, '/tickets'), isNull);
  });
}
