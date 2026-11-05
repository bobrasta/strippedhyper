import '../models/task_item.dart';
import 'api_client.dart';

class TaskService {
  TaskService._();
  static final instance = TaskService._();

  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. cachedDefaultList covers the fully unfiltered call (used by
  // the staff task board); cachedByAssignee covers the per-technician
  // "assignedTo: me" call (used by the technician dashboard) — both are
  // real, repeated query shapes, so each gets its own key.
  static List<TaskItem>? cachedDefaultList;
  static final Map<int, List<TaskItem>> cachedByAssignee = {};

  Future<List<TaskItem>> list({int? assignedTo, String? status, String? category}) async {
    final res = await _dio.get('/tasks', queryParameters: {
      'assigned_to': ?assignedTo,
      'status':      ?status,
      'category':    ?category,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final tasks = data.map((e) => TaskItem.fromJson(e as Map<String, dynamic>)).toList();
    if (status == null && category == null) {
      if (assignedTo == null) {
        cachedDefaultList = tasks;
      } else {
        cachedByAssignee[assignedTo] = tasks;
      }
    }
    return tasks;
  }

  Future<TaskItem> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/tasks', data: data);
    return TaskItem.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<TaskItem> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/tasks/$id', data: data);
    return TaskItem.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> delete(int id) async {
    await _dio.delete('/tasks/$id');
  }
}
