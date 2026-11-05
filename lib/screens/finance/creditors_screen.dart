import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../main.dart' show hasAccountantAuthority, userRoleNotifier;
import '../../models/creditor.dart';
import '../../services/creditor_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/finance/connections_button.dart';
import '../../widgets/finance/payment_request_dialog.dart';
import 'connections_screen.dart';

/// Creditors Ledger: the suppliers and vendors Hypermed owes, International
/// (foreign currency) and Local (TZS), as at any date — the accounts team's
/// CREDITOR LEDGERS workbook, kept by the system. Tap a creditor for their
/// statement.
class CreditorsScreen extends StatefulWidget {
  const CreditorsScreen({super.key});

  @override
  State<CreditorsScreen> createState() => _CreditorsScreenState();
}

class _CreditorsScreenState extends State<CreditorsScreen> {
  CreditorList? _list = CreditorService.cachedList;
  String? _error;
  String _category = 'international';
  DateTime? _asAt;
  bool _onlyWithBalance = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await CreditorService.instance.list(asAt: _asAt);
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  List<CreditorRow> get _rows {
    final all = _list?.creditors ?? const <CreditorRow>[];
    return all.where((c) => c.category == _category
        && (!_onlyWithBalance || c.lines > 0)
        && (_q.isEmpty || c.name.toLowerCase().contains(_q.toLowerCase()))).toList()
      ..sort((a, b) => b.bookBalanceTzs.compareTo(a.bookBalanceTzs));
  }

