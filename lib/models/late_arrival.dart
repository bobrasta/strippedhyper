class LateArrival {
  final int     id;
  final int     userId;
  final String? userName;
  final String  date;
  final String? expectedTime;
  final String? reason;
  final String? createdAt;

  const LateArrival({
    required this.id,
    required this.userId,
    this.userName,
    required this.date,
    this.expectedTime,
    this.reason,
    this.createdAt,
  });

  factory LateArrival.fromJson(Map<String, dynamic> j) => LateArrival(
    id:           (j['id'] as num).toInt(),
    userId:       (j['user_id'] as num? ?? 0).toInt(),
    userName:     j['user_name'] as String?,
    date:         j['date'] as String? ?? '—',
    expectedTime: j['expected_time'] as String?,
    reason:       j['reason'] as String?,
    createdAt:    j['created_at'] as String?,
  );
}
