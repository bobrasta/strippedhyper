import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/client.dart';
import '../../models/inventory_item.dart';
import '../../models/inventory_lot.dart';
import '../../models/invoice.dart';
import '../../services/client_service.dart';
import '../../services/inventory_service.dart';
import '../../services/invoice_service.dart';
import '../../services/quotation_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/tin.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/sales/line_items.dart';
import '../../widgets/sales/terms_editor.dart';

String _fmtDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The sale form (Clickhuduma "Add sale"): raises a sale directly — no
/// quotation or sales order behind it (POST /invoices). Its Status saves
/// it as a Final sale, a Draft or a Proforma (finalised later by editing),
/// or as a Quotation on the Quotations page.
///
/// [editing] opens an existing sale for editing (PUT /invoices/{id});
/// [duplicateFrom] pre-fills a new sale from an existing one. Pops with
/// the saved [Invoice] (null when it was saved as a quotation).
class InvoiceBuilderScreen extends StatefulWidget {
  const InvoiceBuilderScreen({super.key, this.editing, this.duplicateFrom, this.initialStatus = 'final', this.onDone});
  final Invoice? editing;
  final Invoice? duplicateFrom;
  // final | draft | quotation | proforma — the sidebar's Add sale / Add
  // draft / Add quotation open the form on one of these.
  final String initialStatus;
  // Set when the form is a sidebar page rather than a pushed route: called
  // with the saved status instead of popping (there's nothing to pop to).
  final ValueChanged<String>? onDone;

  @override
  State<InvoiceBuilderScreen> createState() => _InvoiceBuilderScreenState();
}

class _InvoiceBuilderScreenState extends State<InvoiceBuilderScreen> {
  final _clientCtrl  = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _tinCtrl     = TextEditingController();
  final _notesCtrl   = TextEditingController();
  // The linked customer (its id is known at once, so saving can't unlink it).
  int? _hospitalId;
  DateTime _issueDate = DateTime.now();
  // Payment term (Clickhuduma style — 30 days on nearly every sale); the
  // due date is worked out from it.
  final _termCtrl     = TextEditingController(text: '30');
  String _termType    = 'days';
  final _shipCtrl     = TextEditingController();
  // Optional first payment taken now — the rest stays on credit.
  final _depositCtrl  = TextEditingController();
  final _depositRefCtrl = TextEditingController();
  String _depositMethod = 'bank_transfer';
  String _currency    = 'TZS';
  int    _taxRate     = 0;
  bool   _saving      = false;
  final _lines = [LineItemEntry()];
  List<InventoryItem> _invItems = [];
  Map<int, List<InventoryLot>> _lots = const {};
  Map<String, String> _errors = {};
  final _staffNoteCtrl = TextEditingController();
  final _terms = TermsController();
  // final | draft | proforma | quotation
  String _saleStatus = 'final';
  String? _hospitalLabel;

  bool get _isEdit => widget.editing != null;
  // A final sale can't go back to draft/proforma once saved.
  bool get _lockedFinal => _isEdit && widget.editing!.isFinal;

  @override
  void initState() {
    super.initState();
    InventoryService.instance.openLots().then((lots) {
      if (mounted) setState(() => _lots = lots);
    }).catchError((_) {});
    InventoryService.instance.list().then((items) {
      if (mounted) setState(() => _invItems = items);
    }).catchError((_) {});
    _saleStatus = widget.initialStatus;
    final src = widget.editing ?? widget.duplicateFrom;
    if (src != null) _prefill(src);
    _terms.load(src?.termItems).then((_) { if (mounted) setState(() {}); });
    for (final l in _lines) { _attach(l); }
  }

