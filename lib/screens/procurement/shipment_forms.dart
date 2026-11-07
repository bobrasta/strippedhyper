import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/shipment.dart';
import '../../services/shipment_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/procurement/proc_widgets.dart';
import 'tender_forms.dart' show ProcDialog, formHeading, formRow, OptionalDateField, isoDate;

// Dialogs for Section 18: shipment create/edit, moving the status, the
// Section 16 clearing fee. Every rule is checked again
// server-side (ShipmentFlow) — these only guide.

String _tsh(int v) => 'TSh ${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';

Future<({String path, String name})?> pickShipmentFile(BuildContext context) async {
  if (Platform.isAndroid) {
    showErrorToast(context, Exception('File uploads aren\'t available on Android in this build.'));
    return null;
  }
  // Some Windows PCs fail to open the file dialog; say so instead of doing nothing.
  FilePickerResult? r;
  try {
    r = await FilePicker.pickFiles(allowMultiple: false, withData: false,
        type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'xls', 'xlsx']);
  } catch (e) {
    if (context.mounted) showErrorToast(context, Exception('Couldn\'t open the file picker: $e'));
    return null;
  }
  if (r == null || r.files.isEmpty) return null;
  if (r.files.first.path == null) {
    if (context.mounted) showErrorToast(context, Exception('That file can\'t be read from here — save it to the PC (e.g. Documents) and pick it again.'));
    return null;
  }
  return (path: r.files.first.path!, name: r.files.first.name);
}

/// Mirrors ShipmentFlow::requiredDocTypes on the API. Non-medical goods have
/// no required documents.
List<String> requiredShipmentDocs(String direction, String mode, {bool coaRequired = true, bool nonMedical = false}) => [
  if (!nonMedical) ...[
    mode == 'air' ? 'air_waybill' : 'bill_of_lading',
    'packing_list',
    'commercial_invoice',
    if (direction == 'import' && coaRequired) 'coa',
  ],
];

/// The shipping documents the create form offers: the required ones, or for
/// non-medical goods the same papers as optional uploads.
List<String> offeredShipmentDocs(String direction, String mode, {bool coaRequired = true, bool nonMedical = false}) =>
    nonMedical ? requiredShipmentDocs(direction, mode, coaRequired: false) : requiredShipmentDocs(direction, mode, coaRequired: coaRequired);

String goodsCategoryLabel(String v) => v == 'non_medical' ? 'Non-medical goods' : 'Medical devices / reagents';

String _vendorTypeSuffix(dynamic type) => switch (type) {
  'clearing' => '',
  'courier' => ' · courier',
  _ => ' · $type',
};

const shipmentDocLabels = {
  'air_waybill': 'Air Waybill',
  'bill_of_lading': 'Bill of Lading',
  'packing_list': 'Packing list',
  'commercial_invoice': 'Commercial invoice',
  'coa': 'Certificate of Analysis',
  'tmda_permit': 'TMDA permit',
  'recipient_receipt': 'Signed receipt from recipient',
  // From "Assessment received" on, kept for the record (optional).
  'assessment_notice': 'Assessment notice',
  'customs_release': 'Customs release order',
  'clearing_other': 'Other clearing documents',
  // At "Arrived at HQ": papers for the storage & handling the agent paid for us.
  'storage_handling': 'Storage & handling (Swissport etc.)',
  'arrival_other': 'Other arrival documents',
};

/// Optional papers kept for the record from "Assessment received" on.
const assessmentRecordDocs = ['assessment_notice', 'customs_release', 'clearing_other'];

/// Storage & handling papers (Swissport etc.), attached at "Arrived at HQ".
const arrivalRecordDocs = ['storage_handling', 'arrival_other'];

// ── Create / edit ───────────────────────────────────────────────────────────

Future<Shipment?> showShipmentForm(BuildContext context, {Shipment? shipment, int? tenderId}) =>
    showDialog<Shipment>(context: context, builder: (_) => _ShipmentForm(shipment: shipment, tenderId: tenderId));

class _ShipmentForm extends StatefulWidget {
  const _ShipmentForm({this.shipment, this.tenderId});
  final Shipment? shipment;
  final int? tenderId;
  @override
  State<_ShipmentForm> createState() => _ShipmentFormState();
}

