import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/expense.dart';
import '../../models/supplier.dart';
import '../../models/tax_rate.dart';
import '../../models/vendor_bill.dart';
import '../../services/expense_service.dart';
import '../../services/supplier_service.dart';
import '../../services/tax_rate_service.dart';
import '../../services/vendor_bill_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/finance/connections_button.dart';
import '../../widgets/finance/payment_request_dialog.dart';
import '../../models/creditor.dart' show money;
import '../../models/purchase_order.dart';
import '../../services/purchase_order_service.dart';

class VendorBillsScreen extends StatefulWidget {
  const VendorBillsScreen({super.key});

  @override
  State<VendorBillsScreen> createState() => _VendorBillsScreenState();
}

class _VendorBillsScreenState extends State<VendorBillsScreen> {
  final _payRunKey = GlobalKey();
  List<VendorBill>      _bills      = [];
  List<Supplier>        _suppliers  = [];
  List<ExpenseCategory> _categories = [];
  bool    _loading = true;
  bool    _payingRun = false;
  String? _error;
  bool    _showCreate = false;
  VendorBill? _selected;

  List<VendorBill> get _open => _bills.where((b) => b.canPay).toList();
  // Across currencies, totals are in TZS at each invoice's own rate.
  int get _totalPayable => _open.fold(0, (s, b) => s + b.balanceDueTzs);

  List<VendorBill> get _dueSoon {
    final now = DateTime.now();
    return _open.where((b) {
      final d = DateTime.tryParse(b.dueDate);
      if (d == null) return false;
      final days = d.difference(now).inDays;
      return days >= 0 && days <= 7;
    }).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  List<VendorBill> get _overdue {
    final now = DateTime.now();
    return _open.where((b) {
      final d = DateTime.tryParse(b.dueDate);
      return d != null && d.isBefore(now);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — same reasoning as MachineListScreen's own
    // fix: show the last-known bundle instantly on a fresh mount (this
    // widget isn't kept alive across navigation), then quietly refresh.
    final cached = VendorBillService.cachedDefaultList;
    if (cached != null) {
      _bills = cached;
      _suppliers = SupplierService.cachedDefaultList ?? [];
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
      if (_bills.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        VendorBillService.instance.list(),
        SupplierService.instance.list(),
        ExpenseService.instance.categories(),
      ]);
      if (!mounted) return;
      setState(() {
        _bills      = results[0] as List<VendorBill>;
        _suppliers  = results[1] as List<Supplier>;
        _categories = results[2] as List<ExpenseCategory>;
        _loading    = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  void _scrollToPayRun() {
    final ctx = _payRunKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  /// Asks the Director to pay every TSh invoice due within a week, from one
  /// account. Foreign-currency invoices each need their own rate, so they're
  /// paid one at a time from the invoice.
  Future<void> _schedulePayRun() async {
    final due = _dueSoon.where((b) => !b.isForeign && !b.hasPendingPayment).toList();
    final foreign = _dueSoon.where((b) => b.isForeign).length;
    if (due.isEmpty) {
      showErrorToast(context, Exception(foreign > 0
          ? 'Only foreign-currency invoices are due — request each payment from the invoice (it needs its exchange rate).'
          : 'Payments for these invoices are already waiting on the Director.'));
      return;
    }
    final account = await pickPaymentAccount(context, title: 'Pay run — paid from',
        note: 'Sends ${due.length} payment request(s) totalling ${tshFromDouble(due.fold<int>(0, (s, b) => s + b.balanceDueTzs))} '
            'to the Director.${foreign > 0 ? ' $foreign foreign-currency invoice(s) are left out — pay those from the invoice.' : ''}');
    if (account == null || !mounted) return;
    setState(() => _payingRun = true);
    try {
      for (final b in due) {
        await VendorBillService.instance.recordPayment(b.id, {
          'amount': b.balanceDue,
          'paid_from_account_id': account.id,
          'payment_date': DateTime.now().toIso8601String().substring(0, 10),
          'notes': 'Pay run',
        });
      }
      if (mounted) showSuccessToast(context, 'Pay run sent — ${due.length} payment(s) waiting on the Director.');
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _payingRun = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      LayoutBuilder(builder: (ctx, cst) {
        final pad  = cst.maxWidth < 560 ? 16.0 : 26.0;
        final wide = cst.maxWidth >= 1000;
        return Padding(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TitleWithActions(
              leading: Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(2))),
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Accounts Payable', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                const SizedBox(height: 3),
                Text('Supplier invoices · payments go to the Director · ${_suppliers.length} suppliers on file', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ]),
              actions: [
                OutlinedButton.icon(onPressed: _scrollToPayRun, icon: const Icon(Symbols.send, size: 15), label: const Text('Pay run')),
                FilledButton.icon(onPressed: () => setState(() => _showCreate = true), icon: const Icon(Symbols.add, size: 16), label: const Text('New invoice')),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  // A background refresh failing while stale-but-valid
                  // cached data is already showing shouldn't blow that
                  // away — only "genuinely nothing to show" surfaces the
                  // error screen.
                  : _error != null && _bills.isEmpty
                      ? ErrorView(message: _error!, onRetry: _load)
                      : SingleChildScrollView(child: wide
                          // No IntrinsicHeight here: both columns contain
                          // LayoutBuilders, which can't report intrinsic sizes.
                          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(flex: 7, child: _mainColumn(context)),
                              const SizedBox(width: 16),
                              Expanded(flex: 5, child: _rail(context)),
                            ])
                          : Column(children: [_mainColumn(context), const SizedBox(height: 16), _rail(context)])),
            ),
          ]),
        );
      }),
      if (_showCreate)
        _NewBillDialog(
          suppliers: _suppliers,
          categories: _categories,
          onClose: () => setState(() => _showCreate = false),
          onSaved: () { setState(() => _showCreate = false); _load(); },
        ),
      if (_selected != null)
        _BillDetailSheet(
          bill: _selected!,
          onClose: () => setState(() => _selected = null),
          onChanged: () { setState(() => _selected = null); _load(); },
        ),
    ]);
  }

