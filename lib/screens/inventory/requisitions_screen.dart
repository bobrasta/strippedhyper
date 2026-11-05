import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/inventory_item.dart';
import '../../models/purchase_requisition.dart';
import '../../services/inventory_service.dart';
import '../../services/purchase_requisition_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/shimmer_box.dart';

class RequisitionsScreen extends StatefulWidget {
  const RequisitionsScreen({super.key});

  @override
  State<RequisitionsScreen> createState() => _RequisitionsScreenState();
}

class _RequisitionsScreenState extends State<RequisitionsScreen> {
  String? _statusFilter;
  PurchaseRequisition? _selected;
  bool _showCreate = false;

  List<PurchaseRequisition> _prs = [];
  bool   _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known list immediately (if any)
    // instead of blanking to a spinner on every navigation — see
    // MachineService for the full reasoning.
    final cached = PurchaseRequisitionService.cachedDefaultList;
    if (cached != null) { _prs = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_prs.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final data = await PurchaseRequisitionService.instance.list(status: _statusFilter);
      if (mounted) setState(() { _prs = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _loadDetail(int id) async {
    // Show a cached full record instantly (if we have one) rather than
    // leaving the panel on the list row's summary fields until the fetch
    // resolves.
    final cached = PurchaseRequisitionService.cachedById[id];
    if (cached != null && mounted) setState(() => _selected = cached);
    try {
      final full = await PurchaseRequisitionService.instance.get(id);
      if (mounted) setState(() => _selected = full);
    } catch (_) {}
  }

  Future<void> _action(Future<PurchaseRequisition> Function() fn, String msg) async {
    try {
      final updated = await fn();
      if (mounted) { setState(() => _selected = updated); _load(); }
      if (mounted) showSuccessToast(context, msg);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  static Color _statusColor(String s) => switch (s) {
    'draft'     => AppColors.textDim,
    'submitted' => AppColors.blue,
    'approved'  => AppColors.teal,
    'rejected'  => AppColors.coral,
    'ordered'   => AppColors.violet,
    _           => AppColors.textDim,
  };

  @override
  Widget build(BuildContext context) {
    const statuses = ['draft', 'submitted', 'approved', 'rejected', 'ordered'];
    const sLabels  = ['Draft', 'Submitted', 'Approved', 'Rejected', 'Ordered'];

    return LayoutBuilder(builder: (context, cst) {
    // Phones show the list, or one requisition in its place; back closes it.
    final phone       = isPhoneWidth(cst.maxWidth);
    final phoneDetail = phone && _selected != null;
    return PopScope(
      canPop: !phoneDetail,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && phoneDetail) setState(() => _selected = null);
      },
      child: Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Header ──
        if (phoneDetail) const SizedBox.shrink()
        else if (phone) PhonePageHeader(
          title: 'Purchase Requisitions',
          subtitle: 'Internal requests to procure stock',
          primary: PageAction(label: 'New Requisition', shortLabel: 'New', icon: Symbols.add,
              onPressed: () => setState(() => _showCreate = true)),
          filters: [
            _StatusChip(label: 'All', active: _statusFilter == null,
                onTap: () { setState(() => _statusFilter = null); _load(); }),
            for (final (i, st) in statuses.indexed)
              _StatusChip(label: sLabels[i], color: _statusColor(st), active: _statusFilter == st,
                  onTap: () { setState(() => _statusFilter = _statusFilter == st ? null : st); _load(); }),
          ],
        ) else Container(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Purchase Requisitions', style: AppTheme.pageTitle),
              const SizedBox(height: 2),
              Text('Internal requests to procure stock', style: AppTheme.bodySub),
            ]),
            const SizedBox(width: 20),
            Wrap(spacing: 6, children: [
              _StatusChip(label: 'All', active: _statusFilter == null,
                  onTap: () { setState(() => _statusFilter = null); _load(); }),
              ...statuses.asMap().entries.map((e) => _StatusChip(
                label: sLabels[e.key], color: _statusColor(e.value),
                active: _statusFilter == e.value,
                onTap: () {
                  setState(() => _statusFilter = _statusFilter == e.value ? null : e.value);
                  _load();
                },
              )),
            ]),
            const Spacer(),
            AppButton(label: 'New Requisition', icon: Symbols.add, variant: BtnVariant.primary,
                onPressed: () => setState(() => _showCreate = true)),
          ]),
        ),
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // List
          if (!phoneDetail) Expanded(flex: 3, child: RefreshIndicator(
            onRefresh: _load,
            child: Column(children: [
              // Table header
              if (phone) const SizedBox(height: 10) else Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
                child: Row(children: [
                  _Th('PR Number', flex: 2), _Th('Title', flex: 4),
                  _Th('Status', flex: 2), _Th('Requested By', flex: 2), _Th('Date', flex: 2),
                ]),
              ),
              Expanded(child: _loading
                ? shimmerTable(count: 8, cols: 5)
                : _error != null && _prs.isEmpty
                  ? ErrorView(message: _error!, onRetry: _load, compact: true)
                  : _prs.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Symbols.assignment, size: 36, color: context.pal.textDim),
                        const SizedBox(height: 10),
                        Text('No requisitions found', style: AppTheme.bodySub),
                      ]))
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _prs.length,
                        itemBuilder: (_, i) {
                          final pr = _prs[i];
                          if (phone) {
                            return PhoneRecordCard(
                              title: pr.title,
                              subtitle: pr.prNumber,
                              badge: PhonePill(pr.statusLabel, _statusColor(pr.status)),
                              meta: [?pr.requestedByName, formatDate(pr.createdAt)],
                              onTap: () {
                                setState(() => _selected = pr);
                                _loadDetail(pr.id);
                              },
                            );
                          }
                          return _PRRow(
                            pr: pr, selected: _selected?.id == pr.id,
                            statusColor: _statusColor(pr.status),
                            onTap: () {
                              setState(() => _selected = pr);
                              _loadDetail(pr.id);
                            },
                          );
                        },
                      )),
            ]),
          )),
          // Detail
          if (_selected != null) ...[
            if (!phone) Container(width: 1, color: context.pal.border),
            Expanded(flex: 2, child: _PRDetailPanel(
              pr: _selected!,
              statusColor: _statusColor(_selected!.status),
              onClose: () => setState(() => _selected = null),
              onSubmit:  () => _action(
                () => PurchaseRequisitionService.instance.submit(_selected!.id),
                'Requisition submitted'),
              onApprove: () => _action(
                () => PurchaseRequisitionService.instance.approve(_selected!.id),
                'Requisition approved'),
              onReject:  () => _action(
                () => PurchaseRequisitionService.instance.reject(_selected!.id),
                'Requisition rejected'),
            )),
          ],
        ])),
      ]),
      if (_showCreate)
        _CreatePRModal(
          onClose: () => setState(() => _showCreate = false),
          onSaved: () { setState(() => _showCreate = false); _load(); },
        ),
    ]));
    });
  }
}

