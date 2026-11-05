import 'dart:io';

import 'package:bienhypermed/main.dart' show authTokenNotifier;
import 'package:bienhypermed/services/api_client.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// A file upload that takes longer to send than the JSON timeout must still
// go through (a signed tender contract was cut off at 20 s on office lines).
void main() {
  test('multipart uploads outlast the normal send timeout', () async {
    authTokenNotifier = ValueNotifier<String?>(null);
    // Reads the body slowly, so sending it takes ~3 s.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      var got = 0;
      await for (final chunk in req) {
        got += chunk.length;
        await Future<void>.delayed(Duration(microseconds: chunk.length * 3));
      }
      req.response
        ..headers.contentType = ContentType.json
        ..write('{"data":{"bytes":$got}}');
      await req.response.close();
    });

    final dio = ApiClient.instance.dio;
    final saved = (dio.options.baseUrl, dio.options.sendTimeout, dio.options.receiveTimeout, dio.httpClientAdapter);
    dio.options
      ..baseUrl = 'http://127.0.0.1:${server.port}'
      ..sendTimeout = const Duration(seconds: 1)
      ..receiveTimeout = const Duration(seconds: 1);
    dio.httpClientAdapter = IOHttpClientAdapter();
    try {
      final file = Uint8List(6 * 1024 * 1024);
      final watch = Stopwatch()..start();
      final res = await dio.post('/upload',
          data: FormData.fromMap({'file': MultipartFile.fromBytes(file, filename: 'Signed Contract.pdf')}));
      expect(ApiClient.unwrap(res)['bytes'], greaterThan(file.length));
      expect(watch.elapsed, greaterThan(const Duration(seconds: 2)), reason: 'the server must read slowly for this test to mean anything');
    } finally {
      dio.options
        ..baseUrl = saved.$1
        ..sendTimeout = saved.$2
        ..receiveTimeout = saved.$3;
      dio.httpClientAdapter = saved.$4;
      await server.close(force: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
