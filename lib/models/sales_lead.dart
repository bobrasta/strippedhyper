enum PipelineStage { lead, qualified, demoScheduled, proposalSent, negotiation, won, lost }

extension PipelineStageX on PipelineStage {
  String get label {
    switch (this) {
      case PipelineStage.lead:          return 'Lead';
      case PipelineStage.qualified:     return 'Qualified';
      case PipelineStage.demoScheduled: return 'Demo Scheduled';
      case PipelineStage.proposalSent:  return 'Proposal Sent';
      case PipelineStage.negotiation:   return 'Negotiation';
      case PipelineStage.won:           return 'Won';
      case PipelineStage.lost:          return 'Lost';
    }
  }
}

PipelineStage _parseStage(String s) => switch (s) {
  'qualified'      => PipelineStage.qualified,
  'demo_scheduled' => PipelineStage.demoScheduled,
  'proposal_sent'  => PipelineStage.proposalSent,
  'negotiation'    => PipelineStage.negotiation,
  'won'            => PipelineStage.won,
  'lost'           => PipelineStage.lost,
  _                => PipelineStage.lead,
};

// referral | tender | inbound_call | walk_in | other
enum LeadSource { referral, tender, inboundCall, walkIn, other }

extension LeadSourceX on LeadSource {
  String get label => switch (this) {
    LeadSource.referral    => 'Referral',
    LeadSource.tender      => 'Tender',
    LeadSource.inboundCall => 'Inbound Call',
    LeadSource.walkIn      => 'Walk-in',
    LeadSource.other       => 'Other',
  };

  String get apiValue => switch (this) {
    LeadSource.referral    => 'referral',
    LeadSource.tender      => 'tender',
    LeadSource.inboundCall => 'inbound_call',
    LeadSource.walkIn      => 'walk_in',
    LeadSource.other       => 'other',
  };
}

LeadSource? _parseSource(String? s) => switch (s) {
  'referral'     => LeadSource.referral,
  'tender'       => LeadSource.tender,
  'inbound_call' => LeadSource.inboundCall,
  'walk_in'      => LeadSource.walkIn,
  'other'        => LeadSource.other,
  _              => null,
};

// The rep's own confidence call on a deal, used by the sales dashboard's
// forecast. Unset is treated as pipeline.
enum ForecastCategory { commit, bestCase, pipeline }

extension ForecastCategoryX on ForecastCategory {
  String get label => switch (this) {
    ForecastCategory.commit   => 'Commit',
    ForecastCategory.bestCase => 'Best case',
    ForecastCategory.pipeline => 'Pipeline',
  };

  String get hint => switch (this) {
    ForecastCategory.commit   => 'I\'m confident this closes by the date',
    ForecastCategory.bestCase => 'Could close by the date if things go well',
    ForecastCategory.pipeline => 'Too early to call',
  };

  String get apiValue => switch (this) {
    ForecastCategory.commit   => 'commit',
    ForecastCategory.bestCase => 'best_case',
    ForecastCategory.pipeline => 'pipeline',
  };
}

ForecastCategory parseForecastCategory(String? s) => switch (s) {
  'commit'    => ForecastCategory.commit,
  'best_case' => ForecastCategory.bestCase,
  _           => ForecastCategory.pipeline,
};

class LeadEvent {
  final String type;
  final String title;
  final String? note;
  final String? by;
  final DateTime? at;

  const LeadEvent({required this.type, required this.title, this.note, this.by, this.at});

  factory LeadEvent.fromJson(Map<String, dynamic> j) => LeadEvent(
    type: j['type'] as String? ?? '',
    title: j['title'] as String? ?? '',
    note: j['note'] as String?,
    by: j['by'] as String?,
    at: j['at'] != null ? DateTime.tryParse(j['at'] as String) : null,
  );
}

class SalesLead {
  final int    id;
  final String hospital;
  final String contact;
  final String? contactEmail;
  final String? contactPhone;
  final LeadSource? source;
  final String? sourceNotes;
  final String? notes;
  final String machineType;
  final int    dealValue;
  final int    daysInStage;
  final int    daysOpen;
  final PipelineStage stage;
  final String? demoDate;
  final String? followUpDate;
  final String? expectedCloseDate;
  final ForecastCategory forecastCategory;
  final int?    assignedTo;
  final String? assigneeName;
  final List<LeadEvent> events;
  final DateTime? createdAt;

  const SalesLead({
    required this.id,
    required this.hospital,
    required this.contact,
    this.contactEmail,
    this.contactPhone,
    this.source,
    this.sourceNotes,
    this.notes,
    required this.machineType,
    required this.dealValue,
    required this.daysInStage,
    this.daysOpen = 0,
    required this.stage,
    this.demoDate,
    this.followUpDate,
    this.expectedCloseDate,
    this.forecastCategory = ForecastCategory.pipeline,
    this.assignedTo,
    this.assigneeName,
    this.events = const [],
    this.createdAt,
  });

  factory SalesLead.fromJson(Map<String, dynamic> j) => SalesLead(
    id:          (j['id'] as num? ?? 0).toInt(),
    hospital:    j['hospital'] is Map
        ? (j['hospital'] as Map)['name'] as String? ?? j['hospital_name'] as String? ?? '—'
        : j['hospital'] as String? ?? j['hospital_name_raw'] as String? ?? j['hospital_name'] as String? ?? '—',
    contact:     j['contact']      as String? ?? j['contact_name_raw'] as String? ?? j['contact_name'] as String? ?? '—',
    contactEmail: j['contact_email'] as String?,
    contactPhone: j['contact_phone'] as String?,
    source:      _parseSource(j['source'] as String?),
    sourceNotes: j['source_notes'] as String?,
    notes:       j['notes'] as String?,
    machineType: j['machine_type'] as String? ?? '—',
    dealValue:   (j['deal_value']  as num? ?? 0).toInt(),
    daysInStage: (j['days_in_stage'] as num? ?? 0).toInt(),
    daysOpen:    (j['days_open'] as num? ?? 0).toInt(),
    stage:       _parseStage(j['stage'] as String? ?? 'lead'),
    demoDate:    j['demo_date']    as String?,
    followUpDate: j['follow_up_date'] as String?,
    expectedCloseDate: j['expected_close_date'] as String?,
    forecastCategory: parseForecastCategory(j['forecast_category'] as String?),
    assignedTo:  (j['assigned_to'] as num?)?.toInt(),
    assigneeName: j['assignee'] is Map ? (j['assignee'] as Map)['name'] as String? : null,
    events:      j['events'] is List
        ? (j['events'] as List).map((e) => LeadEvent.fromJson(e as Map<String, dynamic>)).toList()
        : const [],
    createdAt:   j['created_at'] != null ? DateTime.tryParse(j['created_at'] as String) : null,
  );

  bool get isFollowUpDue {
    if (followUpDate == null) return false;
    final d = DateTime.tryParse(followUpDate!);
    if (d == null) return false;
    final today = DateTime.now();
    return !d.isAfter(DateTime(today.year, today.month, today.day));
  }

  bool get isDemoOverdue {
    if (demoDate == null) return false;
    if (stage != PipelineStage.demoScheduled) return false;
    final d = DateTime.tryParse(demoDate!);
    if (d == null) return false;
    final today = DateTime.now();
    return d.isBefore(DateTime(today.year, today.month, today.day));
  }
}