// ── PR row ───────────────────────────────────────────────────────────────────

class _PRRow extends StatelessWidget {
  const _PRRow({required this.pr, required this.selected,
      required this.statusColor, required this.onTap});
  final PurchaseRequisition pr;
  final bool selected;
  final Color statusColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: BoxDecoration(
        color: selected ? context.pal.surface2 : Colors.transparent,
        border: Border(bottom: BorderSide(color: context.pal.divider)),
      ),
      child: Row(children: [
        Expanded(flex: 2, child: Text(pr.prNumber,
            style: AppTheme.monoXs.copyWith(color: AppColors.teal, fontSize: 12))),
        Expanded(flex: 4, child: Text(pr.title,
            style: AppTheme.bodyStrong.copyWith(fontSize: 13), overflow: TextOverflow.ellipsis)),
        Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(pr.statusLabel, style: AppTheme.monoXs.copyWith(
              color: statusColor, fontSize: 11), overflow: TextOverflow.ellipsis),
        ))),
        Expanded(flex: 2, child: Text(pr.requestedByName ?? '—',
            style: AppTheme.bodySub.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis)),
        Expanded(flex: 2, child: Text(formatDate(pr.createdAt),
            style: AppTheme.bodySub.copyWith(fontSize: 12))),
      ]),
    ),
  );
}

// ── PR detail panel ──────────────────────────────────────────────────────────

