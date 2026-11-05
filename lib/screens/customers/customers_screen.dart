import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/contact.dart';
import '../../models/customer.dart';
import '../../services/contact_service.dart';
import '../../services/customer_service.dart';
import '../../services/client_service.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../widgets/common/avatar_widget.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/email/compose_modal.dart';
import '../../theme/app_palette.dart';
import 'edit_client_dialog.dart';
import '../sales/invoices_screen.dart' show showInvoiceDetail;
import '../sales/quotations_screen.dart' show QuotationDetailScreen;
import '../finance/receivables_screen.dart' show CustomerStatementScreen;
import '../../main.dart' show userRoleNotifier, allowedScreenKeys, hasAccountantAuthority, can;
import '../../widgets/common/phone_layout.dart';

/// Customers = the client facilities we sell to or service; the people we
/// talk to there are each customer's contacts.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();
  String _filter = 'all';
  int _showCount = _pageSize;
  static const _pageSize = 40;

  List<Customer> _all = [];
  bool _loading = true;
  String? _error;

  int? _selectedId;
  Customer? _detail;
  bool _loadingDetail = false;
  bool _showDetailNarrow = false;

  // A contact person opened from the customer's detail.
  Contact? _openContact;
  bool _loadingContact = false;

  // Dialogs (Stack overlays, same as before).
  bool _showAddContact = false;
  Contact? _logFor, _editFor, _followupFor;
  bool _editCustomer = false;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known list instantly, then refresh.
    final cached = CustomerService.cachedList;
    if (cached != null) {
      _all = cached;
      _loading = false;
      if (cached.isNotEmpty) {
        _selectedId = cached.first.id;
        _detail = CustomerService.cachedById[cached.first.id];
      }
    }
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      if (_all.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final list = await CustomerService.instance.list();
      if (!mounted) return;
      setState(() { _all = list; _loading = false; });
      final keep = _selectedId != null && list.any((c) => c.id == _selectedId);
      if (!keep && list.isNotEmpty) {
        _select(list.first);
      } else if (keep) {
        _loadDetail(_selectedId!);
      }
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  void _select(Customer c) {
    setState(() {
      _selectedId = c.id;
      _openContact = null;
      _showDetailNarrow = true;
      final cached = CustomerService.cachedById[c.id];
      _detail = cached ?? c;
    });
    _loadDetail(c.id);
  }

  Future<void> _loadDetail(int id) async {
    setState(() => _loadingDetail = true);
    try {
      final full = await CustomerService.instance.get(id);
      if (mounted && _selectedId == id) setState(() { _detail = full; _loadingDetail = false; });
    } catch (e) {
      if (mounted) { setState(() => _loadingDetail = false); showErrorToast(context, e); }
    }
  }

  Future<void> _openContactDetail(Contact c) async {
    setState(() { _openContact = c; _loadingContact = true; });
    try {
      final full = await ContactService.instance.get(c.id);
      if (mounted && _openContact?.id == c.id) setState(() { _openContact = full; _loadingContact = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingContact = false);
    }
  }

  // After any contact change: refresh the customer and, if open, the contact.
  void _afterContactSaved() {
    if (_selectedId != null) _loadDetail(_selectedId!);
    final open = _openContact;
    if (open != null) _openContactDetail(open);
  }

  void _openCompose(Contact c) {
    showDialog(
      context: context,
      builder: (dialogCtx) => ComposeModal(
        initialTo: c.email ?? '',
        onClose: () => Navigator.of(dialogCtx).pop(),
        onSent:  () => Navigator.of(dialogCtx).pop(),
      ),
    );
  }

  Future<void> _openInvoice(int id) async {
    final changed = await showInvoiceDetail(context, id);
    if (changed && mounted) _load();
  }

  // Same gate as GET /receivables/statement: the Finance screen or
  // accountant authority (procurement.initiate_payment).
  bool get _canSeeLedger {
    final role = userRoleNotifier.value;
    final allowed = allowedScreenKeys(role);
    return allowed == null || allowed.contains('finance') || hasAccountantAuthority(role) || can('procurement.initiate_payment');
  }

  /// The customer's ledger — every invoice and payment with a running
  /// balance, and what they owed on any date — even once fully paid.
  Future<void> _openLedger(Customer c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerStatementScreen(hospitalId: c.id, clientName: c.name)));
    if (mounted && _selectedId != null) _loadDetail(_selectedId!);
  }

  Future<void> _openQuotation(int id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => QuotationDetailScreen(quotationId: id)));
    if (mounted && _selectedId != null) _loadDetail(_selectedId!);
  }

  List<Customer> get _filtered {
    var list = _all;
    if (_filter == 'owing') list = list.where((c) => c.balance > 0).toList();
    if (_filter == 'contacts') list = list.where((c) => c.contactsCount > 0).toList();
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final digits = q.replaceAll(RegExp(r'\D'), '');
      list = list.where((c) =>
        c.name.toLowerCase().contains(q) ||
        (c.region ?? '').toLowerCase().contains(q) ||
        (digits.length >= 3 && ((c.tin ?? '').replaceAll(RegExp(r'\D'), '').contains(digits) ||
            (c.phone ?? '').replaceAll(RegExp(r'\D'), '').contains(digits)))).toList();
    }
    return list;
  }

  void _setFilter(String f) => setState(() { _filter = f; _showCount = _pageSize; });

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final shown = filtered.take(_showCount).toList();
    final remaining = filtered.length - shown.length;
    final owingTotal = _all.fold<int>(0, (s, c) => s + c.balance);

    return Stack(children: [
      LayoutBuilder(builder: (ctx, cst) {
        final narrow = cst.maxWidth < 760;

        final listPane = Container(
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: narrow ? Colors.transparent : context.pal.border)),
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Customers', style: AppTheme.pageTitle.copyWith(fontSize: 18))),
                  if (!_loading)
                    Text('${_all.length}', style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
                ]),
                if (owingTotal > 0) ...[
                  const SizedBox(height: 2),
                  Text('${tshFromDouble(owingTotal)} owed in total',
                      style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.amber)),
                ],
                const SizedBox(height: 12),
                SearchField(
                  hint: 'Search name, TIN, phone or region…',
                  controller: _search,
                  onChanged: (_) => setState(() => _showCount = _pageSize),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final (v, l) in const [('all', 'All'), ('owing', 'Owing'), ('contacts', 'With contacts')]) ...[
                      _TagChip(label: l, active: _filter == v, onTap: () => _setFilter(v)),
                      const SizedBox(width: 6),
                    ],
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _error != null && _all.isEmpty
                    ? ErrorView(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: shown.isEmpty
                          ? ListView(children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 48),
                                child: Center(child: Text('No customers found', style: AppTheme.bodySub)),
                              ),
                            ])
                          : ListView.builder(
                              itemCount: shown.length + (remaining > 0 ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i == shown.length) {
                                  return InkWell(
                                    onTap: () => setState(() => _showCount += _pageSize),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      alignment: Alignment.center,
                                      child: Text('Load $remaining more',
                                          style: AppTheme.bodySm.copyWith(color: AppColors.teal, fontSize: 12.5)),
                                    ),
                                  );
                                }
                                final c = shown[i];
                                return _CustomerListItem(
                                  customer: c,
                                  selected: c.id == _selectedId,
                                  onTap: () => _select(c),
                                );
                              },
                            ),
                      ),
            ),
          ]),
        );

        Widget detailPane() {
          final d = _detail;
          if (d == null) {
            return Center(child: Text(_loading ? '' : 'Select a customer', style: TextStyle(color: context.pal.textMute)));
          }
          final open = _openContact;
          if (open != null) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _BackLink(label: 'Back to ${d.name}', onTap: () => setState(() => _openContact = null)),
              Expanded(child: _ContactDetail(
                contact: open,
                loadingDetail: _loadingContact,
                onLogInteraction: () => setState(() => _logFor = open),
                onEditContact: () => setState(() => _editFor = open),
                onScheduleFollowup: () => setState(() => _followupFor = open),
                onSendEmail: () => _openCompose(open),
              )),
            ]);
          }
          return _CustomerDetail(
            customer: d,
            loading: _loadingDetail,
            onAddContact: () => setState(() => _showAddContact = true),
            onEditCustomer: () => setState(() => _editCustomer = true),
            onOpenContact: _openContactDetail,
            onLogInteraction: (c) => setState(() => _logFor = c),
            onEditContact: (c) => setState(() => _editFor = c),
            onEmailContact: _openCompose,
            onOpenInvoice: _openInvoice,
            onOpenQuotation: _openQuotation,
            onOpenLedger: _canSeeLedger && d.invoicesCount > 0 ? () => _openLedger(d) : null,
          );
        }

        if (narrow) {
          if (_showDetailNarrow && _detail != null) {
            // Back (Android button / gesture) steps out one level: an open
            // contact first, then the customer, before leaving the screen.
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                setState(() {
                  if (_openContact != null) {
                    _openContact = null;
                  } else {
                    _showDetailNarrow = false;
                  }
                });
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_openContact == null)
                  _BackLink(label: 'Back to customers', onTap: () => setState(() => _showDetailNarrow = false)),
                Expanded(child: detailPane()),
              ]),
            );
          }
          return listPane;
        }

        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 360, child: listPane),
          Expanded(child: detailPane()),
        ]);
      }),

      // Dialogs
      if (_showAddContact && _detail != null)
        _AddContactDialog(
          hospitalId: _detail!.id,
          hospitalName: _detail!.name,
          onClose: () => setState(() => _showAddContact = false),
          onSaved: () { setState(() => _showAddContact = false); _afterContactSaved(); _load(); },
        ),
      if (_logFor != null)
        _LogInteractionDialog(
          contact: _logFor,
          onClose: () => setState(() => _logFor = null),
          onSaved: () { setState(() => _logFor = null); _afterContactSaved(); },
        ),
      if (_editFor != null)
        _EditContactDialog(
          contact: _editFor!,
          onClose: () => setState(() => _editFor = null),
          onSaved: () { setState(() => _editFor = null); _afterContactSaved(); },
        ),
      if (_followupFor != null)
        _ScheduleFollowupDialog(
          contact: _followupFor!,
          onClose: () => setState(() => _followupFor = null),
          onSaved: () { setState(() => _followupFor = null); _afterContactSaved(); },
        ),
      if (_editCustomer && _detail != null)
        _EditCustomerLoader(
          customerId: _detail!.id,
          onClose: () {
            setState(() => _editCustomer = false);
            _load();
          },
        ),
    ]);
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.active, required this.onTap});
  final String label; final bool active; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? AppColors.tealSoft : context.pal.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: active ? AppColors.teal : context.pal.border),
      ),
      child: Text(label, style: AppTheme.bodySub.copyWith(
        color: active ? AppColors.teal : context.pal.textMute,
        fontSize: 11.5, fontWeight: FontWeight.w500,
      )),
    ),
  );
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.label, required this.onTap});
  final String label; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
      child: Row(children: [
        Icon(Symbols.arrow_back, size: 16, color: AppColors.teal),
        const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySm.copyWith(color: AppColors.teal))),
      ]),
    ),
  );
}