class _ShipmentFormState extends State<_ShipmentForm> {
  late final Shipment? s = widget.shipment;
  late String _dir = s?.direction ?? 'import';
  late String _mode = s?.freightMode ?? 'sea';
  late final _desc = TextEditingController(text: s?.description ?? '');
  late final _reason = TextEditingController(text: s?.outboundReason ?? '');
  late final _port = TextEditingController(text: s?.port ?? '');
  late final _notes = TextEditingController(text: s?.locationNotes ?? '');
  late DateTime? _eta = s?.expectedArrival;
  late int? _supplierId = s?.supplierId;
  /// A supplier not in the list: typed here, saved to Suppliers with the shipment.
  String _newSupplier = '';
  late int? _poId = s?.purchaseOrderId;
  late int? _deptId = s?.departmentId;
  late Set<int> _notifyIds = {for (final u in s?.notifyUsers ?? const <Map<String, dynamic>>[]) (u['id'] as num).toInt()};
  late int? _tenderId = (s?.tender?['id'] as num?)?.toInt() ?? widget.tenderId;
  late bool _coaRequired = s?.coaRequired ?? true;
  late String _goods = s?.goodsCategory ?? 'medical';
  bool get _nonMedical => _goods == 'non_medical';
  late int? _carrierId = s?.carrierVendorId;
  late String _costBearer = s?.costBearer ?? 'hypermed';
  late final _paidBy = TextEditingController(text: s?.paidBy ?? '');
  late final _costNote = TextEditingController(text: s?.costNote ?? '');
  late DateTime? _permitSentAt = s?.permitSentAt;
  late int? _permitVendorId = s?.permitSentVendorId;
  final _files = <String, ({String path, String name})>{};
  ShipmentOptions? _opts;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ShipmentService.instance.options().then((o) {
      if (mounted) setState(() => _opts = o);
    }).catchError((Object e) {
      if (mounted) showErrorToast(context, e);
    });
  }

  @override
  void dispose() {
    for (final c in [_desc, _reason, _port, _notes, _paidBy, _costNote]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _attach(String type) async {
    final f = await pickShipmentFile(context);
    if (f != null && mounted) setState(() => _files[type] = f);
  }

  Future<void> _save() async {
    if (_desc.text.trim().isEmpty) {
      showErrorToast(context, Exception('Describe what is being shipped.'));
      return;
    }
    final manufacturerPaid = _dir == 'import' && _costBearer == 'manufacturer';
    if (manufacturerPaid && _paidBy.text.trim().isEmpty) {
      showErrorToast(context, Exception('Enter who paid, e.g. the manufacturer\'s name.'));
      return;
    }
    String? txt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final data = <String, dynamic>{
      if (s == null) 'direction': _dir,
      'freight_mode': _mode,
      'description': _desc.text.trim(),
      'supplier_id': _supplierId,
      if (_supplierId == null && _newSupplier.trim().isNotEmpty) 'supplier_name': _newSupplier.trim(),
      'purchase_order_id': _dir == 'import' ? _poId : null,
      'outbound_reason': _dir == 'export' ? txt(_reason) : null,
      'department_id': _deptId,
      // Only people still on the active staff list (a deactivated pick would be refused).
      'notify_user_ids': [for (final id in _notifyIds) if (_opts!.staff.any((u) => u['id'] == id)) id],
      'tender_id': _tenderId,
      'expected_arrival': _eta == null ? null : isoDate(_eta!),
      'port': txt(_port),
      'location_notes': txt(_notes),
      'carrier_vendor_id': _carrierId,
      'goods_category': _goods,
      if (_dir == 'import') 'coa_required': _coaRequired,
      'cost_bearer': manufacturerPaid ? 'manufacturer' : 'hypermed',
      'paid_by': manufacturerPaid ? _paidBy.text.trim() : null,
      'cost_note': manufacturerPaid ? txt(_costNote) : null,
      if (_dir == 'import' && !_nonMedical) ...{
        'permit_sent_at': _permitSentAt == null ? null : isoDate(_permitSentAt!),
        'permit_sent_vendor_id': _permitVendorId,
      },
    };
    setState(() => _saving = true);
    try {
      final saved = s == null
          ? await ShipmentService.instance.create(data, {
              for (final e in _files.entries)
                if (offeredShipmentDocs(_dir, _mode, coaRequired: _coaRequired, nonMedical: _nonMedical).contains(e.key)) e.key: e.value,
            })
          : await ShipmentService.instance.update(s!.id, data);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final o = _opts;
    final docs = offeredShipmentDocs(_dir, _mode, coaRequired: _coaRequired, nonMedical: _nonMedical);
    final attached = docs.where(_files.containsKey).length;
    final pos = (o?.purchaseOrders ?? []).where((p) => _supplierId == null || p['supplier_id'] == _supplierId).toList();

    return ProcDialog(
      title: s == null ? 'New shipment' : 'Edit ${s!.reference}',
      icon: Symbols.local_shipping,
      width: 720,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _saving || o == null ? null : _save,
          icon: const Icon(Symbols.check, size: 15),
          label: Text(_saving ? 'Saving…' : s == null ? 'Create shipment' : 'Save'),
        ),
      ],
      body: o == null
          ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              formRow([
                if (s == null)
                  LabeledDropdown<String>(label: 'Direction', value: _dir, items: const ['import', 'export'],
                      displayBuilder: (v) => v == 'import' ? 'Import' : 'Export', onChanged: (v) => setState(() => _dir = v))
                else
                  LabeledStaticField(label: 'Direction', value: s!.isImport ? 'Import' : 'Export'),
                LabeledDropdown<String>(label: 'Freight', value: _mode, items: const ['sea', 'air', 'road'],
                    displayBuilder: freightLabel, onChanged: (v) => setState(() => _mode = v)),
                LabeledDropdown<String>(label: 'Goods', value: _goods, items: const ['medical', 'non_medical'],
                    displayBuilder: goodsCategoryLabel, onChanged: (v) => setState(() => _goods = v)),
              ]),
              if (_nonMedical)
                const Padding(padding: EdgeInsets.only(bottom: 12), child: ProcNote(
                    'Non-medical goods: all documents are optional and no TMDA permit is needed, so the shipment can be '
                    'completed without uploads.', icon: Symbols.inventory_2, tone: ProcTone.green)),
              LabeledTextField(label: "What's being shipped", controller: _desc,
                  hint: 'e.g. Haematology analysers ×3 — Acme Diagnostics Ltd'),
              const SizedBox(height: 12),
              formRow([
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  // Pick a saved supplier, or type a new one — it's saved with the shipment.
                  AppSearchableSelectField<int>(
                    label: _dir == 'import' ? 'Supplier' : 'Recipient (supplier)',
                    hint: 'Search, or type a new supplier',
                    selectedLabel: _supplierId != null && o.suppliers.any((x) => x['id'] == _supplierId)
                        ? o.suppliers.firstWhere((x) => x['id'] == _supplierId)['name'] as String
                        : _newSupplier,
                    items: [for (final x in o.suppliers) AppSelectItem(value: (x['id'] as num).toInt(), label: x['name'] as String)],
                    onSelected: (sel) => setState(() {
                      _supplierId = sel?.value;
                      _newSupplier = '';
                      if (_poId != null && !o.purchaseOrders.any((p) => p['id'] == _poId && (_supplierId == null || p['supplier_id'] == _supplierId))) _poId = null;
                    }),
                    onTextChanged: (t) => setState(() {
                      // An exact (any case) match is that supplier, not a new one.
                      final match = o.suppliers.where((x) => (x['name'] as String).toLowerCase() == t.trim().toLowerCase());
                      _supplierId = match.isEmpty ? null : (match.first['id'] as num).toInt();
                      _newSupplier = match.isEmpty ? t : '';
                      if (_poId != null && _supplierId == null) _poId = null;
                    }),
                  ),
                  if (_supplierId == null && _newSupplier.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('"${_newSupplier.trim()}" will be saved as a new supplier.',
                        style: AppTheme.bodySub.copyWith(fontSize: 11, color: AppColors.green)),
                  ],
                ]),
                if (_dir == 'import')
                  LabeledDropdown<int?>(
                    label: 'Purchase order',
                    value: pos.any((p) => p['id'] == _poId) ? _poId : null,
                    items: [null, ...pos.map((p) => (p['id'] as num).toInt())],
                    displayBuilder: (id) {
                      if (id == null) return 'Not linked';
                      final p = pos.firstWhere((x) => x['id'] == id);
                      return '${p['po_number']}${p['supplier_name'] == null ? '' : ' · ${p['supplier_name']}'}';
                    },
                    onChanged: (v) => setState(() => _poId = v),
                  )
                else
                  LabeledTextField(label: 'Reason for export', controller: _reason, hint: 'e.g. Warranty return, RMA 4471'),
              ]),
              formRow([
                LabeledDropdown<int?>(
                  label: 'Relevant department · its manager is notified',
                  value: o.departments.any((d) => d.id == _deptId) ? _deptId : null,
                  items: [null, ...o.departments.map((d) => d.id)],
                  displayBuilder: (id) {
                    if (id == null) return 'None';
                    final d = o.departments.firstWhere((x) => x.id == id);
                    return '${d.name} · ${d.managerName ?? 'no head set'}';
                  },
                  onChanged: (v) => setState(() => _deptId = v),
                ),
                LabeledDropdown<int?>(
                  label: 'Tender · optional',
                  value: o.tenders.any((t) => t['id'] == _tenderId) ? _tenderId : null,
                  items: [null, ...o.tenders.map((t) => (t['id'] as num).toInt())],
                  displayBuilder: (id) => id == null ? 'None' : o.tenders.firstWhere((t) => t['id'] == id)['tender_number'] as String,
                  onChanged: (v) => setState(() => _tenderId = v),
                ),
              ]),
              AppMultiSelectField<int>(
                label: 'People to notify · optional',
                hint: 'Tick everyone who should hear about this shipment',
                values: _notifyIds,
                items: [
                  for (final u in o.staff)
                    AppSelectItem(value: (u['id'] as num).toInt(),
                        label: '${u['name']} · ${(u['role'] as String? ?? '').replaceAll('_', ' ').toUpperCase()}'),
                ],
                onChanged: (v) => setState(() => _notifyIds = v),
              ),
              Padding(padding: const EdgeInsets.only(top: 4, bottom: 12), child: Text(
                  'They get the same notifications as the department manager on creation and every status change, and can open this shipment.',
                  style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim))),
              formRow([
                LabeledDropdown<int?>(
                  label: 'Carrier / courier · optional',
                  value: o.carriers.any((v) => v['id'] == _carrierId) ? _carrierId : null,
                  items: [null, ...o.carriers.map((v) => (v['id'] as num).toInt())],
                  displayBuilder: (id) {
                    if (id == null) return o.carriers.isEmpty ? 'No couriers — add one in Vendors & Delivery' : 'Not set';
                    final v = o.carriers.firstWhere((x) => x['id'] == id);
                    return '${v['name']}${v['type'] == 'courier' ? '' : ' · ${v['type']}'}';
                  },
                  onChanged: (v) => setState(() => _carrierId = v),
                ),
                if (_dir == 'import' && !_nonMedical)
                  LabeledDropdown<bool>(label: 'Certificate of Analysis', value: _coaRequired, items: const [true, false],
                      displayBuilder: (v) => v ? 'Required' : 'Not required for this shipment',
                      onChanged: (v) => setState(() => _coaRequired = v)),
              ]),
              if (_dir == 'import') formRow([
                LabeledDropdown<String>(label: 'Who pays clearing, duty and freight', value: _costBearer,
                    items: const ['hypermed', 'manufacturer'],
                    displayBuilder: (v) => v == 'hypermed' ? 'HyperMed' : 'Manufacturer — no cost to HyperMed',
                    onChanged: (v) => setState(() => _costBearer = v)),
                if (_costBearer == 'manufacturer')
                  LabeledTextField(label: 'Paid by', controller: _paidBy, hint: 'e.g. Diasorin'),
              ]),
              if (_dir == 'import' && _costBearer == 'manufacturer') ...[
                LabeledTextField(label: 'Note · optional', controller: _costNote, maxLines: 2,
                    hint: 'e.g. Diasorin paid shipping; DHL called us and we emailed them the import permit'),
                const SizedBox(height: 12),
              ],
              if (_dir == 'import' && !_nonMedical) formRow([
                OptionalDateField(label: 'Import permit sent to courier · optional', value: _permitSentAt,
                    onChanged: (v) => setState(() {
                      _permitSentAt = v;
                      // Usually the courier carrying it.
                      if (v != null && _permitVendorId == null && o.carriers.any((c) => c['id'] == _carrierId)) _permitVendorId = _carrierId;
                    })),
                LabeledDropdown<int?>(
                  label: 'Courier it was sent to',
                  value: o.carriers.any((v) => v['id'] == _permitVendorId) ? _permitVendorId : null,
                  items: [null, ...o.carriers.map((v) => (v['id'] as num).toInt())],
                  displayBuilder: (id) => id == null ? 'Not sent' : o.carriers.firstWhere((x) => x['id'] == id)['name'] as String,
                  onChanged: (v) => setState(() => _permitVendorId = v),
                ),
              ]),
              if (_dir == 'import' && _costBearer == 'manufacturer')
                const Padding(padding: EdgeInsets.only(bottom: 12), child: ProcNote(
                    'No clearing fee is recorded and the control-number and payment steps don\'t hold the shipment up. '
                    'Who paid is kept on the shipment\'s timeline.', icon: Symbols.volunteer_activism, tone: ProcTone.green)),
              formRow([
                OptionalDateField(label: _dir == 'import' ? 'Expected arrival' : 'Expected delivery', value: _eta,
                    onChanged: (v) => setState(() => _eta = v)),
                LabeledTextField(label: _dir == 'import' ? 'Port / airport' : 'Destination', controller: _port,
                    hint: _dir == 'import' ? 'e.g. Dar es Salaam port' : null),
              ]),
              LabeledTextField(label: 'Location / notes · optional', controller: _notes, maxLines: 3,
                  hint: 'e.g. Loaded at Shenzhen, vessel MSC Aurora, ETA Dar 18 Oct'),
              if (s == null) ...[
                formHeading(_nonMedical ? 'Shipping documents · optional' : 'Shipping documents · $attached / ${docs.length}'),
                for (final t in docs) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: pal.border)),
                  child: Row(children: [
                    Icon(_files.containsKey(t) ? Symbols.check_circle : Symbols.upload_file, size: 16,
                        color: _files.containsKey(t) ? AppColors.green : pal.textDim),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(shipmentDocLabels[t]!, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                      if (_files[t] != null) Text(_files[t]!.name, style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim),
                          overflow: TextOverflow.ellipsis),
                    ])),
                    TextButton(onPressed: () => _attach(t), child: Text(_files.containsKey(t) ? 'Replace' : 'Attach')),
                  ]),
                ),
                if (attached < docs.length && !_nonMedical)
                  ProcNote('Documents can follow later. Until all ${docs.length} are in, the shipment is flagged and can\'t move past '
                      '"${_dir == 'import' ? 'Shipped' : 'Preparing'}".', icon: Symbols.warning, tone: ProcTone.amber),
              ],
            ]),
    );
  }
}

