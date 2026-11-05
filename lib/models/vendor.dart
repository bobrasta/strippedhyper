class Vendor {
  final int     id;
  final String  name;
  final String  type; // clearing | delivery | courier | other
  final String? tin;
  final String? paymentAccountType;
  final String? paymentAccountName;
  final String? paymentAccountNumber;
  final String? paymentBankName;
  final String? contactName;
  final String? contactPhone;
  final String? contactEmail;
  final bool    isActive;

  const Vendor({
    required this.id, required this.name, required this.type,
    this.tin, this.paymentAccountType, this.paymentAccountName,
    this.paymentAccountNumber, this.paymentBankName,
    this.contactName, this.contactPhone, this.contactEmail,
    this.isActive = true,
  });

  factory Vendor.fromJson(Map<String, dynamic> j) => Vendor(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String? ?? '—',
    type: j['type'] as String? ?? 'other',
    tin: j['tin'] as String?,
    paymentAccountType: j['payment_account_type'] as String?,
    paymentAccountName: j['payment_account_name'] as String?,
    paymentAccountNumber: j['payment_account_number'] as String?,
    paymentBankName: j['payment_bank_name'] as String?,
    contactName: j['contact_name'] as String?,
    contactPhone: j['contact_phone'] as String?,
    contactEmail: j['contact_email'] as String?,
    isActive: j['is_active'] as bool? ?? true,
  );

  String get typeLabel => switch (type) {
    'clearing' => 'Clearing / transit',
    'delivery' => 'Delivery',
    'courier'  => 'Courier (clears + delivers)',
    _          => 'Other',
  };
}

class VendorReceipt {
  final int      id;
  final String   receiptType; // efd | other
  final String   receiptNumber;
  final String   issuerName;
  final String?  issuerTin;
  final String   receiptDate;
  final int      amount;
  final String?  fileName;
  final bool     verified;
  final String?  verifiedBy;
  final String?  uploadedBy;

  const VendorReceipt({
    required this.id, required this.receiptType, required this.receiptNumber,
    required this.issuerName, this.issuerTin, required this.receiptDate,
    required this.amount, this.fileName, this.verified = false,
    this.verifiedBy, this.uploadedBy,
  });

  factory VendorReceipt.fromJson(Map<String, dynamic> j) => VendorReceipt(
    id: (j['id'] as num).toInt(),
    receiptType: j['receipt_type'] as String? ?? 'other',
    receiptNumber: j['receipt_number'] as String? ?? '',
    issuerName: j['issuer_name'] as String? ?? '',
    issuerTin: j['issuer_tin'] as String?,
    receiptDate: j['receipt_date'] as String? ?? '',
    amount: (j['amount'] as num? ?? 0).toInt(),
    fileName: j['file_name'] as String?,
    verified: j['verified'] as bool? ?? false,
    verifiedBy: j['verified_by'] as String?,
    uploadedBy: j['uploaded_by'] as String?,
  );
}

// Matches the API's 4-state enum exactly (VendorFee::$fillable's status).
/// pendingManager: the recorder's manager (Patrick for Tender & Procurement)
/// approves first, then Finance, then the Director (2026-10-26).
enum VendorFeeStatus { pendingManager, pendingReceipt, readyForPayment, paid, rejected }

VendorFeeStatus _parseVendorFeeStatus(String s) => switch (s) {
  'pending_manager'    => VendorFeeStatus.pendingManager,
  'ready_for_payment' => VendorFeeStatus.readyForPayment,
  'paid'               => VendorFeeStatus.paid,
  'rejected'           => VendorFeeStatus.rejected,
  _                    => VendorFeeStatus.pendingReceipt,
};

extension VendorFeeStatusX on VendorFeeStatus {
  String get label => switch (this) {
    VendorFeeStatus.pendingManager  => 'Awaiting manager',
    VendorFeeStatus.pendingReceipt  => 'Pending Receipt',
    VendorFeeStatus.readyForPayment => 'Ready for Payment',
    VendorFeeStatus.paid            => 'Paid',
    VendorFeeStatus.rejected        => 'Rejected',
  };
}

class VendorFeeDeliveryJobRef {
  final int    id;
  final String jobNumber;
  final bool   hasDeliveryNote;
  final bool   deliveryNoteGoodsMismatch;

  const VendorFeeDeliveryJobRef({
    required this.id, required this.jobNumber,
    this.hasDeliveryNote = false, this.deliveryNoteGoodsMismatch = false,
  });

  factory VendorFeeDeliveryJobRef.fromJson(Map<String, dynamic> j) => VendorFeeDeliveryJobRef(
    id: (j['id'] as num).toInt(),
    jobNumber: j['job_number'] as String? ?? '',
    hasDeliveryNote: j['has_delivery_note'] as bool? ?? false,
    deliveryNoteGoodsMismatch: j['delivery_note_goods_mismatch'] as bool? ?? false,
  );
}

class VendorFee {
  final int      id;
  final int?     vendorId;
  final String?  vendorName;
  final VendorFeeDeliveryJobRef? deliveryJob;
  final String   description;
  final int      billedAmount;
  final String   currency;
  final VendorFeeStatus status;
  final int      receiptsTotal;
  final int      outstandingGap;
  final int      unverifiedReceiptCount;
  final String?  paymentBlockReason;
  /// Clearing fees: paid first, the receipt follows (2026-10-26).
  final bool     receiptAfterPayment;
  final String?  receiptFollowUp;
  final String?  statusLabel;
  final bool     isPayable;
  final List<VendorReceipt> receipts;
  final String?  createdBy;
  /// Who approves at the manager stage, and who did.
  final int?     approverId;
  final String?  approverName;
  final String?  managerApprovedBy;
  final String?  submittedBy;
  final String?  paidBy;
  final String?  paymentReference;
  final String?  rejectedBy;
  final String?  rejectionReason;

