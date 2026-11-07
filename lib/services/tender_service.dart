import 'package:dio/dio.dart';
import '../models/tender.dart';
import 'api_client.dart';

/// Section 19 — TenderController / DeviceRegistrationController.
class TenderService {
  TenderService._();
  static final instance = TenderService._();
  final _dio = ApiClient.instance.dio;

  Map<String, dynamic> _map(Response res) => Map<String, dynamic>.from(ApiClient.unwrap(res) as Map);

  // Stale-while-revalidate cache for the list (see InventoryService).
  static TenderList? cachedList;

  Future<TenderList> list({String? q}) async {
    final res = await _dio.get('/tenders', queryParameters: {'q': ?q});
    final m = _map(res);
    final list = TenderList(
      tenders: [for (final t in (m['tenders'] as List? ?? [])) Tender.fromJson(Map<String, dynamic>.from(t as Map))],
      needsAction: [for (final t in (m['needs_action'] as List? ?? [])) Tender.fromJson(Map<String, dynamic>.from(t as Map))],
      canManage: m['can_manage'] == true,
    );
    if (q == null) cachedList = list;
    return list;
  }

  Future<Tender> get(int id) async => Tender.fromJson(_map(await _dio.get('/tenders/$id')));

  Future<Tender> create(Map<String, dynamic> data) async => Tender.fromJson(_map(await _dio.post('/tenders', data: data)));

  Future<Tender> update(int id, Map<String, dynamic> data) async => Tender.fromJson(_map(await _dio.put('/tenders/$id', data: data)));

  /// [reason] is required for not submitted / cancelled / lost.
  Future<Tender> setStatus(int id, String status, {String? reason}) async =>
      Tender.fromJson(_map(await _dio.post('/tenders/$id/status', data: {'status': status, 'reason': ?reason})));

  /// Generates (and stores) a fresh draft; returns the .docx bytes.
  Future<List<int>> generate(int id, String type, {String? date}) async {
    final res = await _dio.post<List<int>>('/tenders/$id/documents/$type/generate',
        data: {'date': ?date}, options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  Future<List<int>> download(int id, String type, String which) async {
    final res = await _dio.get<List<int>>('/tenders/$id/documents/$type/$which', options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  Future<Tender> uploadExecuted(int id, String type, String path, String name) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: name)});
    return Tender.fromJson(_map(await _dio.post('/tenders/$id/documents/$type/executed', data: form)));
  }

  Future<List<ProcuringEntity>> entities({String? q}) async {
    final res = await _dio.get('/procuring-entities', queryParameters: {'q': ?q});
    return [for (final e in (ApiClient.unwrap(res) as List)) ProcuringEntity.fromJson(Map<String, dynamic>.from(e as Map))];
  }

  Future<ProcuringEntity> saveEntity(Map<String, dynamic> data, {int? id}) async {
    final res = id == null ? await _dio.post('/procuring-entities', data: data) : await _dio.put('/procuring-entities/$id', data: data);
    return ProcuringEntity.fromJson(_map(res));
  }

  Future<List<BoardResolution>> resolutions() async {
    final res = await _dio.get('/board-resolutions');
    return [for (final r in (ApiClient.unwrap(res) as List)) BoardResolution.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  Future<BoardResolution> addResolution(String number, String date, {String? notes}) async =>
      BoardResolution.fromJson(_map(await _dio.post('/board-resolutions', data: {'number': number, 'resolution_date': date, 'notes': ?notes})));

  Future<Map<String, dynamic>> companyProfile() async => _map(await _dio.get('/company-profile'));

  Future<Map<String, dynamic>> saveCompanyProfile(Map<String, dynamic> data) async => _map(await _dio.put('/company-profile', data: data));

  // ── Device registrations ──────────────────────────────────────────────────

  Future<(List<DeviceRegistration>, bool)> devices() async {
    final m = _map(await _dio.get('/device-registrations'));
    return ([for (final d in (m['devices'] as List? ?? [])) DeviceRegistration.fromJson(Map<String, dynamic>.from(d as Map))], m['can_manage'] == true);
  }

  Future<DeviceRegistration> device(int id) async => DeviceRegistration.fromJson(_map(await _dio.get('/device-registrations/$id')));

  Future<DeviceRegistration> saveDevice(Map<String, dynamic> data, {int? id}) async {
    final res = id == null ? await _dio.post('/device-registrations', data: data) : await _dio.put('/device-registrations/$id', data: data);
    return DeviceRegistration.fromJson(_map(res));
  }

  Future<DeviceRegistration> updateRequirement(int id, int no, Map<String, dynamic> data) async =>
      DeviceRegistration.fromJson(_map(await _dio.put('/device-registrations/$id/requirements/$no', data: data)));

  Future<DeviceRegistration> uploadDeviceFile(int id, String path, String name, List<int> principles, {String? description}) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: name),
      for (var i = 0; i < principles.length; i++) 'principle_nos[$i]': principles[i],
      'description': ?description,
    });
    return DeviceRegistration.fromJson(_map(await _dio.post('/device-registrations/$id/files', data: form)));
  }

  Future<List<int>> downloadDeviceFile(int id, int fileId) async {
    final res = await _dio.get<List<int>>('/device-registrations/$id/files/$fileId', options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  Future<DeviceRegistration> deleteDeviceFile(int id, int fileId) async =>
      DeviceRegistration.fromJson(_map(await _dio.delete('/device-registrations/$id/files/$fileId')));

  Future<List<int>> importLetter(int id, {required int office, String? purpose, String? date}) async {
    final res = await _dio.post<List<int>>('/device-registrations/$id/import-letter',
        data: {'office': office, 'purpose': ?purpose, 'date': ?date}, options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  Future<List<int>> checklistDocument(int id) async {
    final res = await _dio.get<List<int>>('/device-registrations/$id/checklist-document', options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }
}

class TenderList {
  final List<Tender> tenders, needsAction;
  final bool canManage;
  const TenderList({required this.tenders, required this.needsAction, required this.canManage});
}
