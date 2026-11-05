import 'package:dio/dio.dart';
import '../models/letter.dart';
import 'api_client.dart';

/// Letters list plus what the page needs to know about signature / stamp.
class LettersPage {
  const LettersPage(this.letters, {required this.hasStamp, required this.mySignature, required this.canManageStamp});
  final List<Letter> letters;
  final bool hasStamp, mySignature, canManageStamp;
}

class LetterService {
  LetterService._();
  static final instance = LetterService._();
  Dio get _dio => ApiClient.instance.dio;

  Future<LettersPage> list() async {
    final res = await _dio.get('/letters');
    final body = res.data as Map;
    final meta = (body['meta'] as Map?) ?? const {};
    return LettersPage(
      [for (final j in (body['data'] as List)) Letter.fromJson(Map<String, dynamic>.from(j as Map))],
      hasStamp: meta['has_stamp'] == true, mySignature: meta['my_signature'] == true,
      canManageStamp: meta['can_manage_stamp'] == true,
    );
  }

  Future<List<LetterSignatory>> signatories() async {
    final res = await _dio.get('/letters/signatories');
    return [for (final j in ApiClient.unwrap(res) as List) LetterSignatory.fromJson(Map<String, dynamic>.from(j as Map))];
  }

  Future<Letter> create(Map<String, dynamic> data) async =>
      Letter.fromJson(ApiClient.unwrap(await _dio.post('/letters', data: data)) as Map<String, dynamic>);

  Future<Letter> update(int id, Map<String, dynamic> data) async =>
      Letter.fromJson(ApiClient.unwrap(await _dio.put('/letters/$id', data: data)) as Map<String, dynamic>);

  Future<void> delete(int id) => _dio.delete('/letters/$id');

  Future<Letter> sign(int id) async =>
      Letter.fromJson(ApiClient.unwrap(await _dio.post('/letters/$id/sign')) as Map<String, dynamic>);

  Future<Letter> unsign(int id) async =>
      Letter.fromJson(ApiClient.unwrap(await _dio.post('/letters/$id/unsign')) as Map<String, dynamic>);

  Future<List<int>> pdfBytes(int id) async {
    final res = await _dio.get<List<int>>('/letters/$id/pdf', options: Options(responseType: ResponseType.bytes));
    return res.data ?? const [];
  }

  Future<void> uploadSignature(String path, String name) =>
      _dio.post('/letters/my-signature', data: FormData.fromMap({'file': MultipartFile.fromFileSync(path, filename: name)}));

  Future<void> removeSignature() => _dio.delete('/letters/my-signature');

  Future<void> uploadStamp(String path, String name) =>
      _dio.post('/letters/stamp', data: FormData.fromMap({'file': MultipartFile.fromFileSync(path, filename: name)}));
}
