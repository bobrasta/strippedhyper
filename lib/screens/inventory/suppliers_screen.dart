import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show can;
import '../../models/supplier.dart';
import '../../services/supplier_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/error_view.dart';
import '../../utils/tin.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/shimmer_box.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  // Suppliers is a shared top-level page (inventory + the shipments
  // department) — reading is open, changing it needs catalog authority,
  // same as SupplierController's write gate.
  bool get _canEdit => can('inventory.manage_catalog') || can('authority.admin_tier');
  String? _typeFilter;
  String  _search = '';
  Supplier? _selected;
  bool _showAdd  = false;
  bool _showEdit = false;

  List<Supplier> _suppliers = [];
  bool   _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known list immediately (if any)
    // instead of blanking to a spinner on every navigation — see
    // MachineService for the full reasoning.
    final cached = SupplierService.cachedDefaultList;
    if (cached != null) { _suppliers = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_suppliers.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final data = await SupplierService.instance.list();
      if (mounted) setState(() { _suppliers = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  List<Supplier> get _filtered {
    var list = _suppliers;
    if (_typeFilter != null) list = list.where((s) => s.type == _typeFilter).toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((s) =>
        s.name.toLowerCase().contains(q) ||
        (s.country?.toLowerCase().contains(q) ?? false)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final types = {'manufacturer', 'distributor', 'importer', 'local_vendor'};

    return LayoutBuilder(builder: (context, cst) {
    final phone = isPhoneWidth(cst.maxWidth);
    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Header ───────────────────────────────────────────────────────────
        if (phone) PhonePageHeader(
          title: 'Suppliers',
          subtitle: '${_suppliers.length} registered suppliers',
          primary: _canEdit ? PageAction(label: 'Add Supplier', shortLabel: 'Add', icon: Symbols.add,
              onPressed: () => setState(() => _showAdd = true)) : null,
          search: SearchField(hint: 'Search…', onChanged: (v) => setState(() => _search = v)),
          filters: [
            for (final t in types)
              _TypeChip(label: _typeLabel(t), active: _typeFilter == t,
                  onTap: () => setState(() => _typeFilter = _typeFilter == t ? null : t)),
          ],
        ) else Container(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Suppliers', style: AppTheme.pageTitle),
              const SizedBox(height: 2),
              Text('${_suppliers.length} registered suppliers', style: AppTheme.bodySub),
            ]),
            const Spacer(),
            // Type filter chips
            ...types.map((t) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _TypeChip(
                label: _typeLabel(t), active: _typeFilter == t,
                onTap: () => setState(() {
                  _typeFilter = _typeFilter == t ? null : t;
                }),
              ),
            )),
            const SizedBox(width: 8),
            // Search
            SearchField(width: 220, hint: 'Search…', onChanged: (v) => setState(() => _search = v)),
            const SizedBox(width: 8),
            if (_canEdit) AppButton(label: 'Add Supplier', icon: Symbols.add, variant: BtnVariant.primary,
                onPressed: () => setState(() => _showAdd = true)),
          ]),
        ),
        // ── Two-panel body ───────────────────────────────────────────────────
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // List panel
          Expanded(flex: 3, child: RefreshIndicator(
            onRefresh: _load,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(children: [
                // Table header
                if (phone) const SizedBox(height: 10) else Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
                  child: Row(children: [
                    _Th('Supplier', flex: 3), _Th('Type', flex: 1),
                    _Th('Location', flex: 2), _Th('Lead Time', flex: 1),
                    _Th('Currency', flex: 1), _Th('Rating', flex: 1),
                    _Th('Items', flex: 1),
                  ]),
                ),
                if (_loading)
                  shimmerTable(count: 6, cols: 7)
                else if (_error != null && _suppliers.isEmpty)
                  ErrorView(message: _error!, onRetry: _load, compact: true)
                else if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Symbols.business, size: 36, color: context.pal.textDim),
                      const SizedBox(height: 10),
                      Text('No suppliers found', style: AppTheme.bodySub),
                    ])),
                  )
                else if (phone)
                  ...filtered.map((s) => PhoneRecordCard(
                    title: s.name,
                    subtitle: s.location,
                    badge: PhonePill(s.typeLabel, _SupplierRow._typeColor(s.type)),
                    meta: ['${s.leadTimeDays}d lead time', s.currency, '${s.itemsCount} items',
                        if (s.rating > 0) '★' * s.rating],
                    onTap: () => pushPhoneDetail(context, (ctx) => _SupplierDetailPanel(
                      supplier: s,
                      onClose: () => Navigator.of(ctx).pop(),
                      onEdit: _canEdit ? () {
                        Navigator.of(ctx).pop();
                        setState(() { _selected = s; _showEdit = true; });
                      } : null,
                    )),
                  ))
                else
                  ...filtered.map((s) => _SupplierRow(
                    supplier: s, selected: _selected == s,
                    onTap: () => setState(() => _selected = _selected == s ? null : s),
                    onEdit: _canEdit ? () => setState(() { _selected = s; _showEdit = true; }) : null,
                  )),
              ]),
            ),
          )),
          // Detail panel (phones open it as a page instead)
          if (_selected != null && !phone) ...[
            Container(width: 1, color: context.pal.border),
            Expanded(flex: 2, child: _SupplierDetailPanel(
              supplier: _selected!,
              onClose: () => setState(() => _selected = null),
              onEdit:  _canEdit ? () => setState(() => _showEdit = true) : null,
            )),
          ],
        ])),
      ]),
      if (_showAdd)
        _SupplierFormModal(
          onClose: () => setState(() => _showAdd = false),
          onSaved: () { setState(() => _showAdd = false); _load(); },
        ),
      if (_showEdit && _selected != null)
        _SupplierFormModal(
          supplier: _selected!,
          onClose: () => setState(() => _showEdit = false),
          onSaved: () { setState(() => _showEdit = false); _load(); },
        ),
    ]);
    });
  }

  static String _typeLabel(String t) => switch (t) {
    'manufacturer' => 'Manufacturer',
    'distributor'  => 'Distributor',
    'importer'     => 'Importer',
    'local_vendor' => 'Local Vendor',
    _              => t,
  };
}