AvatarVariant _variantFor(String name) =>
    AvatarVariant.values[name.hashCode.abs() % AvatarVariant.values.length];

String _money(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}TSh $b';
}

String _fmtDate(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  return d == null ? '—' : formatDate(d);
}

class _CustomerListItem extends StatelessWidget {
  const _CustomerListItem({required this.customer, required this.selected, required this.onTap});
  final Customer customer; final bool selected; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final sub = [
      if (c.location.isNotEmpty) c.location,
      if (c.tin != null) 'TIN ${c.tin}',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? context.pal.surface2 : Colors.transparent,
          border: Border(bottom: BorderSide(color: context.pal.divider)),
        ),
        child: Row(children: [
          AvatarWidget(initials: c.initials, size: 34, variant: _variantFor(c.name)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
            if (sub.isNotEmpty)
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
            if (c.contactsCount > 0) ...[
              const SizedBox(height: 3),
              Text('${c.contactsCount} contact${c.contactsCount == 1 ? '' : 's'}',
                  style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
            ],
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (c.balance > 0)
              Text(tshFromDouble(c.balance), style: AppTheme.monoSm.copyWith(fontSize: 12, color: AppColors.amber))
            else if (c.invoicesCount > 0)
              Text('Paid up', style: AppTheme.bodySub.copyWith(fontSize: 11, color: AppColors.green)),
            if (c.invoicesCount > 0)
              Text('${c.invoicesCount} inv', style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
          ]),
        ]),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child; final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: context.pal.surface1,
      borderRadius: BorderRadius.circular(AppColors.rLg),
      border: Border.all(color: context.pal.border),
    ),
    child: child,
  );
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, {this.color});
  final String label, value; final Color? color;

  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: AppTheme.labelCaps),
      const SizedBox(height: 6),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: AppTheme.bodyStrong.copyWith(fontSize: 16, color: color ?? context.pal.text)),
    ]),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.icon, this.label, this.value);
  final IconData icon; final String label; final String? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 15, color: context.pal.textDim),
      const SizedBox(width: 10),
      SizedBox(width: 70, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12))),
      Expanded(child: SelectableText(value ?? '—', style: AppTheme.bodySm.copyWith(
          fontSize: 12.5, color: value == null ? context.pal.textDim : context.pal.text))),
    ]),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'paid' || 'accepted' || 'converted' => AppColors.green,
      'overdue' || 'rejected' || 'expired' => AppColors.coral,
      'partial' || 'pending' || 'sent' => AppColors.amber,
      _ => context.pal.textMute,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status.isEmpty ? '—' : status[0].toUpperCase() + status.substring(1),
          style: AppTheme.bodySub.copyWith(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _CustomerDetail extends StatelessWidget {
  const _CustomerDetail({
    required this.customer,
    required this.loading,
    required this.onAddContact,
    required this.onEditCustomer,
    required this.onOpenContact,
    required this.onLogInteraction,
    required this.onEditContact,
    required this.onEmailContact,
    required this.onOpenInvoice,
    required this.onOpenQuotation,
    this.onOpenLedger,
  });
  final Customer customer;
  final bool loading;
  final VoidCallback onAddContact, onEditCustomer;
  final ValueChanged<Contact> onOpenContact, onLogInteraction, onEditContact, onEmailContact;
  final ValueChanged<int> onOpenInvoice, onOpenQuotation;
  final VoidCallback? onOpenLedger;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final typeLabel = c.type == null ? null : c.type![0].toUpperCase() + c.type!.substring(1);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        _Card(
          padding: const EdgeInsets.all(20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AvatarWidget(initials: c.initials, size: 52, variant: _variantFor(c.name)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: AppTheme.pageTitle.copyWith(fontSize: 20)),
              const SizedBox(height: 4),
              Text([?typeLabel, if (c.location.isNotEmpty) c.location].join(' · '),
                  style: AppTheme.bodySub),
              if (c.lastInvoiceDate != null) ...[
                const SizedBox(height: 4),
                Text('Last invoice ${_fmtDate(c.lastInvoiceDate)}'
                    '${c.firstInvoiceDate != null ? ' · customer since ${_fmtDate(c.firstInvoiceDate)}' : ''}',
                    style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
              ],
            ])),
            if (loading)
              const Padding(padding: EdgeInsets.only(right: 12, top: 4),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              AppButton(label: 'Add contact', icon: Symbols.person_add, variant: BtnVariant.primary, small: true,
                  onPressed: onAddContact),
              const SizedBox(height: 8),
              AppButton(label: 'Edit details', icon: Symbols.edit, variant: BtnVariant.normal, small: true,
                  onPressed: onEditCustomer),
              if (onOpenLedger != null) ...[
                const SizedBox(height: 8),
                AppButton(label: 'Ledger', icon: Symbols.receipt_long, variant: BtnVariant.normal, small: true,
                    onPressed: onOpenLedger),
              ],
            ]),
          ]),
        ),
        const SizedBox(height: 16),

        // Numbers
        LayoutBuilder(builder: (ctx, cst) {
          final kpis = [
            _Kpi('Total billed', tshFromDouble(c.totalBilled)),
            _Kpi('Paid', tshFromDouble(c.isDetail ? c.totalPaid : c.totalBilled - c.balance), color: AppColors.green),
            _Kpi('Balance owed', tshFromDouble(c.balance), color: c.balance > 0 ? AppColors.amber : null),
            _Kpi('Invoices', '${c.invoicesCount}${c.openInvoices > 0 ? ' · ${c.openInvoices} open' : ''}'),
          ];
          final perRow = cst.maxWidth > 820 ? 4 : cst.maxWidth > 480 ? 3 : 2;
          final w = (cst.maxWidth - 12 * (perRow - 1)) / perRow;
          return Wrap(spacing: 12, runSpacing: 12,
              children: kpis.map((k) => SizedBox(width: w, child: k)).toList());
        }),
        const SizedBox(height: 16),

        // Customer details
        _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Customer details', style: AppTheme.cardTitle),
          const SizedBox(height: 14),
          _InfoLine(Symbols.badge, 'TIN', c.tin),
          _InfoLine(Symbols.phone, 'Phone', c.phone),
          _InfoLine(Symbols.mail, 'Email', c.email),
          _InfoLine(Symbols.location_on, 'Address', c.address),
          if (c.contactName != null) _InfoLine(Symbols.person, 'Contact', c.contactName),
          if (c.notes != null && !c.notes!.startsWith('Client imported from Clickhuduma'))
            _InfoLine(Symbols.notes, 'Notes', c.notes),
        ])),
        const SizedBox(height: 16),

        // Contact people
        _Card(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                Expanded(child: Text(c.isDetail ? 'Contacts (${c.contacts.length})' : 'Contacts',
                    style: AppTheme.cardTitle)),
                AppButton(label: 'Add', icon: Symbols.add, variant: BtnVariant.ghost, small: true, onPressed: onAddContact),
              ]),
            ),
            if (c.isDetail && c.contacts.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Text('No contact people yet. Add the person you deal with at ${c.name}.',
                    style: AppTheme.bodySub),
              ),
            for (final p in c.contacts)
              InkWell(
                onTap: () => onOpenContact(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.divider))),
                  child: Row(children: [
                    AvatarWidget(initials: p.initials, size: 32, variant: _variantFor(p.fullName)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.fullName, style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
                      Text([?p.jobTitle, ?p.phone, ?p.email].where((s) => s.trim().isNotEmpty).join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                    ])),
                    IconButton(tooltip: 'Log interaction', iconSize: 17,
                        icon: const Icon(Symbols.add_comment), onPressed: () => onLogInteraction(p)),
                    IconButton(tooltip: 'Send email', iconSize: 17,
                        icon: const Icon(Symbols.mail), onPressed: p.email == null ? null : () => onEmailContact(p)),
                    IconButton(tooltip: 'Edit contact', iconSize: 17,
                        icon: const Icon(Symbols.edit), onPressed: () => onEditContact(p)),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),

        // Invoices
        if (c.isDetail)
          _Card(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(children: [
                  Expanded(child: Text('Invoices', style: AppTheme.cardTitle)),
                  if (c.invoicesCount > c.recentInvoices.length)
                    Text('latest ${c.recentInvoices.length} of ${c.invoicesCount}',
                        style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
                ]),
              ),
              if (c.recentInvoices.isEmpty)
                Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    child: Text('No invoices yet.', style: AppTheme.bodySub)),
              for (final inv in c.recentInvoices)
                _DocRow(
                  number: inv.number,
                  date: _fmtDate(inv.issueDate),
                  status: inv.status,
                  total: _money(inv.total),
                  extra: inv.balance > 0 ? '${_money(inv.balance)} due' : null,
                  onTap: () => onOpenInvoice(inv.id),
                ),
            ]),
          ),
        if (c.isDetail && c.recentQuotations.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Card(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text('Quotations', style: AppTheme.cardTitle),
              ),
              for (final q in c.recentQuotations)
                _DocRow(
                  number: q.number,
                  date: _fmtDate(q.date),
                  status: q.status,
                  total: _money(q.total),
                  onTap: () => onOpenQuotation(q.id),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({required this.number, required this.date, required this.status,
      required this.total, this.extra, required this.onTap});
  final String number, date, status, total;
  final String? extra;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.divider))),
      child: LayoutBuilder(builder: (context, cst) => cst.maxWidth < 420
          // Phones: number + status, then date + amount.
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(number, style: AppTheme.monoSm.copyWith(fontSize: 12.5),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                _StatusPill(status),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Text(date, style: AppTheme.bodySub.copyWith(fontSize: 12))),
                if (extra != null) ...[
                  Text(extra!, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: AppColors.amber)),
                  const SizedBox(width: 8),
                ],
                Text(total, style: AppTheme.monoSm.copyWith(fontSize: 12.5)),
              ]),
            ])
          : Row(children: [
        Expanded(flex: 3, child: Text(number, style: AppTheme.monoSm.copyWith(fontSize: 12.5))),
        Expanded(flex: 3, child: Text(date, style: AppTheme.bodySub.copyWith(fontSize: 12))),
        Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: _StatusPill(status))),
        Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(total, style: AppTheme.monoSm.copyWith(fontSize: 12.5)),
          if (extra != null)
            Text(extra!, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: AppColors.amber)),
        ])),
      ])),
    ),
  );
}

