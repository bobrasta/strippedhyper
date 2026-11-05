import 'api_client.dart';

class TeamMember {
  const TeamMember({
    required this.id,
    required this.name,
    required this.email,
    required this.initials,
    this.zone,
    required this.availStatus,
    this.maxDiscountPercent,
    required this.openLeads,
    required this.revenueMtd,
  });

  final int id;
  final String name;
  final String email;
  final String initials;
  final String? zone;
  final String availStatus;
  final double? maxDiscountPercent;
  final int openLeads;
  final int revenueMtd;

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
    id:      (j['id'] as num).toInt(),
    name:    j['name'] as String? ?? '—',
    email:   j['email'] as String? ?? '—',
    initials: j['initials'] as String? ?? '?',
    zone:    j['zone'] as String?,
    availStatus: j['avail_status'] as String? ?? 'Available',
    maxDiscountPercent: (j['max_discount_percent'] as num?)?.toDouble(),
    openLeads: (j['open_leads'] as num? ?? 0).toInt(),
    revenueMtd: (j['revenue_mtd'] as num? ?? 0).toInt(),
  );
}

class TeamActivity {
  const TeamActivity({required this.title, required this.note, this.at});
  final String title;
  final String note;
  final DateTime? at;

  factory TeamActivity.fromJson(Map<String, dynamic> j) => TeamActivity(
    title: j['title'] as String? ?? '',
    note:  j['note'] as String? ?? '',
    at:    j['at'] != null ? DateTime.tryParse(j['at'] as String) : null,
  );
}

class UnassignedRep {
  const UnassignedRep({required this.id, required this.name, required this.email});
  final int id;
  final String name;
  final String email;

  factory UnassignedRep.fromJson(Map<String, dynamic> j) => UnassignedRep(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String? ?? '—',
    email: j['email'] as String? ?? '—',
  );
}

class SalesTeamService {
  SalesTeamService._();
  static final instance = SalesTeamService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. load() takes no filter params, so every call is the default
  // (single, unfiltered) view.
  static List<TeamMember>? cachedTeam;
  static List<TeamActivity>? cachedActivity;

  Future<(List<TeamMember>, List<TeamActivity>)> load() async {
    final res = await _dio.get('/sales-team');
    final data = ApiClient.unwrap(res) as Map<String, dynamic>;
    final team = (data['team'] as List? ?? [])
        .map((e) => TeamMember.fromJson(e as Map<String, dynamic>)).toList();
    final activity = (data['recent_activity'] as List? ?? [])
        .map((e) => TeamActivity.fromJson(e as Map<String, dynamic>)).toList();
    cachedTeam = team;
    cachedActivity = activity;
    return (team, activity);
  }

  Future<List<UnassignedRep>> unassigned() async {
    final res = await _dio.get('/sales-team/unassigned');
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((e) => UnassignedRep.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> assign(int userId) => _dio.post('/sales-team/$userId/assign');
}
