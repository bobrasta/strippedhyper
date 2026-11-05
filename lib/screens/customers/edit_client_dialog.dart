import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/client.dart';
import '../../services/client_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/tin.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/phone_layout.dart';

const _kRegions = [
  'Arusha', 'Dar Es Salaam', 'Dodoma', 'Geita', 'Iringa', 'Kagera', 'Katavi', 'Kigoma',
  'Kilimanjaro', 'Lindi', 'Manyara', 'Mara', 'Mbeya', 'Morogoro', 'Mtwara', 'Mwanza',
  'Njombe', 'Pwani', 'Rukwa', 'Ruvuma', 'Shinyanga', 'Simiyu', 'Singida', 'Songwe',
  'Tabora', 'Tanga',
];

/// Edits a customer organisation's record (name, code, TIN, contact,
/// address, credit limit). Shown as an in-screen modal overlay.
class EditClientDialog extends StatefulWidget {
  const EditClientDialog({super.key, required this.client, required this.onClose});
  final Client client;
  final VoidCallback onClose;

  @override
  State<EditClientDialog> createState() => _EditClientDialogState();
}

class _EditClientDialogState extends State<EditClientDialog> {
  late final _nameCtrl     = TextEditingController(text: widget.client.name);
  late final _codeCtrl     = TextEditingController(text: widget.client.shortCode);
  late final _districtCtrl = TextEditingController(text: widget.client.district);
  late final _contactCtrl  = TextEditingController(text: widget.client.contactName);
  late final _phoneCtrl    = TextEditingController(text: widget.client.contactPhone);
  late final _tinCtrl      = TextEditingController(text: widget.client.tin ?? '');
  late final _addressCtrl  = TextEditingController(text: widget.client.address ?? '');
  late final _creditLimitCtrl = TextEditingController(
      text: widget.client.creditLimit?.toString() ?? '');
  late String _type   = const ['public', 'private', 'mission'].contains(widget.client.type) ? widget.client.type : 'private';
  late String _region = _matchRegion(widget.client.region);
  bool        _saving = false;
  String?     _error;

  static String _matchRegion(String r) => _kRegions.firstWhere(
      (k) => k.toLowerCase() == r.trim().toLowerCase(), orElse: () => _kRegions[1]);

  @override
  void dispose() {
    _nameCtrl.dispose(); _codeCtrl.dispose(); _districtCtrl.dispose();
    _contactCtrl.dispose(); _phoneCtrl.dispose();
    _tinCtrl.dispose(); _addressCtrl.dispose(); _creditLimitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_tinCtrl.text.trim().isNotEmpty && normalizeTin(_tinCtrl.text) == null) {
      setState(() => _error = 'TIN must be 9 digits (e.g. 123-456-789).');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ClientService.instance.update(widget.client.id, {
        'name':          _nameCtrl.text.trim(),
        'short_code':    _codeCtrl.text.trim(),
        'type':          _type,
        'region':        _region,
        'district':      _districtCtrl.text.trim(),
        'contact_name':  _contactCtrl.text.trim(),
        'contact_phone': _phoneCtrl.text.trim(),
        'tin':           normalizeTin(_tinCtrl.text),
        'address':       _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'credit_limit':  _creditLimitCtrl.text.trim().isEmpty
            ? null : int.tryParse(_creditLimitCtrl.text.trim()),
      });
      widget.onClose();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error  = e.toString().contains('422') ? 'Validation failed — check all fields.' : 'Failed to save.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onClose,
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 520,
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
                Icon(Symbols.edit, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text('Edit: ${widget.client.name}',
                    style: AppTheme.bodyStrong, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Row(children: [
                  Expanded(flex: 3, child: _Field('Client name', _nameCtrl, '')),
                  const SizedBox(width: 14),
                  Expanded(flex: 1, child: _Field('Code', _codeCtrl, 'e.g. ABC')),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Dropdown(
                    label: 'Type', value: _type,
                    items: const ['public', 'private', 'mission'],
                    display: const ['Public', 'Private', 'NGO / Faith'],
                    onChanged: (v) => setState(() => _type = v),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _Dropdown(
                    label: 'Region', value: _region, items: _kRegions,
                    onChanged: (v) => setState(() => _region = v),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _Field('District', _districtCtrl, '')),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Field('Contact person', _contactCtrl, '')),
                  const SizedBox(width: 14),
                  Expanded(child: _Field('Phone', _phoneCtrl, '')),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Field('TIN', _tinCtrl, '123-456-789')),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: _Field('Address', _addressCtrl, 'P.O. Box, street, town')),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Field('Credit Limit (TZS, blank = unlimited)',
                      _creditLimitCtrl, 'e.g. 5000000', numeric: true)),
                  const SizedBox(width: 14),
                  const Expanded(child: SizedBox()),
                ]),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.error_outline, size: 14, color: AppColors.coral),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_error!,
                      style: AppTheme.bodySub.copyWith(color: AppColors.coral, fontSize: 12))),
                  ]),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                    decoration: BoxDecoration(color: AppColors.teal,
                        borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Save Changes', style: AppTheme.bodyStrong.copyWith(
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

class _Field extends StatelessWidget {
  const _Field(this.label, this.ctrl, this.hint, {this.numeric = false});
  final String label, hint;
  final TextEditingController ctrl;
  final bool numeric;

  @override
  Widget build(BuildContext context) => LabeledTextField(label: label, controller: ctrl, hint: hint,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text);
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.label, required this.value, required this.items,
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
      items: items.asMap().entries.map((e) => DropdownMenuItem(
            value: e.value,
            child: Text(display != null ? display![e.key] : e.value))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    ),
  ]);
}
