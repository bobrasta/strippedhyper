// Response shape for GET /dashboard/admin-overview — the admin-only
// "Command Centre". Mirrors the backend response; the service/fleet parts
// of that response (machines, technicians, map zones) are ignored here.
class AdminGreeting {
  final String name;
  final String date;

  const AdminGreeting({required this.name, required this.date});

  factory AdminGreeting.fromJson(Map<String, dynamic> j) => AdminGreeting(
        name: j['name'] as String? ?? '',
        date: j['date'] as String? ?? '',
      );
}

class AttentionItem {
  final String title;
  final String meta;
  final String? age;
  final String severity;

  const AttentionItem({required this.title, required this.meta, this.age, required this.severity});

  factory AttentionItem.fromJson(Map<String, dynamic> j) => AttentionItem(
        title:    j['title'] as String? ?? '',
        meta:     j['meta'] as String? ?? '',
        age:      j['age'] as String?,
        severity: j['severity'] as String? ?? 'info',
      );
}

class AdminOverview {
  final AdminGreeting greeting;
  final Map<String, dynamic> kpis;
  final List<AttentionItem> attention;
  final Map<String, dynamic> sales;
  final Map<String, dynamic> finance;
  final Map<String, dynamic> inventory;
  final Map<String, dynamic> people;

  const AdminOverview({
    required this.greeting, required this.kpis, required this.attention,
    required this.sales, required this.finance, required this.inventory, required this.people,
  });

  factory AdminOverview.fromJson(Map<String, dynamic> j) => AdminOverview(
        greeting: AdminGreeting.fromJson((j['greeting'] as Map?)?.cast<String, dynamic>() ?? const {}),
        kpis: (j['kpis'] as Map?)?.cast<String, dynamic>() ?? const {},
        attention: (j['attention'] as List? ?? [])
            .map((a) => AttentionItem.fromJson((a as Map).cast<String, dynamic>())).toList(),
        sales:     (j['sales'] as Map?)?.cast<String, dynamic>() ?? const {},
        finance:   (j['finance'] as Map?)?.cast<String, dynamic>() ?? const {},
        inventory: (j['inventory'] as Map?)?.cast<String, dynamic>() ?? const {},
        people:    (j['people'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}