class _PRDetailPanel extends StatelessWidget {
  const _PRDetailPanel({
    required this.pr, required this.statusColor, required this.onClose,
    this.onSubmit, this.onApprove, this.onReject,
  });
  final PurchaseRequisition pr;
  final Color statusColor;
  final VoidCallback onClose;
  final VoidCallback? onSubmit, onApprove, onReject;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(pr.prNumber,
            style: AppTheme.monoXs.copyWith(color: AppColors.teal, fontSize: 13))),
        GestureDetector(onTap: onClose,
            child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
      ]),
      const SizedBox(height: 4),
      Text(pr.title, style: AppTheme.bodyStrong),
      const SizedBox(height: 12),
      // Status badge
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
        ),
        child: Text(pr.statusLabel, style: AppTheme.bodyStrong.copyWith(
            color: statusColor, fontSize: 12.5)),
      ),
      const SizedBox(height: 14),
      if (pr.requestedByName != null) _Row('Requested By', pr.requestedByName!),
      if (pr.approvedByName != null)  _Row('Approved By',  pr.approvedByName!),
      _Row('Created', formatDate(pr.createdAt)),
      if (pr.submittedAt != null) _Row('Submitted', formatDate(pr.submittedAt!)),
      if (pr.approvedAt != null)  _Row('Approved',  formatDate(pr.approvedAt!)),
      if (pr.notes != null) ...[
        const SizedBox(height: 10),
        Text('Notes', style: AppTheme.cardTitle.copyWith(fontSize: 12)),
        const SizedBox(height: 4),
        Text(pr.notes!, style: AppTheme.bodySub.copyWith(fontSize: 12.5)),
      ],
      if (pr.items.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Items (${pr.items.length})', style: AppTheme.cardTitle.copyWith(fontSize: 12)),
        const SizedBox(height: 8),
        ...pr.items.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.pal.surface2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.itemName ?? '—', style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
              if (item.itemSku != null)
                Text(item.itemSku!, style: AppTheme.monoXs.copyWith(
                    color: context.pal.textMute, fontSize: 10.5)),
            ])),
            Text('×${item.quantityRequested}',
                style: AppTheme.bodyStrong.copyWith(color: AppColors.teal)),
          ]),
        )),
      ],
      const SizedBox(height: 20),
      // Action buttons
      if (pr.status == 'draft')
        _ActionBtn(label: 'Submit for Approval', color: AppColors.blue,
            icon: Symbols.send, onTap: onSubmit),
      if (pr.status == 'submitted') ...[
        _ActionBtn(label: 'Approve', color: AppColors.teal,
            icon: Symbols.check_circle, onTap: onApprove),
        const SizedBox(height: 8),
        _ActionBtn(label: 'Reject', color: AppColors.coral,
            icon: Symbols.cancel, onTap: onReject),
      ],
    ]),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 100, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12))),
      Expanded(child: Text(value, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
    ]),
  );
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.label, required this.color, required this.icon, this.onTap});
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Text(label, style: AppTheme.bodyStrong.copyWith(color: color, fontSize: 13)),
        ]),
      ),
    ),
  );
}

// ── Create PR modal ──────────────────────────────────────────────────────────

class _CreatePRModal extends StatefulWidget {
  const _CreatePRModal({required this.onClose, this.onSaved});
  final VoidCallback  onClose;
  final VoidCallback? onSaved;

  @override
  State<_CreatePRModal> createState() => _CreatePRModalState();
}