  const VendorFee({
    required this.id, this.vendorId, this.vendorName, this.deliveryJob,
    required this.description, required this.billedAmount, this.currency = 'TZS',
    this.status = VendorFeeStatus.pendingReceipt,
    this.receiptsTotal = 0, this.outstandingGap = 0, this.unverifiedReceiptCount = 0,
    this.paymentBlockReason, this.receiptAfterPayment = false, this.receiptFollowUp, this.statusLabel,
    this.isPayable = false, this.receipts = const [],
    this.createdBy, this.approverId, this.approverName, this.managerApprovedBy,
    this.submittedBy, this.paidBy, this.paymentReference,
    this.rejectedBy, this.rejectionReason,
  });

  factory VendorFee.fromJson(Map<String, dynamic> j) => VendorFee(
    id: (j['id'] as num).toInt(),
    vendorId: (j['vendor'] as Map<String, dynamic>?)?['id'] != null ? ((j['vendor'] as Map<String, dynamic>)['id'] as num).toInt() : null,
    vendorName: (j['vendor'] as Map<String, dynamic>?)?['name'] as String?,
    deliveryJob: j['delivery_job'] != null ? VendorFeeDeliveryJobRef.fromJson(j['delivery_job'] as Map<String, dynamic>) : null,
    description: j['description'] as String? ?? '',
    billedAmount: (j['billed_amount'] as num? ?? 0).toInt(),
    currency: j['currency'] as String? ?? 'TZS',
    status: _parseVendorFeeStatus(j['status'] as String? ?? 'pending_receipt'),
    receiptsTotal: (j['receipts_total'] as num? ?? 0).toInt(),
    outstandingGap: (j['outstanding_gap'] as num? ?? 0).toInt(),
    unverifiedReceiptCount: (j['unverified_receipt_count'] as num? ?? 0).toInt(),
    paymentBlockReason: j['payment_block_reason'] as String?,
    receiptAfterPayment: j['receipt_after_payment'] == true,
    receiptFollowUp: j['receipt_follow_up'] as String?,
    statusLabel: j['status_label'] as String?,
    isPayable: j['is_payable'] as bool? ?? false,
    receipts: (j['receipts'] as List<dynamic>? ?? [])
        .map((r) => VendorReceipt.fromJson(r as Map<String, dynamic>))
        .toList(),
    createdBy: j['created_by'] as String?,
    approverId: (j['approver_id'] as num?)?.toInt(),
    approverName: j['approver'] as String?,
    managerApprovedBy: j['manager_approved_by'] as String?,
    submittedBy: j['submitted_by'] as String?,
    paidBy: j['paid_by'] as String?,
    paymentReference: j['payment_reference'] as String?,
    rejectedBy: j['rejected_by'] as String?,
    rejectionReason: j['rejection_reason'] as String?,
  );
}

class DeliveryGoodsLine {
  final String  item;
  final String? serial;
  final int     quantity;

  const DeliveryGoodsLine({required this.item, this.serial, this.quantity = 1});

  factory DeliveryGoodsLine.fromJson(Map<String, dynamic> j) => DeliveryGoodsLine(
    item: j['item'] as String? ?? '',
    serial: j['serial'] as String?,
    quantity: (j['quantity'] as num? ?? 1).toInt(),
  );

  Map<String, dynamic> toJson() => {'item': item, 'serial': serial, 'quantity': quantity};
}

class DeliveryJob {
  final int      id;
  final String   jobNumber;
  final int?     vendorId;
  final String?  vendorName;
  final String?  destination;
  final List<DeliveryGoodsLine> goodsList;
  final String   status; // pending | delivered | billed | paid
  final bool     hasDeliveryNote;
  final String?  deliveryNoteReceiverName;
  final String?  deliveryNoteDate;
  final bool     deliveryNoteGoodsMismatch;
  final int?     feeId;

  const DeliveryJob({
    required this.id, required this.jobNumber, this.vendorId, this.vendorName,
    this.destination, this.goodsList = const [], this.status = 'pending',
    this.hasDeliveryNote = false, this.deliveryNoteReceiverName, this.deliveryNoteDate,
    this.deliveryNoteGoodsMismatch = false, this.feeId,
  });

  factory DeliveryJob.fromJson(Map<String, dynamic> j) => DeliveryJob(
    id: (j['id'] as num).toInt(),
    jobNumber: j['job_number'] as String? ?? '',
    vendorId: (j['vendor'] as Map<String, dynamic>?)?['id'] != null ? ((j['vendor'] as Map<String, dynamic>)['id'] as num).toInt() : null,
    vendorName: (j['vendor'] as Map<String, dynamic>?)?['name'] as String?,
    destination: j['destination'] as String?,
    goodsList: (j['goods_list'] as List<dynamic>? ?? [])
        .map((g) => DeliveryGoodsLine.fromJson(g as Map<String, dynamic>))
        .toList(),
    status: j['status'] as String? ?? 'pending',
    hasDeliveryNote: j['has_delivery_note'] as bool? ?? false,
    deliveryNoteReceiverName: j['delivery_note_receiver_name'] as String?,
    deliveryNoteDate: j['delivery_note_date'] as String?,
    deliveryNoteGoodsMismatch: j['delivery_note_goods_mismatch'] as bool? ?? false,
    feeId: (j['fee_id'] as num?)?.toInt(),
  );
}