  Widget _mainColumn(BuildContext context) {
    final overdueTotal = _overdue.fold<int>(0, (s, b) => s + b.balanceDueTzs);
    final dueSoonTotal = _dueSoon.fold<int>(0, (s, b) => s + b.balanceDueTzs);
    final paidToDate = _bills.fold<int>(0, (s, b) => s + b.amountPaidTzs);

    final now = DateTime.now();
    final buckets = <String, int>{'Current': 0, '1–30 d': 0, '31–60 d': 0, '60 d +': 0};
    for (final b in _open) {
      final d = DateTime.tryParse(b.dueDate);
      final daysLate = d == null ? 0 : now.difference(d).inDays;
      if (daysLate <= 0) buckets['Current'] = buckets['Current']! + b.balanceDueTzs;
      else if (daysLate <= 30) buckets['1–30 d'] = buckets['1–30 d']! + b.balanceDueTzs;
      else if (daysLate <= 60) buckets['31–60 d'] = buckets['31–60 d']! + b.balanceDueTzs;
      else buckets['60 d +'] = buckets['60 d +']! + b.balanceDueTzs;
    }
    final bucketColors = {'Current': AppColors.green, '1–30 d': AppColors.amber, '31–60 d': const Color(0xFFFF8A3D), '60 d +': AppColors.coral};
    final agingTotal = buckets.values.fold(0, (a, b) => a + b);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, cst) {
            final total = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('OUTSTANDING PAYABLE', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
              const SizedBox(height: 5),
              Text(tshFromDouble(_totalPayable), style: AppTheme.kpiValue.copyWith(fontSize: 25)),
            ]);
            final stats = [
              _apStat('Due in 7 days', tshFromDouble(dueSoonTotal), AppColors.amber),
              _apStat('Overdue', tshFromDouble(overdueTotal), AppColors.coral),
              _apStat('Open bills', '${_open.length}', context.pal.text),
              _apStat('Paid to date', tshFromDouble(paidToDate), AppColors.green),
            ];
            // Phones: headline total, then the four figures two to a row.
            if (isPhoneWidth(cst.maxWidth)) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                total,
                const SizedBox(height: 14),
                PhoneStatGrid(spacing: 12, children: stats),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              total,
              const Spacer(),
              for (final (i, st) in stats.indexed) ...[if (i > 0) const SizedBox(width: 22), st],
            ]);
          }),
          const SizedBox(height: 16),
          if (agingTotal > 0) ClipRRect(borderRadius: BorderRadius.circular(4), child: Row(children: buckets.entries.map((e) =>
              Expanded(flex: (e.value == 0 ? 1 : e.value), child: Container(width: double.infinity, height: 8, color: e.value == 0 ? context.pal.surface3 : bucketColors[e.key])),
          ).toList())),
          const SizedBox(height: 11),
          Wrap(spacing: 20, runSpacing: 6, children: buckets.entries.map((e) => Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: bucketColors[e.key], borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 7),
            Text(e.key, style: AppTheme.bodySub.copyWith(fontSize: 11)),
            const SizedBox(width: 6),
            Text(tshFromDouble(e.value), style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.text)),
          ])).toList()),
        ]),
      ),
      const SizedBox(height: 14),
      // Phones: one card per bill; wider screens keep the table.
      LayoutBuilder(builder: (context, cst) => isPhoneWidth(cst.maxWidth) ? _billCards(context) : Container(
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            height: 38, padding: const EdgeInsets.symmetric(horizontal: 16),
            color: context.pal.surface2,
            child: Row(children: [
              SizedBox(width: 100, child: Text('BILL NO.', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
              Expanded(flex: 3, child: Text('SUPPLIER', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
              Expanded(child: Text('TOTAL', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
              Expanded(child: Text('DUE', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
              Expanded(child: Text('DUE DATE', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
              Expanded(child: Text('STATUS', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
              const SizedBox(width: 54),
            ]),
          ),
          if (_bills.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('No supplier invoices yet.', style: AppTheme.bodySub))),
          ..._bills.map((b) {
            final now2 = DateTime.now();
            final d = DateTime.tryParse(b.dueDate);
            final daysDiff = d?.difference(now2).inDays;
            final overdue = b.status == 'overdue' || (daysDiff != null && daysDiff < 0 && b.canPay);
            final agingLabel = b.isPaid ? 'settled' : b.status == 'cancelled' ? 'voided' : daysDiff == null ? '—' : daysDiff >= 0 ? 'in $daysDiff days' : '${-daysDiff} days late';
            final stColor = switch (b.status) { 'paid' => AppColors.green, 'approved' => AppColors.cyan, 'partial' => AppColors.amber, 'cancelled' => AppColors.textMute, _ => overdue ? AppColors.coral : context.pal.textMute };
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: overdue ? AppColors.coral.withValues(alpha: 0.05) : null, border: Border(bottom: BorderSide(color: context.pal.divider))),
              child: Row(children: [
                SizedBox(width: 100, child: Text(b.displayNumber, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.textMute))),
                Expanded(flex: 3, child: Text(b.supplierName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Expanded(child: Text(money(b.total, b.currency), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.monoSm.copyWith(fontSize: 12.5))),
                Expanded(child: Text(b.balanceDue > 0 ? money(b.balanceDue, b.currency) : '—', textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.monoSm.copyWith(fontSize: 12.5, color: overdue ? AppColors.coral : context.pal.text))),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.dueDate, style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
                  Text(agingLabel, style: AppTheme.bodySub.copyWith(fontSize: 10, color: overdue ? AppColors.coral : context.pal.textDim)),
                ])),
                Expanded(child: Align(alignment: Alignment.centerRight, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: stColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
                  child: Text(b.statusLabel.toUpperCase(), style: AppTheme.monoXs.copyWith(fontSize: 9, color: stColor)),
                ))),
                SizedBox(width: 54, child: Align(alignment: Alignment.centerRight, child: OutlinedButton(
                  onPressed: () => setState(() => _selected = b),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 26)),
                  child: Text(b.canPay && !b.hasPendingPayment ? 'Pay' : 'View', style: const TextStyle(fontSize: 11)),
                ))),
              ]),
            );
          }),
        ]),
      )),
    ]);
  }

  Widget _billCards(BuildContext context) {
    if (_bills.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(child: Text('No supplier invoices yet.', style: AppTheme.bodySub)));
    }
    final now = DateTime.now();
    return Column(children: [
      for (final b in _bills)
        Builder(builder: (context) {
          final d = DateTime.tryParse(b.dueDate);
          final daysDiff = d?.difference(now).inDays;
          final overdue = b.status == 'overdue' || (daysDiff != null && daysDiff < 0 && b.canPay);
          final aging = b.isPaid ? 'settled' : b.status == 'cancelled' ? 'voided' : daysDiff == null ? '' : daysDiff >= 0 ? 'in $daysDiff days' : '${-daysDiff} days late';
          final stColor = switch (b.status) { 'paid' => AppColors.green, 'approved' => AppColors.cyan, 'partial' => AppColors.amber, 'cancelled' => AppColors.textMute, _ => overdue ? AppColors.coral : context.pal.textMute };
          return PhoneRecordCard(
            margin: const EdgeInsets.only(bottom: 8),
            title: b.supplierName ?? '—',
            subtitle: b.displayNumber,
            badge: PhonePill(b.statusLabel, stColor),
            meta: ['due ${b.dueDate}${aging.isEmpty ? '' : ' ($aging)'}', 'total ${money(b.total, b.currency)}'],
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(b.balanceDue > 0 ? money(b.balanceDue, b.currency) : 'Paid',
                  style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: overdue ? AppColors.coral : null)),
              if (b.canPay && !b.hasPendingPayment) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _selected = b),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(64, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                  child: const Text('Pay', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ]),
            onTap: () => setState(() => _selected = b),
          );
        }),
    ]);
  }

  Widget _apStat(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9)),
    const SizedBox(height: 5),
    Text(value, style: AppTheme.monoXs.copyWith(fontSize: 15, color: color)),
  ]);

  Widget _sectionHeader(BuildContext context, IconData icon, Color color, String title) => Row(children: [
    Icon(icon, size: 13, color: color),
    const SizedBox(width: 8),
    Text(title.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
    const SizedBox(width: 8),
    Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
  ]);

  Widget _rail(BuildContext context) {
    final due = _dueSoon;
    final dueTotal = due.fold<int>(0, (s, b) => s + b.balanceDueTzs);
    final bySupplier = <String, int>{};
    for (final b in _bills) { bySupplier[b.supplierName ?? '—'] = (bySupplier[b.supplierName ?? '—'] ?? 0) + b.totalTzsOrRate; }
    final topSuppliers = bySupplier.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxSupplier = topSuppliers.isEmpty ? 1 : topSuppliers.first.value;

    return Column(key: _payRunKey, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionHeader(context, Symbols.event_available, AppColors.green, 'Next pay run'),
      const SizedBox(height: 9),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(tshFromDouble(dueTotal), style: AppTheme.kpiValue.copyWith(fontSize: 20)),
            const SizedBox(width: 8),
            Flexible(child: Text('${due.length} bill${due.length == 1 ? '' : 's'} due within 7 days', style: AppTheme.bodySub.copyWith(fontSize: 11))),
          ]),
          const SizedBox(height: 10),
          Container(width: double.infinity, height: 1, color: context.pal.divider),
          const SizedBox(height: 10),
          if (due.isEmpty) Text('Nothing due within a week.', style: AppTheme.bodySub.copyWith(fontSize: 12))
          else ...due.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Icon(Symbols.check_box_outline_blank, size: 14, color: context.pal.textDim),
              const SizedBox(width: 9),
              Expanded(child: Text(b.supplierName ?? '—', style: AppTheme.bodySub.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(money(b.balanceDue, b.currency), style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.text)),
            ]),
          )),
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: due.isEmpty || _payingRun ? null : _schedulePayRun,
            child: _payingRun ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Request pay run'),
          )),
        ]),
      ),
      const SizedBox(height: 16),
      _sectionHeader(context, Symbols.apartment, AppColors.violet, 'Top suppliers'),
      const SizedBox(height: 9),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: topSuppliers.isEmpty
            ? Text('No bills on file yet.', style: AppTheme.bodySub.copyWith(fontSize: 12))
            : Column(children: topSuppliers.take(5).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(e.key, style: AppTheme.bodySub.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(tshFromDouble(e.value), style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.text)),
                  ]),
                  const SizedBox(height: 5),
                  ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: e.value / maxSupplier, minHeight: 6, backgroundColor: context.pal.surface3, valueColor: AlwaysStoppedAnimation(AppColors.violet))),
                ]),
              )).toList()),
      ),
    ]);
  }
}

