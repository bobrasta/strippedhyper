class BankStatementLine {
  final int     id;
  final String  txnDate;
  final String  description;
  final int     debit;
  final int     credit;
  final int?    matchedPaymentId;
  final int?    matchedExpenseId;
  final int?    matchedVendorBillPaymentId;
  final bool    isMatched;

  const BankStatementLine({
    required this.id,
    required this.txnDate,
    required this.description,
    required this.debit,
    required this.credit,
    this.matchedPaymentId,
    this.matchedExpenseId,
    this.matchedVendorBillPaymentId,
    required this.isMatched,
  });

  factory BankStatementLine.fromJson(Map<String, dynamic> j) => BankStatementLine(
    id:          (j['id'] as num).toInt(),
    txnDate:     j['txn_date'] as String? ?? '—',
    description: j['description'] as String? ?? '',
    debit:       (j['debit'] as num? ?? 0).toInt(),
    credit:      (j['credit'] as num? ?? 0).toInt(),
    matchedPaymentId:           j['matched_payment_id'] != null ? (j['matched_payment_id'] as num).toInt() : null,
    matchedExpenseId:           j['matched_expense_id'] != null ? (j['matched_expense_id'] as num).toInt() : null,
    matchedVendorBillPaymentId: j['matched_vendor_bill_payment_id'] != null ? (j['matched_vendor_bill_payment_id'] as num).toInt() : null,
    isMatched:   j['is_matched'] as bool? ?? false,
  );
}

class ReconciliationTotals {
  final int sysDr;
  final int sysCr;
  final int cashBookBalance;
  final int unmatchedStmtCredit;
  final int unmatchedStmtDebit;
  final int reconciledBalance;
  final int statementClosingBalance;
  final int difference;

  const ReconciliationTotals({
    required this.sysDr,
    required this.sysCr,
    required this.cashBookBalance,
    required this.unmatchedStmtCredit,
    required this.unmatchedStmtDebit,
    required this.reconciledBalance,
    required this.statementClosingBalance,
    required this.difference,
  });

  factory ReconciliationTotals.fromJson(Map<String, dynamic> j) => ReconciliationTotals(
    sysDr:                    (j['sys_dr'] as num? ?? 0).toInt(),
    sysCr:                    (j['sys_cr'] as num? ?? 0).toInt(),
    cashBookBalance:          (j['cash_book_balance'] as num? ?? 0).toInt(),
    unmatchedStmtCredit:      (j['unmatched_stmt_credit'] as num? ?? 0).toInt(),
    unmatchedStmtDebit:       (j['unmatched_stmt_debit'] as num? ?? 0).toInt(),
    reconciledBalance:        (j['reconciled_balance'] as num? ?? 0).toInt(),
    statementClosingBalance:  (j['statement_closing_balance'] as num? ?? 0).toInt(),
    difference:               (j['difference'] as num? ?? 0).toInt(),
  );

  static const zero = ReconciliationTotals(
    sysDr: 0, sysCr: 0, cashBookBalance: 0, unmatchedStmtCredit: 0,
    unmatchedStmtDebit: 0, reconciledBalance: 0, statementClosingBalance: 0, difference: 0,
  );
}

class BankReconciliation {
  final int     id;
  final String  periodFrom;
  final String  periodTo;
  final String  currency;
  final int     statementClosingBalance;
  final String  status; // draft | complete
  final String? notes;
  final String? createdByName;
  final ReconciliationTotals totals;
  final List<BankStatementLine> lines;
  final DateTime? createdAt;

  const BankReconciliation({
    required this.id,
    required this.periodFrom,
    required this.periodTo,
    this.currency = 'TZS',
    required this.statementClosingBalance,
    required this.status,
    this.notes,
    this.createdByName,
    this.totals = ReconciliationTotals.zero,
    this.lines = const [],
    this.createdAt,
  });

  factory BankReconciliation.fromJson(Map<String, dynamic> j) => BankReconciliation(
    id:                       (j['id'] as num).toInt(),
    periodFrom:               j['period_from'] as String? ?? '—',
    periodTo:                 j['period_to'] as String? ?? '—',
    currency:                 j['currency'] as String? ?? 'TZS',
    statementClosingBalance:  (j['statement_closing_balance'] as num? ?? 0).toInt(),
    status:                   j['status'] as String? ?? 'draft',
    notes:                    j['notes'] as String?,
    createdByName:            j['created_by_name'] as String?,
    totals:                   j['totals'] is Map
                                  ? ReconciliationTotals.fromJson(j['totals'] as Map<String, dynamic>)
                                  : ReconciliationTotals.zero,
    lines:                    (j['lines'] as List? ?? [])
                                  .map((e) => BankStatementLine.fromJson(e as Map<String, dynamic>)).toList(),
    createdAt:                j['created_at'] != null ? DateTime.tryParse(j['created_at'] as String) : null,
  );

  bool get isComplete => status == 'complete';
}