/// Loads the full client record, then shows the edit dialog for it (TIN, phone, address, …).
class _EditCustomerLoader extends StatefulWidget {
  const _EditCustomerLoader({required this.customerId, required this.onClose});
  final int customerId;
  final VoidCallback onClose;

  @override
  State<_EditCustomerLoader> createState() => _EditCustomerLoaderState();
}

class _EditCustomerLoaderState extends State<_EditCustomerLoader> {
  late final _future = ClientService.instance.get(widget.customerId);

  @override
  void initState() {
    super.initState();
    _future.then((_) {}, onError: (Object e) {
      if (mounted) { showErrorToast(context, e); widget.onClose(); }
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _future,
    builder: (context, snap) => snap.hasData
        ? EditClientDialog(client: snap.data!, onClose: widget.onClose)
        : Container(color: const Color(0xAA06070A), alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2)),
  );
}

class _ContactDetail extends StatelessWidget {
  const _ContactDetail({
    required this.contact,
    this.loadingDetail = false,
    this.onLogInteraction,
    this.onEditContact,
    this.onScheduleFollowup,
    this.onSendEmail,
  });
  final Contact contact;
  final bool loadingDetail;
  final VoidCallback? onLogInteraction;
  final VoidCallback? onEditContact;
  final VoidCallback? onScheduleFollowup;
  final VoidCallback? onSendEmail;

