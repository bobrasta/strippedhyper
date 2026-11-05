// Section 18 — import/export shipments (ShipmentController). The status is a
// 1-based step index; its labels come from the API (relabelable in Shipments
// settings), and every gate is enforced server-side (ShipmentFlow).

int? _int(dynamic v) => v == null ? null : (v as num).toInt();
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

/// none · action (documents incomplete) · blocked (next step gated) · done.
enum ShipmentFlag { none, action, blocked, done }

ShipmentFlag _flag(dynamic v) => switch (v) {
  'action' => ShipmentFlag.action,
  'blocked' => ShipmentFlag.blocked,
  'done' => ShipmentFlag.done,
  _ => ShipmentFlag.none,
};

String freightLabel(String mode) => switch (mode) { 'air' => 'Air', 'road' => 'Road', _ => 'Sea' };

class ShipmentDocument {
  const ShipmentDocument({required this.type, required this.label, required this.required, this.notApplicable = false,
    this.forRecords = false, this.fileName, this.uploadedBy, this.uploadedAt});
  final String type;
  final String label;
  final bool required;
  /// The COA when the shipment is marked "COA not required"; the COA and TMDA
  /// permit for non-medical goods.
  final bool notApplicable;
  /// Optional papers kept for the record from "Assessment received" on
  /// (assessment notice, customs release, other clearing documents).
  final bool forRecords;
  final String? fileName;
  final String? uploadedBy;
  final DateTime? uploadedAt;
  bool get isUploaded => fileName != null;

  factory ShipmentDocument.fromJson(Map<String, dynamic> j) => ShipmentDocument(
    type: j['type'] as String,
    label: j['label'] as String,
    required: j['required'] == true,
    notApplicable: j['not_applicable'] == true,
    forRecords: j['for_records'] == true,
    fileName: j['file_name'] as String?,
    uploadedBy: j['uploaded_by'] as String?,
    uploadedAt: _date(j['uploaded_at']),
  );
}

class ShipmentEvent {
  const ShipmentEvent({required this.toStep, required this.label, this.fromStep, this.note, this.reason, this.backward = false, this.by, this.at});
  final int? fromStep;
  final int toStep;
  final String label;
  final String? note;
  final String? reason;
  final bool backward;
  final String? by;
  final DateTime? at;

  factory ShipmentEvent.fromJson(Map<String, dynamic> j) => ShipmentEvent(
    fromStep: _int(j['from_step']),
    toStep: _int(j['to_step'])!,
    label: j['label'] as String,
    note: j['note'] as String?,
    reason: j['reason'] as String?,
    backward: j['backward'] == true,
    by: j['by'] as String?,
    at: _date(j['at']),
  );
}

/// Read model of the linked Section 16 vendor fee — payment happens there.
class ClearingFee {
  const ClearingFee({required this.id, required this.billed, required this.receiptsTotal, required this.status,
    this.vendorId, this.vendorName, this.description, this.receiptUploaded = false, this.financeVerified = false, this.blockReason,
    this.apiStatusLabel, this.receiptAfterPayment = false, this.receiptFollowUp});
  final int id;
  final int? vendorId;
  /// The API's own label (e.g. "Awaiting payment request", "Paid · receipt to follow").
  final String? apiStatusLabel;
  /// Clearing fees are paid first; the agent's receipt follows (2026-10-26).
  final bool receiptAfterPayment;
  /// Paid but the receipt hasn't fully come in: what's missing.
  final String? receiptFollowUp;
  final String? vendorName;
  final String? description;
  final int billed;
  final int receiptsTotal;
  final bool receiptUploaded;
  final bool financeVerified;
  final String status; // pending_receipt · ready_for_payment · paid · rejected
  final String? blockReason;
  bool get paid => status == 'paid';

  /// A receipt can go on now: awaiting it, or (paid first) until it's in.
  bool get canAttachReceipt => status == 'pending_receipt' || (receiptAfterPayment && status != 'rejected' && receiptsTotal < billed);

  String get statusLabel => apiStatusLabel ?? switch (status) {
    'paid' => 'Paid',
    'rejected' => 'Rejected',
    'ready_for_payment' => 'Awaiting Director approval',
    _ => 'Awaiting receipt',
  };

