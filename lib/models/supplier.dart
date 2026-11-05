class Supplier {
  final int    id;
  final String name;
  final String? shortCode;
  final String type;         // manufacturer | distributor | importer | local_vendor
  final String? contactName;
  final String? contactEmail;
  final String? contactPhone;
  final String? website;
  final String? city;
  final String? address;
  final String? tin;
  final String? country;
  final String currency;
  final String? paymentTerms;
  final int    leadTimeDays;
  final int    rating;       // 1–5
  final String? notes;
  final bool   isActive;
  final int    itemsCount;   // from withCount('items')

  const Supplier({
    required this.id,
    required this.name,
    this.shortCode,
    required this.type,
    this.contactName,
    this.contactEmail,
    this.contactPhone,
    this.website,
    this.city,
    this.address,
    this.tin,
    this.country,
    this.currency = 'USD',
    this.paymentTerms,
    this.leadTimeDays = 0,
    this.rating = 3,
    this.notes,
    this.isActive = true,
    this.itemsCount = 0,
  });

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
    id:            (j['id']   as num).toInt(),
    name:          j['name']          as String? ?? '—',
    shortCode:     j['short_code']    as String?,
    type:          j['type']          as String? ?? 'distributor',
    contactName:   j['contact_name']  as String?,
    contactEmail:  j['contact_email'] as String?,
    contactPhone:  j['contact_phone'] as String?,
    website:       j['website']       as String?,
    city:          j['city']          as String?,
    address:       j['address']       as String?,
    tin:           j['tin']           as String?,
    country:       j['country']       as String?,
    currency:      j['currency']      as String? ?? 'USD',
    paymentTerms:  j['payment_terms'] as String?,
    leadTimeDays:  (j['lead_time_days'] as num? ?? 0).toInt(),
    rating:        (j['rating']       as num? ?? 3).toInt(),
    notes:         j['notes']         as String?,
    isActive:      j['is_active']     as bool? ?? true,
    itemsCount:    (j['items_count']  as num? ?? 0).toInt(),
  );

  String get typeLabel => switch (type) {
    'manufacturer' => 'Manufacturer',
    'distributor'  => 'Distributor',
    'importer'     => 'Importer',
    'local_vendor' => 'Local Vendor',
    _              => type,
  };

  String get location {
    if (city != null && country != null) return '$city, $country';
    return country ?? city ?? '—';
  }
}
