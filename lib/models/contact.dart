class Contact {
  final int    id;
  final String firstName;
  final String lastName;
  final String? jobTitle;
  final String? department;
  final String? email;
  final String? phone;
  final String? whatsapp;
  final int?    hospitalId;
  final String hospitalName;
  final String? lastContactedAt;
  final String? nextFollowupAt;
  final List<String> tags;
  final List<ContactInteraction> interactions;

  const Contact({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.jobTitle,
    this.department,
    this.email,
    this.phone,
    this.whatsapp,
    this.hospitalId,
    required this.hospitalName,
    this.lastContactedAt,
    this.nextFollowupAt,
    this.tags = const [],
    this.interactions = const [],
  });

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
    id:              (j['id'] as num).toInt(),
    firstName:       j['first_name']  as String? ?? '',
    lastName:        j['last_name']   as String? ?? '',
    jobTitle:        j['job_title']   as String?,
    department:      j['department']  as String?,
    email:           j['email']       as String?,
    phone:           j['phone']       as String?,
    whatsapp:        j['whatsapp']    as String?,
    hospitalId:      (j['hospital_id'] as num?)?.toInt(),
    hospitalName:    j['hospital'] is Map
        ? (j['hospital'] as Map)['name'] as String? ?? j['hospital_name'] as String? ?? '—'
        : j['hospital_name'] as String? ?? j['hospital'] as String? ?? '—',
    lastContactedAt: j['last_contacted_at'] as String?,
    nextFollowupAt:  j['next_followup_at']  as String?,
    tags:            (j['tags'] as List? ?? []).map((e) => e.toString()).toList(),
    interactions:    (j['interactions'] as List? ?? [])
        .map((e) => ContactInteraction.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  String get fullName => '$firstName $lastName';
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty  ? lastName[0]  : '';
    return '$f$l'.toUpperCase();
  }
}

class ContactInteraction {
  final String type;
  final String summary;
  final String? outcome;
  final String? nextAction;
  final String? nextActionDate;
  final String createdAt;

  const ContactInteraction({
    required this.type,
    required this.summary,
    this.outcome,
    this.nextAction,
    this.nextActionDate,
    required this.createdAt,
  });

  factory ContactInteraction.fromJson(Map<String, dynamic> j) =>
      ContactInteraction(
        type:           j['type']             as String? ?? 'note',
        summary:        j['summary']          as String? ?? '',
        outcome:        j['outcome']          as String?,
        nextAction:     j['next_action']      as String?,
        nextActionDate: j['next_action_date'] as String?,
        createdAt:      j['created_at']       as String? ?? '',
      );
}
