class OrgNode {
  OrgNode({
    required this.id,
    required this.label,
    this.parentId,
    required this.x,
    required this.y,
    required this.colorIndex,
  });

  String id;
  String label;
  String? parentId;
  double x;
  double y;
  int colorIndex;

  Map<String, dynamic> toJson() => {
    'id': id, 'label': label, 'parentId': parentId,
    'x': x, 'y': y, 'colorIndex': colorIndex,
  };

  factory OrgNode.fromJson(Map<String, dynamic> j) => OrgNode(
    id:         j['id'] as String,
    label:      j['label'] as String,
    parentId:   j['parentId'] as String?,
    x:          (j['x'] as num).toDouble(),
    y:          (j['y'] as num).toDouble(),
    colorIndex: (j['colorIndex'] as num?)?.toInt() ?? 0,
  );
}
