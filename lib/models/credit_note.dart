class CreditNote {
  final int id;
  final String creditNoteNumber;
  final int invoiceId;
  final String reason;
  final int amount;
  final String status; // draft | approved | applied
  final String? createdByName;
  final String? approvedByName;
  final String? appliedAt;

  const CreditNote({
    required this.id, required this.creditNoteNumber, required this.invoiceId,
    required this.reason, required this.amount, required this.status,
    this.createdByName, this.approvedByName, this.appliedAt,
  });

  factory CreditNote.fromJson(Map<String, dynamic> j) => CreditNote(
    id:               (j['id'] as num).toInt(),
    creditNoteNumber: j['credit_note_number'] as String,
    invoiceId:        (j['invoice_id'] as num).toInt(),
    reason:           j['reason'] as String? ?? '',
    amount:           (j['amount'] as num).toInt(),
    status:           j['status'] as String? ?? 'draft',
    createdByName:    j['created_by_name'] as String?,
    approvedByName:   j['approved_by_name'] as String?,
    appliedAt:        j['applied_at'] as String?,
  );
}