// ── Supplier row ─────────────────────────────────────────────────────────────

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({required this.supplier, required this.selected,
      required this.onTap, this.onEdit});
  final Supplier supplier;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColor(supplier.type);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? context.pal.surface2 : Colors.transparent,
          border: Border(bottom: BorderSide(color: context.pal.divider)),
        ),
        child: Row(children: [
          // Name
          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(supplier.name, style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
            if (supplier.shortCode != null)
              Text(supplier.shortCode!, style: AppTheme.monoXs.copyWith(
                  color: context.pal.textMute, fontSize: 10)),
          ])),
          // Type
          Expanded(flex: 1, child: Align(alignment: Alignment.centerLeft, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(supplier.typeLabel, style: AppTheme.monoXs.copyWith(
                color: typeColor, fontSize: 9.5), overflow: TextOverflow.ellipsis),
          ))),
          // Location
          Expanded(flex: 2, child: Text(supplier.location,
              style: AppTheme.bodySub.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis)),
          // Lead time
          Expanded(flex: 1, child: Text('${supplier.leadTimeDays}d',
              style: AppTheme.monoXs.copyWith(color: context.pal.textMute))),
          // Currency
          Expanded(flex: 1, child: Text(supplier.currency,
              style: AppTheme.monoXs.copyWith(color: context.pal.textMute))),
          // Rating
          Expanded(flex: 1, child: Row(children: List.generate(5, (i) => Icon(
            i < supplier.rating ? Symbols.star : Symbols.star_outline,
            size: 12, color: AppColors.amber,
          )))),
          // Items count
          Expanded(flex: 1, child: Text('${supplier.itemsCount} items',
              style: AppTheme.bodySub.copyWith(fontSize: 12))),
        ]),
      ),
    );
  }

  static Color _typeColor(String t) => switch (t) {
    'manufacturer' => AppColors.teal,
    'distributor'  => AppColors.blue,
    'importer'     => AppColors.violet,
    'local_vendor' => AppColors.amber,
    _              => AppColors.textDim,
  };
}

