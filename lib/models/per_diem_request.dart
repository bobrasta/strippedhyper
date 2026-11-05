// Five real stages: requester -> team lead -> CTO -> finance (initiates
// payment, doesn't move money on their own authority) -> Director
// (authorizes/actually marks paid). 'approved' is kept only so any old
// cached/offline data still parses to something sane; the backend no
// longer writes it.
enum PerDiemStatus { pendingTeamLead, pendingCto, pendingPayment, pendingDirector, approved, paid, rejected, cancelled }

extension PerDiemStatusX on PerDiemStatus {
  String get label => switch (this) {
    PerDiemStatus.pendingTeamLead => 'Awaiting Team Lead',
    PerDiemStatus.pendingCto      => 'Awaiting CTO',
    PerDiemStatus.pendingPayment  => 'Awaiting Payment Initiation',
    PerDiemStatus.pendingDirector => 'Awaiting Director Authorization',
    PerDiemStatus.approved        => 'Approved',
    PerDiemStatus.paid            => 'Paid',
    PerDiemStatus.rejected        => 'Rejected',
    PerDiemStatus.cancelled       => 'Cancelled',
  };
}

PerDiemStatus _parsePerDiemStatus(String s) => switch (s) {
  'pending_cto'      => PerDiemStatus.pendingCto,
  'pending_payment'  => PerDiemStatus.pendingPayment,
  'pending_director' => PerDiemStatus.pendingDirector,
  'approved'         => PerDiemStatus.approved,
  'paid'             => PerDiemStatus.paid,
  'rejected'         => PerDiemStatus.rejected,
  'cancelled'        => PerDiemStatus.cancelled,
  _                  => PerDiemStatus.pendingTeamLead,
};

class PerDiemLine {
  final int?    id;
  final int     seqNo;
  final String  date;
  final String? region;
  final String? district;
  final String? siteName;
  final String? activity;
  final int     laborCost;
  final int     perDiemCost;
  final int     transportFare;

  const PerDiemLine({
    this.id,
    required this.seqNo,
    required this.date,
    this.region,
    this.district,
    this.siteName,
    this.activity,
    this.laborCost = 0,
    this.perDiemCost = 0,
    this.transportFare = 0,
  });

  int get total => laborCost + perDiemCost + transportFare;

  factory PerDiemLine.fromJson(Map<String, dynamic> j) => PerDiemLine(
    id:            (j['id'] as num?)?.toInt(),
    seqNo:         (j['seq_no'] as num? ?? 0).toInt(),
    date:          j['date'] as String? ?? '',
    region:        j['region'] as String?,
    district:      j['district'] as String?,
    siteName:      j['site_name'] as String?,
    activity:      j['activity'] as String?,
    laborCost:     (j['labor_cost'] as num? ?? 0).toInt(),
    perDiemCost:   (j['per_diem_cost'] as num? ?? 0).toInt(),
    transportFare: (j['transport_fare'] as num? ?? 0).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'date':           date,
    'region':         region,
    'district':       district,
    'site_name':      siteName,
    'activity':       activity,
    'labor_cost':     laborCost,
    'per_diem_cost':  perDiemCost,
    'transport_fare': transportFare,
  };
}

// Section 8: "every edit creates a revision: who, what changed, old and
// new values, time, reason." Also doubles as the technician-edit approval
// queue (status pending_cto_approval while awaiting CTO review).
class PerDiemRevision {
  final int     id;
  final String? editedByName;
  final String  editorRole; // cto | technician
  final String  status;     // applied | pending_cto_approval | rejected
  final String  reason;
  final String? reviewedByName;
  final String? reviewedAt;
  final String? createdAt;

  const PerDiemRevision({
    required this.id,
    this.editedByName,
    required this.editorRole,
    required this.status,
    required this.reason,
    this.reviewedByName,
    this.reviewedAt,
    this.createdAt,
  });

  bool get isPendingReview => status == 'pending_cto_approval';