// ── Move status ─────────────────────────────────────────────────────────────

Future<Shipment?> showShipmentStatusDialog(BuildContext context, Shipment s) =>
    showDialog<Shipment>(context: context, builder: (_) => _StatusDialog(s));

class _StatusDialog extends StatefulWidget {
  const _StatusDialog(this.s);
  final Shipment s;
  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  Shipment get s => widget.s;
  late int _step = s.step < s.lastStep ? s.step + 1 : s.step;
  final _note = TextEditingController();
  final _reason = TextEditingController();
  late final _appRef = TextEditingController(text: s.tmda?['application_ref'] as String? ?? '');
  late final _control = TextEditingController(text: s.controlNumber ?? '');
  // "Assessment received": the clearing agent and the assessed cost — the
  // accountant is notified to pay; the receipt follows after payment.
  late final _cost = TextEditingController(text: s.clearingFee?.billed.toString() ?? '');
  late int? _agentId = s.clearingFee?.vendorId;
  // "Arrived at HQ": storage & handling (Swissport etc.) the clearing agent
  // paid for us — owed to the agent, same approvals as the clearing fee.
  late final _handling = TextEditingController(text: s.handlingFee?.billed.toString() ?? '');
  /// An agent not saved yet — typed here, saved as a clearing agent.
  String _newAgent = '';
  List<Map<String, dynamic>> _agents = const [];
  /// Assessment notice etc. chosen in this dialog, uploaded with the status.
  final Map<String, ({String path, String name})> _recordFiles = {};
  late DateTime? _issued = s.tmda?['issued_at'] == null ? null : DateTime.tryParse(s.tmda!['issued_at'] as String);
  // Payment mode, chosen on the step: "We pay" or manufacturer-paid (payment not required).
  late String _bearer = s.costBearer;
  late final _paidBy = TextEditingController(text: s.paidBy ?? '');
  late final _costNote = TextEditingController(text: s.costNote ?? '');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (s.isImport) {
      ShipmentService.instance.options().then((o) {
        if (!mounted) return;
        setState(() {
          // Every saved vendor, clearing agents first (an agent saved as
          // "other" was missing before).
          _agents = o.vendors;
        });
      }).catchError((_) {});
    }
  }

  int? get _costValue => parseShillings(_cost.text);
  /// The cost can be (re)entered until the accountant has asked for payment.
  bool get _costEditable => s.clearingFee == null || s.clearingFee!.status == 'pending_receipt' || s.clearingFee!.status == 'rejected';
  bool get _costChanged => _costEditable && _costValue != null && _costValue! > 0 &&
      (_costValue != s.clearingFee?.billed || (_agentId != null && _agentId != s.clearingFee?.vendorId) || _newAgent.trim().isNotEmpty);

  /// The last import step: storage & handling and the agent's receipt.
  bool get _arrival => s.isImport && _step == s.lastStep && !_back;
  int? get _handlingValue => parseShillings(_handling.text);
  bool get _handlingEditable => const [null, 'pending_manager', 'pending_receipt', 'rejected'].contains(s.handlingFee?.status);
  bool get _handlingChanged => _arrival && !_manufacturer && _handlingEditable && _handlingValue != null && _handlingValue! > 0 &&
      _handlingValue != s.handlingFee?.billed;

  @override
  void dispose() {
    for (final c in [_note, _reason, _appRef, _control, _paidBy, _costNote, _cost, _handling]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _back => _step < s.step;
  /// Imports of medical goods need a TMDA permit; non-medical goods don't.
  bool get _permit => s.isImport && !s.nonMedical;
  /// The payment mode is offered from the assessment step (7) on.
  bool get _payStep => s.isImport && _step >= 7 && !_back;
  bool get _manufacturer => _payStep ? _bearer == 'manufacturer' : s.manufacturerPaid;

  Future<void> _save() async {
    String? txt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    // The current status again only saves what changed on it (e.g. the
    // clearing agent's control number); otherwise there's nothing to do.
    // Same status, details changed: saved on the status. Only documents
    // chosen: just upload them (the status itself doesn't change).
    final detailsChanged = (!_manufacturer && (txt(_control) != s.controlNumber || _costChanged)) || _bearer != s.costBearer || _handlingChanged;
    final sameStepEdit = _step == s.step && s.isImport && _step >= 7 && (detailsChanged || _recordFiles.isNotEmpty);
    if (_step == s.step && !sameStepEdit) {
      Navigator.pop(context);
      return;
    }
    if (_back && _reason.text.trim().length < 10) {
      showErrorToast(context, Exception('Going back a status needs a reason (at least 10 characters).'));
      return;
    }
    if (_payStep && _manufacturer && _paidBy.text.trim().isEmpty) {
      showErrorToast(context, Exception('Enter who paid, e.g. the manufacturer\'s name.'));
      return;
    }
    final payChanged = _payStep && (_bearer != s.costBearer ||
        (_manufacturer && (txt(_paidBy) != s.paidBy || txt(_costNote) != s.costNote)));
    setState(() => _saving = true);
    try {
      final (saved, notice) = _step == s.step && !detailsChanged ? (s, null) : await ShipmentService.instance.setStep(s.id, {
        'step': _step,
        'note': txt(_note),
        if (_back) 'reason': _reason.text.trim(),
        if (_permit && _step >= 4) 'tmda_application_ref': txt(_appRef),
        if (_permit && _step >= 5 && _issued != null) 'tmda_issued_at': isoDate(_issued!),
        if (s.isImport && _step >= 7 && !_manufacturer) 'control_number': txt(_control),
        if (s.isImport && _step >= 7 && !_manufacturer && _costChanged) ...{
          'clearing_cost': _costValue,
          'clearing_vendor_id': ?_agentId,
          if (_agentId == null && _newAgent.trim().isNotEmpty) 'clearing_vendor_name': _newAgent.trim(),
        },
        if (_handlingChanged) 'handling_cost': _handlingValue,
        if (payChanged) ...{
          'cost_bearer': _bearer,
          'paid_by': _manufacturer ? txt(_paidBy) : null,
          'cost_note': _manufacturer ? txt(_costNote) : null,
        },
      });
      // The record documents chosen here go on once the status is saved.
      var latest = saved;
      for (final e in _recordFiles.entries) {
        try {
          latest = await ShipmentService.instance.uploadDocument(s.id, e.key, e.value.path, e.value.name);
        } catch (err) {
          if (mounted) showErrorToast(context, Exception('${shipmentDocLabels[e.key]} not uploaded: ${friendlyError(err)}'));
        }
      }
      if (!mounted) return;
      if (notice != null) showSuccessToast(context, notice);
      Navigator.pop(context, latest);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final fee = s.clearingFee;
    return ProcDialog(
      title: 'Move ${s.reference}',
      icon: Symbols.route,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Symbols.check, size: 15),
            label: Text(_saving ? 'Saving…' : _back ? 'Correct status' : _step == s.step ? 'Save' : 'Update status')),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Now: ${s.step}. ${s.statusLabel}', style: AppTheme.bodySub.copyWith(color: pal.textMute)),
        const SizedBox(height: 12),
        LabeledDropdown<int>(
          label: 'Move to',
          value: _step,
          items: [for (var i = 1; i <= s.lastStep; i++) i],
          displayBuilder: (i) => '$i. ${s.labelFor(i)}${i == s.step ? ' (current)' : i < s.step ? ' · correction' : ''}',
          onChanged: (v) => setState(() => _step = v),
        ),
        const SizedBox(height: 12),
        if (_permit && _step >= 4 && !_back) ...[
          LabeledTextField(label: 'TMDA permit application reference', controller: _appRef),
          const SizedBox(height: 12),
        ],
        if (_permit && _step >= 5 && !_back) ...[
          OptionalDateField(label: 'TMDA permit issued', value: _issued, onChanged: (v) => setState(() => _issued = v),
              hint: _step == 5 ? 'Required for this status' : 'Required before documents go to the clearing agent (unless switched off in settings)'),
          const SizedBox(height: 12),
        ],
        if (_payStep) ...[
          LabeledDropdown<String>(label: 'Payment', value: _bearer, items: const ['hypermed', 'manufacturer'],
              displayBuilder: (v) => v == 'hypermed' ? 'We pay' : 'Manufacturer paid shipping / payment not required',
              onChanged: (v) => setState(() => _bearer = v)),
          const SizedBox(height: 12),
        ],
        if (_payStep && _manufacturer) ...[
          LabeledTextField(label: 'Paid by', controller: _paidBy, hint: 'e.g. Diasorin'),
          const SizedBox(height: 12),
          LabeledTextField(label: 'Note · optional', controller: _costNote, maxLines: 2,
              hint: 'e.g. DHL called us; we emailed them the import permit'),
          const SizedBox(height: 12),
        ],
        if (s.isImport && _step >= 7 && !_back && !_manufacturer) ...[
          LabeledTextField(label: "Clearing agent's control number", controller: _control),
          const SizedBox(height: 12),
          if (_costEditable) ...[
            // Pick a saved agent, or type a new one — saved as a clearing agent.
            AppSearchableSelectField<int>(
              label: 'Clearing agent',
              hint: 'Search, or type a new agent',
              selectedLabel: _agentId != null
                  ? '${_agents.firstWhere((a) => (a['id'] as num).toInt() == _agentId, orElse: () => {'name': s.clearingFee?.vendorName ?? ''})['name']}'
                  : _newAgent,
              items: [for (final a in _agents) AppSelectItem(value: (a['id'] as num).toInt(),
                  label: '${a['name']}${a['type'] == 'clearing' ? '' : ' · ${a['type']}'}')],
              onSelected: (sel) => setState(() { _agentId = sel?.value; _newAgent = ''; }),
              onTextChanged: (t) => setState(() {
                final match = _agents.where((a) => '${a['name']}'.toLowerCase() == t.trim().toLowerCase());
                _agentId = match.isEmpty ? null : (match.first['id'] as num).toInt();
                _newAgent = match.isEmpty ? t : '';
              }),
            ),
            if (_agentId == null && _newAgent.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('"${_newAgent.trim()}" will be saved as a new clearing agent.',
                  style: AppTheme.bodySub.copyWith(fontSize: 11, color: AppColors.green)),
            ],
            const SizedBox(height: 12),
            LabeledTextField(label: 'Assessed cost (TZS)', controller: _cost, keyboardType: TextInputType.number,
                hint: 'From the assessment — the accountant is notified to pay', onChanged: (_) => setState(() {})),
            const SizedBox(height: 4),
            Text('Patrick approves, then Finance requests payment; the agent\'s receipt is attached at "${s.labelFor(s.lastStep)}".',
                style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
            const SizedBox(height: 12),
          ],
        ],
        if (_arrival && !_manufacturer) ...[
          Text('STORAGE & HANDLING · SWISSPORT ETC.', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
          const SizedBox(height: 6),
          if (_handlingEditable)
            LabeledTextField(label: 'Storage & handling charges (TZS) · optional', controller: _handling, keyboardType: TextInputType.number,
                hint: 'Paid by the clearing agent on our behalf', onChanged: (_) => setState(() {}))
          else
            Text('Storage & handling ${_tsh(s.handlingFee!.billed)} · ${s.handlingFee!.statusLabel}',
                style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
          const SizedBox(height: 4),
          Text('Owed to ${s.handlingFee?.vendorName ?? s.clearingFee?.vendorName ?? 'the clearing agent'}, who paid it for us — '
              'it goes through the same approvals as the clearing fee.',
              style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
          const SizedBox(height: 10),
        ],
        // The assessment papers (or, at arrival, the Swissport papers), kept for the record — optional.
        if (s.isImport && _step >= 7 && !_back) ...[
          Text(_arrival ? 'ARRIVAL DOCUMENTS · FOR THE RECORD (OPTIONAL)' : 'ASSESSMENT DOCUMENTS · FOR THE RECORD (OPTIONAL)',
              style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
          const SizedBox(height: 6),
          for (final t in _arrival ? arrivalRecordDocs : assessmentRecordDocs) Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: pal.border)),
            child: Row(children: [
              Icon(_recordFiles.containsKey(t) || s.documents.any((d) => d.type == t && d.isUploaded) ? Symbols.check_circle : Symbols.upload_file,
                  size: 16, color: _recordFiles.containsKey(t) || s.documents.any((d) => d.type == t && d.isUploaded) ? AppColors.green : pal.textDim),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shipmentDocLabels[t]!, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                Text(_recordFiles[t]?.name ?? s.documents.where((d) => d.type == t && d.isUploaded).map((d) => d.fileName!).firstOrNull ?? 'Not uploaded',
                    overflow: TextOverflow.ellipsis, style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
              ])),
              TextButton(onPressed: () async {
                final f = await pickShipmentFile(context);
                if (f != null && mounted) setState(() => _recordFiles[t] = f);
              }, child: Text(_recordFiles.containsKey(t) ? 'Replace' : 'Attach')),
            ]),
          ),
          const SizedBox(height: 6),
        ],
        if (s.isImport && _step >= 7 && !_back && _manufacturer)
          const Padding(padding: EdgeInsets.only(bottom: 12), child: ProcNote(
            'No cost to HyperMed: no control number, clearing fee or payment needed. Who paid goes on the timeline.',
            icon: Symbols.volunteer_activism, tone: ProcTone.green)),
        if (s.isImport && _step >= 8 && !_back && !_manufacturer)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: ProcNote(
            fee == null
                ? 'Link the clearing agent\'s vendor fee first. Payment runs through Section 16 (receipt, Finance check, Director approval).'
                : fee.paid ? 'Clearing fee ${_tsh(fee.billed)} is paid.' : 'Clearing fee: ${fee.statusLabel}. ${fee.blockReason ?? ''}',
            icon: fee?.paid == true ? Symbols.verified : Symbols.info,
            tone: fee?.paid == true ? ProcTone.green : ProcTone.amber)),
        if (_arrival && !_manufacturer)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: ProcNote(
            'The clearing agent\'s receipt is attached here, once this is saved. If it hasn\'t come yet, '
            'the shipment still arrives and shows "receipt to follow".',
            icon: Symbols.receipt_long, tone: ProcTone.teal)),
        if (_back) ...[
          LabeledTextField(label: 'Reason for the correction · required', controller: _reason, maxLines: 2,
              hint: 'Logged on the timeline and sent with the notification'),
          const SizedBox(height: 12),
        ],
        LabeledTextField(label: 'Note · optional', controller: _note, maxLines: 2, hint: 'e.g. cleared customs, awaiting pickup by transporter'),
        const SizedBox(height: 8),
        Text('The CTO, MD, Sales Manager and the department manager are notified.',
            style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
      ]),
    );
  }
}

