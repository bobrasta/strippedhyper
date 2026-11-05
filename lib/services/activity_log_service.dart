import 'api_client.dart';

/// One changed field, already made readable by the API (labels, and ids
/// resolved to names): e.g. Position: Sales Manager → Field Technician.
class ActivityFieldChange {
  final String field;
  final String? oldValue;
  final String? newValue;
  const ActivityFieldChange({required this.field, this.oldValue, this.newValue});

  factory ActivityFieldChange.fromJson(Map<String, dynamic> j) => ActivityFieldChange(
    field: j['field'] as String? ?? '',
    oldValue: j['old'] as String?,
    newValue: j['new'] as String?,
  );
}

class ActivityLogEntry {
  final int id;
  final String description;
  final String? summary;       // "Bob Tem updated user Florian Mwaisumbe"
  final String subjectType;
  final int? subjectId;
  final String? subjectLabel;  // the record's name/number
  final String? causerName;
  final String? causerRole;    // ALL CAPS
  final List<ActivityFieldChange> fieldChanges;
  final Map<String, dynamic>? changes;
  final String? createdAt;

  const ActivityLogEntry({
    required this.id,
    required this.description,
    this.summary,
    required this.subjectType,
    this.subjectId,
    this.subjectLabel,
    this.causerName,
    this.causerRole,
    this.fieldChanges = const [],
    this.changes,
    this.createdAt,
  });

  factory ActivityLogEntry.fromJson(Map<String, dynamic> j) => ActivityLogEntry(
    id: (j['id'] as num).toInt(),
    description: j['description'] as String? ?? '—',
    summary: j['summary'] as String?,
    subjectType: j['subject_type'] as String? ?? '—',
    subjectId: (j['subject_id'] as num?)?.toInt(),
    subjectLabel: j['subject_label'] as String?,
    causerName: j['causer_name'] as String?,
    causerRole: j['causer_role'] as String?,
    fieldChanges: [
      for (final c in (j['field_changes'] as List? ?? const []))
        if (c is Map) ActivityFieldChange.fromJson(c.cast<String, dynamic>()),
    ],
    // An entry with no field diff can arrive as [] (empty PHP array).
    changes: j['changes'] is Map ? (j['changes'] as Map).cast<String, dynamic>() : null,
    createdAt: j['created_at'] as String?,
  );
}

class ActivityLogPage {
  final List<ActivityLogEntry> items;
  final int currentPage;
  final int lastPage;
  const ActivityLogPage({required this.items, required this.currentPage, required this.lastPage});
}

// Read-only view onto ApprovalLog/spatie-activitylog history — admin-tier
// only server-side (ActivityLogController::index), same gate the sidebar
// entry relies on to stay hidden for everyone else (see allowedScreenKeys).
class ActivityLogService {
  ActivityLogService._();
  static final instance = ActivityLogService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. Scoped to the default view only (page 1, no filters) — the
  // screen only ever shows this page immediately, then background-refreshes.
  static ActivityLogPage? cachedFirstPage;

  Future<ActivityLogPage> list({int page = 1, String? subjectType, int? causerId}) async {
    final res = await _dio.get('/activity-log', queryParameters: {
      'page': page,
      'subject_type': ?subjectType,
      'causer_id': ?causerId,
    });
    final data = ApiClient.unwrap(res) as Map<String, dynamic>;
    final items = (data['data'] as List).map((j) => ActivityLogEntry.fromJson(j as Map<String, dynamic>)).toList();
    final result = ActivityLogPage(
      items: items,
      currentPage: (data['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (data['last_page'] as num?)?.toInt() ?? 1,
    );
    if (page == 1 && subjectType == null && causerId == null) {
      cachedFirstPage = result;
    }
    return result;
  }
}
