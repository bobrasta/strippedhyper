// One entry per department the current viewer holds the screens.* permission
// for — presence in this list IS the gate; nothing on the client re-checks
// permissions. `data` stays a raw JSON map since each section's shape
// genuinely differs (kpi_grid vs chart vs mixed); the unified dashboard
// screen picks the right widget per `key`.
class UnifiedDashboardSection {
  final String key;
  final String title;
  final String type;
  final Map<String, dynamic> data;

  const UnifiedDashboardSection({
    required this.key,
    required this.title,
    required this.type,
    required this.data,
  });

  factory UnifiedDashboardSection.fromJson(Map<String, dynamic> j) => UnifiedDashboardSection(
        key:   j['key']   as String? ?? '',
        title: j['title'] as String? ?? '',
        type:  j['type']  as String? ?? '',
        data:  (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}
