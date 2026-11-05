class ChartOfAccount {
  final int    id;
  final String code;
  final String name;
  final int    categoryId;
  final String categoryType; // asset | liability | equity | revenue | expense
  final String currency;
  final int    balance;
  final String status; // active | inactive
  final DateTime? createdAt;

  const ChartOfAccount({
    required this.id,
    required this.code,
    required this.name,
    required this.categoryId,
    required this.categoryType,
    this.currency = 'TZS',
    required this.balance,
    this.status = 'active',
    this.createdAt,
  });

  factory ChartOfAccount.fromJson(Map<String, dynamic> j) => ChartOfAccount(
    id:           (j['id'] as num).toInt(),
    code:         j['code'] as String? ?? '—',
    name:         j['name'] as String? ?? '—',
    categoryId:   (j['category_id'] as num? ?? 0).toInt(),
    categoryType: j['category_type'] as String? ?? '—',
    currency:     j['currency'] as String? ?? 'TZS',
    balance:      (j['balance'] as num? ?? 0).toInt(),
    status:       j['status'] as String? ?? 'active',
    createdAt:    j['created_at'] != null ? DateTime.tryParse(j['created_at'] as String) : null,
  );

  String get categoryLabel => switch (categoryType) {
    'asset'     => 'Asset',
    'liability' => 'Liability',
    'equity'    => 'Equity',
    'revenue'   => 'Revenue',
    'expense'   => 'Expense',
    _           => categoryType,
  };
}

class LedgerEntry {
  final int    id;
  final String accountCode;
  final String accountName;
  final String type; // debit | credit
  final int    amount;
  final String? description;
  final String? reference;
  final DateTime? createdAt;

  const LedgerEntry({
    required this.id,
    required this.accountCode,
    required this.accountName,
    required this.type,
    required this.amount,
    this.description,
    this.reference,
    this.createdAt,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
    id:          (j['id'] as num).toInt(),
    accountCode: j['account_code'] as String? ?? '—',
    accountName: j['account_name'] as String? ?? '—',
    type:        j['type'] as String? ?? 'debit',
    amount:      (j['amount'] as num? ?? 0).toInt(),
    description: j['description'] as String?,
    reference:   j['reference'] as String?,
    createdAt:   j['created_at'] != null ? DateTime.tryParse(j['created_at'] as String) : null,
  );

  bool get isDebit => type == 'debit';
}