  factory PerDiemRevision.fromJson(Map<String, dynamic> j) => PerDiemRevision(
    id:             (j['id'] as num).toInt(),
    editedByName:   j['edited_by_name'] as String?,
    editorRole:     j['editor_role'] as String? ?? 'cto',
    status:         j['status'] as String? ?? 'applied',
    reason:         j['reason'] as String? ?? '',
    reviewedByName: j['reviewed_by_name'] as String?,
    reviewedAt:     j['reviewed_at'] as String?,
    createdAt:      j['created_at'] as String?,
  );
}

// Section 8: "the CTO grants edit permission on a specific plan... with an
// optional expiry, and can revoke it at any time."
class PerDiemEditGrant {
  final int     id;
  final String? grantedByName;
  final String? expiresAt;
  final String? revokedAt;
  final bool    isActive;

  const PerDiemEditGrant({
    required this.id,
    this.grantedByName,
    this.expiresAt,
    this.revokedAt,
    required this.isActive,
  });

  factory PerDiemEditGrant.fromJson(Map<String, dynamic> j) => PerDiemEditGrant(
    id:            (j['id'] as num).toInt(),
    grantedByName: j['granted_by_name'] as String?,
    expiresAt:     j['expires_at'] as String?,
    revokedAt:     j['revoked_at'] as String?,
    isActive:      j['is_active'] as bool? ?? false,
  );
}

// Section 8: "the original release is never rewritten... record an
// adjustment (extra amount to send, or amount to return)."
class PerDiemAdjustment {
  final int     id;
  final int     amount; // signed: + owed to technician, - to recover
  final String  reason;
  final String? createdByName;
  final String? createdAt;

  const PerDiemAdjustment({
    required this.id,
    required this.amount,
    required this.reason,
    this.createdByName,
    this.createdAt,
  });

  factory PerDiemAdjustment.fromJson(Map<String, dynamic> j) => PerDiemAdjustment(
    id:            (j['id'] as num).toInt(),
    amount:        (j['amount'] as num? ?? 0).toInt(),
    reason:        j['reason'] as String? ?? '',
    createdByName: j['created_by_name'] as String?,
    createdAt:     j['created_at'] as String?,
  );
}

// Section 15.3: computed server-side (PerDiemRequest::summary() in the
// API) so web, Flutter, PDF and XLSX always agree — never recomputed
// client-side.
class PerDiemSummary {
  final int    totalLabor;
  final int    totalPerDiem;
  final int    totalTransport;
  final int    grandTotal;
  final int    daysSpent;
  final int    sitesVisited;
  final double? avgDaysPerSite;
  final double? avgCostPerSite;

  const PerDiemSummary({
    required this.totalLabor,
    required this.totalPerDiem,
    required this.totalTransport,
    required this.grandTotal,
    required this.daysSpent,
    required this.sitesVisited,
    this.avgDaysPerSite,
    this.avgCostPerSite,
  });

  factory PerDiemSummary.fromJson(Map<String, dynamic> j) => PerDiemSummary(
    totalLabor:     (j['total_labor'] as num? ?? 0).toInt(),
    totalPerDiem:   (j['total_per_diem'] as num? ?? 0).toInt(),
    totalTransport: (j['total_transport'] as num? ?? 0).toInt(),
    grandTotal:     (j['grand_total'] as num? ?? 0).toInt(),
    daysSpent:      (j['days_spent'] as num? ?? 0).toInt(),
    sitesVisited:   (j['sites_visited'] as num? ?? 0).toInt(),
    avgDaysPerSite: (j['avg_days_per_site'] as num?)?.toDouble(),
    avgCostPerSite: (j['avg_cost_per_site'] as num?)?.toDouble(),
  );
}

// Section 15.7: masked to the last 4 digits unless the viewer is the
// plan's own requester, accountant/finance-tier, or admin-tier — see
// PerDiemRequestResource::paymentSnapshotForViewer() (server-enforced,
// this is just what the API already decided to send).
class PerDiemPaymentSnapshot {
  final String? provider;
  final String? accountNumber;
  final String? accountName;
  final bool    masked;

  const PerDiemPaymentSnapshot({this.provider, this.accountNumber, this.accountName, required this.masked});