  AvatarVariant _variant(String name) {
    final h = name.hashCode;
    const variants = AvatarVariant.values;
    return variants[h.abs() % variants.length];
  }

  String _interactionIcon(String type) => switch (type) {
    'call'     => '📞',
    'email'    => '✉️',
    'meeting'  => '🤝',
    'whatsapp' => '💬',
    'visit'    => '🏥',
    _          => '📋',
  };

  Color _dotColor(String type) => switch (type) {
    'call'     => AppColors.teal,
    'email'    => AppColors.blue,
    'meeting'  => AppColors.violet,
    'whatsapp' => const Color(0xFF25D366),
    'visit'    => AppColors.amber,
    _          => AppColors.textDim,
  };

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Profile header
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: context.pal.border),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AvatarWidget(initials: contact.initials, size: 56, variant: _variant(contact.fullName)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(contact.fullName, style: AppTheme.pageTitle.copyWith(fontSize: 20)),
            const SizedBox(height: 2),
            if (contact.jobTitle != null)
              Text(contact.jobTitle!, style: AppTheme.bodySub),
            const SizedBox(height: 8),
            Row(children: [
              const SizedBox(width: 6),
              Text(contact.hospitalName, style: AppTheme.bodySm),
            ]),
            if (contact.department != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const SizedBox(width: 6),
                Text(contact.department!, style: AppTheme.bodySm),
              ]),
            ],
          ])),
          Column(children: [
            AppButton(label: 'Log Interaction', icon: Symbols.add_comment, variant: BtnVariant.primary, small: true,
                onPressed: onLogInteraction),
            const SizedBox(height: 8),
            AppButton(label: 'Edit Contact', icon: Symbols.edit, variant: BtnVariant.normal, small: true,
                onPressed: onEditContact),
            const SizedBox(height: 8),
            AppButton(label: 'Send Email', icon: Symbols.mail, variant: BtnVariant.normal, small: true,
                onPressed: contact.email != null ? onSendEmail : null),
          ]),
        ]),
      ),
      const SizedBox(height: 16),

      // Contact info + follow-up row
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Contact details
        Expanded(child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(AppColors.rLg),
            border: Border.all(color: context.pal.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const SizedBox(width: 8),
              Text('Contact Details', style: AppTheme.cardTitle),
            ]),
            const SizedBox(height: 14),
            if (contact.email != null)
              _DetailRow(icon: Symbols.mail_outline, value: contact.email!),
            if (contact.phone != null) ...[
              const SizedBox(height: 8),
              _DetailRow(icon: Symbols.phone, value: contact.phone!),
            ],
            if (contact.whatsapp != null) ...[
              const SizedBox(height: 8),
              _DetailRow(icon: Symbols.chat, value: contact.whatsapp!),
            ],
            if (contact.lastContactedAt != null) ...[
              const SizedBox(height: 14),
              const SizedBox(height: 10),
              _DetailRow(icon: Symbols.history, value: 'Last contacted: ${contact.lastContactedAt!}'),
            ],
          ]),
        )),
        const SizedBox(width: 16),
        // Follow-up
        Expanded(child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(AppColors.rLg),
            border: Border.all(color: context.pal.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const SizedBox(width: 8),
              Text('Follow-up & Tags', style: AppTheme.cardTitle),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: contact.nextFollowupAt != null ? AppColors.amberSoft : context.pal.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: contact.nextFollowupAt != null
                    ? AppColors.amber.withValues(alpha: 0.3) : context.pal.border),
              ),
              child: Row(children: [
                Icon(Symbols.calendar_today, size: 14,
                    color: contact.nextFollowupAt != null ? AppColors.amber : context.pal.textDim),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Next Follow-up', style: AppTheme.labelCaps),
                  Text(contact.nextFollowupAt ?? 'Not scheduled',
                      style: AppTheme.bodyStrong.copyWith(
                          color: contact.nextFollowupAt != null ? AppColors.amber : context.pal.textMute)),
                ])),
                GestureDetector(
                  onTap: onScheduleFollowup,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Symbols.edit_calendar, size: 14, color: AppColors.teal),
                    const SizedBox(width: 4),
                    Text('Set', style: AppTheme.bodySub.copyWith(color: AppColors.teal, fontSize: 11.5)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            if (contact.tags.isNotEmpty) ...[
              Text('TAGS', style: AppTheme.labelCaps),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: contact.tags.map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.tealSoft, borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
                ),
                child: Text(tag, style: AppTheme.bodySub.copyWith(
                  color: AppColors.teal, fontSize: 11.5, fontWeight: FontWeight.w500)),
              )).toList()),
            ],
          ]),
        )),
      ]),
      const SizedBox(height: 16),

      // Interaction history
      Container(
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: context.pal.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(children: [
              const SizedBox(width: 8),
              Expanded(child: Text('Interaction History', style: AppTheme.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (loadingDetail)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Text('${contact.interactions.length} interactions',
                  style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
            ]),
          ),
          if (!loadingDetail && contact.interactions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text('No interactions logged yet', style: AppTheme.bodySub)),
            )
          else if (!loadingDetail)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: contact.interactions.asMap().entries.map((e) {
                  final isLast = e.key == contact.interactions.length - 1;
                  final ix = e.value;
                  return IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Timeline spine
                      SizedBox(width: 32, child: Column(children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: _dotColor(ix.type).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(color: _dotColor(ix.type).withValues(alpha: 0.5)),
                          ),
                          alignment: Alignment.center,
                          child: Text(_interactionIcon(ix.type), style: const TextStyle(fontSize: 13)),
                        ),
                        if (!isLast)
                          Expanded(child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: context.pal.divider,
                          )),
                      ])),
                      const SizedBox(width: 12),
                      // Content
                      Expanded(child: Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SizedBox(height: 4),
                          Row(children: [
                            Text(ix.type.toUpperCase(), style: AppTheme.labelCaps),
                            const SizedBox(width: 8),
                            Text(ix.createdAt, style: AppTheme.bodySub.copyWith(fontSize: 11)),
                          ]),
                          const SizedBox(height: 4),
                          Text(ix.summary, style: AppTheme.bodySm.copyWith(height: 1.5)),
                          if (ix.outcome != null) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Text('Outcome: ', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                              Flexible(child: Text(ix.outcome!,
                                  style: AppTheme.bodySm.copyWith(fontSize: 11.5, color: AppColors.teal))),
                            ]),
                          ],
                          if (ix.nextAction != null) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Symbols.arrow_forward, size: 12, color: AppColors.amber),
                              const SizedBox(width: 4),
                              Flexible(child: Text(
                                '${ix.nextAction!}${ix.nextActionDate != null ? "  ·  ${ix.nextActionDate}" : ""}',
                                style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.amber))),
                            ]),
                          ],
                        ]),
                      )),
                    ]),
                  );
                }).toList(),
              ),
            ),
        ]),
      ),
    ]),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.value});
  final IconData icon; final String value;

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 14, color: context.pal.textDim),
    const SizedBox(width: 8),
    Expanded(child: Text(value, style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
  ]);
}