  void _open(CreditorRow c) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CreditorStatementScreen(type: c.type, id: c.id, name: c.name))).then((_) => _load());

  Future<void> _xlsx() => downloadPdf(context, () => CreditorService.instance.allXlsx(to: _asAt),
      'Creditor-Ledgers-${(_asAt ?? DateTime.now()).toIso8601String().substring(0, 10)}.xlsx');

  @override
  Widget build(BuildContext context) {
    final l = _list;
    return LayoutBuilder(builder: (context, c) {
      final pad = c.maxWidth < 560 ? 16.0 : 26.0;
      final phone = isPhoneWidth(c.maxWidth);
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.all(pad), children: [
          TitleWithActions(
            leading: Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.violet, borderRadius: BorderRadius.circular(2))),
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Creditors', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
              const SizedBox(height: 3),
              Text('Suppliers & vendors Hypermed owes · invoices, payments and balances', style: AppTheme.bodySub.copyWith(fontSize: 12)),
            ]),
            actions: [
              AsAtDateBox(value: _asAt, onChanged: (d) { setState(() => _asAt = d); _load(); }),
              OutlinedButton.icon(onPressed: _xlsx, icon: const Icon(Symbols.table_view, size: 15), label: const Text('Excel')),
            ],
          ),
          const SizedBox(height: 16),
          if (l == null)
            _error != null ? ErrorView(message: _error!, onRetry: _load) : const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else ...[
            _summary(context, l, phone),
            const SizedBox(height: 12),
            _reconciliation(context, l),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'international', label: Text('International'), icon: Icon(Symbols.public, size: 15)),
                  ButtonSegment(value: 'local', label: Text('Local'), icon: Icon(Symbols.flag, size: 15)),
                ],
                selected: {_category},
                onSelectionChanged: (s) => setState(() => _category = s.first),
              ),
              FilterChip(label: const Text('With activity only'), selected: _onlyWithBalance,
                  onSelected: (v) => setState(() => _onlyWithBalance = v)),
              SizedBox(width: phone ? double.infinity : 260,
                  child: SearchField(hint: 'Search creditors', onChanged: (v) => setState(() => _q = v))),
            ]),
            const SizedBox(height: 12),
            phone ? _cards(context) : _table(context),
          ],
        ]),
      );
    });
  }

  Widget _summary(BuildContext context, CreditorList l, bool phone) {
    final tiles = [
      _stat('INTERNATIONAL', money(l.internationalTzs, 'TZS'), 'Trade Creditors 2024', AppColors.violet),
      _stat('LOCAL', money(l.localTzs, 'TZS'), 'Trade Creditors 2025', AppColors.cyan),
      _stat('TOTAL OWED', money(l.internationalTzs + l.localTzs, 'TZS'), _asAt == null ? 'today' : 'as at ${formatDate(_asAt!)}', AppColors.coral),
      _stat('AWAITING DIRECTOR', '${l.pendingPayments}', 'payment request(s)', AppColors.amber),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      child: phone ? PhoneStatGrid(spacing: 12, children: tiles)
          : Row(children: [for (final (i, t) in tiles.indexed) ...[if (i > 0) const SizedBox(width: 18), Expanded(child: t)]]),
    );
  }

  Widget _stat(String label, String value, String sub, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
    const SizedBox(height: 5),
    Text(value, style: AppTheme.monoXs.copyWith(fontSize: 16, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
    Text(sub, style: AppTheme.bodySub.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
  ]);

  /// The ledgers must add up to Trade Creditors in the books.
  Widget _reconciliation(BuildContext context, CreditorList l) {
    final off = l.reconciliation.entries.where((e) => e.value.difference != 0).toList();
    final ok = off.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (ok ? AppColors.green : AppColors.amber).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (ok ? AppColors.green : AppColors.amber).withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(ok ? Symbols.verified : Symbols.warning, size: 16, color: ok ? AppColors.green : AppColors.amber),
        const SizedBox(width: 10),
        Expanded(child: Text(ok
            ? 'The creditor ledgers agree with Trade Creditors in the books.'
            : off.map((e) => '${e.key == 'international' ? 'International' : 'Local'} (${e.value.account}): books ${money(e.value.books, 'TZS')}, '
                'ledgers ${money(e.value.ledgers, 'TZS')} — difference ${money(e.value.difference, 'TZS')}').join('\n'),
            style: AppTheme.bodySub.copyWith(fontSize: 12, color: ok ? AppColors.green : AppColors.amber))),
      ]),
    );
  }

  Widget _table(BuildContext context) {
    final rows = _rows;
    final intl = _category == 'international';
    Widget head(String t, {int flex = 1, bool right = false}) => Expanded(flex: flex,
        child: Text(t, textAlign: right ? TextAlign.right : TextAlign.left, style: AppTheme.labelCaps.copyWith(fontSize: 9.5)));
    return Container(
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          height: 38, padding: const EdgeInsets.symmetric(horizontal: 16), color: context.pal.surface2,
          child: Row(children: [
            head('CREDITOR', flex: 4), head('TYPE', flex: 2),
            head('CREDIT', flex: 2, right: true), head('DEBIT', flex: 2, right: true),
            head('BALANCE', flex: 2, right: true), if (intl) head('IN TZS', flex: 2, right: true),
            head('LAST ACTIVITY', flex: 2, right: true),
          ]),
        ),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(28), child: Text(
              _onlyWithBalance ? 'No ${intl ? 'international' : 'local'} creditor has invoices, payments or an opening balance yet.' : 'No creditors.',
              style: AppTheme.bodySub)),
        for (final c in rows)
          InkWell(
            onTap: () => _open(c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.divider))),
              child: Row(children: [
                Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: AppTheme.bodySm.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (c.pendingPayments > 0)
                    Text('${c.pendingPayments} payment(s) awaiting Director · ${money(c.pendingAmount, c.currency)}',
                        style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: AppColors.amber), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                Expanded(flex: 2, child: Text('${c.type == 'vendor' ? 'Vendor' : 'Supplier'} · ${c.currency}',
                    style: AppTheme.bodySub.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: _num(context, money(c.totalCredit, c.currency))),
                Expanded(flex: 2, child: _num(context, money(c.totalDebit, c.currency))),
                Expanded(flex: 2, child: _num(context, money(c.balance, c.currency), bold: true,
                    color: c.balance < 0 ? AppColors.cyan : null)),
                if (intl) Expanded(flex: 2, child: _num(context, money(c.balanceTzs, 'TZS'))),
                Expanded(flex: 2, child: Text(c.lastActivity == null ? '—' : formatDate(c.lastActivity!), textAlign: TextAlign.right,
                    style: AppTheme.monoXs.copyWith(fontSize: 10.5))),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _num(BuildContext context, String v, {bool bold = false, Color? color}) => Text(v, textAlign: TextAlign.right,
      maxLines: 1, overflow: TextOverflow.ellipsis,
      style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: color ?? context.pal.text, fontWeight: bold ? FontWeight.w700 : null));

  Widget _cards(BuildContext context) {
    final rows = _rows;
    if (rows.isEmpty) {
      return Padding(padding: const EdgeInsets.all(24), child: Text('Nothing to show.', style: AppTheme.bodySub));
    }
    return Column(children: [
      for (final c in rows)
        PhoneRecordCard(
          margin: const EdgeInsets.only(bottom: 8),
          title: c.name,
          subtitle: '${c.type == 'vendor' ? 'Vendor' : 'Supplier'} · ${c.currency}',
          meta: [
            'credit ${money(c.totalCredit, c.currency)}',
            'paid ${money(c.totalDebit, c.currency)}',
            if (c.pendingPayments > 0) '${c.pendingPayments} awaiting Director',
          ],
          trailing: Text(money(c.balance, c.currency), style: AppTheme.bodyStrong.copyWith(fontSize: 13.5)),
          onTap: () => _open(c),
        ),
    ]);
  }
}

// ── Statement ────────────────────────────────────────────────────────────────

/// One creditor's ledger: their invoices (credit) against our payments
/// (debit), the running balance in their currency and TZS at each line's
/// rate; Excel (the accounts team's layout) and PDF; opening balance and
/// payment requests. Each line opens the records behind it.
class CreditorStatementScreen extends StatefulWidget {
  const CreditorStatementScreen({super.key, required this.type, required this.id, required this.name});
  final String type;
  final int id;
  final String name;

  @override
  State<CreditorStatementScreen> createState() => _CreditorStatementScreenState();
}

class _CreditorStatementScreenState extends State<CreditorStatementScreen> {
  CreditorStatement? _s;
  List<SupplierPayment> _pending = const [];
  String? _error;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait([
        CreditorService.instance.statement(widget.type, widget.id, from: _from, to: _to),
        CreditorService.instance.payments(status: 'pending_director', creditorType: widget.type, creditorId: widget.id),
      ]);
      if (mounted) setState(() { _s = r[0] as CreditorStatement; _pending = r[1] as List<SupplierPayment>; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  String get _slug => widget.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');

  Future<void> _requestPayment(CreditorStatement s) async {
    final c = s.creditor;
    final body = await showPaymentRequestDialog(context,
        title: 'Pay ${c.name}', creditorName: c.name, currency: c.currency,
        amount: s.closingBalance > 0 ? s.closingBalance : null,
        hint: 'Settles their oldest unpaid invoices first; anything beyond what\'s owed is an advance.');
    if (body == null || !mounted) return;
    try {
      await CreditorService.instance.requestPayment({if (widget.type == 'supplier') 'supplier_id': widget.id else 'vendor_id': widget.id, ...body});
      if (mounted) showSuccessToast(context, 'Payment sent to the Director for approval.');
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _editOpening(CreditorStatement s) async {
    final saved = await showDialog<bool>(context: context, builder: (dialogCtx) => _OpeningDialog(statement: s, type: widget.type, id: widget.id));
    if (saved == true) _load();
  }

  Future<void> _pickDate(bool from) async {
    final d = await showDatePicker(context: context, initialDate: (from ? _from : _to) ?? DateTime.now(),
        firstDate: DateTime(2015), lastDate: DateTime.now());
    if (d == null) return;
    setState(() => from ? _from = d : _to = d);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final canManage = hasAccountantAuthority(userRoleNotifier.value);
    return Scaffold(
      backgroundColor: context.pal.bg,
      body: SafeArea(child: s == null
          ? (_error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : LayoutBuilder(builder: (context, c) {
              final pad = c.maxWidth < 560 ? 16.0 : 24.0;
              final phone = isPhoneWidth(c.maxWidth);
              final cr = s.creditor;
              return RefreshIndicator(onRefresh: _load, child: ListView(padding: EdgeInsets.all(pad), children: [
                Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Symbols.arrow_back, size: 16), label: const Text('Creditors'))),
                TitleWithActions(
                  title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cr.name, style: AppTheme.pageTitle.copyWith(fontSize: 22), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text([
                      cr.isInternational ? 'International' : 'Local',
                      cr.type == 'vendor' ? 'vendor' : cr.kind,
                      cr.currency,
                      if (cr.country != null) cr.country!,
                      if (cr.contactPerson != null) cr.contactPerson!,
                      if (cr.email != null) cr.email!,
                      if (cr.phone != null) cr.phone!,
                    ].join(' · '), style: AppTheme.bodySub.copyWith(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                  actions: [
                    ConnectionsButton(type: widget.type, id: widget.id),
                    OutlinedButton.icon(
                      onPressed: () => downloadPdf(context, () => CreditorService.instance.statementXlsx(widget.type, widget.id, from: _from, to: _to), 'Creditor-Ledger-$_slug.xlsx'),
                      icon: const Icon(Symbols.table_view, size: 15), label: const Text('Excel')),
                    OutlinedButton.icon(
                      onPressed: () => downloadPdf(context, () => CreditorService.instance.statementPdf(widget.type, widget.id, from: _from, to: _to), 'Creditor-Ledger-$_slug.pdf'),
                      icon: const Icon(Symbols.picture_as_pdf, size: 15), label: const Text('PDF')),
                    if (canManage) ...[
                      OutlinedButton.icon(onPressed: () => _editOpening(s), icon: const Icon(Symbols.account_balance, size: 15),
                          label: Text(s.opening == null ? 'Opening balance' : 'Edit opening')),
                      FilledButton.icon(onPressed: () => _requestPayment(s), icon: const Icon(Symbols.payments, size: 15), label: const Text('Request payment')),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  SizedBox(width: 180, child: LabeledDateField(label: 'From', date: _from, placeholder: 'Start', onTap: () => _pickDate(true),
                      onClear: _from == null ? null : () { setState(() => _from = null); _load(); })),
                  SizedBox(width: 180, child: LabeledDateField(label: 'To', date: _to, placeholder: 'Today', onTap: () => _pickDate(false),
                      onClear: _to == null ? null : () { setState(() => _to = null); _load(); })),
                ]),
                const SizedBox(height: 14),
                _summary(context, s, phone),
                if (_pending.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final p in _pending)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.amber.withValues(alpha: 0.3))),
                      child: Row(children: [
                        Icon(Symbols.hourglass_top, size: 15, color: AppColors.amber),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${p.number}: ${money(p.amount, p.currency)} from ${p.paidFrom ?? 'the bank'} — awaiting the Director',
                            style: AppTheme.bodySub.copyWith(fontSize: 12, color: AppColors.amber), maxLines: 2, overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                ],
                const SizedBox(height: 14),
                phone ? _cards(context, s) : _ledgerTable(context, s),
              ]));
            })),
    );
  }

  Widget _summary(BuildContext context, CreditorStatement s, bool phone) {
    final cur = s.creditor.currency;
    final tiles = [
      _tile('OPENING B/F', money(s.openingBalance, cur), context.pal.text),
      _tile('TOTAL CREDIT', money(s.totalCredit, cur), context.pal.text),
      _tile('TOTAL DEBIT', money(s.totalDebit, cur), AppColors.teal),
      _tile('BALANCE', money(s.closingBalance, cur), s.closingBalance > 0 ? AppColors.coral : AppColors.green),
      if (cur != 'TZS') _tile('IN TZS (LAST RATE)', money(s.closingBalanceTzs, 'TZS'), context.pal.text),
      _tile('IN THE BOOKS', money(s.bookBalanceTzs, 'TZS'), context.pal.textMute),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      child: phone ? PhoneStatGrid(spacing: 12, children: tiles)
          : Row(children: [for (final (i, t) in tiles.indexed) ...[if (i > 0) const SizedBox(width: 16), Expanded(child: t)]]),
    );
  }

  Widget _tile(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.labelCaps.copyWith(fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
    const SizedBox(height: 5),
    Text(value, style: AppTheme.monoXs.copyWith(fontSize: 14, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
  ]);

  void _openSource(LedgerLine l) {
    if (l.sourceType.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ConnectionsScreen(type: l.sourceType, id: l.sourceId)));
  }

  Widget _ledgerTable(BuildContext context, CreditorStatement s) {
    final cur = s.creditor.currency;
    final fx = cur != 'TZS';
    Widget h(String t, {int flex = 2, bool right = true}) => Expanded(flex: flex,
        child: Text(t, textAlign: right ? TextAlign.right : TextAlign.left, style: AppTheme.labelCaps.copyWith(fontSize: 9.5)));
    Widget n(String v, {bool bold = false, Color? color}) => Expanded(flex: 2, child: Text(v, textAlign: TextAlign.right,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: color ?? context.pal.text, fontWeight: bold ? FontWeight.w700 : null)));
    String amt(double v) => v == 0 ? '' : money(v, cur).replaceFirst(RegExp(r'^[A-Za-z]+ '), '');

    return Container(
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          height: 38, padding: const EdgeInsets.symmetric(horizontal: 16), color: context.pal.surface2,
          child: Row(children: [
            h('DATE', right: false), h('NARRATION', flex: 4, right: false), h('REF', right: false),
            if (fx) h('XRATE'),
            h('DEBIT $cur'), h('CREDIT $cur'), h('BALANCE $cur'),
            if (fx) h('BALANCE TZS'),
          ]),
        ),
        if (s.from != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.divider))),
            child: Row(children: [
              Expanded(flex: 2, child: Text(formatDate(s.from!), style: AppTheme.monoXs.copyWith(fontSize: 10.5))),
              Expanded(flex: 4, child: Text('OPENING BALANCE b/f', style: AppTheme.bodySm.copyWith(fontSize: 12, fontWeight: FontWeight.w600))),
              const Spacer(flex: 2),
              if (fx) const Spacer(flex: 2),
              const Spacer(flex: 2), const Spacer(flex: 2),
              n(amt(s.openingBalance), bold: true),
              if (fx) n(money(s.openingBalanceTzs, 'TZS').replaceFirst('TSh ', '')),
            ]),
          ),
        if (s.entries.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text('No invoices or payments in this period.', style: AppTheme.bodySub)),
        for (final l in s.entries)
          InkWell(
            onTap: () => _openSource(l),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.divider))),
              child: Row(children: [
                Expanded(flex: 2, child: Text(l.date == null ? '' : formatDate(l.date!), style: AppTheme.monoXs.copyWith(fontSize: 10.5))),
                Expanded(flex: 4, child: Text(l.narration, style: AppTheme.bodySm.copyWith(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Text(l.ref ?? '', style: AppTheme.monoXs.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (fx) n(l.rate.toStringAsFixed(l.rate == l.rate.roundToDouble() ? 0 : 2)),
                n(amt(l.debit), color: AppColors.teal),
                n(amt(l.credit)),
                n(amt(l.balance), bold: true),
                if (fx) n(money(l.balanceTzs, 'TZS').replaceFirst('TSh ', '')),
              ]),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: context.pal.surface2,
          child: Row(children: [
            const Spacer(flex: 2),
            Expanded(flex: 4, child: Text('TOTAL', style: AppTheme.labelCaps.copyWith(fontSize: 10))),
            const Spacer(flex: 2),
            if (fx) const Spacer(flex: 2),
            n(amt(s.totalDebit), bold: true, color: AppColors.teal),
            n(amt(s.totalCredit), bold: true),
            n(amt(s.closingBalance), bold: true),
            if (fx) n(money(s.closingBalanceTzs, 'TZS').replaceFirst('TSh ', ''), bold: true),
          ]),
        ),
      ]),
    );
  }

  Widget _cards(BuildContext context, CreditorStatement s) {
    final cur = s.creditor.currency;
    return Column(children: [
      for (final l in s.entries)
        PhoneRecordCard(
          margin: const EdgeInsets.only(bottom: 8),
          title: l.narration,
          subtitle: [if (l.date != null) formatDate(l.date!), if (l.ref != null) l.ref!].join(' · '),
          meta: [
            if (l.credit > 0) 'credit ${money(l.credit, cur)}',
            if (l.debit > 0) 'paid ${money(l.debit, cur)}',
            if (cur != 'TZS') '@ ${l.rate}',
          ],
          trailing: Text(money(l.balance, cur), style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
          onTap: () => _openSource(l),
        ),
      if (s.entries.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('No invoices or payments in this period.', style: AppTheme.bodySub)),
    ]);
  }
}

/// What Hypermed owed this creditor (or had paid ahead, negative) at the
/// cut-over date. Posts to the books (opening-balance suspense).
class _OpeningDialog extends StatefulWidget {
  const _OpeningDialog({required this.statement, required this.type, required this.id});
  final CreditorStatement statement;
  final String type;
  final int id;
  @override
  State<_OpeningDialog> createState() => _OpeningDialogState();
}

class _OpeningDialogState extends State<_OpeningDialog> {
  late final Map<String, dynamic>? _o = widget.statement.opening;
  late final _amount = TextEditingController(text: _o == null ? '' : '${_o['amount']}');
  late final _rate = TextEditingController(text: _o == null ? '' : '${_o['exchange_rate']}');
  late final _notes = TextEditingController(text: _o?['notes'] as String? ?? '');
  late DateTime _asAt = DateTime.tryParse('${_o?['as_at'] ?? ''}') ?? DateTime(DateTime.now().year, 1, 1);
  bool _saving = false;
  String? _error;

  String get _cur => widget.statement.creditor.currency;

  @override
  void dispose() {
    for (final c in [_amount, _rate, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', ''));
    final rate = double.tryParse(_rate.text.replaceAll(',', ''));
    if (amount == null || amount == 0) {
      setState(() => _error = 'Enter the amount (negative if you had paid them in advance).');
      return;
    }
    if (_cur != 'TZS' && (rate == null || rate <= 0)) {
      setState(() => _error = 'Enter the exchange rate on that date.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await CreditorService.instance.saveOpening(widget.type, widget.id, asAt: _asAt, amount: amount,
          rate: _cur == 'TZS' ? null : rate, notes: _notes.text.trim().isEmpty ? null : _notes.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    title: Text('Opening balance · ${widget.statement.creditor.name}', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
    content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('What Hypermed owed them on the cut-over date, from the old ledgers. It posts to Trade Creditors '
          '(against the opening-balance account) and is the first line of their ledger.',
          style: AppTheme.bodySub.copyWith(fontSize: 12)),
      const SizedBox(height: 12),
      LabeledDateField(label: 'As at', date: _asAt, onTap: () async {
        final d = await showDatePicker(context: context, initialDate: _asAt, firstDate: DateTime(2015), lastDate: DateTime.now());
        if (d != null && mounted) setState(() => _asAt = d);
      }),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Amount owed ($_cur)', controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), hint: 'e.g. 120500'),
      if (_cur != 'TZS') ...[
        const SizedBox(height: 12),
        LabeledTextField(label: 'Exchange rate on that date (TZS per $_cur)', controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      ],
      const SizedBox(height: 12),
      LabeledTextField(label: 'Notes · optional', controller: _notes),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
      ],
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
    ],
  );
}
