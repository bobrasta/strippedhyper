class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.category,
    required this.taskType,
    required this.priority,
    required this.status,
    required this.createdAt,
    this.description,
    this.assignedTo,
    this.assigneeName,
    this.assigneeInitials,
    this.assigneeRole,
    this.createdBy,
    this.creatorName,
    this.dueDate,
    this.startedAt,
    this.completedAt,
  });

  final int     id;
  final String  title;
  final String? description;
  final String  category;       // field | sales | finance | office | cs | general
  final String  taskType;       // PM | Customer Visit | Report | Meeting | Custom …
  final String  priority;       // critical | high | medium | low
  final String  status;         // assigned | in_progress | completed | overdue
  final int?    assignedTo;
  final String? assigneeName;
  final String? assigneeInitials;
  final String? assigneeRole;
  final int?    createdBy;
  final String? creatorName;
  final String? dueDate;        // date string YYYY-MM-DD
  final String? startedAt;      // ISO-8601
  final String? completedAt;    // ISO-8601
  final String  createdAt;      // ISO-8601

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
    id:               j['id'] as int,
    title:            j['title'] as String,
    description:      j['description'] as String?,
    category:         j['category'] as String? ?? 'general',
    taskType:         j['task_type'] as String? ?? 'Custom',
    priority:         j['priority'] as String? ?? 'medium',
    status:           j['status'] as String? ?? 'assigned',
    assignedTo:       j['assigned_to'] as int?,
    assigneeName:     j['assignee_name'] as String?,
    assigneeInitials: j['assignee_initials'] as String?,
    assigneeRole:     j['assignee_role'] as String?,
    createdBy:        j['created_by'] as int?,
    creatorName:      j['creator_name'] as String?,
    dueDate:          j['due_date'] as String?,
    startedAt:        j['started_at'] as String?,
    completedAt:      j['completed_at'] as String?,
    createdAt:        j['created_at'] as String? ?? '',
  );

  // Task types available per category — drives the form dropdown
  static const Map<String, List<String>> typesByCategory = {
    'field':   ['PM', 'Corrective', 'Inspection', 'Installation', 'Calibration', 'Service Report'],
    'sales':   ['Customer Visit', 'Follow-up Call', 'Demo', 'Proposal', 'Contract Review', 'Report'],
    'finance': ['Invoice Review', 'Monthly Report', 'Reconciliation', 'Budget Review', 'Audit'],
    'office':  ['Meeting Schedule', 'Calendar Update', 'Document Prep', 'Communication', 'Follow-up'],
    'cs':      ['Support Call', 'Issue Resolution', 'Client Update', 'Training', 'Follow-up'],
    'general': ['Custom Task'],
  };

  // Default category for each staff role
  static String defaultCategoryForRole(String? role) => switch (role) {
    'technician' => 'field',
    'sales'      => 'sales',
    'finance'    => 'finance',
    'cs'         => 'cs',
    'admin'      => 'general',
    'manager'    => 'general',
    _            => 'general',
  };
}
