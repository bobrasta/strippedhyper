class ExpenseCategory {
  final int    id;
  final String name;
  final int    accountId;
  final String? accountCode;
  final String? accountName;
  final int?    parentId;
  final String? parentName;
  final bool   requiresDirectorApproval;

  const ExpenseCategory({
    required this.id, required this.name, required this.accountId,
    this.accountCode, this.accountName, this.parentId, this.parentName,
    this.requiresDirectorApproval = false,
  });

  factory ExpenseCategory.fromJson(Map<String, dynamic> j) => ExpenseCategory(
    id:        (j['id'] as num).toInt(),
    name:      j['name'] as String? ?? '—',
    accountId: (j['account_id'] as num? ?? 0).toInt(),
    accountCode: j['account_code'] as String?,
    accountName: j['account_name'] as String?,
    parentId:  (j['parent_id'] as num?)?.toInt(),
    parentName: j['parent_name'] as String?,
    requiresDirectorApproval: j['requires_director_approval'] as bool? ?? false,
  );

  bool get isSubcategory => parentId != null;
}

// pendingPayment/pendingRelease/paid replace the old single "approved"
// terminal-ish status (which used to post to the ledger the instant
// CTO/Director signed off, with no separate payment-release step or
// self-approval check — see 2026_09_12_090000_add_payment_release_to_expenses_table
// in hypermed-api). Mirrors PerDiemRequest's pendingPayment/paid split.
// pendingManager (2026-10-24): the submitter's own line manager approves first.
enum ExpenseStatus { pendingManager, pendingCto, pendingDirector, pendingPayment, pendingRelease, paid, rejected }

extension ExpenseStatusX on ExpenseStatus {
  String get label => switch (this) {
    ExpenseStatus.pendingManager  => 'Awaiting manager',
    ExpenseStatus.pendingCto      => 'Awaiting CTO',
    ExpenseStatus.pendingDirector => 'Awaiting Director',
    ExpenseStatus.pendingPayment  => 'Awaiting Payment',
    ExpenseStatus.pendingRelease  => 'Awaiting Release',
    ExpenseStatus.paid            => 'Paid',
    ExpenseStatus.rejected        => 'Rejected',
  };
}

ExpenseStatus _parseExpenseStatus(String s) => switch (s) {
  'pending_manager'   => ExpenseStatus.pendingManager,
  'pending_cto'       => ExpenseStatus.pendingCto,
  'pending_director'  => ExpenseStatus.pendingDirector,
  'pending_payment'   => ExpenseStatus.pendingPayment,
  'pending_release'   => ExpenseStatus.pendingRelease,
  'paid'              => ExpenseStatus.paid,
  'rejected'          => ExpenseStatus.rejected,
  // An unrecognised status must never be silently treated as an actionable
  // "awaiting my approval" — that previously made the CTO/Director icons
  // clickable on rows the backend then correctly rejected with a 422.
  _                   => ExpenseStatus.paid,
};

class Expense {
  final int     id;
  final String  name;
  final int     categoryId;
  final String? categoryName;
  final int     amount;
  final double  taxRate;
  final int     taxAmount;
  final int     grossAmount;
  final String  paymentMode; // cash | bank | mobile_money
  final String  expenseDate;
  final String? reference;
  final String? notes;
  final String? createdByName;
  final DateTime? createdAt;
  final ExpenseStatus status;
  final bool     requiresDirectorApproval;
  final String?  escalationReason;
  final String?  reviewerName;
  /// The line manager it waits on at pendingManager.
  final int?     approverId;
  final String?  approverName;
  /// A team leader only filters: passing it sends it to [nextApproverName].
  final bool     approverIsFilter;
  final String?  nextApproverName;
  final String?  rejectionReason;
  final int?     paymentInitiatedBy;
  final String?  paymentInitiatedByName;
  final String?  paidByName;
  final bool     isRecurring;
  final String?  recurIntervalType;
  final int?     recurInterval;
  final String?  recurStoppedOn;
  final int?     recurParentId;

  const Expense({
    required this.id,
    required this.name,
    required this.categoryId,
    this.categoryName,
    required this.amount,
    this.taxRate = 0,
    required this.taxAmount,
    required this.grossAmount,
    this.paymentMode = 'cash',
    required this.expenseDate,
    this.reference,
    this.notes,
    this.createdByName,
    this.createdAt,
    this.status = ExpenseStatus.pendingCto,
    this.requiresDirectorApproval = false,
    this.escalationReason,
    this.reviewerName,
    this.approverId,
    this.approverName,
    this.approverIsFilter = false,
    this.nextApproverName,
    this.rejectionReason,
    this.paymentInitiatedBy,
    this.paymentInitiatedByName,
    this.paidByName,
    this.isRecurring = false,
    this.recurIntervalType,
    this.recurInterval,
    this.recurStoppedOn,
    this.recurParentId,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id:            (j['id'] as num).toInt(),
    name:          j['name'] as String? ?? '—',
    categoryId:    (j['category_id'] as num? ?? 0).toInt(),
    categoryName:  j['category_name'] as String?,
    amount:        (j['amount'] as num? ?? 0).toInt(),
    taxRate:       (j['tax_rate'] as num? ?? 0).toDouble(),
    taxAmount:     (j['tax_amount'] as num? ?? 0).toInt(),
    grossAmount:   (j['gross_amount'] as num? ?? 0).toInt(),
    paymentMode:   j['payment_mode'] as String? ?? 'cash',
    expenseDate:   j['expense_date'] as String? ?? '—',
    reference:     j['reference'] as String?,
    notes:         j['notes'] as String?,
    createdByName: j['created_by_name'] as String?,
    createdAt:     j['created_at'] != null ? DateTime.tryParse(j['created_at'] as String) : null,
    status:        _parseExpenseStatus(j['status'] as String? ?? 'pending_cto'),
    requiresDirectorApproval: j['requires_director_approval'] as bool? ?? false,
    escalationReason: j['escalation_reason'] as String?,
    reviewerName:     j['reviewer_name'] as String?,
    approverId:       (j['approver_id'] as num?)?.toInt(),
    approverName:     j['approver_name'] as String?,
    approverIsFilter: j['approver_is_filter'] as bool? ?? false,
    nextApproverName: j['next_approver_name'] as String?,
    rejectionReason:  j['rejection_reason'] as String?,
    paymentInitiatedBy:     (j['payment_initiated_by'] as num?)?.toInt(),
    paymentInitiatedByName: j['payment_initiated_by_name'] as String?,
    paidByName:             j['paid_by_name'] as String?,
    isRecurring:            j['is_recurring'] as bool? ?? false,
    recurIntervalType:      j['recur_interval_type'] as String?,
    recurInterval:          (j['recur_interval'] as num?)?.toInt(),
    recurStoppedOn:         j['recur_stopped_on'] as String?,
    recurParentId:          (j['recur_parent_id'] as num?)?.toInt(),
  );

  // A template that's still generating occurrences (not one of its
  // generated children, and not manually stopped).
  bool get isActiveRecurringTemplate => isRecurring && recurParentId == null && recurStoppedOn == null;

  String get paymentModeLabel => switch (paymentMode) {
    'bank'         => 'Bank',
    'mobile_money' => 'Mobile Money',
    _              => 'Cash',
  };
}