// ── Add Contact Dialog ──────────────────────────────────────────────────────
class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog({required this.onClose, this.onSaved, this.hospitalId, this.hospitalName});
  final VoidCallback  onClose;
  final VoidCallback? onSaved;
  // The customer the contact works at, when adding from a customer's page.
  final int?    hospitalId;
  final String? hospitalName;
  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl  = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  late int?    _hospitalId   = widget.hospitalId;
  late String? _hospitalName = widget.hospitalName;
  bool   _saving   = false;

  @override
  void dispose() {
    _firstCtrl.dispose(); _lastCtrl.dispose(); _titleCtrl.dispose();
    _emailCtrl.dispose(); _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _firstCtrl.text.trim().isEmpty || _hospitalId == null) return;
    setState(() => _saving = true);
    try {
      await ContactService.instance.create({
        'first_name':  _firstCtrl.text.trim(),
        'last_name':   _lastCtrl.text.trim(),
        'job_title':   _titleCtrl.text.trim(),
        'hospital_id': _hospitalId,
        'email':       _emailCtrl.text.trim(),
        'phone':       _phoneCtrl.text.trim(),
      });
      if (mounted) showSuccessToast(context, 'Contact created');
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) { setState(() => _saving = false); showErrorToast(context, e); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ModalShell(
    onClose: widget.onClose,
    onSave: _save,
    saving: _saving,
    icon: Symbols.person_add,
    title: widget.hospitalName != null ? 'Add contact · ${widget.hospitalName}' : 'Add Contact',
    saveLabel: 'Save Contact',
    child: Column(children: [
      Row(children: [
        Expanded(child: _CField('First name', _firstCtrl, 'Amina')),
        const SizedBox(width: 14),
        Expanded(child: _CField('Last name', _lastCtrl, 'Hassan')),
      ]),
      const SizedBox(height: 14),
      _CField('Job title', _titleCtrl, 'e.g. Head of Procurement'),
      const SizedBox(height: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('HOSPITAL', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
        const SizedBox(height: 6),
        AppSearchableSelectField<int>(
          hint: 'Search clients…',
          selectedLabel: _hospitalName,
          asyncSearch: (q) async {
            final results = await ClientService.instance.search(q);
            return results.map((h) => AppSelectItem(value: h.id, label: h.name)).toList();
          },
          onSelected: (item) => setState(() {
            _hospitalId = item?.value;
            _hospitalName = item?.label;
          }),
        ),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _CField('Email', _emailCtrl, 'name@company.co.tz')),
        const SizedBox(width: 14),
        Expanded(child: _CField('Phone', _phoneCtrl, '+255 7XX XXX XXX')),
      ]),
    ]),
  );
  }
}

