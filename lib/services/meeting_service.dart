import 'package:dio/dio.dart';
import '../models/meeting.dart';
import 'api_client.dart';

/// Meetings register — MeetingController on the API.
class MeetingService {
  MeetingService._();
  static final instance = MeetingService._();
  final _dio = ApiClient.instance.dio;

  Map<String, dynamic> _map(Response res) => Map<String, dynamic>.from(ApiClient.unwrap(res) as Map);

  // Stale-while-revalidate cache for the default (this-year) list.
  static MeetingList? cachedList;

  Future<MeetingList> list({Map<String, dynamic> query = const {}}) async {
    final res = await _dio.get('/meetings', queryParameters: query);
    final body = Map<String, dynamic>.from(res.data as Map);
    final list = MeetingList(
      meetings: [for (final m in (body['data'] as List? ?? [])) Meeting(Map<String, dynamic>.from(m as Map))],
      canManage: body['can_manage'] == true,
      departments: [
        for (final d in (body['departments'] as List? ?? []))
          ((d as Map)['id'] as int, (d['name'] ?? '') as String),
      ],
      categories: [for (final c in (body['categories'] as List? ?? [])) c as String],
    );
    return list;
  }

  Future<Meeting> get(int id) async => Meeting(_map(await _dio.get('/meetings/$id')));

  Future<Meeting> create(Map<String, dynamic> data) async => Meeting(_map(await _dio.post('/meetings', data: data)));

  Future<Meeting> update(int id, Map<String, dynamic> data) async => Meeting(_map(await _dio.put('/meetings/$id', data: data)));

  Future<void> delete(int id) => _dio.delete('/meetings/$id');

  Future<Meeting> circulate(int id) async => Meeting(_map(await _dio.post('/meetings/$id/circulate')));

  Future<List<int>> pdf(int id) async {
    final res = await _dio.get<List<int>>('/meetings/$id/pdf', options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  Future<void> addActionItem(int meetingId, {required String description, required int ownerId, DateTime? due}) =>
      _dio.post('/meetings/$meetingId/action-items', data: {
        'description': description,
        'owner_id': ownerId,
        'due_date': ?(due == null ? null : _date(due)),
      });

  Future<void> updateActionItem(int meetingId, int itemId, Map<String, dynamic> data) =>
      _dio.put('/meetings/$meetingId/action-items/$itemId', data: data);

  Future<void> deleteActionItem(int meetingId, int itemId) => _dio.delete('/meetings/$meetingId/action-items/$itemId');

  Future<void> uploadAttachment(int meetingId, String path, String name) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: name)});
    await _dio.post('/meetings/$meetingId/attachments', data: form);
  }

  Future<void> deleteAttachment(int meetingId, int attachmentId) => _dio.delete('/meetings/$meetingId/attachments/$attachmentId');

  Future<Map<String, dynamic>> report(Map<String, dynamic> query) async =>
      _map(await _dio.get('/meetings/report', queryParameters: query));

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
