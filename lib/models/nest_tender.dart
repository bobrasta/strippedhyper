// NeST (nest.go.tz) tender tracker — mirrors NestTenderResource and the
// /nest/* payloads in hypermed-api. Dates arrive as ISO 8601 with +03:00.
// Free text NeST users typed (descriptions, clarifications, addendum notes)
// can arrive as HTML from its rich-text editor — it's turned into plain text
// here so no screen ever shows tags.

import '../utils/html_text.dart';

DateTime? _date(dynamic v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
int? _intOrNull(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
List<String> _strings(dynamic v) => [for (final x in (v as List? ?? const [])) '$x'];

/// Tags a rule (and a tender) can carry, in display order.
const nestTags = ['DEVICES', 'REAGENTS', 'CONSUMABLES', 'SERVICE'];

String nestTagLabel(String tag) => switch (tag) {
  'DEVICES' => 'Devices',
  'REAGENTS' => 'Reagents',
  'CONSUMABLES' => 'Consumables',
  'SERVICE' => 'Service',
  _ => tag,
};

/// Pipeline buckets shown in the app (triage + the linked bid's status).
const nestPipeline = ['new', 'reviewing', 'bidding', 'submitted', 'won', 'lost', 'skipped'];

String nestPipelineLabel(String p) => switch (p) {
  'new' => 'New',
  'reviewing' => 'Reviewing',
  'bidding' => 'Bidding',
  'submitted' => 'Submitted',
  'won' => 'Won',
  'lost' => 'Lost',
  'skipped' => 'Skipped',
  _ => p,
};

/// East Africa Time is UTC+3 all year (no DST) — show NeST times in it
/// whatever the device's own zone is.
DateTime toEat(DateTime d) => d.toUtc().add(const Duration(hours: 3));

class NestTender {
  final int id;
  final String entityUuid;
  final String? entityNumber, referenceNumber, entityType, subCategoryName, subCategoryAcronym;
  final String? procurementCategory, procurementCategoryName, procuringEntityName, procuringEntityUuid, financialYear;
  final String description;
  final int? lotCount;
  final bool hasAddendum;
  final DateTime? invitationAt, closingAt, firstSeenAt;
  final int? closingInDays;
  final bool isOpen, isClosingSoon, isRelevant;
  final int relevanceScore;
  final String relevance; // relevant | maybe | other
  final List<String> tags;
  final String triageStatus, pipelineStatus;
  final int? assignedToId;
  final String? assignedToName;
  final int? tenderId;
  final String? tenderStatus;
  final String nestUrl;
  // Detail only.
  final List<String> eligibleTypes;
  final List<NestMatch> matched;
  final String? notes;
  final List<NestChange> changes;

  const NestTender({
    required this.id, required this.entityUuid, this.entityNumber, this.referenceNumber, this.entityType,
    this.subCategoryName, this.subCategoryAcronym, this.procurementCategory, this.procurementCategoryName,
    this.procuringEntityName, this.procuringEntityUuid, this.financialYear, required this.description,
    this.lotCount, this.hasAddendum = false, this.invitationAt, this.closingAt, this.firstSeenAt,
    this.closingInDays, this.isOpen = false, this.isClosingSoon = false, this.isRelevant = false,
    this.relevanceScore = 0, this.relevance = 'other', this.tags = const [], this.triageStatus = 'new',
    this.pipelineStatus = 'new', this.assignedToId, this.assignedToName, this.tenderId, this.tenderStatus,
    this.nestUrl = 'https://nest.go.tz', this.eligibleTypes = const [], this.matched = const [], this.notes,
    this.changes = const [],
  });

  factory NestTender.fromJson(Map<String, dynamic> j) {
    final assigned = j['assigned_to'] is Map ? Map<String, dynamic>.from(j['assigned_to'] as Map) : null;
    final tender = j['tender'] is Map ? Map<String, dynamic>.from(j['tender'] as Map) : null;
    return NestTender(
      id: _int(j['id']),
      entityUuid: '${j['entity_uuid'] ?? ''}',
      entityNumber: j['entity_number'] as String?,
      referenceNumber: j['reference_number'] as String?,
      entityType: j['entity_type'] as String?,
      subCategoryName: j['sub_category_name'] as String?,
      subCategoryAcronym: j['sub_category_acronym'] as String?,
      procurementCategory: j['procurement_category'] as String?,
      procurementCategoryName: j['procurement_category_name'] as String?,
      procuringEntityName: j['procuring_entity_name'] as String?,
      procuringEntityUuid: j['procuring_entity_uuid'] as String?,
      financialYear: j['financial_year'] as String?,
      description: htmlToPlainText('${j['description'] ?? ''}'),
      lotCount: _intOrNull(j['lot_count']),
      hasAddendum: j['has_addendum'] == true,
      invitationAt: _date(j['invitation_at']),
      closingAt: _date(j['closing_at']),
      firstSeenAt: _date(j['first_seen_at']),
      closingInDays: _intOrNull(j['closing_in_days']),
      isOpen: j['is_open'] == true,
      isClosingSoon: j['is_closing_soon'] == true,
      isRelevant: j['is_relevant'] == true,
      relevanceScore: _int(j['relevance_score']),
      relevance: '${j['relevance'] ?? 'other'}',
      tags: _strings(j['tags']),
      triageStatus: '${j['triage_status'] ?? 'new'}',
      pipelineStatus: '${j['pipeline_status'] ?? 'new'}',
      assignedToId: _intOrNull(assigned?['id']),
      assignedToName: assigned?['name'] as String?,
      tenderId: _intOrNull(tender?['id']),
      tenderStatus: tender?['status'] as String?,
      nestUrl: '${j['nest_url'] ?? 'https://nest.go.tz'}',
      eligibleTypes: _strings(j['eligible_types']),
      matched: [for (final m in (j['matched_keywords'] as List? ?? const [])) NestMatch.fromJson(Map<String, dynamic>.from(m as Map))],
      notes: j['notes'] as String?,
      changes: [for (final c in (j['changes'] as List? ?? const [])) NestChange.fromJson(Map<String, dynamic>.from(c as Map))],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'entity_uuid': entityUuid, 'entity_number': entityNumber, 'reference_number': referenceNumber,
    'entity_type': entityType, 'description': description, 'sub_category_name': subCategoryName,
    'sub_category_acronym': subCategoryAcronym, 'procurement_category': procurementCategory,
    'procurement_category_name': procurementCategoryName, 'procuring_entity_name': procuringEntityName,
    'procuring_entity_uuid': procuringEntityUuid, 'financial_year': financialYear, 'lot_count': lotCount,
    'has_addendum': hasAddendum, 'invitation_at': invitationAt?.toIso8601String(),
    'closing_at': closingAt?.toIso8601String(), 'first_seen_at': firstSeenAt?.toIso8601String(),
    'closing_in_days': closingInDays, 'is_open': isOpen,
    'is_closing_soon': isClosingSoon, 'is_relevant': isRelevant, 'relevance_score': relevanceScore,
    'relevance': relevance, 'tags': tags, 'triage_status': triageStatus, 'pipeline_status': pipelineStatus,
    'assigned_to': assignedToId == null ? null : {'id': assignedToId, 'name': assignedToName},
    'tender': tenderId == null ? null : {'id': tenderId, 'status': tenderStatus},
    'nest_url': nestUrl, 'eligible_types': eligibleTypes,
    'matched_keywords': [for (final m in matched) m.toJson()], 'notes': notes,
    'changes': [for (final c in changes) c.toJson()],
  };

  String get reference => referenceNumber ?? entityNumber ?? '—';
  bool get bidStarted => tenderId != null;

  /// "closes in 4 days", "closes today", "closed 3 days ago".
  String get countdown {
    final d = closingInDays;
    if (closingAt == null || d == null) return 'no closing date';
    if (!isOpen) return d == 0 ? 'closed today' : 'closed ${-d} day${d == -1 ? '' : 's'} ago';
    if (d <= 0) return 'closes today';
    if (d == 1) return 'closes tomorrow';
    return 'closes in $d days';
  }

  /// Short text for Share / clipboard.
  String summary(String Function(DateTime) fmt) => [
    description,
    ?procuringEntityName,
    'Ref: $reference',
    if (closingAt != null) 'Closes: ${fmt(toEat(closingAt!))} EAT ($countdown)',
    if (lotCount != null) 'Lots: $lotCount',
    if (hasAddendum) 'Has addendum',
    'NeST: $nestUrl',
  ].join('\n');
}

class NestMatch {
  final String term, type;
  final String? tag, note;
  final int weight;
  final bool counted;
  const NestMatch({required this.term, required this.type, this.tag, this.note, required this.weight, this.counted = true});

  factory NestMatch.fromJson(Map<String, dynamic> j) => NestMatch(
    term: '${j['term'] ?? ''}', type: '${j['type'] ?? ''}', tag: j['tag'] as String?, note: j['note'] as String?,
    weight: _int(j['weight']), counted: j['counted'] != false,
  );

  Map<String, dynamic> toJson() => {'term': term, 'type': type, 'tag': tag, 'weight': weight, 'counted': counted, 'note': note};
}

class NestChange {
  final String field;
  final String? oldValue, newValue;
  final DateTime? detectedAt;
  const NestChange({required this.field, this.oldValue, this.newValue, this.detectedAt});

  factory NestChange.fromJson(Map<String, dynamic> j) => NestChange(
    field: '${j['field'] ?? ''}', oldValue: htmlToPlainTextOrNull(j['old_value'] as String?),
    newValue: htmlToPlainTextOrNull(j['new_value'] as String?),
    detectedAt: _date(j['detected_at']),
  );

  Map<String, dynamic> toJson() => {'field': field, 'old_value': oldValue, 'new_value': newValue, 'detected_at': detectedAt?.toIso8601String()};
}

class NestRule {
  final int id;
  final String type; // keyword | exclude | health_subcategory | entity_hint
  final String? tag;
  final String term;
  final int weight;
  final bool active;
  /// null = always counts; 'text' = only with health wording in the tender;
  /// 'health' = also for a health buyer. Keywords only.
  final String? context;
  const NestRule({required this.id, required this.type, this.tag, required this.term, required this.weight, this.active = true, this.context});

  factory NestRule.fromJson(Map<String, dynamic> j) => NestRule(
    id: _int(j['id']), type: '${j['type']}', tag: j['tag'] as String?, term: '${j['term']}',
    weight: _int(j['weight']), active: j['active'] != false, context: j['context'] as String?,
  );

  Map<String, dynamic> toJson() => {'type': type, 'tag': tag, 'term': term, 'weight': weight, 'active': active, 'context': context};

  /// Group heading in the rules editor.
  String get group => type == 'keyword' ? (tag ?? 'Keyword') : type;
}

class NestEntity {
  final String uuid, name;
  final int totalCount, relevantCount;
  final DateTime? lastTenderAt, lastRelevantAt;
  const NestEntity({required this.uuid, required this.name, this.totalCount = 0, this.relevantCount = 0, this.lastTenderAt, this.lastRelevantAt});

  factory NestEntity.fromJson(Map<String, dynamic> j) => NestEntity(
    uuid: '${j['uuid']}', name: '${j['name'] ?? '—'}', totalCount: _int(j['total_count']),
    relevantCount: _int(j['relevant_count']), lastTenderAt: _date(j['last_tender_at']), lastRelevantAt: _date(j['last_relevant_at']),
  );
}

class NestSyncStatus {
  final String? lastStatus, lastError;
  final DateTime? lastOkAt, lastStartedAt;
  final int runsToday, maxRunsPerDay, totalStored;
  const NestSyncStatus({this.lastStatus, this.lastError, this.lastOkAt, this.lastStartedAt, this.runsToday = 0, this.maxRunsPerDay = 3, this.totalStored = 0});

  factory NestSyncStatus.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const NestSyncStatus();
    final last = j['last_run'] is Map ? Map<String, dynamic>.from(j['last_run'] as Map) : null;
    return NestSyncStatus(
      lastStatus: last?['status'] as String?, lastError: last?['error'] as String?,
      lastStartedAt: _date(last?['started_at']), lastOkAt: _date(j['last_ok_at']),
      runsToday: _int(j['runs_today']), maxRunsPerDay: _int(j['max_runs_per_day'] ?? 3), totalStored: _int(j['total_stored']),
    );
  }

  bool get canRunNow => runsToday < maxRunsPerDay && lastStatus != 'running';
}

class NestDashboard {
  final int openRelevant, openMaybe, closing3, closing7, newSinceVisit, myOpen;
  final Map<String, int> byTag, byPipeline;
  final List<NestEntity> topEntities;
  final NestSyncStatus sync;
  final bool canManage;
  const NestDashboard({
    this.openRelevant = 0, this.openMaybe = 0, this.closing3 = 0, this.closing7 = 0, this.newSinceVisit = 0,
    this.myOpen = 0, this.byTag = const {}, this.byPipeline = const {}, this.topEntities = const [],
    this.sync = const NestSyncStatus(), this.canManage = false,
  });

  factory NestDashboard.fromJson(Map<String, dynamic> j) {
    Map<String, int> counts(dynamic v) => {for (final e in Map<String, dynamic>.from(v as Map? ?? const {}).entries) e.key: _int(e.value)};
    return NestDashboard(
      openRelevant: _int(j['open_relevant']), openMaybe: _int(j['open_maybe']), closing3: _int(j['closing_3_days']),
      closing7: _int(j['closing_7_days']), newSinceVisit: _int(j['new_since_last_visit']), myOpen: _int(j['my_open']),
      byTag: counts(j['by_tag']), byPipeline: counts(j['by_pipeline']),
      topEntities: [for (final e in (j['top_entities'] as List? ?? const []))
        NestEntity(uuid: '${(e as Map)['procuring_entity_uuid']}', name: '${e['procuring_entity_name'] ?? '—'}', relevantCount: _int(e['relevant_count']))],
      sync: NestSyncStatus.fromJson(j['sync'] is Map ? Map<String, dynamic>.from(j['sync'] as Map) : null),
      canManage: j['can_manage'] == true,
    );
  }
}

class NestSettings {
  final Map<String, bool> notifications;
  final int threshold, maybeMin;
  final String? nestUsername, lastLoginError;
  final bool hasPassword, serverReady;
  final DateTime? lastLoginOkAt;
  final NestSyncStatus sync;
  final bool canManage;
  const NestSettings({
    this.notifications = const {}, this.threshold = 10, this.maybeMin = 5, this.nestUsername, this.lastLoginError,
    this.hasPassword = false, this.serverReady = false, this.lastLoginOkAt, this.sync = const NestSyncStatus(), this.canManage = false,
  });

  factory NestSettings.fromJson(Map<String, dynamic> j) {
    final login = Map<String, dynamic>.from(j['nest_login'] as Map? ?? const {});
    return NestSettings(
      notifications: {for (final e in Map<String, dynamic>.from(j['notifications'] as Map? ?? const {}).entries) e.key: e.value == true},
      threshold: _int(j['threshold'] ?? 10), maybeMin: _int(j['maybe_min'] ?? 5),
      nestUsername: login['username'] as String?, hasPassword: login['has_password'] == true,
      serverReady: login['server_ready'] == true, lastLoginOkAt: _date(login['last_ok_at']),
      lastLoginError: login['last_error'] as String?,
      sync: NestSyncStatus.fromJson(j['sync'] is Map ? Map<String, dynamic>.from(j['sync'] as Map) : null),
      canManage: j['can_manage'] == true,
    );
  }
}

/// List filters, sent as query parameters to GET /nest/tenders.
class NestFilter {
  final bool open;
  final String relevance; // relevant | maybe | all
  final Set<String> tags;
  final int? closingWithin;
  final bool mine, newSinceVisit;
  final Set<String> pipeline;
  final String sort; // closing | newest | score
  final String q;
  final String? entityUuid;

  const NestFilter({
    this.open = true, this.relevance = 'relevant', this.tags = const {}, this.closingWithin, this.mine = false,
    this.newSinceVisit = false, this.pipeline = const {}, this.sort = 'closing', this.q = '', this.entityUuid,
  });

  NestFilter copyWith({bool? open, String? relevance, Set<String>? tags, int? Function()? closingWithin, bool? mine,
      bool? newSinceVisit, Set<String>? pipeline, String? sort, String? q, String? Function()? entityUuid}) => NestFilter(
    open: open ?? this.open, relevance: relevance ?? this.relevance, tags: tags ?? this.tags,
    closingWithin: closingWithin != null ? closingWithin() : this.closingWithin, mine: mine ?? this.mine,
    newSinceVisit: newSinceVisit ?? this.newSinceVisit, pipeline: pipeline ?? this.pipeline, sort: sort ?? this.sort,
    q: q ?? this.q, entityUuid: entityUuid != null ? entityUuid() : this.entityUuid,
  );

  Map<String, dynamic> toQuery({int page = 1}) => {
    'page': page,
    if (open) 'open': 1,
    'relevance': relevance,
    if (tags.isNotEmpty) 'tags[]': tags.toList(),
    'closing_within': ?closingWithin,
    if (mine) 'assigned_to': 'me',
    if (newSinceVisit) 'new_since_visit': 1,
    if (pipeline.isNotEmpty) 'pipeline_status[]': pipeline.toList(),
    'sort': sort,
    if (q.trim().isNotEmpty) 'q': q.trim(),
    'procuring_entity_uuid': ?entityUuid,
  };

  @override
  bool operator ==(Object other) => other is NestFilter && other.toQuery().toString() == toQuery().toString();
  @override
  int get hashCode => toQuery().toString().hashCode;
}

/// One file NeST shows a tenderer for a tender (GET /nest/tenders/{id}/documents).
class NestDocument {
  final String id, title, kind; // kind: tender_document | clarification | pre_bid | requisition
  final String? note;
  const NestDocument({required this.id, required this.title, required this.kind, this.note});

  factory NestDocument.fromJson(Map<String, dynamic> j) =>
      NestDocument(id: '${j['id']}', title: htmlToPlainText('${j['title'] ?? 'Document'}'), kind: '${j['kind'] ?? ''}',
          note: htmlToPlainTextOrNull(j['note'] as String?));
}

class NestClarificationReply {
  final bool fromBuyer;
  final String? text;
  final DateTime? at;
  const NestClarificationReply({required this.fromBuyer, this.text, this.at});
}

class NestClarification {
  final String title;
  final String? question;
  final bool fromBuyer;
  final DateTime? at;
  final List<NestClarificationReply> replies;
  const NestClarification({required this.title, this.question, this.fromBuyer = false, this.at, this.replies = const []});

  factory NestClarification.fromJson(Map<String, dynamic> j) => NestClarification(
    title: htmlToPlainText('${j['title'] ?? 'Clarification'}'),
    question: htmlToPlainTextOrNull(j['question'] as String?),
    fromBuyer: j['from'] == 'procuring_entity',
    at: _date(j['at']),
    replies: [for (final r in (j['replies'] as List? ?? const []))
      NestClarificationReply(fromBuyer: (r as Map)['from'] == 'procuring_entity',
          text: htmlToPlainTextOrNull(r['text'] as String?), at: _date(r['at']))],
  );
}

/// Documents + clarifications + addendum for one tender, as NeST shows a tenderer.
class NestDocuments {
  final List<NestDocument> documents;
  final List<NestClarification> clarifications;
  final List<(String? area, String? reason)> addendumChanges;
  final String? addendumStatus;
  final DateTime? preBidDate;
  final String? preBidVenue;
  final List<String> errors;
  final DateTime? fetchedAt;
  const NestDocuments({this.documents = const [], this.clarifications = const [], this.addendumChanges = const [],
    this.addendumStatus, this.preBidDate, this.preBidVenue, this.errors = const [], this.fetchedAt});

  factory NestDocuments.fromJson(Map<String, dynamic> j) {
    final add = j['addendum'] is Map ? Map<String, dynamic>.from(j['addendum'] as Map) : null;
    final pre = j['pre_bid'] is Map ? Map<String, dynamic>.from(j['pre_bid'] as Map) : null;
    return NestDocuments(
      documents: [for (final d in (j['documents'] as List? ?? const [])) NestDocument.fromJson(Map<String, dynamic>.from(d as Map))],
      clarifications: [for (final c in (j['clarifications'] as List? ?? const [])) NestClarification.fromJson(Map<String, dynamic>.from(c as Map))],
      addendumChanges: [for (final c in (add?['changes'] as List? ?? const [])) (htmlToPlainTextOrNull((c as Map)['area'] as String?), htmlToPlainTextOrNull(c['reason'] as String?))],
      addendumStatus: add?['status'] as String?,
      preBidDate: _date(pre?['date']),
      preBidVenue: htmlToPlainTextOrNull(pre?['venue'] as String?),
      errors: _strings(j['errors']),
      fetchedAt: _date(j['fetched_at']),
    );
  }
}
