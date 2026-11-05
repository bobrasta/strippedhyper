import '../widgets/common/avatar_widget.dart';

enum AvailStatus { available, assigned, onTask, busy, atDesk, offDuty }

extension AvailStatusX on AvailStatus {
  String get label => switch (this) {
    AvailStatus.available => 'Available',
    AvailStatus.assigned  => 'Assigned',
    AvailStatus.onTask    => 'On task',
    AvailStatus.busy      => 'Busy',
    AvailStatus.atDesk    => 'At desk',
    AvailStatus.offDuty   => 'Off duty',
  };
}

AvailStatus _parseStatus(String s) => switch (s.toLowerCase()) {
  'available'   => AvailStatus.available,
  'assigned'    => AvailStatus.assigned,
  'on_task' || 'on task'  => AvailStatus.onTask,
  'busy'        => AvailStatus.busy,
  'at_desk' || 'at desk'  => AvailStatus.atDesk,
  'off_duty' || 'off duty' => AvailStatus.offDuty,
  _             => AvailStatus.available,
};

String _initials(String name) {
  final parts = name.trim().split(' ');
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
  return '?';
}

AvatarVariant _variantFromId(int id) {
  const variants = AvatarVariant.values;
  return variants[id % variants.length];
}

class StaffMember {
  final int    id;
  final String name;
  final String initials;
  final String role;
  final String? group;   // 'field' | 'office' | 'admin'
  final String? zone;
  final AvailStatus availStatus;
  final double workload; // 0.0–1.0
  final AvatarVariant variant;
  final String? currentTask;
  final String? email;
  final String? phone;
  final bool? twoFa;
  final DateTime? lastActiveAt;
  final int? managerId;
  final int? positionId;
  final String? positionTitle;
  final String? gender;
  final DateTime? hireDate;
  final String? nextOfKinName;
  final String? nextOfKinPhone;
  final String? nextOfKinRelationship;
  final String? nssfNumber;
  final String? tinNumber;
  final String? nidaNumber;
  final String? biometricId;

  const StaffMember({
    required this.id,
    required this.name,
    required this.initials,
    required this.role,
    this.group,
    this.zone,
    this.availStatus = AvailStatus.available,
    this.workload = 0.0,
    this.variant = AvatarVariant.teal,
    this.currentTask,
    this.email,
    this.phone,
    this.twoFa,
    this.lastActiveAt,
    this.managerId,
    this.positionId,
    this.positionTitle,
    this.gender,
    this.hireDate,
    this.nextOfKinName,
    this.nextOfKinPhone,
    this.nextOfKinRelationship,
    this.nssfNumber,
    this.tinNumber,
    this.nidaNumber,
    this.biometricId,
  });

  factory StaffMember.fromJson(Map<String, dynamic> j) {
    final id   = (j['id'] as num).toInt();
    final name = j['name'] as String? ?? '—';
    return StaffMember(
      id:          id,
      name:        name,
      initials:    j['initials'] as String? ?? _initials(name),
      role:        j['role'] as String? ?? j['job_title'] as String? ?? '—',
      group:       j['group'] as String? ?? _groupFromRole(j['role'] as String? ?? ''),
      zone:        j['zone']  as String? ?? j['region'] as String?,
      availStatus: _parseStatus(j['avail_status'] as String? ?? j['availability'] as String? ?? 'available'),
      workload:    (j['workload'] as num? ?? 0).toDouble(),
      variant:     _variantFromId(id),
      currentTask: j['current_task'] is Map
          ? (j['current_task'] as Map)['title'] as String?
          : j['current_task'] as String?,
      email:       j['email'] as String?,
      phone:       j['phone'] as String?,
      twoFa:       j['two_factor_enabled'] as bool? ?? j['two_fa'] as bool?,
      lastActiveAt: j['last_active_at'] != null
          ? DateTime.tryParse(j['last_active_at'] as String)
          : null,
      managerId:     (j['manager_id'] as num?)?.toInt(),
      positionId:    (j['position_id'] as num?)?.toInt(),
      positionTitle: j['position_title'] as String?,
      gender:        j['gender'] as String?,
      hireDate:      j['hire_date'] != null ? DateTime.tryParse(j['hire_date'] as String) : null,
      nextOfKinName:         j['next_of_kin_name'] as String?,
      nextOfKinPhone:        j['next_of_kin_phone'] as String?,
      nextOfKinRelationship: j['next_of_kin_relationship'] as String?,
      nssfNumber:  j['nssf_number'] as String?,
      tinNumber:   j['tin_number'] as String?,
      nidaNumber:  j['nida_number'] as String?,
      biometricId: j['biometric_id'] as String?,
    );
  }

  bool get isAvailable =>
      availStatus == AvailStatus.available || availStatus == AvailStatus.atDesk;

  // Change-detection only, not a general equality operator — used to skip
  // a staffNotifier update (and the rebuild it triggers everywhere) when a
  // background poll's fetch is identical to what's already cached.
  // Deliberately excludes lastActiveAt: that field ticks on every request
  // for an active user, so including it would mean "nothing changed" never
  // actually holds and every poll would notify regardless.
  String get syncSignature => [
    id, name, role, group, zone, availStatus, workload, currentTask,
    email, phone, twoFa, managerId, positionId, positionTitle, gender,
    hireDate, nextOfKinName, nextOfKinPhone, nextOfKinRelationship,
    nssfNumber, tinNumber, nidaNumber, biometricId,
  ].join('');
}

String _groupFromRole(String role) {
  final r = role.toLowerCase();
  if (r.contains('tech')) return 'field';
  if (r.contains('admin') || r.contains('owner')) return 'admin';
  return 'office';
}