// ── Supplier detail panel ────────────────────────────────────────────────────

class _SupplierDetailPanel extends StatelessWidget {
  const _SupplierDetailPanel({required this.supplier, required this.onClose, this.onEdit});
  final Supplier supplier;
  final VoidCallback onClose;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(supplier.name, style: AppTheme.bodyStrong)),
        GestureDetector(onTap: onClose,
            child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
      ]),
      const SizedBox(height: 3),
      if (supplier.shortCode != null)
        Text(supplier.shortCode!, style: AppTheme.monoXs.copyWith(color: context.pal.textMute)),
      const SizedBox(height: 14),
      // Rating
      Row(children: [
        ...List.generate(5, (i) => Icon(
          i < supplier.rating ? Symbols.star : Symbols.star_outline,
          size: 16, color: AppColors.amber,
        )),
        const SizedBox(width: 8),
        Text('${supplier.rating}/5', style: AppTheme.bodySub),
      ]),
      const SizedBox(height: 14),
      _Row('Type',         supplier.typeLabel),
      _Row('Location',     supplier.location),
      _Row('Currency',     supplier.currency),
      _Row('Lead Time',    '${supplier.leadTimeDays} days'),
      if (supplier.paymentTerms != null)
        _Row('Payment',    _ptLabel(supplier.paymentTerms!)),
      const SizedBox(height: 14),
      Text('Contact', style: AppTheme.cardTitle.copyWith(fontSize: 12)),
      const SizedBox(height: 8),
      if (supplier.contactName != null) _Row('Name', supplier.contactName!),
      if (supplier.contactEmail != null)
        _ClickRow(label: 'Email', value: supplier.contactEmail!, icon: Symbols.mail),
      if (supplier.contactPhone != null)
        _Row('Phone', supplier.contactPhone!),
      if (supplier.tin != null)
        _Row('TIN', supplier.tin!),
      if (supplier.address != null && supplier.address!.isNotEmpty)
        _Row('Address', supplier.address!),
      if (supplier.website != null)
        _ClickRow(label: 'Website', value: supplier.website!, icon: Symbols.open_in_new),
      if (supplier.notes != null) ...[
        const SizedBox(height: 14),
        Text('Notes', style: AppTheme.cardTitle.copyWith(fontSize: 12)),
        const SizedBox(height: 6),
        Text(supplier.notes!, style: AppTheme.bodySub.copyWith(fontSize: 12.5)),
      ],
      if (onEdit != null) ...[
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: GestureDetector(
        onTap: onEdit,
        child: Container(height: 38,
          decoration: BoxDecoration(border: Border.all(color: context.pal.border),
              borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text('Edit Supplier', style: AppTheme.bodySm)),
        ),
      )),
      ],
    ]),
  );

  static String _ptLabel(String pt) => switch (pt) {
    'prepaid' => 'Prepaid', 'net_15' => 'Net 15',
    'net_30'  => 'Net 30',  'net_60' => 'Net 60', 'net_90' => 'Net 90',
    _ => pt,
  };
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12))),
      Expanded(child: Text(value, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
    ]),
  );
}

class _ClickRow extends StatelessWidget {
  const _ClickRow({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12))),
      Icon(icon, size: 13, color: AppColors.teal),
      const SizedBox(width: 5),
      Expanded(child: Text(value,
          style: AppTheme.bodySm.copyWith(color: AppColors.teal, fontSize: 12.5),
          overflow: TextOverflow.ellipsis)),
    ]),
  );
}

// ── Add / Edit modal ─────────────────────────────────────────────────────────

class _SupplierFormModal extends StatefulWidget {
  const _SupplierFormModal({this.supplier, required this.onClose, this.onSaved});
  final Supplier? supplier;
  final VoidCallback  onClose;
  final VoidCallback? onSaved;

  @override
  State<_SupplierFormModal> createState() => _SupplierFormModalState();
}

