// Meetings register — MeetingController on the API.

DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

const meetingStatusLabels = {
  'scheduled': 'Scheduled',
  'held': 'Held',
  'minutes_final': 'Minutes final',
  'circulated': 'Minutes circulated',
  'cancelled': 'Cancelled',
};

const attendanceLabels = {
  'invited': 'Invited',
  'present': 'Present',
  'absent': 'Absent',
  'apologies': 'Apologies',
};

const actionItemStatusLabels = {
  'open': 'Open',
  'in_progress': 'In progress',
  'done': 'Done',
  'overdue': 'Overdue',
};

String meetingCategoryLabel(String c) => c.isEmpty ? '—' : '${c[0].toUpperCase()}${c.substring(1).replaceAll('_', ' ')}';

class MeetingAttendee {
  MeetingAttendee({this.id, this.userId, required this.name, this.guestOrganisation, this.guestEmail, this.attendance = 'invited'});
  final int? id;
  final int? userId;
  String name;
  String? guestOrganisation;
  String? guestEmail;
  String attendance;

  bool get isGuest => userId == null;

  factory MeetingAttendee.fromJson(Map<String, dynamic> j) => MeetingAttendee(
    id: j['id'] as int?,
    userId: j['user_id'] as int?,
    name: (j['name'] ?? j['guest_name'] ?? '') as String,
    guestOrganisation: j['guest_organisation'] as String?,
    guestEmail: j['guest_email'] as String?,
    attendance: (j['attendance'] ?? 'invited') as String,
  );

  Map<String, dynamic> toJson() => isGuest
      ? {'guest_name': name, 'guest_organisation': guestOrganisation, 'guest_email': guestEmail, 'attendance': attendance}
      : {'user_id': userId, 'attendance': attendance};
}

class MeetingActionItem {
  MeetingActionItem({required this.id, required this.description, required this.ownerId, this.owner, this.dueDate, this.taskId, required this.status});
  final int id;
  final String description;
  final int ownerId;
  final String? owner;
  final DateTime? dueDate;
  final int? taskId;
  final String status; // open | in_progress | done | overdue

  bool get isDone => status == 'done';

  factory MeetingActionItem.fromJson(Map<String, dynamic> j) => MeetingActionItem(
    id: j['id'] as int,
    description: (j['description'] ?? '') as String,
    ownerId: j['owner_id'] as int,
    owner: j['owner'] as String?,
    dueDate: j['due_date'] == null ? null : DateTime.tryParse(j['due_date'] as String),
    taskId: j['task_id'] as int?,
    status: (j['status'] ?? 'open') as String,
  );
}

class MeetingAttachment {
  MeetingAttachment({required this.id, required this.name, required this.url, this.size = 0});
  final int id;
  final String name;
  final String url;
  final int size;

  factory MeetingAttachment.fromJson(Map<String, dynamic> j) => MeetingAttachment(
    id: j['id'] as int,
    name: (j['name'] ?? '') as String,
    url: (j['url'] ?? '') as String,
    size: (j['size'] as num?)?.toInt() ?? 0,
  );
}

class Meeting {
  Meeting(this.j);
  final Map<String, dynamic> j;

  int get id => j['id'] as int;
  String get title => (j['title'] ?? '') as String;
  String get category => (j['category'] ?? 'general') as String;
  String get status => (j['status'] ?? 'scheduled') as String;
  String get statusLabel => meetingStatusLabels[status] ?? status;
  DateTime? get startsAt => _dt(j['starts_at']);
  DateTime? get endsAt => _dt(j['ends_at']);
  DateTime? get circulatedAt => _dt(j['circulated_at']);
  String? get location => j['location'] as String?;
  String? get onlineLink => j['online_link'] as String?;
  String? get department => j['department'] as String?;
  int? get departmentId => j['department_id'] as int?;
  String? get chair => j['chair'] as String?;
  int? get chairedBy => j['chaired_by'] as int?;
  String? get secretary => j['secretary'] as String?;
  int? get recordedBy => j['recorded_by'] as int?;
  int get attendeesCount => (j['attendees_count'] as num?)?.toInt() ?? 0;
  int get actionItemsCount => (j['action_items_count'] as num?)?.toInt() ?? 0;
  String? get agenda => j['agenda'] as String?;
  String? get minutes => j['minutes'] as String?;
  String? get decisions => j['decisions'] as String?;
  bool get minutesVisible => j['minutes_visible'] == true;
  bool get canManage => j['can_manage'] == true;

  bool get isUpcoming => status == 'scheduled' && (startsAt?.isAfter(DateTime.now().subtract(const Duration(hours: 3))) ?? false);
  bool get awaitingMinutes => status == 'held' || status == 'minutes_final';

  String get venue => [if ((location ?? '').isNotEmpty) location!, if ((onlineLink ?? '').isNotEmpty) 'Online'].join(' · ');

  List<MeetingAttendee> get attendees =>
      [for (final a in (j['attendees'] as List? ?? [])) MeetingAttendee.fromJson(Map<String, dynamic>.from(a as Map))];
  List<MeetingActionItem> get actionItems =>
      [for (final a in (j['action_items'] as List? ?? [])) MeetingActionItem.fromJson(Map<String, dynamic>.from(a as Map))];
  List<MeetingAttachment> get attachments =>
      [for (final a in (j['attachments'] as List? ?? [])) MeetingAttachment.fromJson(Map<String, dynamic>.from(a as Map))];
}

class MeetingList {
  MeetingList({required this.meetings, required this.canManage, required this.departments, required this.categories});
  final List<Meeting> meetings;
  final bool canManage;
  final List<(int, String)> departments;
  final List<String> categories;
}