class _CreatePRModalState extends State<_CreatePRModal> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  List<InventoryItem> _availableItems = [];
  // line items: [{item, qty, estimatedCost}]
  final List<Map<String, dynamic>> _lines = [];
  bool   _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    InventoryService.instance.list().then((list) {
      if (mounted) setState(() => _availableItems = list);
    });
  }

  @override
  void dispose() { _titleCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  void _addLine() {
    if (_availableItems.isEmpty) return;
    setState(() => _lines.add({
      'item': _availableItems.first,
      'qty':  TextEditingController(text: '1'),
      'cost': TextEditingController(text: ''),
    }));
  }

  void _removeLine(int i) {
    (_lines[i]['qty']  as TextEditingController).dispose();
    (_lines[i]['cost'] as TextEditingController).dispose();
    setState(() => _lines.removeAt(i));
  }

  Future<void> _save() async {
    if (_saving || _titleCtrl.text.trim().isEmpty || _lines.isEmpty) {
      setState(() => _error = 'Add a title and at least one item.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final items = _lines.map((l) {
        final item = l['item'] as InventoryItem;
        return {
          'inventory_item_id':  item.id,
          'quantity_requested': int.tryParse((l['qty'] as TextEditingController).text) ?? 1,
          'estimated_cost':     double.tryParse((l['cost'] as TextEditingController).text) ?? 0,
        };
      }).toList();

      await PurchaseRequisitionService.instance.create({
        'title': _titleCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'items': items,
      });
      if (mounted) showSuccessToast(context, 'Requisition created');
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
          width: 560,
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
                Icon(Symbols.assignment_add, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text('New Purchase Requisition', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Fld('Title', _titleCtrl, 'e.g. Monthly Consumables Restock'),
                const SizedBox(height: 12),
                _Fld('Notes (optional)', _notesCtrl, 'Reason or additional details'),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Text('Items', style: AppTheme.cardTitle.copyWith(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  GestureDetector(
                    onTap: _addLine,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.tealSoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Symbols.add, size: 14, color: AppColors.teal),
                        const SizedBox(width: 4),
                        Text('Add Item', style: AppTheme.bodySm.copyWith(color: AppColors.teal, fontSize: 12)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                if (_lines.isEmpty)
                  Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: context.pal.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.pal.border),
                    ),
                    child: Center(child: Text('No items added yet',
                        style: AppTheme.bodySub.copyWith(fontSize: 12.5))),
                  )
                else
                  ..._lines.asMap().entries.map((e) => _LineItemRow(
                    index: e.key,
                    line: e.value,
                    availableItems: _availableItems,
                    onRemove: () => _removeLine(e.key),
                    onItemChanged: (item) => setState(() => _lines[e.key]['item'] = item),
                  )),
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
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Create Requisition', style: AppTheme.bodyStrong.copyWith(
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

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({required this.index, required this.line, required this.availableItems,
      required this.onRemove, required this.onItemChanged});
  final int index;
  final Map<String, dynamic> line;
  final List<InventoryItem> availableItems;
  final VoidCallback onRemove;
  final ValueChanged<InventoryItem> onItemChanged;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: context.pal.surface2,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.pal.border),
    ),
    child: Row(children: [
      // Item picker — inventory catalog can run to hundreds/thousands of
      // SKUs, client-side combobox per Section 4 of
      // hypermed_claude_code_prompt.md.
      Expanded(flex: 3, child: AppSearchableSelectField<int>(
        selectedLabel: '${(line['item'] as InventoryItem).sku} · ${(line['item'] as InventoryItem).name}',
        items: availableItems.map((i) => AppSelectItem(
          value: i.id, label: '${i.sku} · ${i.name}')).toList(),
        onSelected: (item) {
          if (item == null) return;
          onItemChanged(availableItems.firstWhere((i) => i.id == item.value));
        },
      )),
      const SizedBox(width: 8),
      // Qty
      SizedBox(width: 64, child: CellField(controller: line['qty'] as TextEditingController, hint: 'Qty', keyboardType: TextInputType.number)),
      const SizedBox(width: 8),
      GestureDetector(onTap: onRemove,
          child: Icon(Symbols.close, size: 16, color: AppColors.coral)),
    ]),
  );
}

class _Fld extends StatelessWidget {
  const _Fld(this.label, this.ctrl, this.hint);
  final String label, hint;
  final TextEditingController ctrl;

  // The Settings text input (shared LabeledTextField).
  @override
  Widget build(BuildContext context) => LabeledTextField(label: label, controller: ctrl, hint: hint);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.active, required this.onTap, this.color});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? (color ?? AppColors.teal).withValues(alpha: 0.12) : context.pal.surface1,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: active ? (color ?? AppColors.teal) : context.pal.border),
      ),
      child: Text(label, style: AppTheme.bodySm.copyWith(
          color: active ? (color ?? AppColors.teal) : context.pal.textMute, fontSize: 12)),
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