class _SupplierFormModalState extends State<_SupplierFormModal> {
  late final _nameCtrl    = TextEditingController(text: widget.supplier?.name ?? '');
  late final _codeCtrl    = TextEditingController(text: widget.supplier?.shortCode ?? '');
  late final _cNameCtrl   = TextEditingController(text: widget.supplier?.contactName ?? '');
  late final _emailCtrl   = TextEditingController(text: widget.supplier?.contactEmail ?? '');
  late final _phoneCtrl   = TextEditingController(text: widget.supplier?.contactPhone ?? '');
  late final _cityCtrl    = TextEditingController(text: widget.supplier?.city ?? '');
  late final _tinCtrl     = TextEditingController(text: widget.supplier?.tin ?? '');
  late final _addressCtrl = TextEditingController(text: widget.supplier?.address ?? '');
  late final _countryCtrl = TextEditingController(text: widget.supplier?.country ?? '');
  late final _notesCtrl   = TextEditingController(text: widget.supplier?.notes ?? '');
  late String _type   = widget.supplier?.type ?? 'distributor';
  late String _curr   = widget.supplier?.currency ?? 'USD';
  late String _terms  = widget.supplier?.paymentTerms ?? 'net_30';
  late int    _lead   = widget.supplier?.leadTimeDays ?? 14;
  late int    _rating = widget.supplier?.rating ?? 3;
  bool   _saving = false;
  String? _error;

  static const _types  = ['manufacturer', 'distributor', 'importer', 'local_vendor'];
  static const _tLabels = ['Manufacturer', 'Distributor', 'Importer', 'Local Vendor'];
  static const _terms_  = ['prepaid', 'net_15', 'net_30', 'net_60', 'net_90'];
  static const _tTerms  = ['Prepaid', 'Net 15', 'Net 30', 'Net 60', 'Net 90'];
  static const _currs   = ['USD', 'EUR', 'GBP', 'TZS', 'KES'];

