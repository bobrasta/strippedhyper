// Section 19 — Tenders & Contracts, TMDA device registrations.
//
// Deadlines, their state and the "flagged" verdict all come from the API
// (TenderDeadlineService is the single source of truth, so reminders, the
// list sort and this screen can never disagree). The client only formats.

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
int? _int(dynamic v) => v == null ? null : (v is int ? v : int.tryParse(v.toString()));

/// Main flow in order; lost/cancelled are side exits at step 5.
const tenderFlow = <String>[
  'identified', 'preparing_bid', 'bid_submitted', 'awaiting_award', 'won', 'accepted',
  'performance_security_submitted', 'contract_signed', 'fulfilling', 'delivered', 'closed',
];

/// Ending a tender these ways needs a reason.
const tenderStatusesNeedingReason = {'not_submitted', 'cancelled', 'lost'};

String tenderTypeLabel(String t) => switch (t) {
  'framework' => 'Framework agreement',
  'pre_qualification' => 'Pre-qualification',
  _ => 'Standard tender',
};

String tenderStatusLabel(String s) => switch (s) {
  'identified' => 'Identified',
  'preparing_bid' => 'Preparing bid',
  'bid_submitted' => 'Bid submitted',
  'awaiting_award' => 'Awaiting award',
  'won' => 'Won',
  'lost' => 'Lost',
  'cancelled' => 'Cancelled by buyer',
  'not_submitted' => 'Not submitted',
  'accepted' => 'Accepted',
  'performance_security_submitted' => 'Performance security submitted',
  'contract_signed' => 'Contract signed',
  'fulfilling' => 'Fulfilling',
  'delivered' => 'Delivered',
  'closed' => 'Closed',
  _ => s,
};

enum DeadlineState { ok, soon, dueToday, overdue, notSet, met, voided }

DeadlineState _state(String? s) => switch (s) {
  'soon' => DeadlineState.soon,
  'due_today' => DeadlineState.dueToday,
  'overdue' => DeadlineState.overdue,
  'not_set' => DeadlineState.notSet,
  'met' => DeadlineState.met,
  'void' => DeadlineState.voided,
  _ => DeadlineState.ok,
};

class TenderDeadline {
  final String kind, label, basis;
  final DateTime? due;
  final int? daysLeft;
  final bool computed, highRisk;
  final DeadlineState state;

  const TenderDeadline({required this.kind, required this.label, required this.basis, this.due, this.daysLeft,
    required this.computed, required this.highRisk, required this.state});

  factory TenderDeadline.fromJson(Map<String, dynamic> j) => TenderDeadline(
    kind: j['kind'] as String, label: j['label'] as String, basis: j['basis'] as String? ?? '',
    due: _date(j['due']), daysLeft: _int(j['days_left']), computed: j['computed'] == true,
    highRisk: j['high_risk'] == true, state: _state(j['state'] as String?),
  );

  String get relative {
    switch (state) {
      case DeadlineState.met: return 'Met';
      case DeadlineState.voided: return 'No longer applies';
      case DeadlineState.notSet: return 'Not set';
      default:
    }
    final d = daysLeft;
    if (d == null) return '—';
    if (d < 0) return '${-d} day${d == -1 ? '' : 's'} overdue';
    if (d == 0) return 'Today';
    return 'in $d day${d == 1 ? '' : 's'}';
  }
}

class ProcuringEntity {
  final int id;
  final String name;
  final String? addressee, address, shortCode, contact;
  const ProcuringEntity({required this.id, required this.name, this.addressee, this.address, this.shortCode, this.contact});
  factory ProcuringEntity.fromJson(Map<String, dynamic> j) => ProcuringEntity(
    id: _int(j['id'])!, name: j['name'] as String? ?? '', addressee: j['addressee'] as String?,
    address: j['address'] as String?, shortCode: j['short_code'] as String?, contact: j['contact'] as String?);

  String get addressBlock => [
    if ((addressee ?? '').isNotEmpty) addressee!,
    name,
    if ((address ?? '').isNotEmpty) address!,
  ].join('\n');
}

class BoardResolution {
  final int id;
  final String number;
  final DateTime date;
  final String? notes;
  final List<String> tenderNumbers;
  const BoardResolution({required this.id, required this.number, required this.date, this.notes, this.tenderNumbers = const []});
  factory BoardResolution.fromJson(Map<String, dynamic> j) => BoardResolution(
    id: _int(j['id'])!, number: j['number'].toString(), date: _date(j['resolution_date'])!, notes: j['notes'] as String?,
    tenderNumbers: [for (final t in (j['tenders'] as List? ?? [])) (t as Map)['tender_number'].toString()]);
}