  void _prefill(Invoice inv) {
    if (_isEdit) _saleStatus = inv.saleStatus;
    _clientCtrl.text = inv.displayName == '—' ? '' : inv.displayName;
    _contactCtrl.text = inv.clientContact ?? '';
    _emailCtrl.text = inv.clientEmail ?? '';
    _tinCtrl.text = inv.clientTin ?? '';
    _notesCtrl.text = inv.notes ?? '';
    _staffNoteCtrl.text = inv.staffNote ?? '';
    if (_isEdit) _issueDate = DateTime.tryParse(inv.issueDate) ?? DateTime.now();
    if (inv.payTermNumber != null) {
      _termCtrl.text = '${inv.payTermNumber}';
      _termType = inv.payTermType == 'months' ? 'months' : 'days';
    }
    if (inv.shippingCharges > 0) _shipCtrl.text = '${inv.shippingCharges}';
    _taxRate = inv.taxRate.round() == 18 ? 18 : 0;
    _currency = const ['TZS', 'USD', 'EUR', 'KES'].contains(inv.currency) ? inv.currency : 'TZS';
    if (inv.lineItems.isNotEmpty) {
      for (final l in _lines) { l.dispose(); }
      _lines
        ..clear()
        ..addAll(inv.lineItems.map((li) {
          final e = LineItemEntry();
          e.descCtrl.text = li.description;
          e.qtyCtrl.text = li.quantity == li.quantity.roundToDouble() ? '${li.quantity.toInt()}' : '${li.quantity}';
          e.priceCtrl.text = '${li.unitPrice}';
          if (li.discount > 0) e.discCtrl.text = '${li.discount}';
          e.inventoryItemId = li.inventoryItemId;
          e.uomCtrl.text = li.unitOfMeasure ?? '';
          e.lotCtrl.text = li.lotNumber ?? '';
          e.expiry = li.expiryDate == null ? null : DateTime.tryParse(li.expiryDate!);
          return e;
        }));
    }
    _hospitalId = inv.hospitalId;
    if (inv.hospitalId != null) {
      _hospitalLabel = inv.hospitalName ?? inv.displayName;
    }
  }

  void _attach(LineItemEntry l) {
    l.qtyCtrl.addListener(_recalc);
    l.priceCtrl.addListener(_recalc);
    l.discCtrl.addListener(_recalc);
  }

