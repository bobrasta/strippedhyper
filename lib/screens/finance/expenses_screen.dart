import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/expense.dart';
import '../../models/tax_rate.dart';
import '../../services/expense_service.dart';
import '../../services/tax_rate_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/period_filter.dart';

const _categoryIcons = <String, IconData>{
  'Salaries & Wages': Symbols.groups,
  'Medical Supplies': Symbols.medical_services,
  'Rent & Facilities': Symbols.apartment,
  'Utilities': Symbols.bolt,
  'Transport': Symbols.local_shipping,
};
final _categoryColorPalette = [AppColors.coral, AppColors.amber, AppColors.violet, AppColors.cyan, AppColors.textMute];

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Expense>         _expenses   = [];
  List<ExpenseCategory> _categories = [];
  bool    _loading = true;
  String? _error;
  bool    _showCreate = false;
  String  _search = '';
  Set<int> _categoryFilter = {};
  Period  _period = Period.defaultPeriod;

  Color _categoryColor(String? name) {
    if (name == null) return AppColors.textMute;
    final i = _categories.indexWhere((c) => c.name == name);
    return _categoryColorPalette[(i < 0 ? 0 : i) % _categoryColorPalette.length];
  }

  List<Expense> get _filtered => _expenses.where((e) {
    if (_categoryFilter.isNotEmpty && !_categoryFilter.contains(e.categoryId)) return false;
    if (_search.isNotEmpty && !e.name.toLowerCase().contains(_search.toLowerCase()) && !(e.reference ?? '').toLowerCase().contains(_search.toLowerCase())) return false;
    return true;
  }).toList();

  double get _totalThisMonth {
    final now = DateTime.now();
    return _expenses.where((e) {
      final d = DateTime.tryParse(e.expenseDate);
      return d != null && d.year == now.year && d.month == now.month;
    }).fold(0, (s, e) => s + e.grossAmount);
  }

  double get _totalLastMonth {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    return _expenses.where((e) {
      final d = DateTime.tryParse(e.expenseDate);
      return d != null && d.year == lastMonth.year && d.month == lastMonth.month;
    }).fold(0, (s, e) => s + e.grossAmount);
  }

  List<Expense> get _awaitingApproval => _expenses.where((e) => e.status == ExpenseStatus.pendingManager
      || e.status == ExpenseStatus.pendingCto || e.status == ExpenseStatus.pendingDirector).toList();

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — same reasoning as InventoryItemsScreen's own
    // fix: show the last-known bundle instantly on a fresh mount (this
    // widget isn't kept alive across navigation), then quietly refresh.
    final cached = ExpenseService.cachedDefaultList;
    if (cached != null) {
      _expenses = cached;
      _categories = ExpenseService.cachedCategories ?? [];
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      // Only show the blank/shimmer state when there's genuinely nothing
      // to show yet — a background refresh of an already-populated list
      // (or a return visit seeded from the cache above) updates silently.
      if (_expenses.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ExpenseService.instance.list(period: _period),
        ExpenseService.instance.categories(),
      ]);
      if (!mounted) return;
      setState(() {
        _expenses   = results[0] as List<Expense>;
        _categories = results[1] as List<ExpenseCategory>;
        _loading    = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _approve(Expense e) async {
    try {
      await ExpenseService.instance.approve(e.id);
      if (mounted) showSuccessToast(context, 'Expense approved.');
      _load();
    } catch (err) { if (mounted) showErrorToast(context, err); }
  }

  Future<void> _reject(Expense e) async {
    try {
      await ExpenseService.instance.reject(e.id);
      if (mounted) showSuccessToast(context, 'Expense rejected.');
      _load();
    } catch (err) { if (mounted) showErrorToast(context, err); }
  }

  Future<void> _stopRecurring(Expense e) async {
    try {
      await ExpenseService.instance.stopRecurring(e.id);
      if (mounted) showSuccessToast(context, 'Recurring expense stopped.');
      _load();
    } catch (err) { if (mounted) showErrorToast(context, err); }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      LayoutBuilder(builder: (ctx, cst) {
        final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
        final phone = isPhoneWidth(cst.maxWidth);
        final vatReclaimable = _expenses.fold<double>(0, (s, e) => s + e.taxAmount);
        final vatCount = _expenses.where((e) => e.taxAmount > 0).length;
        final vsLastMonth = _totalLastMonth > 0 ? ((_totalThisMonth - _totalLastMonth) / _totalLastMonth * 100) : 0.0;

        return Padding(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Expenses', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                const SizedBox(height: 3),
                Text('Operating expenses & petty cash · ${_expenses.length} entries this view', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ])),
              FilledButton.icon(onPressed: () => setState(() => _showCreate = true), icon: const Icon(Symbols.add, size: 16), label: const Text('New expense')),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  // A background refresh failing while stale-but-valid
                  // cached data is already showing shouldn't blow that
                  // away — only "genuinely nothing to show" surfaces the
                  // error screen.
                  : _error != null && _expenses.isEmpty
                      ? ErrorView(message: _error!, onRetry: _load)
                      : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Container(
                            decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
                            child: phone ? PhoneStatGrid(children: [
                              _stat(_period.label, tshFromDouble(_expenses.fold<double>(0, (s, e) => s + e.grossAmount)), context.pal.text, '${_expenses.length} entries'),
                              _stat('Awaiting approval', tshFromDouble(_awaitingApproval.fold<double>(0, (s, e) => s + e.grossAmount)), AppColors.amber, '${_awaitingApproval.length} pending', border: true),
                              _stat('VAT reclaimable', tshFromDouble(vatReclaimable), AppColors.cyan, '$vatCount with VAT'),
                              _stat('vs last month', '${vsLastMonth >= 0 ? '+' : ''}${vsLastMonth.toStringAsFixed(1)}%', vsLastMonth > 0 ? AppColors.coral : AppColors.green, '${tshFromDouble(_totalLastMonth)} last month', border: true),
                            ]) : Row(children: [
                              Expanded(child: _stat(_period.label, tshFromDouble(_expenses.fold<double>(0, (s, e) => s + e.grossAmount)), context.pal.text, '${_expenses.length} entries · ${tshFromDouble(_totalThisMonth)} this month')),
                              Expanded(child: _stat('Awaiting approval', tshFromDouble(_awaitingApproval.fold<double>(0, (s, e) => s + e.grossAmount)), AppColors.amber, '${_awaitingApproval.length} entries pending', border: true)),
                              Expanded(child: _stat('VAT reclaimable', tshFromDouble(vatReclaimable), AppColors.cyan, '$vatCount entries with VAT', border: true)),
                              Expanded(child: _stat('vs last month', '${vsLastMonth >= 0 ? '+' : ''}${vsLastMonth.toStringAsFixed(1)}%', vsLastMonth > 0 ? AppColors.coral : AppColors.green, '${tshFromDouble(_totalLastMonth)} last month', border: true)),
                            ]),
                          ),
                          const SizedBox(height: 14),
                          if (phone) ...[
                            SearchField(
                              hint: 'Search description or reference…',
                              onChanged: (v) => setState(() => _search = v),
                            ),
                            const SizedBox(height: 10),
                            PhoneScrollRow(spacing: 8, children: [
                              PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
                              _categoryDropdown(context),
                            ]),
                            const SizedBox(height: 8),
                            Text('Showing ${_filtered.length} of ${_expenses.length}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                          ] else Row(children: [
                            PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
                            const SizedBox(width: 8),
                            SearchField(
                              width: 260,
                              hint: 'Search description or reference…',
                              onChanged: (v) => setState(() => _search = v),
                            ),
                            const SizedBox(width: 8),
                            _categoryDropdown(context),
                            const Spacer(),
                            Text('Showing ${_filtered.length} of ${_expenses.length}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                          ]),
                          const SizedBox(height: 14),
                          if (phone) ..._phoneCards(context) else _table(context),
                        ])),
            ),
          ]),
        );
      }),
      if (_showCreate)
        NewExpenseDialog(
          categories: _categories,
          onClose: () => setState(() => _showCreate = false),
          onSaved: () { setState(() => _showCreate = false); _load(); },
        ),
    ]);
  }

  // Was a Row of one chip per category — with 100+ categories (parent +
  // subcategory) that overflowed the header horizontally. A dropdown scales
  // to any count; parent categories lead, their subcategories indented
  // directly beneath so the hierarchy is still visible while picking.
  // Multi-select, matching the reference checkbox-dropdown pattern — lets
  // you filter by several categories at once instead of only one.
  Widget _categoryDropdown(BuildContext context) {
    final topLevel = _categories.where((c) => c.parentId == null).toList()..sort((a, b) => a.name.compareTo(b.name));
    final byParent = <int, List<ExpenseCategory>>{};
    for (final c in _categories) {
      if (c.parentId != null) (byParent[c.parentId!] ??= []).add(c);
    }
    for (final list in byParent.values) { list.sort((a, b) => a.name.compareTo(b.name)); }

    final items = <AppSelectItem<int>>[
      for (final parent in topLevel) ...[
        AppSelectItem(value: parent.id, label: parent.name),
        for (final child in byParent[parent.id] ?? const <ExpenseCategory>[])
          AppSelectItem(value: child.id, label: '    ${child.name}'),
      ],
    ];

    return AppMultiSelectField<int>(
      width: 240,
      hint: 'All categories',
      values: _categoryFilter,
      items: items,
      onChanged: (v) => setState(() => _categoryFilter = v),
    );
  }

  Widget _stat(String label, String value, Color color, String note, {bool border = false}) => Container(
    padding: const EdgeInsets.all(15),
    decoration: border ? BoxDecoration(border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.06)))) : null,
    child: Builder(builder: (context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
      const SizedBox(height: 7),
      Text(value, style: AppTheme.kpiValue.copyWith(fontSize: 19, color: color)),
      const SizedBox(height: 6),
      Text(note, style: AppTheme.bodySub.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
    ])),
  );

  Widget _statusPill(ExpenseStatus s) {
    final (label, color) = switch (s) {
      ExpenseStatus.pendingPayment => ('awaiting payment', AppColors.blue),
      ExpenseStatus.pendingRelease => ('awaiting release', AppColors.violet),
      ExpenseStatus.paid           => ('paid', AppColors.green),
      ExpenseStatus.rejected       => ('rejected', AppColors.coral),
      _ => ('pending', AppColors.amber),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
      child: Text(label.toUpperCase(), style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: color)),
    );
  }

  /// Phone list: one card per expense; pending ones carry approve/reject.
  List<Widget> _phoneCards(BuildContext context) {
    final rows = _filtered;
    if (rows.isEmpty) {
      return [Padding(padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(child: Text('No expenses match this view.', style: AppTheme.bodySub)))];
    }
    return [
      for (final e in rows)
        PhoneRecordCard(
            margin: const EdgeInsets.only(bottom: 8),
            lead: Icon(_categoryIcons[e.categoryName] ?? Symbols.receipt_long, size: 20,
                color: _categoryColor(e.categoryName)),
            title: e.name,
            subtitle: e.categoryName,
            badge: _statusPill(e.status),
            meta: [e.expenseDate, e.paymentModeLabel, ?e.reference, ?e.createdByName,
                if (e.taxAmount > 0) 'VAT ${tshFromDouble(e.taxAmount)}'],
            amount: tshFromDouble(e.grossAmount),
            trailing: (e.status == ExpenseStatus.pendingCto || e.status == ExpenseStatus.pendingDirector)
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(tshFromDouble(e.grossAmount), style: AppTheme.bodyStrong.copyWith(fontSize: 13.5)),
                    IconButton(tooltip: 'Reject', onPressed: () => _reject(e),
                        icon: Icon(Symbols.close, size: 20, color: AppColors.coral)),
                    IconButton(tooltip: 'Approve', onPressed: () => _approve(e),
                        icon: Icon(Symbols.check, size: 20, color: AppColors.green)),
                  ])
                : null,
        ),
    ];
  }

  Widget _table(BuildContext context) {
    final rows = _filtered;
    return Container(
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          height: 38, padding: const EdgeInsets.symmetric(horizontal: 16),
          color: context.pal.surface2,
          child: Row(children: [
            const SizedBox(width: 20),
            Expanded(flex: 6, child: Text('DESCRIPTION', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 4, child: Text('CATEGORY', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 2, child: Text('AMOUNT', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 2, child: Text('VAT', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 2, child: Text('METHOD', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 2, child: Text('DATE', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 2, child: Text('STATUS', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
          ]),
        ),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('No expenses match this view.', style: AppTheme.bodySub))),
        ...rows.map((e) {
          final color = _categoryColor(e.categoryName);
          final pending = e.status == ExpenseStatus.pendingCto || e.status == ExpenseStatus.pendingDirector;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
            child: Row(children: [
              Icon(_categoryIcons[e.categoryName] ?? Symbols.receipt_long, size: 15, color: color),
              const SizedBox(width: 12),
              Expanded(flex: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(e.name, style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (e.isActiveRecurringTemplate) ...[
                    const SizedBox(width: 6),
                    Tooltip(message: 'Recurring — tap to stop', child: GestureDetector(
                      onTap: () => _stopRecurring(e),
                      child: Icon(Symbols.repeat, size: 13, color: AppColors.violet),
                    )),
                  ] else if (e.recurParentId != null) ...[
                    const SizedBox(width: 6),
                    Tooltip(message: 'Auto-generated from a recurring expense', child: Icon(Symbols.repeat, size: 12, color: context.pal.textDim)),
                  ],
                ]),
                if (e.reference != null || e.createdByName != null) Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text([if (e.reference != null) e.reference!, if (e.createdByName != null) e.createdByName!].join(' · '), style: AppTheme.bodySub.copyWith(fontSize: 11)),
                ),
              ])),
              Expanded(flex: 4, child: Row(children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 7),
                Expanded(child: Text(e.categoryName ?? '—', style: AppTheme.bodySub.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ])),
              Expanded(flex: 2, child: Text(tshFromDouble(e.grossAmount), textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 12.5))),
              Expanded(flex: 2, child: Text(e.taxAmount > 0 ? tshFromDouble(e.taxAmount) : '—', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: e.taxAmount > 0 ? AppColors.cyan : context.pal.textDim))),
              Expanded(flex: 2, child: Text(e.paymentModeLabel, style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
              Expanded(flex: 2, child: Text(e.expenseDate, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim))),
              Expanded(flex: 2, child: pending
                  ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      IconButton(onPressed: () => _reject(e), icon: Icon(Symbols.close, size: 15, color: AppColors.coral), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
                      IconButton(onPressed: () => _approve(e), icon: Icon(Symbols.check, size: 15, color: AppColors.green), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
                    ])
                  : Align(alignment: Alignment.centerRight, child: _statusPill(e.status))),
            ]),
          );
        }),
        if (rows.isNotEmpty) Container(
          height: 44, padding: const EdgeInsets.symmetric(horizontal: 16),
          color: context.pal.surface2,
          child: Row(children: [
            const SizedBox(width: 27),
            Expanded(flex: 10, child: Text('TOTAL · ${rows.length} SHOWN', style: AppTheme.labelCaps.copyWith(fontSize: 10))),
            Expanded(flex: 2, child: Text(tshFromDouble(rows.fold<double>(0, (s, e) => s + e.grossAmount)), textAlign: TextAlign.right, style: AppTheme.bodyStrong.copyWith(fontSize: 13))),
            Expanded(flex: 2, child: Text(tshFromDouble(rows.fold<double>(0, (s, e) => s + e.taxAmount)), textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: AppColors.cyan))),
            const Expanded(flex: 2, child: SizedBox()), const Expanded(flex: 2, child: SizedBox()), const Expanded(flex: 2, child: SizedBox()),
          ]),
        ),
      ]),
    );
  }
}

