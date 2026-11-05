// Line-item editing pieces shared by the Quotation and Invoice builders.
// UI only — each document keeps its own save logic and API.
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/inventory_item.dart';
import '../../models/inventory_lot.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../common/app_dropdown.dart';
import '../common/labeled_field.dart';

// ── Line item entry (mutable state for form) ───────────────────────────────────

// Column widths shared by the line rows and each builder's header row.
const double kLineQtyW   = 76;
const double kLinePriceW = 130;
const double kLineDiscW  = 100;
const double kLineTotalW = 110;

class LineItemEntry {
  final descCtrl  = TextEditingController();
  final uomCtrl   = TextEditingController(text: 'pcs');
  final qtyCtrl   = TextEditingController(text: '1');
  final priceCtrl = TextEditingController();
  // TSh off this line (user, 2026-10-02 — an amount, not a percentage).
  final discCtrl  = TextEditingController();
  // Lot number and expiry date — invoices only (LineItemTableRow.showLotExpiry).
  final lotCtrl   = TextEditingController();
  DateTime? expiry;
  InventoryItem? selectedItem;
  // The product an existing line was saved with, until another is picked.
  int? inventoryItemId;

  int? get itemId => selectedItem?.id ?? inventoryItemId;

  int get qty      => int.tryParse(qtyCtrl.text) ?? 0;
  int get price    => int.tryParse(priceCtrl.text.replaceAll(',', '')) ?? 0;
  int get gross    => qty * price;
  int get discount => int.tryParse(discCtrl.text.replaceAll(',', '').trim()) ?? 0;
  // What the line comes to after its discount — InvoiceController /
  // QuotationController work it out the same way (App\Support\LineDiscount).
  int get net      => gross - discount;

  void dispose() {
    descCtrl.dispose(); uomCtrl.dispose();
    qtyCtrl.dispose();  priceCtrl.dispose(); discCtrl.dispose(); lotCtrl.dispose();
  }
}

// ── Line item row — compact table row matching the design's Line items panel ────

class LineItemTableRow extends StatelessWidget {
  const LineItemTableRow({
    super.key,
    required this.entry,
    required this.invItems,
    required this.onChanged,
    required this.onRemove,
    this.lots = const {},
    this.showDiscount = true,
    this.showLotExpiry = false,
  });

  final LineItemEntry entry;
  final List<InventoryItem> invItems;
  /// Lots with stock, by product id (InventoryService.openLots) — each lot
  /// is its own option in the product search.
  final Map<int, List<InventoryLot>> lots;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  /// Per-line TSh discount column.
  final bool showDiscount;
  /// A second row under the item with Unit, Lot no. and Expiry (invoices,
  /// like Clickhuduma's sale lines).
  final bool showLotExpiry;

  int get _lineTotal => showDiscount ? entry.net : entry.gross;

  void _pick(InventoryItem? item, [InventoryLot? lot]) {
    entry.selectedItem = item;
    entry.inventoryItemId = null;
    if (item != null) {
      entry.descCtrl.text  = item.name;
      entry.uomCtrl.text   = item.unitOfMeasure;
      entry.priceCtrl.text = item.sellingPrice.toStringAsFixed(0);
      // A lot option fills its lot and expiry; a plain product clears them.
      entry.lotCtrl.text = lot?.lotNumber ?? '';
      entry.expiry       = lot?.expiry;
    }
    onChanged();
  }

  /// The product search options: a product with lots in stock comes once per
  /// lot (soonest expiry first), the rest once — each with its price.
  List<AppSelectItem<ItemPick>> _options() => [
    for (final i in invItems)
      if (lots[i.id] case final itemLots? when itemLots.isNotEmpty)
        for (final l in itemLots)
          AppSelectItem(value: ItemPick(i, l), label: '${i.name} · ${i.sku}',
              subtitle: '${_price(i)} · Lot ${l.lotNumber}'
                  '${l.expiry == null ? '' : ' · Exp ${formatDate(l.expiry!)}'} · ${l.qtyLeft} left')
      else
        AppSelectItem(value: ItemPick(i, null), label: '${i.name} · ${i.sku}', subtitle: _price(i)),
  ];

  static String _price(InventoryItem i) => i.sellingPrice > 0 ? tshExact(i.sellingPrice) : 'No price';