// ── Clearing fee (Section 16) ───────────────────────────────────────────────

Future<Shipment?> showClearingFeeDialog(BuildContext context, Shipment s) =>
    showDialog<Shipment>(context: context, builder: (_) => _ClearingFeeDialog(s));

class _ClearingFeeDialog extends StatefulWidget {
  const _ClearingFeeDialog(this.s);
  final Shipment s;
  @override
  State<_ClearingFeeDialog> createState() => _ClearingFeeDialogState();
}

class _ClearingFeeDialogState extends State<_ClearingFeeDialog> {
  ShipmentOptions? _opts;
  bool _existing = false;
  int? _feeId;
  int? _vendorId;
  final _amount = TextEditingController();
  late final _desc = TextEditingController(text: 'Clearing — ${widget.s.reference}');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ShipmentService.instance.options().then((o) {
      if (!mounted) return;
      setState(() {
        _opts = o;
        final clearing = o.vendors.where((v) => v['type'] == 'clearing' || v['type'] == 'courier');
        _vendorId = clearing.isEmpty ? null : (clearing.first['id'] as num).toInt();
      });
    }).catchError((Object e) {
      if (mounted) showErrorToast(context, e);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseShillings(_amount.text);
    if (_existing ? _feeId == null : (_vendorId == null || amount == null || amount < 1)) {
      showErrorToast(context, Exception(_existing ? 'Pick the vendor fee to link.' : 'Pick the clearing agent and enter the billed amount.'));
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ShipmentService.instance.linkClearingFee(widget.s.id, _existing
          ? {'vendor_fee_id': _feeId}
          : {'vendor_id': _vendorId, 'billed_amount': amount, 'description': _desc.text.trim()});
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _opts;
    return ProcDialog(
      title: 'Clearing fee · ${widget.s.reference}',
      icon: Symbols.receipt_long,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(onPressed: _saving || o == null ? null : _save, icon: const Icon(Symbols.link, size: 15),
            label: Text(_saving ? 'Saving…' : _existing ? 'Link fee' : 'Record fee')),
      ],
      body: o == null
          ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const ProcNote('The clearing cost is a Section 16 vendor fee: no receipt, no payment. The receipt, Finance check and '
                  'Director approval all happen in Vendors & Delivery, not here.'),
              const SizedBox(height: 12),
              LabeledDropdown<bool>(label: 'Fee', value: _existing, items: const [false, true],
                  displayBuilder: (v) => v ? 'Link a fee already recorded' : 'Record a new fee',
                  onChanged: (v) => setState(() => _existing = v)),
              const SizedBox(height: 12),
              if (_existing)
                LabeledDropdown<int?>(
                  label: 'Vendor fee',
                  value: _feeId,
                  items: [null, ...o.openVendorFees.map((f) => (f['id'] as num).toInt())],
                  displayBuilder: (id) {
                    if (id == null) return o.openVendorFees.isEmpty ? 'No unlinked fees' : 'Select…';
                    final f = o.openVendorFees.firstWhere((x) => x['id'] == id);
                    return '${f['vendor_name'] ?? 'Vendor'} · ${_tsh((f['billed_amount'] as num).toInt())} · ${f['description']}';
                  },
                  onChanged: (v) => setState(() => _feeId = v),
                )
              else ...[
                LabeledDropdown<int?>(
                  label: 'Clearing agent',
                  value: o.vendors.any((v) => v['id'] == _vendorId) ? _vendorId : null,
                  items: [null, ...o.vendors.map((v) => (v['id'] as num).toInt())],
                  displayBuilder: (id) {
                    if (id == null) return o.vendors.isEmpty ? 'No vendors — add one in Vendors & Delivery' : 'Select…';
                    final v = o.vendors.firstWhere((x) => x['id'] == id);
                    return '${v['name']}${_vendorTypeSuffix(v['type'])}';
                  },
                  onChanged: (v) => setState(() => _vendorId = v),
                ),
                const SizedBox(height: 12),
                formRow([
                  LabeledTextField(label: 'Billed amount (TZS)', controller: _amount, keyboardType: TextInputType.number),
                  LabeledTextField(label: 'Description', controller: _desc),
                ]),
              ],
            ]),
    );
  }
}

/// "18 Oct 2026" or "—".
String shipDate(DateTime? d) => d == null ? '—' : formatDate(d);
