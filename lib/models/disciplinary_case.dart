class DisciplinaryCaseNote {
  final int id;
  final String note;
  final String? createdBy;
  final String? createdAt;

  const DisciplinaryCaseNote({required this.id, required this.note, this.createdBy, this.createdAt});

  factory DisciplinaryCaseNote.fromJson(Map<String, dynamic> j) => DisciplinaryCaseNote(
    id:        (j['id'] as num).toInt(),
    note:      j['note'] as String,
    createdBy: j['created_by'] as String?,
    createdAt: j['created_at'] as String?,
  );
}

class DisciplinaryCase {
  final int id;
  final int userId;
  final String stage; // verbal_warning | written_warning | final_warning | action_taken
  final String incidentDate;
  final String description;
  final String? actionTaken;
  final String? raisedByName;
  final String? handledByName;
  final String status; // open | closed
  final String? nextStage;
  final List<DisciplinaryCaseNote> notes;

  const DisciplinaryCase({
    required this.id, required this.userId, required this.stage,
    required this.incidentDate, required this.description, this.actionTaken,
    this.raisedByName, this.handledByName, required this.status,
    this.nextStage, this.notes = const [],
  });

  factory DisciplinaryCase.fromJson(Map<String, dynamic> j) => DisciplinaryCase(
    id:            (j['id'] as num).toInt(),
    userId:        (j['user_id'] as num).toInt(),
    stage:         j['stage'] as String,
    incidentDate:  j['incident_date'] as String? ?? '—',
    description:   j['description'] as String? ?? '',
    actionTaken:   j['action_taken'] as String?,
    raisedByName:  j['raised_by_name'] as String?,
    handledByName: j['handled_by_name'] as String?,
    status:        j['status'] as String? ?? 'open',
    nextStage:     j['next_stage'] as String?,
    notes: (j['notes'] as List<dynamic>? ?? [])
        .map((n) => DisciplinaryCaseNote.fromJson(n as Map<String, dynamic>)).toList(),
  );

  static const stageLabels = {
    'verbal_warning': 'Verbal Warning',
    'written_warning': 'Written Warning',
    'final_warning': 'Final Warning',
    'action_taken': 'Action Taken',
  };

  String get stageLabel => stageLabels[stage] ?? stage;
}
