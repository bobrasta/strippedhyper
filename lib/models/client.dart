/// A customer organisation (the client an invoice, quotation or contact
/// belongs to). The backend stores these in its `hospitals` table and
/// serves them from `/hospitals`; this build keeps only the customer fields.
class Client {
  final int    id;
  final String name;
  final String shortCode;
  final String type;
  final String region;
  final String district;
  final int?   creditLimit;
  final String contactName;
  final String contactPhone;
  final String contactEmail;
  final String? tin;
  final String? address;
  final String? notes;
  // Only populated by ClientService.get() (the single-client fetch).
  final int?   outstandingBalance;
  final int?   creditAvailable;

  const Client({
    required this.id,
    required this.name,
    required this.shortCode,
    required this.type,
    required this.region,
    required this.district,
    this.creditLimit,
    required this.contactName,
    required this.contactPhone,
    required this.contactEmail,
    this.tin,
    this.address,
    this.notes,
    this.outstandingBalance,
    this.creditAvailable,
  });

  factory Client.fromJson(Map<String, dynamic> j) => Client(
    id:                 (j['id'] as num).toInt(),
    name:               j['name']        as String? ?? '—',
    shortCode:          j['short_code']  as String? ?? j['code'] as String? ?? '??',
    type:               j['type']        as String? ?? 'private',
    region:             j['region']      as String? ?? '—',
    district:           j['district']    as String? ?? '—',
    creditLimit:        (j['credit_limit'] as num?)?.toInt(),
    contactName:        j['contact_name']  as String? ?? '—',
    contactPhone:       j['contact_phone'] as String? ?? '—',
    contactEmail:       j['contact_email'] as String? ?? '—',
    tin:                j['tin'] as String?,
    address:            j['address'] as String?,
    notes:              j['notes'] as String?,
    outstandingBalance: (j['outstanding_balance'] as num?)?.toInt(),
    creditAvailable:    (j['credit_available'] as num?)?.toInt(),
  );
}
