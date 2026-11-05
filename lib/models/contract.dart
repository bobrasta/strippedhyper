class Allowance {
  final int id;
  final int contractId;
  final String type;
  final int amount;
  final bool recurring;
  final String effectiveDate;

  const Allowance({
    required this.id, required this.contractId, required this.type,
    required this.amount, required this.recurring, required this.effectiveDate,
  });

  factory Allowance.fromJson(Map<String, dynamic> j) => Allowance(
    id:             (j['id'] as num).toInt(),
    contractId:     (j['contract_id'] as num).toInt(),
    type:           j['type'] as String,
    amount:         (j['amount'] as num).toInt(),
    recurring:      j['recurring'] as bool? ?? true,
    effectiveDate:  j['effective_date'] as String? ?? '—',
  );
}

class Contract {
  final int id;
  final int userId;
  final String contractType; // permanent | fixed_term
  final String startDate;
  final String? endDate;
  final int probationPeriodDays;
  final String? probationEndDate;
  final int? baseSalary;
  final String status; // active | ended | resigned
  final String? resignationDate;
  final String? resignationReason;
  final int? renewedFromContractId;
  final String? documentUrl;
  final String? documentName;
  final String? documentUploadedAt;
  final String? createdByName;
  final List<Allowance> allowances;

  const Contract({
    required this.id, required this.userId, required this.contractType,
    required this.startDate, this.endDate, required this.probationPeriodDays,
    this.probationEndDate, this.baseSalary, required this.status,
    this.resignationDate, this.resignationReason, this.renewedFromContractId,
    this.documentUrl, this.documentName, this.documentUploadedAt,
    this.createdByName, this.allowances = const [],
  });

  factory Contract.fromJson(Map<String, dynamic> j) => Contract(
    id:                     (j['id'] as num).toInt(),
    userId:                 (j['user_id'] as num).toInt(),
    contractType:           j['contract_type'] as String,
    startDate:              j['start_date'] as String? ?? '—',
    endDate:                j['end_date'] as String?,
    probationPeriodDays:    (j['probation_period_days'] as num? ?? 0).toInt(),
    probationEndDate:       j['probation_end_date'] as String?,
    baseSalary:             (j['base_salary'] as num?)?.toInt(),
    status:                 j['status'] as String? ?? 'active',
    resignationDate:        j['resignation_date'] as String?,
    resignationReason:      j['resignation_reason'] as String?,
    renewedFromContractId:  (j['renewed_from_contract_id'] as num?)?.toInt(),
    documentUrl:            j['document_url'] as String?,
    documentName:           j['document_name'] as String?,
    documentUploadedAt:     j['document_uploaded_at'] as String?,
    createdByName:          j['created_by_name'] as String?,
    allowances:             (j['allowances'] as List<dynamic>? ?? [])
        .map((a) => Allowance.fromJson(a as Map<String, dynamic>)).toList(),
  );

  bool get isActive => status == 'active';
  bool get hasDocument => documentUrl != null;
}