// ── New Expense Dialog ───────────────────────────────────────────────────────

class NewExpenseDialog extends StatefulWidget {
  const NewExpenseDialog({super.key, required this.categories, required this.onClose, required this.onSaved, this.allowRecurring = true});
  /// Off in My Expenses: recurring company costs are Finance's to set up.
  final bool allowRecurring;
  final List<ExpenseCategory> categories;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  @override
  State<NewExpenseDialog> createState() => NewExpenseDialogState();
}

class NewExpenseDialogState extends State<NewExpenseDialog> {
  final _nameCtrl   = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _refCtrl    = TextEditingController();
  int?    _categoryId;
  double  _taxRate   = 18;
  List<TaxRate> _taxRates = const [];
  String  _paymentMode = 'cash';
  bool    _isRecurring = false;
  int     _recurInterval = 1;
  String  _recurIntervalType = 'months';
  bool    _saving  = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.categories.isNotEmpty) _categoryId = widget.categories.first.id;
    _loadTaxRates();
  }

  Future<void> _loadTaxRates() async {
    try {
      final all = await TaxRateService.instance.list();
      if (!mounted || all.isEmpty) return;
      // Dropdown items key on the numeric rate (that's all the backend
      // stores) — dedupe defensively in case two named rates share a %.
      final seenRates = <double>{};
      final rates = all.where((r) => seenRates.add(r.rate)).toList();
      final defaultRate = rates.firstWhere((r) => r.isDefault, orElse: () => rates.first);
      setState(() { _taxRates = rates; _taxRate = defaultRate.rate; });
    } catch (_) {
      // Falls back to the static 0%/18% items below — non-critical.
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _amountCtrl.dispose(); _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = int.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
    if (_nameCtrl.text.trim().isEmpty || amount <= 0 || _categoryId == null) {
      setState(() => _error = 'Please fill in description, category and a valid amount.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ExpenseService.instance.create({
        'name':         _nameCtrl.text.trim(),
        'category_id':  _categoryId,
        'amount':       amount,
        'tax_rate':     _taxRate,
        'payment_mode': _paymentMode,
        'expense_date': DateTime.now().toIso8601String().substring(0, 10),
        'reference':    _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        if (_isRecurring) ...{
          'is_recurring':        true,
          'recur_interval':      _recurInterval,
          'recur_interval_type': _recurIntervalType,
        },
      });
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
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
          width: 480,
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
                Icon(Symbols.receipt_long, size: 18, color: AppColors.coral),
                const SizedBox(width: 10),
                Expanded(child: Text('New Expense', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose, child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12)),
                  ),
                ],
                LabeledTextField(label: 'Description', controller: _nameCtrl, hint: 'e.g. Office rent'),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _LabeledDropdown(
                    label: 'Category',
                    value: _categoryId,
                    items: widget.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => _categoryId = v),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _LabeledDropdown(
                    label: 'Payment Mode',
                    value: _paymentMode,
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank')),
                      DropdownMenuItem(value: 'mobile_money', child: Text('Mobile Money')),
                    ],
                    onChanged: (v) => setState(() => _paymentMode = v ?? 'cash'),
                  )),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: LabeledTextField(label: 'Amount (TSh, excl. VAT)', controller: _amountCtrl, keyboardType: TextInputType.number, hint: '0')),
                  const SizedBox(width: 14),
                  Expanded(child: _LabeledDropdown(
                    label: 'VAT %',
                    value: _taxRate,
                    items: _taxRates.isNotEmpty
                        ? _taxRates.map((r) => DropdownMenuItem(value: r.rate, child: Text(r.name))).toList()
                        : const [
                            DropdownMenuItem(value: 0.0,  child: Text('0%')),
                            DropdownMenuItem(value: 18.0, child: Text('18%')),
                          ],
                    onChanged: (v) => setState(() => _taxRate = v ?? 0),
                  )),
                ]),
                const SizedBox(height: 14),
                LabeledTextField(label: 'Reference (optional)', controller: _refCtrl, hint: 'Receipt / invoice no.'),
                if (widget.allowRecurring) ...[
                const SizedBox(height: 10),
                Row(children: [
                  SizedBox(width: 22, height: 22, child: Checkbox(
                      value: _isRecurring, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) => setState(() => _isRecurring = v ?? false))),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Repeats automatically (e.g. rent, subscriptions)', style: AppTheme.bodySm)),
                ]),
                ],
                if (_isRecurring) ...[
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Text('Every', style: AppTheme.bodySm),
                    const SizedBox(width: 8),
                    SizedBox(width: 56, height: 34, child: _InlineDropdown(
                      value: _recurInterval,
                      items: List.generate(12, (i) => i + 1)
                          .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                          .toList(),
                      onChanged: (v) => setState(() => _recurInterval = v ?? 1),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: SizedBox(height: 34, child: _InlineDropdown(
                      value: _recurIntervalType,
                      items: const [
                        DropdownMenuItem(value: 'days', child: Text('Day(s)')),
                        DropdownMenuItem(value: 'months', child: Text('Month(s)')),
                        DropdownMenuItem(value: 'years', child: Text('Year(s)')),
                      ],
                      onChanged: (v) => setState(() => _recurIntervalType = v ?? 'months'),
                    ))),
                  ]),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Expanded(child: GestureDetector(onTap: widget.onClose,
                  child: Container(height: 38,
                    decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text('Cancel', style: AppTheme.bodySm))))),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(onTap: _save,
                  child: Container(height: 38,
                    decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Save Expense', style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 13)))))),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    DropdownFieldBox<T>(
      value: value,
      items: items,
      onChanged: onChanged,
    ),
  ]);
}

class _InlineDropdown<T> extends StatelessWidget {
  const _InlineDropdown({required this.value, required this.items, required this.onChanged});
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownFieldBox<T>(
    value: value,
    items: items,
    onChanged: onChanged,
  );
}
