class NotificationTemplate {
  final int    id;
  final String templateKey;
  final String notificationType;
  final String titleTemplate;
  final String bodyTemplate;
  final String? description;

  const NotificationTemplate({
    required this.id,
    required this.templateKey,
    required this.notificationType,
    required this.titleTemplate,
    required this.bodyTemplate,
    this.description,
  });

  factory NotificationTemplate.fromJson(Map<String, dynamic> j) => NotificationTemplate(
    id:               (j['id'] as num).toInt(),
    templateKey:      j['template_key'] as String? ?? '',
    notificationType: j['notification_type'] as String? ?? '',
    titleTemplate:    j['title_template'] as String? ?? '',
    bodyTemplate:     j['body_template'] as String? ?? '',
    description:      j['description'] as String?,
  );

  // 'expense.approved_requester' -> 'Expense'
  String get category {
    final head = templateKey.split('.').first;
    return head.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }
}