// ── New supplier invoice ─────────────────────────────────────────────────────

class _BillLineEntry {
  _BillLineEntry({String desc = '', String qty = '1', String price = ''})
      : descCtrl = TextEditingController(text: desc),
        qtyCtrl = TextEditingController(text: qty),
        priceCtrl = TextEditingController(text: price);
  final TextEditingController descCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;

  double get qty => double.tryParse(qtyCtrl.text.replaceAll(',', '')) ?? 0;
  double get price => double.tryParse(priceCtrl.text.replaceAll(',', '')) ?? 0;

  void dispose() { descCtrl.dispose(); qtyCtrl.dispose(); priceCtrl.dispose(); }
}

class _NewBillDialog extends StatefulWidget {
  const _NewBillDialog({required this.suppliers, required this.categories, required this.onClose, required this.onSaved});
  final List<Supplier> suppliers;
  final List<ExpenseCategory> categories;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  @override
  State<_NewBillDialog> createState() => _NewBillDialogState();
}

class _NewBillDialogState extends State<_NewBillDialog> {
  Supplier? _supplier;
  int?   _categoryId;
  PurchaseOrder? _po;
  List<PurchaseOrder> _pos = const [];
  bool   _loadingPos = false;
  double _taxRate = 18;
  List<TaxRate> _taxRates = const [];
  final _lines = [_BillLineEntry()];
  final _refCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  DateTime _issue = DateTime.now();
  DateTime _due = DateTime.now().add(const Duration(days: 30));
  bool   _saving = false;
  String? _error;

