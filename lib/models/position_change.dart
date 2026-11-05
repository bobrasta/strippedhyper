class PositionChange {
  final int id;
  final int userId;
  final String? fromPositionTitle;
  final int toPositionId;
  final String? toPositionTitle;
  final String changeType; // promotion | demotion | lateral
  final String effectiveDate;
  final String? reason;
  final String? approvedByName;

  const PositionChange({
    required this.id, required this.userId, this.fromPositionTitle,
    required this.toPositionId, this.toPositionTitle, required this.changeType,
    required this.effectiveDate, this.reason, this.approvedByName,
  });

  factory PositionChange.fromJson(Map<String, dynamic> j) => PositionChange(
    id:                (j['id'] as num).toInt(),
    userId:            (j['user_id'] as num).toInt(),
    fromPositionTitle: j['from_position_title'] as String?,
    toPositionId:      (j['to_position_id'] as num).toInt(),
    toPositionTitle:   j['to_position_title'] as String?,
    changeType:        j['change_type'] as String,
    effectiveDate:     j['effective_date'] as String? ?? '—',
    reason:            j['reason'] as String?,
    approvedByName:    j['approved_by_name'] as String?,
  );
}