  bool get _isEdit => widget.supplier != null;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _codeCtrl, _cNameCtrl, _emailCtrl,
                     _phoneCtrl, _cityCtrl, _countryCtrl, _notesCtrl, _tinCtrl, _addressCtrl]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _nameCtrl.text.trim().isEmpty) return;
    if (_tinCtrl.text.trim().isNotEmpty && normalizeTin(_tinCtrl.text) == null) {
      setState(() => _error = 'TIN must be 9 digits (e.g. 123-456-789).');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final data = {
        'name':          _nameCtrl.text.trim(),
        'short_code':    _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
        'type':          _type,
        'contact_name':  _cNameCtrl.text.trim().isEmpty ? null : _cNameCtrl.text.trim(),
        'contact_email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'contact_phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'city':          _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        'tin':           normalizeTin(_tinCtrl.text),
        'address':       _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'country':       _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
        'currency':      _curr,
        'payment_terms': _terms,
        'lead_time_days': _lead,
        'rating':        _rating,
        'notes':         _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      };
      if (_isEdit) {
        await SupplierService.instance.update(widget.supplier!.id, data);
      } else {
        await SupplierService.instance.create(data);
      }
      if (mounted) showSuccessToast(context, _isEdit ? 'Supplier updated' : 'Supplier added');
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onClose,
    child: Container(
      color: const Color(0xAA06070A), alignment: Alignment.center,
      child: PhoneModalBox(scroll: false, child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 580,
          margin: const EdgeInsets.all(16),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          decoration: BoxDecoration(
            color: context.pal.surface1, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.business, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Text(_isEdit ? 'Edit: ${widget.supplier!.name}' : 'Add Supplier',
                    style: AppTheme.bodyStrong),
                const Spacer(),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(children: [
                Row(children: [
                  Expanded(child: _Fld('Company name', _nameCtrl, 'e.g. Mindray East Africa')),
                  const SizedBox(width: 14),
                  SizedBox(width: 120, child: _Fld('Short code', _codeCtrl, 'MINDRAY')),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _DD('Type', _type, _types, _tLabels, (v) => setState(() => _type = v))),
                  const SizedBox(width: 14),
                  Expanded(child: _DD('Currency', _curr, _currs, null, (v) => setState(() => _curr = v))),
                  const SizedBox(width: 14),
                  Expanded(child: _DD('Payment Terms', _terms, _terms_, _tTerms, (v) => setState(() => _terms = v))),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Fld('Contact person', _cNameCtrl, 'e.g. Sales Team')),
                  const SizedBox(width: 14),
                  Expanded(child: _Fld('Email', _emailCtrl, 'sales@supplier.com')),
                  const SizedBox(width: 14),
                  Expanded(child: _Fld('Phone', _phoneCtrl, '+255 …')),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Fld('City', _cityCtrl, 'Dar es Salaam')),
                  const SizedBox(width: 14),
                  Expanded(child: _Fld('Country', _countryCtrl, 'Tanzania')),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Fld('TIN', _tinCtrl, '123-456-789')),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: _Fld('Address', _addressCtrl, 'P.O. Box, street')),
                ]),
                const SizedBox(height: 14),
                // Lead time + Rating row
                Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Lead time (days)', style: AppTheme.fieldLabel),
                    const SizedBox(height: 6),
                    Row(children: [
                      GestureDetector(
                        onTap: () => setState(() => _lead = (_lead - 1).clamp(0, 365)),
                        child: _StepBtn(Symbols.remove),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: 44, child: Text('$_lead', textAlign: TextAlign.center,
                          style: AppTheme.bodyStrong)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _lead = (_lead + 1).clamp(0, 365)),
                        child: _StepBtn(Symbols.add),
                      ),
                    ]),
                  ]),
                  const SizedBox(width: 32),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Rating', style: AppTheme.fieldLabel),
                    const SizedBox(height: 6),
                    Row(children: List.generate(5, (i) => GestureDetector(
                      onTap: () => setState(() => _rating = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          i < _rating ? Symbols.star : Symbols.star_outline,
                          size: 22, color: AppColors.amber,
                        ),
                      ),
                    ))),
                  ]),
                ]),
                const SizedBox(height: 14),
                _Fld('Notes', _notesCtrl, 'Optional notes about this supplier'),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
                ],
              ]),
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(children: [
                Expanded(child: GestureDetector(
                  onTap: widget.onClose,
                  child: Container(height: 38,
                    decoration: BoxDecoration(border: Border.all(color: context.pal.border),
                        borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text('Cancel', style: AppTheme.bodySm))),
                )),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: _save,
                  child: Container(height: 38,
                    decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_isEdit ? 'Save Changes' : 'Add Supplier',
                          style: AppTheme.bodyStrong.copyWith(
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

// ── Local-only form widgets ──────────────────────────────────────────────────

class _Fld extends StatelessWidget {
  const _Fld(this.label, this.ctrl, this.hint);
  final String label, hint;
  final TextEditingController ctrl;

  // The Settings text input (shared LabeledTextField).
  @override
  Widget build(BuildContext context) => LabeledTextField(label: label, controller: ctrl, hint: hint);
}

class _DD extends StatelessWidget {
  const _DD(this.label, this.value, this.items, this.labels, this.onChange);
  final String label, value;
  final List<String> items;
  final List<String>? labels;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    DropdownFieldBox<String>(
      value: items.contains(value) ? value : items.first,
      items: items.asMap().entries.map((e) => DropdownMenuItem(
          value: e.value, child: Text(labels != null ? labels![e.key] : e.value),
        )).toList(),
      onChanged: (v) { if (v != null) onChange(v); },
    ),
  ]);
}

class _StepBtn extends StatelessWidget {
  const _StepBtn(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 28, height: 28,
    decoration: BoxDecoration(color: context.pal.surface2,
        borderRadius: BorderRadius.circular(6), border: Border.all(color: context.pal.border)),
    child: Icon(icon, size: 14, color: context.pal.textMute),
  );
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? AppColors.teal.withValues(alpha: 0.12) : context.pal.surface1,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: active ? AppColors.teal : context.pal.border),
      ),
      child: Text(label, style: AppTheme.bodySm.copyWith(
          color: active ? AppColors.teal : context.pal.textMute, fontSize: 12)),
    ),
  );
}

class _Th extends StatelessWidget {
  const _Th(this.label, {required this.flex});
  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(label.toUpperCase(),
        style: AppTheme.monoXs.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.10)),
  );
}