// ── Log Interaction Dialog ──────────────────────────────────────────────────
class _LogInteractionDialog extends StatefulWidget {
  const _LogInteractionDialog({required this.onClose, this.contact, this.onSaved});
  final VoidCallback  onClose;
  final VoidCallback? onSaved;
  final Contact?      contact;
  @override
  State<_LogInteractionDialog> createState() => _LogInteractionDialogState();
}

class _LogInteractionDialogState extends State<_LogInteractionDialog> {
  String    _type    = 'call';
  String    _outcome = 'Positive —follow-up needed';
  DateTime? _nextActionDate;
  bool      _saving  = false;
  String?   _error;
  final _summaryCtrl    = TextEditingController();
  final _nextActionCtrl = TextEditingController();

  @override
  void dispose() { _summaryCtrl.dispose(); _nextActionCtrl.dispose(); super.dispose(); }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextActionDate ?? DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _nextActionDate = picked);
  }

  Future<void> _save() async {
    final contact = widget.contact;
    if (contact == null || _saving || _summaryCtrl.text.trim().isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ContactService.instance.addInteraction(contact.id, {
        'type':             _type,
        'summary':          _summaryCtrl.text.trim(),
        'outcome':          _outcome,
        if (_nextActionCtrl.text.trim().isNotEmpty)
          'next_action': _nextActionCtrl.text.trim(),
        if (_nextActionDate != null)
          'next_action_date': _fmtDate(_nextActionDate!),
      });
      if (mounted) showSuccessToast(context, 'Interaction logged');
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) { setState(() => _saving = false); showErrorToast(context, e); }
    }
  }

  @override
  Widget build(BuildContext context) => _ModalShell(
    onClose: widget.onClose,
    onSave:  _save,
    saving:  _saving,
    icon: Symbols.add_comment,
    title: 'Log Interaction${widget.contact != null ? " · ${widget.contact!.fullName}" : ""}',
    saveLabel: 'Save Interaction',
    child: Column(children: [
      _CDropdown(
        label: 'Type',
        value: _type,
        items: const ['call', 'email', 'meeting', 'whatsapp', 'visit'],
        display: const ['Phone Call', 'Email', 'Meeting', 'WhatsApp', 'Site Visit'],
        onChanged: (v) => setState(() => _type = v),
      ),
      const SizedBox(height: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LabeledTextField(label: 'Summary', controller: _summaryCtrl, maxLines: 3, hint: 'What was discussed?'),
      ]),
      const SizedBox(height: 14),
      _CDropdown(
        label: 'Outcome',
        value: _outcome,
        items: const [
          'Positive —follow-up needed',
          'Proposal requested',
          'Contract signed',
          'Not interested',
          'No answer',
        ],
        onChanged: (v) => setState(() => _outcome = v),
      ),
      const SizedBox(height: 14),
      _CField('Next action', _nextActionCtrl, 'e.g. Send formal proposal'),
      const SizedBox(height: 14),
      // Next action date picker
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Next action date', style: AppTheme.fieldLabel),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.pal.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _nextActionDate != null ? AppColors.teal : context.pal.border),
            ),
            child: Row(children: [
              Icon(Symbols.calendar_today, size: 14,
                  color: _nextActionDate != null ? AppColors.teal : context.pal.textDim),
              const SizedBox(width: 8),
              Text(
                _nextActionDate != null ? _fmtDate(_nextActionDate!) : 'Optional —pick a date',
                style: AppTheme.bodySm.copyWith(
                  color: _nextActionDate != null ? context.pal.text : context.pal.textDim),
              ),
            ]),
          ),
        ),
      ]),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
      ],
    ]),
  );
}