  void _recalc() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _clientCtrl.dispose(); _contactCtrl.dispose();
    _emailCtrl.dispose();  _notesCtrl.dispose(); _tinCtrl.dispose();
    _termCtrl.dispose(); _shipCtrl.dispose(); _depositCtrl.dispose(); _depositRefCtrl.dispose();
    _staffNoteCtrl.dispose();
    _terms.dispose();
    for (final l in _lines) { l.dispose(); }
    super.dispose();
  }

  // Before line discounts; _subtotal is after them (what VAT is charged on).
  int get _gross => _lines.fold(0, (s, l) => s + l.gross);
  int get _discount => _lines.fold(0, (s, l) => s + l.discount);
  int get _subtotal => _gross - _discount;
  // Same rounding as InvoiceController@store.
  int get _tax => (_subtotal * _taxRate / 100).round();
  int get _shipping => int.tryParse(_shipCtrl.text.replaceAll(',', '').trim()) ?? 0;
  int get _total => _subtotal + _tax + _shipping;
  int get _deposit => int.tryParse(_depositCtrl.text.replaceAll(',', '').trim()) ?? 0;
  int? get _term => int.tryParse(_termCtrl.text.trim());

  // Same maths as the API (addDays / addMonthsNoOverflow).
  DateTime? get _dueDate {
    final n = _term;
    if (n == null || n < 0) return null;
    if (_termType == 'days') return _issueDate.add(Duration(days: n));
    final m = _issueDate.month + n;
    final y = _issueDate.year + (m - 1) ~/ 12;
    final month = (m - 1) % 12 + 1;
    final lastDay = DateTime(y, month + 1, 0).day;
    return DateTime(y, month, _issueDate.day > lastDay ? lastDay : _issueDate.day);
  }

  void _pickHospital(Client? h) => setState(() {
    _hospitalId = h?.id;
    _hospitalLabel = h?.name;
    _errors.remove('client');
    if (h != null) {
      _clientCtrl.text = h.name;
      if (h.contactName.isNotEmpty && h.contactName != '—') _contactCtrl.text = h.contactName;
      if (h.contactEmail.isNotEmpty && h.contactEmail != '—') _emailCtrl.text = h.contactEmail;
      if (h.tin != null) { _tinCtrl.text = h.tin!; _errors.remove('tin'); }
    }
  });

  bool _validate() {
    final errs = <String, String>{};
    if (_clientCtrl.text.trim().isEmpty) errs['client'] = 'Pick a client or type a client name';
    // A draft may be saved before the TIN is known, and so may an edit of an
    // existing sale (most imported sales have none). A typed TIN is still checked.
    final tinOptional = _saleStatus == 'draft' || _isEdit;
    final tinErr = tinOptional && _tinCtrl.text.trim().isEmpty ? null : tinError(_tinCtrl.text);
    if (tinErr != null) errs['tin'] = tinErr;
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) errs['email'] = 'Enter a valid email';
    final valid = _lines.where((l) => l.descCtrl.text.trim().isNotEmpty).toList();
    if (valid.isEmpty) errs['items'] = 'Add at least one line item';
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      if (l.descCtrl.text.trim().isEmpty) continue;
      final qty = int.tryParse(l.qtyCtrl.text);
      final price = int.tryParse(l.priceCtrl.text.replaceAll(',', ''));
      if (qty == null || qty <= 0) errs['items'] = 'Line ${i + 1}: enter a quantity';
      if (price == null || price < 0) errs['items'] = 'Line ${i + 1}: enter a unit price';
      final disc = l.discCtrl.text.trim();
      if (disc.isNotEmpty && int.tryParse(disc.replaceAll(',', '')) == null) {
        errs['items'] = 'Line ${i + 1}: enter the discount in TSh, e.g. 5000';
      } else if (l.discount < 0 || l.net < 0) {
        errs['items'] = 'Line ${i + 1}: the discount is more than the line amount';
      }
    }
    if (_term == null || _term! < 0) errs['due'] = 'Enter the payment term (e.g. 30 days)';
    if (_shipCtrl.text.trim().isNotEmpty && int.tryParse(_shipCtrl.text.replaceAll(',', '').trim()) == null) {
      errs['ship'] = 'Enter the delivery charge as a number';
    }
    if (_depositCtrl.text.trim().isNotEmpty && _showDeposit) {
      final d = int.tryParse(_depositCtrl.text.replaceAll(',', '').trim());
      if (d == null || d <= 0) {
        errs['deposit'] = 'Enter the deposit as a number';
      } else if (d > _total) {
        errs['deposit'] = 'Deposit is more than the invoice total';
      }
    }
    // Say at the top why nothing was saved — the field itself may be off screen.
    if (errs.isNotEmpty) errs['_server'] = 'Not saved: ${errs.values.first}';
    setState(() => _errors = errs);
    return errs.isEmpty;
  }

  // Deposit is taken with a new final sale only.
  bool get _showDeposit => !_isEdit && _saleStatus == 'final';

  List<Map<String, dynamic>> get _linePayload => _lines
      .where((l) => l.descCtrl.text.trim().isNotEmpty)
      .map((l) => {
            'inventory_item_id': l.itemId,
            'description': l.descCtrl.text.trim(),
            'quantity':    int.tryParse(l.qtyCtrl.text) ?? 1,
            'unit_of_measure': _text(l.uomCtrl),
            'lot_number':  _text(l.lotCtrl),
            'expiry_date': l.expiry == null ? null : _isoDate(l.expiry!),
            'unit_price':  int.tryParse(l.priceCtrl.text.replaceAll(',', '')) ?? 0,
            'discount':    l.discount,
          })
      .toList();

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_saving || !_validate()) return;
    setState(() => _saving = true);
    try {
      if (_saleStatus == 'quotation') {
        final q = await QuotationService.instance.create({
          'client_name':    _clientCtrl.text.trim(),
          'client_contact': _text(_contactCtrl),
          'client_email':   _text(_emailCtrl),
          'client_tin':     normalizeTin(_tinCtrl.text),
          'valid_until':    _isoDate(_dueDate ?? _issueDate.add(const Duration(days: 30))),
          'currency':       _currency,
          'notes':          _text(_notesCtrl),
          'term_items':     _terms.toJson(),
          // Quotations have no lot/expiry; their UOM column is required.
          'items': _linePayload.map((l) => {
            for (final e in l.entries)
              if (!const {'discount', 'lot_number', 'expiry_date'}.contains(e.key)) e.key: e.value,
            'unit_of_measure': l['unit_of_measure'] ?? 'pcs', 'discount_percent': 0, 'discount_amount': l['discount'],
          }).toList(),
        });
        if (!mounted) return;
        showSuccessToast(context, 'Saved as quotation ${q.quotationNumber} — it is on the Quotations page.');
        _finish(null);
        return;
      }

      final data = <String, dynamic>{
        'hospital_id':    _hospitalId,
        'client_name':    _clientCtrl.text.trim(),
        'client_contact': _text(_contactCtrl),
        'client_email':   _text(_emailCtrl),
        'client_tin':     _tinCtrl.text.trim().isEmpty ? null : normalizeTin(_tinCtrl.text),
        'issue_date':     _isoDate(_issueDate),
        'pay_term_number': _term,
        'pay_term_type':  _termType,
        'shipping_charges': _shipping,
        'tax_rate':       _taxRate,
        'notes':          _text(_notesCtrl),
        'staff_note':     _text(_staffNoteCtrl),
        'term_items':     _terms.toJson(),
        'line_items':     _linePayload,
      };
      final Invoice inv;
      if (_isEdit) {
        inv = await InvoiceService.instance.update(widget.editing!.id, {
          ...data,
          if (!_lockedFinal) 'sale_status': _saleStatus,
        });
      } else {
        inv = await InvoiceService.instance.create({
          ...data,
          'sale_status': _saleStatus,
          'currency':    _currency,
          if (_showDeposit && _deposit > 0) ...{
            'deposit_amount':    _deposit,
            'deposit_method':    _depositMethod,
            'deposit_reference': _text(_depositRefCtrl),
          },
        });
      }
      if (!mounted) return;
      if (widget.onDone != null) showSuccessToast(context, '${inv.invoiceNumber} saved.');
      _finish(inv);
    } catch (e) {
      // Server-side messages (e.g. the client's credit limit) are shown as-is.
      if (mounted) setState(() { _saving = false; _errors = {'_server': friendlyError(e)}; });
    }
  }

  void _finish(Invoice? inv) {
    if (widget.onDone != null) {
      widget.onDone!(_saleStatus);
    } else {
      Navigator.of(context).pop<Invoice>(inv);
    }
  }

  String get _title => _isEdit
      ? 'Edit ${widget.editing!.invoiceNumber}'
      : widget.duplicateFrom != null
          ? 'Duplicate of ${widget.duplicateFrom!.invoiceNumber}'
          : switch (_saleStatus) { 'draft' => 'Add draft', 'quotation' => 'Add quotation', 'proforma' => 'Add proforma', _ => 'Add sale' };

  String get _saveLabel => switch (_saleStatus) {
    'draft'     => 'Save draft',
    'proforma'  => 'Save proforma',
    'quotation' => 'Save quotation',
    _           => _isEdit && !_lockedFinal ? 'Finalise sale' : (_isEdit ? 'Save changes' : 'Save sale'),
  };

  Map<String, String> get _statusOptions => _lockedFinal
      ? const {'final': 'Final'}
      : _isEdit
          ? const {'final': 'Final', 'draft': 'Draft', 'proforma': 'Proforma'}
          : const {'final': 'Final', 'draft': 'Draft', 'quotation': 'Quotation', 'proforma': 'Proforma'};

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.pal.bg,
    appBar: AppBar(
      backgroundColor: context.pal.surface1,
      foregroundColor: context.pal.text,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 4,
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(_title, style: AppTheme.bodyStrong.copyWith(fontSize: 15)),
      ]),
      actions: [
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Symbols.receipt_long, size: 14),
          label: Text(_saveLabel),
        ),
        const SizedBox(width: 16),
      ],
    ),
    body: LayoutBuilder(builder: (ctx, cst) {
      final wide = cst.maxWidth >= 900;
      final left = _leftColumn(context);
      final right = SizedBox(width: wide ? 320 : double.infinity, child: _rightColumn(context));
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: left), const SizedBox(width: 16), right,
              ])
            : Column(children: [left, const SizedBox(height: 16), right]),
      );
    }),
  );

  BoxDecoration _card(BuildContext context) => BoxDecoration(
    color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border));

  Widget _error(String? msg) => msg == null
      ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.only(top: 3), child: Text(msg, style: TextStyle(fontSize: 11, color: AppColors.coral)));

  Widget _leftColumn(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (_errors['_server'] != null)
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.coral.withValues(alpha: 0.1),
          border: Border.all(color: AppColors.coral.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(Symbols.error_outline, size: 14, color: AppColors.coral),
          const SizedBox(width: 8),
          Expanded(child: Text(_errors['_server']!, style: TextStyle(fontSize: 12, color: AppColors.coral))),
        ]),
      ),
    // Client
    Container(
      padding: const EdgeInsets.all(15),
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Text('CLIENT', style: AppTheme.labelCaps.copyWith(fontSize: 11))),
          SizedBox(width: 170, child: LabeledDropdown<String>(
            label: 'Status *',
            value: _saleStatus,
            items: _statusOptions.keys.toList(),
            displayBuilder: (v) => _statusOptions[v]!,
            enabled: !_lockedFinal,
            onChanged: (v) => setState(() { _saleStatus = v; _errors.remove('tin'); }),
          )),
        ]),
        const SizedBox(height: 11),
        AppSearchableSelectField<Client>(
          label: 'Find client in directory',
          hint: 'Type a client name…',
          selectedLabel: _hospitalLabel,
          asyncSearch: (q) async => (await ClientService.instance.search(q))
              .map((h) => AppSelectItem(value: h, label: h.name)).toList(),
          onSelected: (item) => _pickHospital(item?.value),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, cst) {
          final name = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LabeledTextField(label: 'Client name *', controller: _clientCtrl, hint: 'Name printed on the invoice',
                hasError: _errors['client'] != null,
                onChanged: (_) { if (_errors.containsKey('client')) setState(() => _errors.remove('client')); }),
            _error(_errors['client']),
          ]);
          final tin = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LabeledTextField(label: _saleStatus == 'draft' ? 'Client TIN' : 'Client TIN *', controller: _tinCtrl, hint: '123-456-789',
                keyboardType: TextInputType.number, hasError: _errors['tin'] != null,
                onChanged: (_) { if (_errors.containsKey('tin')) setState(() => _errors.remove('tin')); }),
            _error(_errors['tin']),
          ]);
          final contact = LabeledTextField(label: 'Contact', controller: _contactCtrl, hint: 'Person or phone');
          final email = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LabeledTextField(label: 'Email', controller: _emailCtrl, hint: 'client@company.co.tz',
                keyboardType: TextInputType.emailAddress, hasError: _errors['email'] != null),
            _error(_errors['email']),
          ]);
          // Phones: name full width, then TIN + contact, then email.
          if (cst.maxWidth < 560) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              name,
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: tin), const SizedBox(width: 12), Expanded(child: contact),
              ]),
              const SizedBox(height: 12),
              email,
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: name),
            const SizedBox(width: 12),
            Expanded(child: tin),
            const SizedBox(width: 12),
            Expanded(child: contact),
            const SizedBox(width: 12),
            Expanded(child: email),
          ]);
        }),
      ]),
    ),
    const SizedBox(height: 14),
    // Line items
    Container(
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Symbols.playlist_add, size: 14, color: AppColors.amber),
              const SizedBox(width: 8),
              Flexible(child: Text('Line items', style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
              if (_errors['items'] != null) ...[
                const SizedBox(width: 8),
                Flexible(child: Text(_errors['items']!, style: TextStyle(fontSize: 11, color: AppColors.coral))),
              ],
              const Spacer(),
              Text('${_lines.length} line${_lines.length == 1 ? '' : 's'}',
                  style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textMute)),
            ]),
            const SizedBox(height: 11),
            // Column labels only where rows are a table; stacked phone rows
            // label their own fields (see LineItemTableRow).
            LayoutBuilder(builder: (context, cst) => cst.maxWidth < 520 ? const SizedBox.shrink() : Row(children: [
              Expanded(flex: 3, child: Text('ITEM', style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
              SizedBox(width: kLineQtyW, child: Text('QTY', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
              const SizedBox(width: 8),
              SizedBox(width: kLinePriceW, child: Text('UNIT PRICE', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
              const SizedBox(width: 8),
              SizedBox(width: kLineDiscW, child: Text('DISCOUNT (TSH)', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
              const SizedBox(width: 8),
              SizedBox(width: kLineTotalW, child: Text('LINE TOTAL', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
              const SizedBox(width: 22),
            ])),
            Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Container(height: 1, color: context.pal.divider)),
            ..._lines.asMap().entries.map((e) => LineItemTableRow(
              key: ObjectKey(e.value),
              entry: e.value,
              invItems: _invItems,
              lots: _lots,
              // Lot / expiry only once it's a sale, not when saving as a quotation.
              showLotExpiry: _saleStatus != 'quotation',
              onRemove: _lines.length > 1
                  ? () => setState(() { _lines[e.key].dispose(); _lines.removeAt(e.key); })
                  : null,
              onChanged: () => setState(() {}),
            )),
            GestureDetector(
              onTap: () => setState(() { final l = LineItemEntry(); _attach(l); _lines.add(l); }),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                height: 32,
                decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Symbols.add, size: 13, color: context.pal.textDim),
                  const SizedBox(width: 7),
                  Text('Add line', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                ]),
              ),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
          decoration: BoxDecoration(color: context.pal.surface2, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14))),
          child: LayoutBuilder(builder: (context, cst) {
            final issue = SalesDateField(
              label: 'Issue date', selected: _issueDate, firstDate: DateTime(2020),
              onPicked: (d) { if (d != null) setState(() => _issueDate = d); },
            );
            final term = LabeledTextField(label: 'Payment term', controller: _termCtrl,
                keyboardType: TextInputType.number, hasError: _errors['due'] != null,
                onChanged: (_) => setState(() => _errors.remove('due')));
            final termType = _drop<String>(' ', _termType, const {'days': 'Days', 'months': 'Months'},
                (v) => setState(() => _termType = v));
            final due = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LabeledStaticField(label: 'Due date', value: _dueDate == null ? '—' : _fmtDate(_dueDate!)),
              _error(_errors['due']),
            ]);
            final vat = _drop<int>('VAT', _taxRate, const {0: 'None', 18: '18%'}, (v) => setState(() => _taxRate = v));
            final currency = _drop<String>('Currency', _currency,
                const {'TZS': 'TZS', 'USD': 'USD', 'EUR': 'EUR', 'KES': 'KES'}, (v) => setState(() => _currency = v));
            // Phones: dates, then the term, then VAT and currency, in pairs.
            if (cst.maxWidth < 560) {
              Widget pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]);
              return Column(children: [
                pair(issue, due),
                const SizedBox(height: 12),
                pair(term, termType),
                const SizedBox(height: 12),
                pair(vat, currency),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: issue),
              const SizedBox(width: 14),
              SizedBox(width: 90, child: term),
              const SizedBox(width: 8),
              SizedBox(width: 110, child: termType),
              const SizedBox(width: 14),
              Expanded(child: due),
              const SizedBox(width: 14),
              SizedBox(width: 100, child: vat),
              const SizedBox(width: 14),
              SizedBox(width: 90, child: currency),
            ]);
          }),
        ),
      ]),
    ),
    const SizedBox(height: 14),
    Container(
      padding: const EdgeInsets.all(15),
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_showDeposit ? 'DELIVERY & DEPOSIT' : 'DELIVERY', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
        const SizedBox(height: 11),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LabeledTextField(label: 'Delivery / transport charge', controller: _shipCtrl, hint: '0',
                keyboardType: TextInputType.number, hasError: _errors['ship'] != null,
                onChanged: (_) => setState(() => _errors.remove('ship'))),
            _error(_errors['ship']),
          ])),
          if (_showDeposit) ...[
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LabeledTextField(label: 'Deposit paid now', controller: _depositCtrl, hint: 'Leave empty if nothing paid yet',
                keyboardType: TextInputType.number, hasError: _errors['deposit'] != null,
                onChanged: (_) => setState(() => _errors.remove('deposit'))),
            _error(_errors['deposit']),
          ])),
          const SizedBox(width: 14),
          SizedBox(width: 150, child: _drop<String>('Deposit method', _depositMethod, const {
            'bank_transfer': 'Bank transfer', 'cash': 'Cash', 'mobile_money': 'Mobile money', 'cheque': 'Cheque'},
            (v) => setState(() => _depositMethod = v))),
          const SizedBox(width: 14),
          Expanded(child: LabeledTextField(label: 'Deposit reference', controller: _depositRefCtrl, hint: 'Bank ref / receipt no.')),
          ],
        ]),
      ]),
    ),
    const SizedBox(height: 14),
    Container(
      padding: const EdgeInsets.all(15),
      decoration: _card(context),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: LabeledTextField(label: 'Sell note', controller: _notesCtrl, maxLines: 3,
            hint: 'Printed on the invoice')),
        const SizedBox(width: 14),
        Expanded(child: LabeledTextField(label: 'Staff note', controller: _staffNoteCtrl, maxLines: 3,
            hint: 'Internal only — not printed')),
      ]),
    ),
    const SizedBox(height: 14),
    Container(
      padding: const EdgeInsets.all(15),
      decoration: _card(context),
      child: TermsEditor(controller: _terms),
    ),
  ]);

  Widget _drop<T>(String label, T value, Map<T, String> options, ValueChanged<T> onChanged) =>
      LabeledDropdown<T>(label: label, value: value, items: options.keys.toList(),
          displayBuilder: (v) => options[v]!, onChanged: onChanged);

  Widget _rightColumn(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(
      padding: const EdgeInsets.all(15),
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TOTALS', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
        const SizedBox(height: 10),
        _totalsRow(context, 'Subtotal', tshFromDouble(_gross.toDouble())),
        if (_discount > 0) _totalsRow(context, 'Discount', '- ${tshFromDouble(_discount.toDouble())}'),
        _totalsRow(context, _taxRate == 0 ? 'VAT' : 'VAT $_taxRate%', tshFromDouble(_tax.toDouble())),
        if (_shipping > 0) _totalsRow(context, 'Delivery', tshFromDouble(_shipping.toDouble())),
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Container(height: 1, color: context.pal.divider)),
        _totalsRow(context, 'TOTAL', tshFromDouble(_total.toDouble()), big: true),
        if (_showDeposit && _deposit > 0) ...[
          _totalsRow(context, 'Deposit now', '- ${tshFromDouble(_deposit.toDouble())}'),
          _totalsRow(context, 'ON CREDIT', tshFromDouble((_total - _deposit).clamp(0, _total).toDouble()), big: true),
        ],
      ]),
    ),
    const SizedBox(height: 14),
    Container(
      padding: const EdgeInsets.all(15),
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('WHAT HAPPENS ON SAVE', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
        const SizedBox(height: 12),
        ...switch (_saleStatus) {
          'draft' || 'proforma' => [
            _step(context, Symbols.tag, AppColors.amber, _saleStatus == 'draft' ? 'Saved as a draft (DRAFT-…)' : 'Saved as a proforma (PRO-…)',
                _saleStatus == 'draft' ? 'Nothing is billed yet. Edit it any time.' : 'Print it for the client. Nothing is billed yet.'),
            _step(context, Symbols.edit_note, AppColors.teal, 'Finalise it later',
                'Open it from All sales → Edit and set Status to Final. It then gets an invoice number and counts as a sale.', last: true),
          ],
          'quotation' => [
            _step(context, Symbols.request_quote, AppColors.violet, 'Saved on the Quotations page',
                'Valid until ${_dueDate == null ? '30 days from today' : _fmtDate(_dueDate!)}. It goes through the usual quotation approval.', last: true),
          ],
          _ => [
            _step(context, Symbols.tag, AppColors.teal, _isEdit ? 'Keeps its invoice number' : 'Gets the next invoice number',
                'It appears in All sales.'),
            _step(context, Symbols.account_balance, AppColors.violet, 'Posted to receivables',
                'What’s left on credit counts toward Outstanding and the client’s credit limit, due ${_dueDate == null ? 'on the term' : _fmtDate(_dueDate!)}.'),
            if (_showDeposit && _deposit > 0)
              _step(context, Symbols.payments, AppColors.green, 'Deposit recorded',
                  'Saved as the first payment; later payments are added from All sales or Credit & Receivables.'),
            _step(context, Symbols.link_off, context.pal.textDim, 'Stands on its own',
                'Not linked to any quotation or sales order, and no stock is moved.', last: true),
          ],
        },
      ]),
    ),
  ]);

  Widget _totalsRow(BuildContext context, String label, String value, {bool big = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Text(label, style: big ? AppTheme.labelCaps.copyWith(fontSize: 10.5) : AppTheme.bodySub.copyWith(fontSize: 11.5)),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 1, color: context.pal.divider)),
      const SizedBox(width: 8),
      Text(value, style: (big ? AppTheme.kpiValue.copyWith(fontSize: 18) : AppTheme.monoSm.copyWith(fontSize: 12.5))
          .copyWith(color: context.pal.text)),
    ]),
  );

  Widget _step(BuildContext context, IconData icon, Color color, String title, String note, {bool last = false}) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 11),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTheme.bodySm.copyWith(fontSize: 11.5, color: color)),
        const SizedBox(height: 2),
        Text(note, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
      ])),
    ]),
  );
}
