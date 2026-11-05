// Kept for backward-compat display when `leave_type_id`/`leave_type_label`
// aren't loaded — the real source of truth for what types exist is now the
// HR-editable /leave-types catalog (see LeaveTypeCatalogEntry below), not
// this fixed set.
enum LeaveType { sick, vacation, annual, maternity, compassionate, publicHoliday, other }

extension LeaveTypeX on LeaveType {
  String get label => switch (this) {
    LeaveType.sick          => 'Sick',
    LeaveType.vacation      => 'Vacation',
    LeaveType.annual        => 'Annual',
    LeaveType.maternity     => 'Maternity',
    LeaveType.compassionate => 'Compassionate',
    LeaveType.publicHoliday => 'Public Holiday',
    LeaveType.other         => 'Other',
  };

  String get apiValue => switch (this) {
    LeaveType.sick          => 'sick',
    LeaveType.vacation      => 'vacation',
    LeaveType.annual        => 'annual',
    LeaveType.maternity     => 'maternity',
    LeaveType.compassionate => 'compassionate',
    LeaveType.publicHoliday => 'public_holiday',
    LeaveType.other         => 'other',
  };
}

LeaveType _parseLeaveType(String s) => switch (s) {
  'sick'           => LeaveType.sick,
  'vacation'       => LeaveType.vacation,
  'annual'         => LeaveType.annual,
  'maternity'      => LeaveType.maternity,
  'compassionate'  => LeaveType.compassionate,
  'public_holiday' => LeaveType.publicHoliday,
  _                => LeaveType.other,
};

/// A row from the HR-editable /leave-types catalog — the real source of
/// truth for what leave types exist and how many days each grants.
class LeaveTypeCatalogEntry {
  final int id;
  final String key;
  final String label;
  final int defaultDaysPerYear;
  final bool requiresManualDays;
  final bool autoFromCalendar;
  final bool deductsBalance;
  final bool active;

  const LeaveTypeCatalogEntry({
    required this.id,
    required this.key,
    required this.label,
    required this.defaultDaysPerYear,
    required this.requiresManualDays,
    required this.autoFromCalendar,
    required this.deductsBalance,
    required this.active,
  });

  factory LeaveTypeCatalogEntry.fromJson(Map<String, dynamic> j) => LeaveTypeCatalogEntry(
    id:                 (j['id'] as num).toInt(),
    key:                j['key'] as String,
    label:              j['label'] as String,
    defaultDaysPerYear: (j['default_days_per_year'] as num? ?? 0).toInt(),
    requiresManualDays: j['requires_manual_days'] as bool? ?? false,
    autoFromCalendar:   j['auto_from_calendar'] as bool? ?? false,
    deductsBalance:     j['deducts_balance'] as bool? ?? true,
    active:             j['active'] as bool? ?? true,
  );
}

class LeaveBalanceEntry {
  final int leaveTypeId;
  final String leaveTypeKey;
  final String leaveTypeLabel;
  final int year;
  final double allocatedDays;
  final double usedDays;
  final double remainingDays;

  const LeaveBalanceEntry({
    required this.leaveTypeId,
    required this.leaveTypeKey,
    required this.leaveTypeLabel,
    required this.year,
    required this.allocatedDays,
    required this.usedDays,
    required this.remainingDays,
  });

  factory LeaveBalanceEntry.fromJson(Map<String, dynamic> j) => LeaveBalanceEntry(
    leaveTypeId:    (j['leave_type_id'] as num).toInt(),
    leaveTypeKey:   j['leave_type_key'] as String? ?? '',
    leaveTypeLabel: j['leave_type_label'] as String? ?? '—',
    year:           (j['year'] as num).toInt(),
    allocatedDays:  (j['allocated_days'] as num? ?? 0).toDouble(),
    usedDays:       (j['used_days'] as num? ?? 0).toDouble(),
    remainingDays:  (j['remaining_days'] as num? ?? 0).toDouble(),
  );
}

enum LeaveStatus { pending, approved, rejected, cancelled }

extension LeaveStatusX on LeaveStatus {
  String get label => switch (this) {
    LeaveStatus.pending   => 'Pending',
    LeaveStatus.approved  => 'Approved',
    LeaveStatus.rejected  => 'Rejected',
    LeaveStatus.cancelled => 'Cancelled',
  };
}

LeaveStatus _parseLeaveStatus(String s) => switch (s) {
  'approved'  => LeaveStatus.approved,
  'rejected'  => LeaveStatus.rejected,
  'cancelled' => LeaveStatus.cancelled,
  _           => LeaveStatus.pending,
};

class LeaveRequest {
  final int          id;
  final int          userId;
  final String?      userName;
  final String?      userRole;
  final LeaveType    type;
  final int?         leaveTypeId;
  final String?      leaveTypeLabel;
  final bool         requiresManualDays;
  final String       startDate;
  final String       endDate;
  final int          daysCount;
  final String?      reason;
  final LeaveStatus  status;
  final int?         reviewedBy;
  final String?      reviewerName;
  final String?      reviewedAt;
  final String?      rejectionReason;
  final String?      createdAt;

  const LeaveRequest({
    required this.id,
    required this.userId,
    this.userName,
    this.userRole,
    required this.type,
    this.leaveTypeId,
    this.leaveTypeLabel,
    this.requiresManualDays = false,
    required this.startDate,
    required this.endDate,
    required this.daysCount,
    this.reason,
    required this.status,
    this.reviewedBy,
    this.reviewerName,
    this.reviewedAt,
    this.rejectionReason,
    this.createdAt,
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> j) => LeaveRequest(
    id:              (j['id'] as num).toInt(),
    userId:          (j['user_id'] as num? ?? 0).toInt(),
    userName:        j['user_name'] as String?,
    userRole:        j['user_role'] as String?,
    type:            _parseLeaveType(j['type'] as String? ?? 'other'),
    leaveTypeId:     (j['leave_type_id'] as num?)?.toInt(),
    leaveTypeLabel:  j['leave_type_label'] as String?,
    requiresManualDays: j['requires_manual_days'] as bool? ?? false,
    startDate:       j['start_date'] as String? ?? '—',
    endDate:         j['end_date'] as String? ?? '—',
    daysCount:       (j['days_count'] as num? ?? 0).toInt(),
    reason:          j['reason'] as String?,
    status:          _parseLeaveStatus(j['status'] as String? ?? 'pending'),
    reviewedBy:      j['reviewed_by'] != null ? (j['reviewed_by'] as num).toInt() : null,
    reviewerName:    j['reviewer_name'] as String?,
    reviewedAt:      j['reviewed_at'] as String?,
    rejectionReason: j['rejection_reason'] as String?,
    createdAt:       j['created_at'] as String?,
  );

  bool get isPending  => status == LeaveStatus.pending;
  bool get canCancel  => status == LeaveStatus.pending;
  String get displayLabel => leaveTypeLabel ?? type.label;
}