// ── Schedule Follow-up Dialog ───────────────────────────────────────────────
class _ScheduleFollowupDialog extends StatefulWidget {
  const _ScheduleFollowupDialog({required this.contact, required this.onClose, this.onSaved});
  final Contact      contact;
  final VoidCallback onClose;
  final VoidCallback? onSaved;
  @override
  State<_ScheduleFollowupDialog> createState() => _ScheduleFollowupDialogState();
}

class _ScheduleFollowupDialogState extends State<_ScheduleFollowupDialog> {
  DateTime? _date;
  bool      _saving = false;
  String?   _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing follow-up date if set
    if (widget.contact.nextFollowupAt != null) {
      _date = DateTime.tryParse(widget.contact.nextFollowupAt!);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_date == null || _saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ContactService.instance.update(widget.contact.id, {'next_followup_at': _fmtDate(_date!)});
      if (mounted) showSuccessToast(context, 'Follow-up scheduled for ${_fmtDate(_date!)}');
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) => _ModalShell(
    onClose: widget.onClose,
    onSave:  _save,
    saving:  _saving,
    icon: Symbols.edit_calendar,
    title: 'Schedule Follow-up · ${widget.contact.fullName}',
    saveLabel: 'Schedule',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Follow-up date', style: AppTheme.fieldLabel),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: _pickDate,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.pal.surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _date != null ? AppColors.teal : context.pal.border),
          ),
          child: Row(children: [
            Icon(Symbols.calendar_today, size: 16,
                color: _date != null ? AppColors.teal : context.pal.textDim),
            const SizedBox(width: 10),
            Text(
              _date != null ? _fmtDate(_date!) : 'Click to choose a date',
              style: AppTheme.bodySm.copyWith(
                  color: _date != null ? context.pal.text : context.pal.textDim),
            ),
          ]),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
      ],
    ]),
  );
}