  String get _currency => (_supplier?.currency ?? 'TZS').toUpperCase();
  bool get _foreign => _currency != 'TZS';

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
      final seenRates = <double>{};
      final rates = all.where((r) => seenRates.add(r.rate)).toList();
      final defaultRate = rates.firstWhere((r) => r.isDefault, orElse: () => rates.first);
      setState(() { _taxRates = rates; _taxRate = defaultRate.rate; });
    } catch (_) {
      // Falls back to the static 0%/18% items below — non-critical.
    }
  }

  Future<void> _pickSupplier(Supplier? s) async {
    setState(() { _supplier = s; _po = null; _pos = const []; _loadingPos = s != null; });
    if (s == null) return;
    try {
      final pos = await PurchaseOrderService.instance.list(supplierId: s.id, period: Period.of(PeriodPreset.allTime));
      if (mounted && _supplier?.id == s.id) {
        setState(() {
          _pos = pos.where((p) => !const {'draft', 'rejected', 'cancelled'}.contains(p.status)).toList();
          _loadingPos = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPos = false);
    }
  }

  /// An LPO's lines come in as the invoice's lines (edit to match the invoice).
  void _pickPo(PurchaseOrder? po) {
    setState(() {
      _po = po;
      if (po != null && po.items.isNotEmpty) {
        for (final l in _lines) { l.dispose(); }
        _lines
          ..clear()
          ..addAll(po.items.map((i) => _BillLineEntry(
                desc: i.itemName ?? 'Item',
                qty: '${i.quantityReceived > 0 ? i.quantityReceived : i.quantityOrdered}',
                price: i.unitCost == i.unitCost.roundToDouble() ? i.unitCost.toStringAsFixed(0) : i.unitCost.toStringAsFixed(2))));
      }
    });
  }

  @override
  void dispose() {
    for (final l in _lines) { l.dispose(); }
    _refCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_saving) return;
    final validLines = _lines.where((l) => l.descCtrl.text.trim().isNotEmpty).toList();
    final rate = double.tryParse(_rateCtrl.text.replaceAll(',', ''));
    final err = _supplier == null
        ? 'Pick the supplier.'
        : validLines.isEmpty
            ? 'Add at least one line.'
            : _po == null && _categoryId == null
                ? 'Pick the expense category (or link the LPO).'
                : _foreign && (rate == null || rate <= 0)
                    ? 'Enter the invoice\'s exchange rate (TZS per $_currency).'
                    : null;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await VendorBillService.instance.create({
        'supplier_id': _supplier!.id,
        'purchase_order_id': ?_po?.id,
        if (_po == null) 'category_id': _categoryId,
        if (_refCtrl.text.trim().isNotEmpty) 'supplier_reference': _refCtrl.text.trim(),
        if (_foreign) 'exchange_rate': rate,
        'tax_rate':    _taxRate,
        'issue_date':  _iso(_issue),
        'due_date':    _iso(_due.isBefore(_issue) ? _issue : _due),
        'line_items':  validLines.map((l) => {
          'description': l.descCtrl.text.trim(),
          'quantity':    l.qty <= 0 ? 1 : l.qty,
          'unit_price':  l.price,
        }).toList(),
      });
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  Future<void> _date(bool issue) async {
    final d = await showDatePicker(context: context, initialDate: issue ? _issue : _due,
        firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 400)));
    if (d != null && mounted) setState(() => issue ? _issue = d : _due = d);
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = _lines.fold<double>(0, (s, l) => s + l.qty * l.price);
    final total = subtotal * (1 + _taxRate / 100);
    final rate = double.tryParse(_rateCtrl.text.replaceAll(',', ''));
    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: const Color(0xAA06070A),
        alignment: Alignment.center,
        child: PhoneModalBox(scroll: false, child: GestureDetector(
          onTap: () {},
          child: Container(
            width: 640,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
            decoration: BoxDecoration(
              color: context.pal.surface1,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.pal.borderStrong),
              boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(children: [
                  Icon(Symbols.receipt_long, size: 18, color: AppColors.coral),
                  const SizedBox(width: 10),
                  Expanded(child: Text('New supplier invoice', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  GestureDetector(onTap: widget.onClose, child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
                ]),
              ),
              Flexible(child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
                      child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12)),
                    ),
                  ],
                  _pair([
                    LabeledDropdown<Supplier?>(
                      label: 'Supplier',
                      value: _supplier,
                      items: [null, ...widget.suppliers],
                      displayBuilder: (s) => s == null ? 'Select…' : '${s.name} · ${s.currency}',
                      onChanged: _pickSupplier,
                    ),
                    _loadingPos
                        ? const Padding(padding: EdgeInsets.only(top: 30), child: LinearProgressIndicator(minHeight: 2))
                        : LabeledDropdown<PurchaseOrder?>(
                            label: 'LPO · optional',
                            value: _po,
                            items: [null, ..._pos],
                            displayBuilder: (p) => p == null
                                ? (_supplier == null ? 'Pick the supplier first' : _pos.isEmpty ? 'No LPOs for this supplier' : 'Not linked to an LPO')
                                : '${p.poNumber} · ${p.currency} ${p.totalAmount.toStringAsFixed(0)} · ${p.statusLabel}',
                            onChanged: _pickPo,
                          ),
                  ]),
                  const SizedBox(height: 12),
                  _pair([
                    LabeledTextField(label: "Supplier's invoice no.", controller: _refCtrl, hint: 'e.g. PV1, INV-2026-0042'),
                    if (_foreign)
                      LabeledTextField(label: 'Exchange rate (TZS per $_currency)', controller: _rateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true), hint: 'e.g. 2650',
                          onChanged: (_) => setState(() {}))
                    else
                      LabeledStaticField(label: 'Currency', value: _supplier == null ? '—' : 'TZS'),
                  ]),
                  const SizedBox(height: 12),
                  _pair([
                    LabeledDateField(label: 'Invoice date', date: _issue, onTap: () => _date(true)),
                    LabeledDateField(label: 'Due date', date: _due, onTap: () => _date(false)),
                  ]),
                  const SizedBox(height: 12),
                  _pair([
                    if (_po == null)
                      _Dropdown(
                        label: 'Expense category',
                        value: _categoryId,
                        items: widget.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (v) => setState(() => _categoryId = v),
                      )
                    else
                      LabeledStaticField(label: 'Posts to', value: 'Inventory (goods on ${_po!.poNumber})'),
                    _Dropdown<double>(
                      label: 'VAT %',
                      value: _taxRate,
                      items: _taxRates.isNotEmpty
                          ? _taxRates.map((r) => DropdownMenuItem(value: r.rate, child: Text(r.name, overflow: TextOverflow.ellipsis))).toList()
                          : const [
                              DropdownMenuItem(value: 0.0, child: Text('0%')),
                              DropdownMenuItem(value: 18.0, child: Text('18%')),
                            ],
                      onChanged: (v) => setState(() => _taxRate = v ?? 0),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: Text('Lines · $_currency', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                    TextButton.icon(
                      onPressed: () => setState(() => _lines.add(_BillLineEntry())),
                      icon: const Icon(Symbols.add, size: 14), label: const Text('Add line'),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  ..._lines.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(flex: 3, child: _InlineField(controller: e.value.descCtrl, hint: 'Description', onChanged: (_) => setState(() {}))),
                      const SizedBox(width: 8),
                      Expanded(child: _InlineField(controller: e.value.qtyCtrl, hint: 'Qty', number: true, onChanged: (_) => setState(() {}))),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: _InlineField(controller: e.value.priceCtrl, hint: 'Unit price', number: true, onChanged: (_) => setState(() {}))),
                      if (_lines.length > 1) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() { e.value.dispose(); _lines.removeAt(e.key); }),
                          child: Icon(Symbols.close, size: 16, color: context.pal.textDim),
                        ),
                      ],
                    ]),
                  )),
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerRight, child: Text(
                    'Total ${money(total, _currency)}${_foreign && rate != null ? '  =  ${money((total * rate).round(), 'TZS')}' : ''}',
                    style: AppTheme.bodyStrong.copyWith(fontSize: 13))),
                  const SizedBox(height: 4),
                  Text('Posts straight away against Trade Creditors; any advance already paid to this supplier is used first. '
                      'Paying it is a separate request the Director approves.',
                      style: AppTheme.bodySub.copyWith(fontSize: 11, color: context.pal.textDim)),
                ]),
              )),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(children: [
                  Expanded(child: OutlinedButton(onPressed: widget.onClose, child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save invoice'),
                  )),
                ]),
              ),
            ]),
          ),
        )),
      ),
    );
  }
}