  factory ClearingFee.fromJson(Map<String, dynamic> j) => ClearingFee(
    id: _int(j['id'])!,
    vendorId: _int(j['vendor_id']),
    apiStatusLabel: j['status_label'] as String?,
    receiptAfterPayment: j['receipt_after_payment'] == true,
    receiptFollowUp: j['receipt_follow_up'] as String?,
    vendorName: j['vendor_name'] as String?,
    description: j['description'] as String?,
    billed: _int(j['billed']) ?? 0,
    receiptsTotal: _int(j['receipts_total']) ?? 0,
    receiptUploaded: j['receipt_uploaded'] == true,
    financeVerified: j['finance_verified'] == true,
    status: j['status'] as String? ?? 'pending_receipt',
    blockReason: j['block_reason'] as String?,
  );
}

class Shipment {
  Shipment(this.raw);
  final Map<String, dynamic> raw;

  int get id => _int(raw['id'])!;
  String get reference => raw['reference'] as String;
  String get direction => raw['direction'] as String? ?? 'import';
  bool get isImport => direction == 'import';
  String get freightMode => raw['freight_mode'] as String? ?? 'sea';
  String get description => raw['description'] as String? ?? '';
  String? get supplierName => raw['supplier_name'] as String?;
  String? get poNumber => raw['po_number'] as String?;
  String? get outboundReason => raw['outbound_reason'] as String?;
  int? get departmentId => _int(raw['department_id']);
  String? get departmentName => raw['department_name'] as String?;
  int get step => _int(raw['step']) ?? 1;
  int get lastStep => _int(raw['last_step']) ?? 10;
  String get statusLabel => raw['status_label'] as String? ?? '';
  ShipmentFlag get flag => _flag(raw['flag']);
  String? get flagReason => raw['flag_reason'] as String?;
  int get docsUploaded => _int(raw['docs_uploaded']) ?? 0;
  int get docsRequired => _int(raw['docs_required']) ?? 0;
  DateTime? get expectedArrival => _date(raw['expected_arrival']);
  String? get locationNotes => raw['location_notes'] as String?;
  String? get feeStatus => raw['fee_status'] as String?;
  bool get coaRequired => raw['coa_required'] != false;
  /// medical · non_medical. Non-medical goods: every document optional, no TMDA permit.
  String get goodsCategory => raw['goods_category'] as String? ?? 'medical';
  bool get nonMedical => goodsCategory == 'non_medical';
  /// hypermed · manufacturer ("no cost to HyperMed": no clearing fee to wait for).
  String get costBearer => raw['cost_bearer'] as String? ?? 'hypermed';
  bool get manufacturerPaid => costBearer == 'manufacturer';
  String? get paidBy => raw['paid_by'] as String?;
  String? get costNote => raw['cost_note'] as String?;
  /// HyperMed's clearing cost: 0 when the manufacturer paid, null while no fee is recorded.
  int? get clearingCost => _int(raw['clearing_cost']);
  int? get carrierVendorId => _int(raw['carrier_vendor_id']);
  String? get carrierName => raw['carrier_name'] as String?;
  DateTime? get updatedAt => _date(raw['updated_at']);
  bool get isDone => flag == ShipmentFlag.done;