  factory PerDiemPaymentSnapshot.fromJson(Map<String, dynamic> j) => PerDiemPaymentSnapshot(
    provider:      j['provider'] as String?,
    accountNumber: j['account_number'] as String?,
    accountName:   j['account_name'] as String?,
    masked:        j['masked'] as bool? ?? true,
  );
}

// Section 15.6: one line per real approval stage, built server-side from
// the plan's actual actor/timestamp columns — never hardcoded names.
class PerDiemSignatureLine {
  final String  stage;
  final String  roleLabel;
  final String? personName;
  final String? actedAtDisplay;
  final bool    pending;

  const PerDiemSignatureLine({
    required this.stage,
    required this.roleLabel,
    this.personName,
    this.actedAtDisplay,
    required this.pending,
  });

  factory PerDiemSignatureLine.fromJson(Map<String, dynamic> j) => PerDiemSignatureLine(
    stage:          j['stage'] as String? ?? '',
    roleLabel:      j['role_label'] as String? ?? '',
    personName:     j['person_name'] as String?,
    actedAtDisplay: j['acted_at_display'] as String?,
    pending:        j['pending'] as bool? ?? true,
  );
}

class PerDiemRequest {
  final int             id;
  final int             userId;
  final String?         userName;
  final String?         staffNameSnapshot;
  final String?         staffDesignationSnapshot;
  final PerDiemPaymentSnapshot? paymentSnapshot;
  final int?            serviceTicketId;
  final String          destination;
  final String          startDate;
  final String          endDate;
  final int             daysCount;
  final int?            dailyRate;
  final int             amount;
  final String?         purpose;
  final PerDiemStatus   status;
  final int?            teamLeadReviewedBy;
  final String?         teamLeadReviewerName;
  final String?         teamLeadReviewedAt;
  final String?         teamLeadRejectionReason;
  final int?            reviewedBy;
  final String?         reviewerName;
  final String?         reviewedAt;
  final String?         rejectionReason;
  final int?            paymentInitiatedBy;
  final String?         paymentInitiatedByName;
  final String?         paymentInitiatedAt;
  final String?         paymentMethod;
  final String?         paymentReference;
  final String?         paidByName;
  final String?         paidAt;
  final String?         cancelledByName;
  final String?         cancelledAt;
  final String?         cancellationReason;
  final String?         createdAt;
  final List<PerDiemLine> lines;
  final List<PerDiemRevision> revisions;
  final List<PerDiemEditGrant> editGrants;
  final List<PerDiemAdjustment> adjustments;
  final bool hasActiveEditGrant;
  final bool wasEdited;
  final PerDiemSummary? summary;
  final List<PerDiemSignatureLine> signatureBlock;

  const PerDiemRequest({
    required this.id,
    required this.userId,
    this.userName,
    this.staffNameSnapshot,
    this.staffDesignationSnapshot,
    this.paymentSnapshot,
    this.serviceTicketId,
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.daysCount,
    this.dailyRate,
    required this.amount,
    this.purpose,
    required this.status,
    this.teamLeadReviewedBy,
    this.teamLeadReviewerName,
    this.teamLeadReviewedAt,
    this.teamLeadRejectionReason,
    this.reviewedBy,
    this.reviewerName,
    this.reviewedAt,
    this.rejectionReason,
    this.paymentInitiatedBy,
    this.paymentInitiatedByName,
    this.paymentInitiatedAt,
    this.paymentMethod,
    this.paymentReference,
    this.paidByName,
    this.paidAt,
    this.cancelledByName,
    this.cancelledAt,
    this.cancellationReason,
    this.createdAt,
    this.lines = const [],
    this.revisions = const [],
    this.editGrants = const [],
    this.adjustments = const [],
    this.hasActiveEditGrant = false,
    this.wasEdited = false,
    this.summary,
    this.signatureBlock = const [],
  });