// ── Shared modal shell ──────────────────────────────────────────────────────
class _ModalShell extends StatelessWidget {
  const _ModalShell({
    required this.onClose,
    required this.icon,
    required this.title,
    required this.child,
    required this.saveLabel,
    this.onSave,
    this.saving = false,
  });
  final VoidCallback  onClose;
  final VoidCallback? onSave;
  final IconData icon;
  final String title, saveLabel;
  final Widget child;
  final bool saving;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onClose,
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 500,
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(icon, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: AppTheme.bodyStrong)),
                GestureDetector(onTap: onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(padding: const EdgeInsets.all(20), child: child),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Expanded(child: GestureDetector(
                  onTap: onClose,
                  child: Container(height: 38,
                    decoration: BoxDecoration(border: Border.all(color: context.pal.border),
                        borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text('Cancel', style: AppTheme.bodySm))),
                )),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: onSave ?? onClose,
                  child: Container(height: 38,
                    decoration: BoxDecoration(color: AppColors.teal,
                        borderRadius: BorderRadius.circular(8)),
                    child: Center(child: saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(saveLabel, style: AppTheme.bodyStrong.copyWith(
                          color: const Color(0xFF06120F), fontSize: 13)))),
                )),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );
}

class _CField extends StatelessWidget {
  const _CField(this.label, this.ctrl, this.hint);
  final String label, hint;
  final TextEditingController ctrl;

  // The Settings text input (shared LabeledTextField).
  @override
  Widget build(BuildContext context) => LabeledTextField(label: label, controller: ctrl, hint: hint);
}

class _CDropdown extends StatelessWidget {
  const _CDropdown({required this.label, required this.value, required this.items,
      this.display, required this.onChanged});
  final String label, value;
  final List<String> items;
  final List<String>? display;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    DropdownFieldBox<String>(
      value: value,
      items: items.asMap().entries.map((e) =>
            DropdownMenuItem(value: e.value,
                child: Text(display != null ? display![e.key] : e.value))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    ),
  ]);
}

// ── Edit Contact Dialog ─────────────────────────────────────────────────────
class _EditContactDialog extends StatefulWidget {
  const _EditContactDialog({required this.contact, required this.onClose, this.onSaved});
  final Contact      contact;
  final VoidCallback onClose;
  final VoidCallback? onSaved;
  @override
  State<_EditContactDialog> createState() => _EditContactDialogState();
}

class _EditContactDialogState extends State<_EditContactDialog> {
  late final _firstCtrl = TextEditingController(text: widget.contact.firstName);
  late final _lastCtrl  = TextEditingController(text: widget.contact.lastName);
  late final _titleCtrl = TextEditingController(text: widget.contact.jobTitle ?? '');
  late final _emailCtrl = TextEditingController(text: widget.contact.email ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.contact.phone ?? '');
  late int?    _hospitalId   = widget.contact.hospitalId;
  late String? _hospitalName = widget.contact.hospitalName;
  bool        _saving   = false;

  @override
  void dispose() {
    _firstCtrl.dispose(); _lastCtrl.dispose(); _titleCtrl.dispose();
    _emailCtrl.dispose(); _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ContactService.instance.update(widget.contact.id, {
        'first_name':  _firstCtrl.text.trim(),
        'last_name':   _lastCtrl.text.trim(),
        'job_title':   _titleCtrl.text.trim(),
        if (_hospitalId != null) 'hospital_id': _hospitalId,
        'email':       _emailCtrl.text.trim(),
        'phone':       _phoneCtrl.text.trim(),
      });
      if (mounted) showSuccessToast(context, 'Contact updated');
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) { setState(() => _saving = false); showErrorToast(context, e); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ModalShell(
      onClose: widget.onClose,
      onSave: _save,
      saving: _saving,
      icon: Symbols.edit,
      title: 'Edit: ${widget.contact.fullName}',
      saveLabel: 'Save Changes',
      child: Column(children: [
        Row(children: [
          Expanded(child: _CField('First name', _firstCtrl, '')),
          const SizedBox(width: 14),
          Expanded(child: _CField('Last name', _lastCtrl, '')),
        ]),
        const SizedBox(height: 14),
        _CField('Job title', _titleCtrl, ''),
        const SizedBox(height: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('HOSPITAL', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
          const SizedBox(height: 6),
          AppSearchableSelectField<int>(
            hint: 'Search clients…',
            selectedLabel: _hospitalName,
            asyncSearch: (q) async {
              final results = await ClientService.instance.search(q);
              return results.map((h) => AppSelectItem(value: h.id, label: h.name)).toList();
            },
            onSelected: (item) => setState(() {
              _hospitalId = item?.value;
              _hospitalName = item?.label;
            }),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _CField('Email', _emailCtrl, '')),
          const SizedBox(width: 14),
          Expanded(child: _CField('Phone', _phoneCtrl, '')),
        ]),
      ]),
    );
  }
}