  // ── detail-only fields ──
  List<String> get labels => [for (final l in (raw['labels'] as List? ?? [])) l as String];
  String? get port => raw['port'] as String?;
  int? get supplierId => _int(raw['supplier_id']);
  int? get purchaseOrderId => _int(raw['purchase_order_id']);
  Map<String, dynamic>? get tender => raw['tender'] == null ? null : Map<String, dynamic>.from(raw['tender'] as Map);
  String? get departmentManager => raw['department_manager'] as String?;
  /// People picked to be notified of this shipment (they can also open it).
  List<Map<String, dynamic>> get notifyUsers => [for (final u in (raw['notify_users'] as List? ?? [])) Map<String, dynamic>.from(u as Map)];
  Map<String, dynamic>? get tmda => raw['tmda'] == null ? null : Map<String, dynamic>.from(raw['tmda'] as Map);
  String? get controlNumber => raw['control_number'] as String?;
  /// The import permit sent to the courier (e.g. DHL) — recorded whoever pays.
  DateTime? get permitSentAt => _date(tmda?['sent_at']);
  int? get permitSentVendorId => _int(tmda?['sent_vendor_id']);
  String? get permitSentVendorName => tmda?['sent_vendor_name'] as String?;
  List<ShipmentDocument> get documents =>
      [for (final d in (raw['documents'] as List? ?? [])) ShipmentDocument.fromJson(Map<String, dynamic>.from(d as Map))];
  ClearingFee? get clearingFee =>
      raw['clearing_fee'] == null ? null : ClearingFee.fromJson(Map<String, dynamic>.from(raw['clearing_fee'] as Map));
  /// Storage & handling (Swissport etc.) the clearing agent paid for us,
  /// entered at "Arrived at HQ" and owed to the agent.
  ClearingFee? get handlingFee =>
      raw['handling_fee'] == null ? null : ClearingFee.fromJson(Map<String, dynamic>.from(raw['handling_fee'] as Map));
  List<ShipmentEvent> get events =>
      [for (final e in (raw['events'] as List? ?? [])) ShipmentEvent.fromJson(Map<String, dynamic>.from(e as Map))];
  String? get nextBlockReason => raw['next_block_reason'] as String?;
  String? get createdByName => raw['created_by_name'] as String?;
  bool get canManage => raw['can_manage'] == true;
  bool get canApproveFee => raw['can_approve_fee'] == true;
  List<Map<String, dynamic>> get recipients => [for (final r in (raw['recipients'] as List? ?? [])) Map<String, dynamic>.from(r as Map)];

  String labelFor(int step) => step >= 1 && step <= labels.length ? labels[step - 1] : 'Step $step';
}

class ShipmentList {
  const ShipmentList({required this.shipments, required this.counts, required this.canManage});
  final List<Shipment> shipments;
  final Map<String, int> counts;
  final bool canManage;
}

class Department {
  const Department({required this.id, required this.name, this.managerId, this.managerName});
  final int id;
  final String name;
  final int? managerId;
  final String? managerName;
  factory Department.fromJson(Map<String, dynamic> j) => Department(
    id: _int(j['id'])!, name: j['name'] as String, managerId: _int(j['manager_id']), managerName: j['manager_name'] as String?);
}

/// Pick-lists for the create/edit forms (GET /shipments/options).
class ShipmentOptions {
  ShipmentOptions(this.raw);
  final Map<String, dynamic> raw;
  List<Map<String, dynamic>> _list(String k) => [for (final x in (raw[k] as List? ?? [])) Map<String, dynamic>.from(x as Map)];
  List<Map<String, dynamic>> get suppliers => _list('suppliers');
  List<Map<String, dynamic>> get purchaseOrders => _list('purchase_orders');
  List<Department> get departments => [for (final d in _list('departments')) Department.fromJson(d)];
  List<Map<String, dynamic>> get tenders => _list('tenders');
  /// Active staff, for the people to notify.
  List<Map<String, dynamic>> get staff => _list('staff');
  List<Map<String, dynamic>> get vendors => _list('vendors');
  /// Couriers (DHL, FedEx…) and delivery vendors, for the shipment's carrier.
  List<Map<String, dynamic>> get carriers => _list('carriers');
  List<Map<String, dynamic>> get openVendorFees => _list('open_vendor_fees');
  Map<String, String> get docTypes => {
    for (final e in (raw['doc_types'] as Map? ?? {}).entries) e.key as String: e.value as String,
  };
}

class ShipmentSettings {
  ShipmentSettings(this.raw);
  final Map<String, dynamic> raw;
  bool get permitGate => raw['permit_gate'] == true;
  bool get docsRequiredAtCreation => raw['docs_required_at_creation'] == true;
  List<String> get importLabels => [for (final l in (raw['import_labels'] as List? ?? [])) l as String];
  List<String> get exportLabels => [for (final l in (raw['export_labels'] as List? ?? [])) l as String];
  List<String> get assumptions => [for (final a in (raw['assumptions'] as List? ?? [])) a as String];
  Set<int> get confirmed => {for (final i in (raw['confirmed_assumptions'] as List? ?? [])) (i as num).toInt()};
  List<Department> get departments =>
      [for (final d in (raw['departments'] as List? ?? [])) Department.fromJson(Map<String, dynamic>.from(d as Map))];
  List<String> get leadershipRoles => [for (final r in (raw['leadership_roles'] as List? ?? [])) r as String];
  List<String> get fallbackRoles => [for (final r in (raw['fallback_roles'] as List? ?? [])) r as String];
  bool get canEdit => raw['can_edit'] == true;
}