  factory PerDiemRequest.fromJson(Map<String, dynamic> j) => PerDiemRequest(
    id:                      (j['id'] as num).toInt(),
    userId:                  (j['user_id'] as num? ?? 0).toInt(),
    userName:                j['user_name'] as String?,
    staffNameSnapshot:        j['staff_name_snapshot'] as String?,
    staffDesignationSnapshot: j['staff_designation_snapshot'] as String?,
    paymentSnapshot: j['payment_snapshot'] != null
        ? PerDiemPaymentSnapshot.fromJson(j['payment_snapshot'] as Map<String, dynamic>)
        : null,
    serviceTicketId:         j['service_ticket_id'] != null ? (j['service_ticket_id'] as num).toInt() : null,
    destination:             j['destination'] as String? ?? '—',
    startDate:               j['start_date'] as String? ?? '—',
    endDate:                 j['end_date'] as String? ?? '—',
    daysCount:               (j['days_count'] as num? ?? 0).toInt(),
    dailyRate:               (j['daily_rate'] as num?)?.toInt(),
    amount:                  (j['amount'] as num? ?? 0).toInt(),
    purpose:                 j['purpose'] as String?,
    status:                  _parsePerDiemStatus(j['status'] as String? ?? 'pending_team_lead'),
    teamLeadReviewedBy:      j['team_lead_reviewed_by'] != null ? (j['team_lead_reviewed_by'] as num).toInt() : null,
    teamLeadReviewerName:    j['team_lead_reviewer_name'] as String?,
    teamLeadReviewedAt:      j['team_lead_reviewed_at'] as String?,
    teamLeadRejectionReason: j['team_lead_rejection_reason'] as String?,
    reviewedBy:              j['reviewed_by'] != null ? (j['reviewed_by'] as num).toInt() : null,
    reviewerName:            j['reviewer_name'] as String?,
    reviewedAt:              j['reviewed_at'] as String?,
    rejectionReason:         j['rejection_reason'] as String?,
    paymentInitiatedBy:      j['payment_initiated_by'] != null ? (j['payment_initiated_by'] as num).toInt() : null,
    paymentInitiatedByName:  j['payment_initiated_by_name'] as String?,
    paymentInitiatedAt:      j['payment_initiated_at'] as String?,
    paymentMethod:           j['payment_method'] as String?,
    paymentReference:        j['payment_reference'] as String?,
    paidByName:              j['paid_by_name'] as String?,
    paidAt:                  j['paid_at'] as String?,
    cancelledByName:         j['cancelled_by_name'] as String?,
    cancelledAt:             j['cancelled_at'] as String?,
    cancellationReason:      j['cancellation_reason'] as String?,
    createdAt:               j['created_at'] as String?,
    lines: (j['lines'] as List<dynamic>? ?? [])
        .map((l) => PerDiemLine.fromJson(l as Map<String, dynamic>)).toList(),
    revisions: (j['revisions'] as List<dynamic>? ?? [])
        .map((r) => PerDiemRevision.fromJson(r as Map<String, dynamic>)).toList(),
    editGrants: (j['edit_grants'] as List<dynamic>? ?? [])
        .map((g) => PerDiemEditGrant.fromJson(g as Map<String, dynamic>)).toList(),
    adjustments: (j['adjustments'] as List<dynamic>? ?? [])
        .map((a) => PerDiemAdjustment.fromJson(a as Map<String, dynamic>)).toList(),
    hasActiveEditGrant: j['has_active_edit_grant'] as bool? ?? false,
    wasEdited:          j['was_edited'] as bool? ?? false,
    summary: j['summary'] != null ? PerDiemSummary.fromJson(j['summary'] as Map<String, dynamic>) : null,
    signatureBlock: (j['signature_block'] as List<dynamic>? ?? [])
        .map((s) => PerDiemSignatureLine.fromJson(s as Map<String, dynamic>)).toList(),
  );

  bool get isPendingTeamLead     => status == PerDiemStatus.pendingTeamLead;
  bool get isPendingCto          => status == PerDiemStatus.pendingCto;
  bool get isPendingPayment      => status == PerDiemStatus.pendingPayment;
  bool get isPendingDirector     => status == PerDiemStatus.pendingDirector;
  bool get isPaid                => status == PerDiemStatus.paid;
}