  /// Below this width the row stacks: item on its own line, numbers under it.
  static const double _stackBelow = 520;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, cst) =>
      cst.maxWidth < _stackBelow ? _stacked(context) : _row(context));

  /// Phone form: the item search full width (× to remove), then
  /// Qty | Unit price, then Discount | line total — each field labelled
  /// since there's no column header.
  Widget _stacked(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _itemField()),
        if (onRemove != null)
          IconButton(tooltip: 'Remove line', onPressed: onRemove,
              icon: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
      ]),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SizedBox(width: 72, child: _labelled(context, 'QTY', _numField(entry.qtyCtrl, onChanged))),
        const SizedBox(width: 8),
        Expanded(child: _labelled(context, 'UNIT PRICE', _numField(entry.priceCtrl, onChanged))),
      ]),
      const SizedBox(height: 8),
      // Discount (TSh off this line) with the line total beside it.
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (showDiscount)
          SizedBox(width: 140, child: _labelled(context, 'DISCOUNT (TSH)', _numField(entry.discCtrl, onChanged, hint: '0'))),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(tshFromDouble(_lineTotal.toDouble()), textAlign: TextAlign.right,
              style: AppTheme.monoSm.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ]),
      if (showLotExpiry) ...[const SizedBox(height: 8), _lotExpiry(context)],
    ]),
  );

  /// Unit · Lot no. · Expiry — wraps onto more lines when narrow.
  Widget _lotExpiry(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
    SizedBox(width: 110, child: LabeledTextField(label: 'Unit', controller: entry.uomCtrl, hint: 'pcs',
        onChanged: (_) => onChanged())),
    SizedBox(width: 160, child: LabeledTextField(label: 'Lot no.', controller: entry.lotCtrl, hint: 'Optional',
        onChanged: (_) => onChanged())),
    SizedBox(width: 170, child: LabeledDateField(
      label: 'Expiry',
      date: entry.expiry,
      placeholder: 'Optional',
      onClear: () { entry.expiry = null; onChanged(); },
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(context: context, initialDate: entry.expiry ?? now,
            firstDate: DateTime(2015), lastDate: DateTime(now.year + 15));
        if (picked != null) { entry.expiry = picked; onChanged(); }
      },
    )),
  ]);

  Widget _labelled(BuildContext context, String label, Widget field) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute)),
      const SizedBox(height: 4),
      field,
    ]);

  // Type to search the inventory (name or SKU) and pick from the
  // dropdown, or keep typing for a custom line that isn't in stock.
  Widget _itemField() => AppSearchableSelectField<ItemPick>(
          key: ObjectKey(entry),
          hint: 'Type an item name, SKU or lot…',
          selectedLabel: entry.descCtrl.text,
          items: _options(),
          onSelected: (sel) {
            if (sel == null) {
              entry.selectedItem = null;
              entry.descCtrl.clear();
              onChanged();
            } else {
              _pick(sel.value.item, sel.value.lot);
            }
          },
          onTextChanged: (text) {
            // Free text: typing after a pick unlinks the inventory item.
            entry.descCtrl.text = text;
            entry.selectedItem = null;
            entry.inventoryItemId = null;
            onChanged();
          },
        );

  Widget _row(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
     Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(flex: 3, child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: _itemField(),
      )),
      SizedBox(width: kLineQtyW, child: _numField(entry.qtyCtrl, onChanged)),
      const SizedBox(width: 8),
      SizedBox(width: kLinePriceW, child: _numField(entry.priceCtrl, onChanged)),
      const SizedBox(width: 8),
      if (showDiscount) ...[
        SizedBox(width: kLineDiscW, child: _numField(entry.discCtrl, onChanged, hint: '0')),
        const SizedBox(width: 8),
      ],
      SizedBox(width: kLineTotalW, child: Text(tshFromDouble(_lineTotal.toDouble()), textAlign: TextAlign.right,
          style: AppTheme.monoSm.copyWith(fontSize: 12))),
      SizedBox(width: 22, child: onRemove != null
          ? GestureDetector(onTap: onRemove, child: Icon(Symbols.close, size: 15, color: context.pal.textDim))
          : null),
     ]),
     if (showLotExpiry) Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: _lotExpiry(context)),
    ]),
  );

  // The unified text input, right-aligned for numbers.
  Widget _numField(TextEditingController ctrl, VoidCallback onChanged, {String? hint}) => LabeledTextField(
    label: '',
    controller: ctrl,
    hint: hint,
    textAlign: TextAlign.right,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => onChanged(),
  );
}

/// A product search option: the product, and the lot when the option is one.
class ItemPick {
  const ItemPick(this.item, this.lot);
  final InventoryItem item;
  final InventoryLot? lot;
}

// Inventory catalog can run to hundreds/thousands of SKUs — client-side
// combobox per Section 4 of hypermed_claude_code_prompt.md.
class InvItemPicker extends StatelessWidget {
  const InvItemPicker({super.key, required this.items, required this.selected, required this.onSelected});
  final List<InventoryItem> items;
  final InventoryItem? selected;
  final ValueChanged<InventoryItem?> onSelected;

  @override
  Widget build(BuildContext context) => AppSearchableSelectField<InventoryItem>(
    hint: 'Link inventory item (optional)',
    selectedLabel: selected == null ? null : '${selected!.sku} · ${selected!.name}',
    items: items.map((item) => AppSelectItem(
      value: item, label: '${item.sku} · ${item.name}')).toList(),
    onSelected: (item) => onSelected(item?.value),
  );
}

// ── Date picker field ──────────────────────────────────────────────────────────

class SalesDateField extends StatelessWidget {
  const SalesDateField({
    super.key,
    required this.label,
    required this.selected,
    required this.onPicked,
    this.firstDate,
  });
  final String label;
  final DateTime? selected;
  final ValueChanged<DateTime?> onPicked;
  final DateTime? firstDate;

  @override
  Widget build(BuildContext context) => LabeledDateField(
    label: label,
    date: selected,
    placeholder: 'Pick a date',
    onClear: () => onPicked(null),
    onTap: () async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: selected ?? now.add(const Duration(days: 30)),
        firstDate: firstDate ?? now,
        lastDate: now.add(const Duration(days: 365 * 5)),
      );
      if (picked != null) onPicked(picked);
    },
  );
}