/// Two fields side by side, stacked when narrow (phones).
Widget _pair(List<Widget> children) => LayoutBuilder(builder: (context, c) => c.maxWidth < 520
    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, w) in children.indexed) ...[if (i > 0) const SizedBox(height: 12), w],
      ])
    : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, w) in children.indexed) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: w)],
      ]));

class _InlineField extends StatelessWidget {
  const _InlineField({required this.controller, required this.hint, this.number = false, this.onChanged});
  final TextEditingController controller;
  final String hint;
  final bool number;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => LabeledTextField(label: '', controller: controller,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, hint: hint, onChanged: onChanged);
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged});
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

// ── Invoice detail ───────────────────────────────────────────────────────────

class _BillDetailSheet extends StatefulWidget {
  const _BillDetailSheet({required this.bill, required this.onClose, required this.onChanged});
  final VendorBill bill;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  @override
  State<_BillDetailSheet> createState() => _BillDetailSheetState();
}

class _BillDetailSheetState extends State<_BillDetailSheet> {
  late VendorBill _bill = widget.bill;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The list rows don't carry payments; the single invoice does.
    VendorBillService.instance.get(widget.bill.id).then((b) {
      if (mounted) setState(() => _bill = b);
    }).catchError((Object _) {});
  }

  Future<void> _requestPayment() async {
    final b = _bill;
    final body = await showPaymentRequestDialog(context,
        title: 'Pay ${b.displayNumber}',
        creditorName: b.supplierName ?? 'Supplier',
        currency: b.currency,
        amount: b.balanceDue,
        hint: 'Balance ${money(b.balanceDue, b.currency)} on this invoice.');
    if (body == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await VendorBillService.instance.recordPayment(b.id, body);
      if (mounted) showSuccessToast(context, 'Payment sent to the Director for approval.');
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showErrorToast(context, e);
      }
    }
  }

  Future<void> _cancelBill() async {
    try {
      await VendorBillService.instance.cancel(_bill.id);
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    final cur = bill.currency;
    return GestureDetector(
      onTap: widget.onClose,
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
                  Icon(Symbols.receipt, size: 18, color: AppColors.coral),
                  const SizedBox(width: 10),
                  Expanded(child: Text(bill.displayNumber, style: AppTheme.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ConnectionsButton(type: 'vendor_bill', id: bill.id, compact: true),
                  const SizedBox(width: 6),
                  GestureDetector(onTap: widget.onClose, child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Row('Supplier', bill.supplierName ?? '—'),
                  _Row('Our ref.', bill.billNumber),
                  if (bill.purchaseOrderNumber != null) _Row('LPO', bill.purchaseOrderNumber!),
                  _Row('Invoice date', bill.issueDate),
                  _Row('Due date', bill.dueDate),
                  _Row('Subtotal', money(bill.subtotal, cur)),
                  _Row('VAT (${bill.taxRate.toStringAsFixed(0)}%)', money(bill.taxAmount, cur)),
                  _Row('Total', money(bill.total, cur), bold: true),
                  if (bill.isForeign) _Row('Rate', '${bill.exchangeRate} TZS per $cur'),
                  _Row('Posted', money(bill.totalTzsOrRate, 'TZS')),
                  _Row('Paid', money(bill.amountPaid, cur), color: AppColors.teal),
                  if (bill.balanceDue > 0)
                    _Row('Balance due', money(bill.balanceDue, cur), color: AppColors.coral, bold: true),
                  if (bill.payments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('PAYMENTS', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
                    const SizedBox(height: 6),
                    for (final p in bill.payments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Icon(p.isPending ? Symbols.hourglass_top : Symbols.check_circle, size: 14,
                              color: p.isPending ? AppColors.amber : p.status == 'rejected' ? AppColors.coral : AppColors.green),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            '${p.paymentNumber} · ${money(p.applied > 0 ? p.applied : p.amount, p.currency)}'
                            '${p.paidFrom != null ? ' · ${p.paidFrom}' : ''} · ${p.statusLabel}',
                            style: AppTheme.bodySub.copyWith(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                  ],
                ]),
              ),
              if (bill.canCancel || (bill.canPay && !bill.hasPendingPayment))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(children: [
                    if (bill.canCancel)
                      Expanded(child: OutlinedButton(onPressed: _busy ? null : _cancelBill, child: const Text('Cancel invoice'))),
                    if (bill.canCancel && bill.canPay && !bill.hasPendingPayment) const SizedBox(width: 10),
                    if (bill.canPay && !bill.hasPendingPayment)
                      Expanded(flex: 2, child: FilledButton(
                        onPressed: _busy ? null : _requestPayment,
                        child: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Request payment'),
                      )),
                  ]),
                ),
            ]),
          ),
        )),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.color, this.bold = false});
  final String label, value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 130, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12.5))),
      Expanded(child: Text(value, style: AppTheme.bodySm.copyWith(
        color: color ?? context.pal.text,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12.5,
      ))),
    ]),
  );
}
