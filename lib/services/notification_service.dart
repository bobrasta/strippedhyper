import '../models/notification.dart';
import 'api_client.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. list() takes no data filters (noCache only bypasses the
  // HTTP-response cache layer, not a query filter), so it's always cached.
  static List<AppNotification>? cachedDefaultList;

  Future<List<AppNotification>> list({bool noCache = false}) async {
    final res = await _dio.get('/notifications',
        options: noCache ? ApiClient.noCache : null);
    final (data, _) = ApiClient.unwrapList(res);
    final notifications = data.map((j) => AppNotification.fromJson(j as Map<String, dynamic>)).toList();
    cachedDefaultList = notifications;
    return notifications;
  }

  Future<void> markRead(int id)  => _dio.patch('/notifications/$id/read');
  Future<void> markAllRead()     => _dio.post('/notifications/read-all');
}