class TenderDocumentSlot {
  final String type, label;
  final bool generated, hasDraft, hasExecuted;
  final DateTime? draftAt, executedAt;
  final String? executedName;
  const TenderDocumentSlot({required this.type, required this.label, required this.generated, required this.hasDraft,
    required this.hasExecuted, this.draftAt, this.executedAt, this.executedName});
  factory TenderDocumentSlot.fromJson(Map<String, dynamic> j) => TenderDocumentSlot(
    type: j['type'] as String, label: j['label'] as String, generated: j['generated'] == true,
    hasDraft: j['has_draft'] == true, hasExecuted: j['has_executed'] == true,
    draftAt: _date(j['draft_at']), executedAt: _date(j['executed_at']), executedName: j['executed_name'] as String?);
}

class TenderAudit {
  final String what;
  final String? who;
  final DateTime? at;
  const TenderAudit(this.what, this.who, this.at);
}

class Tender {
  final int id;
  final String tenderNumber, title, status, tenderType, currency;
  final String? contractNumber;
  /// Why it ended as not submitted / cancelled / lost.
  final String? statusReason;
  final int step;
  final ProcuringEntity? entity;
  final int? estimatedValue, contractValue;
  final String? ownerName;
  final int? ownerId;
  final TenderDeadline? nextDeadline;
  final bool flagged;
  final int documentsExecuted, documentsTotal;

  // Detail only
  final Map<String, dynamic> raw;
  final List<TenderDeadline> deadlines;
  final List<TenderDocumentSlot> documents;
  final List<TenderAudit> audit;
  final bool canManage;

  const Tender({
    required this.id, required this.tenderNumber, required this.title, required this.status, required this.tenderType,
    required this.currency, this.contractNumber, this.statusReason, required this.step, this.entity, this.estimatedValue, this.contractValue,
    this.ownerName, this.ownerId, this.nextDeadline, required this.flagged, required this.documentsExecuted,
    required this.documentsTotal, this.raw = const {}, this.deadlines = const [], this.documents = const [],
    this.audit = const [], this.canManage = false,
  });

  factory Tender.fromJson(Map<String, dynamic> j) {
    final owner = j['owner'] as Map?;
    final ent = j['procuring_entity'] as Map?;
    return Tender(
      id: _int(j['id'])!,
      tenderNumber: j['tender_number'] as String? ?? '',
      contractNumber: j['contract_number'] as String?,
      statusReason: j['status_reason'] as String?,
      title: j['title'] as String? ?? '',
      status: j['status'] as String? ?? 'identified',
      tenderType: j['tender_type'] as String? ?? 'standard',
      currency: j['currency'] as String? ?? 'TZS',
      step: _int(j['step']) ?? 1,
      entity: ent == null ? null : ProcuringEntity.fromJson(Map<String, dynamic>.from(ent)),
      estimatedValue: _int(j['estimated_value']),
      contractValue: _int(j['contract_value']),
      ownerName: owner?['name'] as String?,
      ownerId: _int(owner?['id']),
      nextDeadline: j['next_deadline'] == null ? null : TenderDeadline.fromJson(Map<String, dynamic>.from(j['next_deadline'] as Map)),
      flagged: j['flagged'] == true,
      documentsExecuted: _int(j['documents_executed']) ?? 0,
      documentsTotal: _int(j['documents_total']) ?? 0,
      raw: j,
      deadlines: [for (final d in (j['deadlines'] as List? ?? [])) TenderDeadline.fromJson(Map<String, dynamic>.from(d as Map))],
      documents: [for (final d in (j['documents'] as List? ?? [])) TenderDocumentSlot.fromJson(Map<String, dynamic>.from(d as Map))],
      audit: [for (final a in (j['audit'] as List? ?? []))
        TenderAudit((a as Map)['description'] as String? ?? '', a['who'] as String?, _date(a['at']))],
      canManage: j['can_manage'] == true,
    );
  }

  String get statusLabel => tenderStatusLabel(status);
  bool get isClosedOrLost => const {'lost', 'cancelled', 'not_submitted', 'closed'}.contains(status);
  int? get value => contractValue ?? estimatedValue;

