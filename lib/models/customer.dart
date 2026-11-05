import 'contact.dart';

/// A customer is a client organisation we do business with;
/// the people we talk to there are its [contacts]. List rows carry the
/// summary fields only — [CustomerService.get] fills the rest.
class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.type,
    this.region,
    this.district,
    this.tin,
    this.phone,
    this.email,
    this.address,
    this.contactName,
    this.contactsCount = 0,
    this.invoicesCount = 0,
    this.totalBilled = 0,
    this.balance = 0,
    this.lastInvoiceDate,
    this.totalPaid = 0,
    this.openInvoices = 0,
    this.firstInvoiceDate,
    this.notes,
    this.contacts = const [],
    this.recentInvoices = const [],
    this.recentQuotations = const [],
    this.isDetail = false,
  });

  final int id;
  final String name;
  final String? type, region, district, tin, phone, email, address, contactName;
  final int contactsCount, invoicesCount, totalBilled, balance;
  final String? lastInvoiceDate;
  // Detail only.
  final int totalPaid, openInvoices;
  final String? firstInvoiceDate, notes;
  final List<Contact> contacts;
  final List<CustomerInvoice> recentInvoices;
  final List<CustomerQuotation> recentQuotations;
  final bool isDetail;

  String get location => [district, region].where((s) => s != null && s.trim().isNotEmpty).join(', ');

  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;
  static String? _s(Object? v) {
    final s = v as String?;
    return s == null || s.trim().isEmpty ? null : s;
  }

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
    id:               _i(j['id']),
    name:             j['name'] as String? ?? '—',
    type:             _s(j['type']),
    region:           _s(j['region']),
    district:         _s(j['district']),
    tin:              _s(j['tin']),
    phone:            _s(j['phone']),
    email:            _s(j['email']),
    address:          _s(j['address']),
    contactName:      _s(j['contact_name']),
    contactsCount:    _i(j['contacts_count']),
    invoicesCount:    _i(j['invoices_count']),
    totalBilled:      _i(j['total_billed']),
    balance:          _i(j['balance']),
    lastInvoiceDate:  _s(j['last_invoice_date']),
    totalPaid:        _i(j['total_paid']),
    openInvoices:     _i(j['open_invoices']),
    firstInvoiceDate: _s(j['first_invoice_date']),
    notes:            _s(j['notes']),
    contacts:         (j['contacts'] as List? ?? [])
        .map((e) => Contact.fromJson(e as Map<String, dynamic>)).toList(),
    recentInvoices:   (j['recent_invoices'] as List? ?? [])
        .map((e) => CustomerInvoice.fromJson(e as Map<String, dynamic>)).toList(),
    recentQuotations: (j['recent_quotations'] as List? ?? [])
        .map((e) => CustomerQuotation.fromJson(e as Map<String, dynamic>)).toList(),
    isDetail:         j.containsKey('contacts'),
  );
}

class CustomerInvoice {
  const CustomerInvoice({required this.id, required this.number, this.issueDate, this.dueDate,
      required this.status, required this.total, required this.balance});
  final int id;
  final String number;
  final String? issueDate, dueDate;
  final String status;
  final int total, balance;

  factory CustomerInvoice.fromJson(Map<String, dynamic> j) => CustomerInvoice(
    id:        (j['id'] as num).toInt(),
    number:    j['invoice_number'] as String? ?? '—',
    issueDate: j['issue_date'] as String?,
    dueDate:   j['due_date'] as String?,
    status:    j['status'] as String? ?? '',
    total:     (j['total'] as num?)?.toInt() ?? 0,
    balance:   (j['balance'] as num?)?.toInt() ?? 0,
  );
}

class CustomerQuotation {
  const CustomerQuotation({required this.id, required this.number, required this.status,
      required this.total, this.date});
  final int id;
  final String number, status;
  final int total;
  final String? date;

  factory CustomerQuotation.fromJson(Map<String, dynamic> j) => CustomerQuotation(
    id:     (j['id'] as num).toInt(),
    number: j['quotation_number'] as String? ?? '—',
    status: j['status'] as String? ?? '',
    total:  (j['total'] as num?)?.toInt() ?? 0,
    date:   j['date'] as String?,
  );
}
