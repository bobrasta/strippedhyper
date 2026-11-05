class Vacancy {
  final int id;
  final int positionId;
  final String? positionTitle;
  final String? department;
  final String? requirements;
  final String status; // open | on_hold | closed
  final String openedAt;
  final String? closedAt;
  final int applicationsCount;

  const Vacancy({
    required this.id, required this.positionId, this.positionTitle, this.department,
    this.requirements, required this.status, required this.openedAt, this.closedAt,
    this.applicationsCount = 0,
  });

  factory Vacancy.fromJson(Map<String, dynamic> j) => Vacancy(
    id: (j['id'] as num).toInt(),
    positionId: (j['position_id'] as num).toInt(),
    positionTitle: j['position_title'] as String?,
    department: j['department'] as String?,
    requirements: j['requirements'] as String?,
    status: j['status'] as String? ?? 'open',
    openedAt: j['opened_at'] as String? ?? '—',
    closedAt: j['closed_at'] as String?,
    applicationsCount: (j['applications_count'] as num?)?.toInt() ?? 0,
  );
}

class ApplicantCvVersion {
  final int id;
  final int version;
  final String originalName;
  final String url;
  final String? uploadedAt;

  const ApplicantCvVersion({
    required this.id, required this.version, required this.originalName,
    required this.url, this.uploadedAt,
  });

  factory ApplicantCvVersion.fromJson(Map<String, dynamic> j) => ApplicantCvVersion(
    id: (j['id'] as num).toInt(),
    version: (j['version'] as num).toInt(),
    originalName: j['original_name'] as String,
    url: j['url'] as String,
    uploadedAt: j['uploaded_at'] as String?,
  );
}

class Applicant {
  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? coverLetter;
  final String? sourceChannel;
  final bool talentPool;
  final String? skillsTags;
  final String? notes;
  final ApplicantCvVersion? latestCv;
  final List<Application> applications;

  const Applicant({
    required this.id, required this.name, this.phone, this.email, this.coverLetter,
    this.sourceChannel, this.talentPool = false, this.skillsTags, this.notes,
    this.latestCv, this.applications = const [],
  });

  factory Applicant.fromJson(Map<String, dynamic> j) => Applicant(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String,
    phone: j['phone'] as String?,
    email: j['email'] as String?,
    coverLetter: j['cover_letter'] as String?,
    sourceChannel: j['source_channel'] as String?,
    talentPool: j['talent_pool'] as bool? ?? false,
    skillsTags: j['skills_tags'] as String?,
    notes: j['notes'] as String?,
    latestCv: (j['latest_cv'] is Map && (j['latest_cv'] as Map).isNotEmpty)
        ? ApplicantCvVersion.fromJson(j['latest_cv'] as Map<String, dynamic>) : null,
    applications: (j['applications'] as List<dynamic>? ?? [])
        .map((a) => Application.fromJson(a as Map<String, dynamic>)).toList(),
  );
}

class Interview {
  final int id;
  final int applicationId;
  final String scheduledAt;
  final String? stage;
  final String? panel;
  final String? interviewerName;
  final String? notes;
  final int? rating;

  const Interview({
    required this.id, required this.applicationId, required this.scheduledAt,
    this.stage, this.panel, this.interviewerName, this.notes, this.rating,
  });

  factory Interview.fromJson(Map<String, dynamic> j) => Interview(
    id: (j['id'] as num).toInt(),
    applicationId: (j['application_id'] as num).toInt(),
    scheduledAt: j['scheduled_at'] as String? ?? '—',
    stage: j['stage'] as String?,
    panel: j['panel'] as String?,
    interviewerName: j['interviewer_name'] as String?,
    notes: j['notes'] as String?,
    rating: (j['rating'] as num?)?.toInt(),
  );
}

class Application {
  final int id;
  final int applicantId;
  final String? applicantName;
  final String? applicantSource;
  final ApplicantCvVersion? applicantCv;
  final int vacancyId;
  final String? vacancyTitle;
  final String status;
  final String appliedAt;
  final String? notes;
  final List<Interview> interviews;

  const Application({
    required this.id, required this.applicantId, this.applicantName,
    this.applicantSource, this.applicantCv,
    required this.vacancyId, this.vacancyTitle, required this.status,
    required this.appliedAt, this.notes, this.interviews = const [],
  });

  factory Application.fromJson(Map<String, dynamic> j) => Application(
    id: (j['id'] as num).toInt(),
    applicantId: (j['applicant_id'] as num).toInt(),
    applicantName: j['applicant_name'] as String?,
    applicantSource: j['applicant_source'] as String?,
    applicantCv: (j['applicant_cv'] is Map && (j['applicant_cv'] as Map).isNotEmpty)
        ? ApplicantCvVersion.fromJson(j['applicant_cv'] as Map<String, dynamic>) : null,
    vacancyId: (j['vacancy_id'] as num).toInt(),
    vacancyTitle: j['vacancy_title'] as String?,
    status: j['status'] as String? ?? 'applied',
    appliedAt: j['applied_at'] as String? ?? '—',
    notes: j['notes'] as String?,
    interviews: (j['interviews'] as List<dynamic>? ?? [])
        .map((i) => Interview.fromJson(i as Map<String, dynamic>)).toList(),
  );

  static const stageLabels = {
    'applied': 'Applied', 'shortlisted': 'Shortlisted', 'interviewed': 'Interviewed',
    'offered': 'Offered', 'hired': 'Hired', 'rejected': 'Rejected',
  };
  String get stageLabel => stageLabels[status] ?? status;
}