  TenderDeadline? deadline(String kind) {
    for (final d in deadlines) {
      if (d.kind == kind) return d;
    }
    return null;
  }

  // Detail fields (only present on the detail response).
  String? str(String k) => raw[k]?.toString();
  DateTime? date(String k) => _date(raw[k]);
  Map<String, dynamic>? get boardResolution => raw['board_resolution'] == null ? null : Map<String, dynamic>.from(raw['board_resolution'] as Map);
  bool get vatInclusive => raw['vat_inclusive'] == true;
}

// ── Device registration (19.5) ────────────────────────────────────────────────

String registrationStatusLabel(String s) => switch (s) {
  'preparing_dossier' => 'Preparing dossier',
  'submitted' => 'Submitted',
  'under_review' => 'Under review',
  'registered' => 'Registered',
  'renewal_due' => 'Renewal due',
  'expired' => 'Expired',
  _ => s,
};

const registrationStatuses = ['preparing_dossier', 'submitted', 'under_review', 'registered', 'renewal_due', 'expired'];

class EssentialRequirement {
  final int no;
  final String principle;
  final bool? applicable;
  final String? method, supportingDocument;
  final bool complete;
  const EssentialRequirement({required this.no, required this.principle, this.applicable, this.method,
    this.supportingDocument, required this.complete});
  factory EssentialRequirement.fromJson(Map<String, dynamic> j) => EssentialRequirement(
    no: _int(j['principle_no'])!, principle: j['principle'] as String? ?? '',
    applicable: j['applicable'] as bool?, method: j['method'] as String?,
    supportingDocument: j['supporting_document'] as String?, complete: j['complete'] == true);
}

class RegistrationFile {
  final int id;
  final String name;
  final List<int> principles;
  final String? description;
  const RegistrationFile({required this.id, required this.name, this.principles = const [], this.description});
  factory RegistrationFile.fromJson(Map<String, dynamic> j) => RegistrationFile(
    id: _int(j['id'])!, name: j['original_name'] as String? ?? '',
    principles: [for (final p in (j['principle_nos'] as List? ?? [])) _int(p)!], description: j['description'] as String?);
}

class DeviceRegistration {
  final int id;
  final String brandName, status;
  final String? commonName, model, manufacturer, riskClass, registrationNumber, notes;
  final DateTime? submittedAt, registeredAt, renewalDueDate;
  final TenderDeadline? renewal;
  final bool allowsImport, canManage;
  final int checklistDone, checklistTotal;
  final List<EssentialRequirement> requirements;
  final List<RegistrationFile> files;

  const DeviceRegistration({
    required this.id, required this.brandName, required this.status, this.commonName, this.model, this.manufacturer,
    this.riskClass, this.registrationNumber, this.notes, this.submittedAt, this.registeredAt, this.renewalDueDate,
    this.renewal, required this.allowsImport, this.canManage = false, required this.checklistDone,
    required this.checklistTotal, this.requirements = const [], this.files = const [],
  });

  factory DeviceRegistration.fromJson(Map<String, dynamic> j) => DeviceRegistration(
    id: _int(j['id'])!, brandName: j['brand_name'] as String? ?? '', status: j['status'] as String? ?? 'preparing_dossier',
    commonName: j['common_name'] as String?, model: j['model'] as String?, manufacturer: j['manufacturer'] as String?,
    riskClass: j['risk_class'] as String?, registrationNumber: j['registration_number'] as String?, notes: j['notes'] as String?,
    submittedAt: _date(j['submitted_at']), registeredAt: _date(j['registered_at']), renewalDueDate: _date(j['renewal_due_date']),
    renewal: j['renewal'] == null ? null : TenderDeadline.fromJson(Map<String, dynamic>.from(j['renewal'] as Map)),
    allowsImport: j['allows_import'] == true, canManage: j['can_manage'] == true,
    checklistDone: _int(j['checklist_done']) ?? 0, checklistTotal: _int(j['checklist_total']) ?? 0,
    requirements: [for (final r in (j['requirements'] as List? ?? [])) EssentialRequirement.fromJson(Map<String, dynamic>.from(r as Map))],
    files: [for (final f in (j['files'] as List? ?? [])) RegistrationFile.fromJson(Map<String, dynamic>.from(f as Map))],
  );

  String get statusLabel => registrationStatusLabel(status);
}
