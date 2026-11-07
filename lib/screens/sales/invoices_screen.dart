import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userRoleNotifier, hasAccountantAuthority;
import '../../models/invoice.dart';
import '../../services/credit_note_service.dart';
import '../../services/finance_report_service.dart';
import '../../services/invoice_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/pdf_download.dart';
import '../../utils/whatsapp_share.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/common/sliver_table.dart';
import 'invoice_builder_screen.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

Color _statusColor(PaymentStatus s) => switch (s) {
  PaymentStatus.pending   => AppColors.textDim,
  PaymentStatus.sent      => AppColors.blue,
  PaymentStatus.partial   => AppColors.amber,
  PaymentStatus.paid      => AppColors.teal,
  PaymentStatus.overdue   => AppColors.coral,
  PaymentStatus.waived    => AppColors.violet,
  PaymentStatus.cancelled => AppColors.coral,
};

String _fmt(int tzs) {
  if (tzs >= 1000000) return 'TSh ${(tzs / 1e6).toStringAsFixed(1)}M';
  if (tzs >= 1000)    return 'TSh ${(tzs / 1000).toStringAsFixed(0)}K';
  return 'TSh $tzs';
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<Invoice>  _all      = [];
  List<Invoice>  _filtered = [];
  bool           _loading  = true;
  String?        _error;
  PaymentStatus? _statusFilter;
  // Rows render in batches — the full period is already loaded (totals and
  // chip counts cover all of it), this only limits how many rows are built.
  static const _batch = 120;
  int _showCount = _batch;
  Map<String, dynamic> _arAging = {};
  Period _period = Period.defaultPeriod;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known invoice list immediately
    // on a return visit instead of blanking to a spinner, then quietly
    // refresh in the background.
    final cached = InvoiceService.cachedDefaultList;
    if (cached != null) {
      _all = cached;
      _loading = false;
      _applyFilter();
    }
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      // Only show the blank/loading state when there's genuinely nothing to
      // show yet — a background refresh (or a return visit seeded from the
      // cache above) updates silently.
      if (_all.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        InvoiceService.instance.list(period: _period),
        FinanceReportService.instance.arAging(),
      ]);
      if (!mounted) return;
      setState(() { _all = results[0] as List<Invoice>; _arAging = results[1] as Map<String, dynamic>; _loading = false; });
      _applyFilter();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  void _sendReminders() {
    final needing = _all.where((i) => i.balanceDue > 0 && !i.isPaid && i.status != PaymentStatus.cancelled).toList();
    if (needing.isEmpty) {
      showSuccessToast(context, 'Nothing outstanding — no reminders needed.');
      return;
    }
    showSuccessToast(context, '${needing.length} invoice${needing.length == 1 ? '' : 's'} need${needing.length == 1 ? 's' : ''} a reminder — open one to send via WhatsApp or email.');
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _showCount = _batch;
      _filtered = _all.where((inv) {
        final matchStatus = _statusFilter == null || inv.effectiveStatus == _statusFilter;
        final matchSearch = q.isEmpty ||
            inv.invoiceNumber.toLowerCase().contains(q) ||
            (inv.displayName).toLowerCase().contains(q);
        return matchStatus && matchSearch;
      }).toList();
    });
  }

  Future<void> _newInvoice() async {
    final created = await Navigator.push<Invoice>(context, MaterialPageRoute(builder: (_) => const InvoiceBuilderScreen()));
    if (created == null || !mounted) return;
    showSuccessToast(context, 'Invoice ${created.invoiceNumber} created.');
    _load();
    _showDetailModal(created);
  }

  Future<void> _showDetailModal(Invoice inv) async {
    // Opens straight away from the row; the full invoice loads inside.
    final reload = await showInvoiceDetail(context, inv.id, preview: inv);
    if (reload && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      final phone = isPhoneWidth(cst.maxWidth);
      final totalRaised = _all.fold<int>(0, (s, i) => s + i.total);
      final outstanding = _all.fold<int>(0, (s, i) => s + i.balanceDue);
      final collected = totalRaised - outstanding;
      final collectionPct = totalRaised > 0 ? collected / totalRaised * 100 : 0.0;
      final overdueCount = _all.where((i) => i.isOverdue).length;
      final buckets = (_arAging['buckets'] as Map?) ?? {};
      num b(String k) => (buckets[k] as num?) ?? 0;
      final agingRows = [
        ('Not due', b('current'), AppColors.green),
        ('1–30 d', b('days_1_30'), AppColors.amber),
        ('31–60 d', b('days_31_60'), const Color(0xFFFF8A3D)),
        ('60 d +', b('days_61_90') + b('days_90_plus'), AppColors.coral),
      ];
      final maxAging = agingRows.fold<num>(1, (a, r) => r.$2 > a ? r.$2 : a);

      // Fixed: page head (title + totals, search, actions) and the filter
      // row. Everything else — KPI cards and the table — scrolls together,
      // with the table's column header pinned, so small screens keep most of
      // their height for rows.
      final chips = _StatusChips(current: _statusFilter, counts: {for (final s in PaymentStatus.values) s: _all.where((i) => i.effectiveStatus == s).length}, total: _all.length, onChanged: (s) => setState(() { _statusFilter = s; _applyFilter(); }));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (phone) PhonePageHeader(
          title: 'Invoices',
          subtitle: '${_all.length} invoices · ${tshFromDouble(outstanding)} outstanding'
              '${overdueCount > 0 ? ' · $overdueCount overdue' : ''}',
          primary: hasAccountantAuthority(userRoleNotifier.value)
              ? PageAction(label: 'New invoice', shortLabel: 'New', icon: Symbols.add, onPressed: _newInvoice)
              : null,
          secondary: [PageAction(label: 'Send reminders', icon: Symbols.notifications_active, onPressed: _sendReminders)],
          search: SearchField(hint: 'Client or INV number…', controller: _searchCtrl),
          filters: [PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); })],
          bottom: SingleChildScrollView(scrollDirection: Axis.horizontal, child: chips),
        ) else Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Invoices', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
              const SizedBox(height: 3),
              Text('${_all.length} invoices · ${tshFromDouble(totalRaised)} raised · ${tshFromDouble(outstanding)} outstanding'
                  '${overdueCount > 0 ? ' · $overdueCount overdue' : ' · none overdue'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySub.copyWith(fontSize: 12)),
            ])),
            const SizedBox(width: 12),
            SearchField(width: 240, hint: 'Client or INV number…', controller: _searchCtrl),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _sendReminders, icon: const Icon(Symbols.notifications_active, size: 15), label: const Text('Send reminders')),
            const SizedBox(width: 8),
            // Direct invoice — its own form, no quotation or sales order needed.
            // Same accountant-tier gate as InvoiceController@store.
            if (hasAccountantAuthority(userRoleNotifier.value))
              FilledButton.icon(onPressed: _newInvoice, icon: const Icon(Symbols.add, size: 16), label: const Text('New invoice')),
          ]),
        ),
        if (!phone) ...[
          const SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Row(children: [
              Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: chips)),
              const SizedBox(width: 8),
              PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              // A background refresh failing while stale-but-valid cached
              // data is already showing shouldn't blow that away — only
              // surface the error when there's nothing else to show.
              : _error != null && _all.isEmpty
                  ? ErrorView(message: _error!, onRetry: _load)
                  : CustomScrollView(slivers: [
                      SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: sideBySideOrStacked(phone, [
            Expanded(flex: 11, child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 15),
              decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Phones: the three figures shrink together rather than overflow.
                fitOnPhone(phone, Row(mainAxisSize: phone ? MainAxisSize.min : MainAxisSize.max, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('OUTSTANDING', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
                    const SizedBox(height: 7),
                    Text(tshFromDouble(outstanding), style: AppTheme.kpiValue.copyWith(fontSize: 24, color: AppColors.amber)),
                  ]),
                  const SizedBox(width: 26),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('COLLECTED', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
                    const SizedBox(height: 7),
                    Text(tshFromDouble(collected), style: AppTheme.kpiValue.copyWith(fontSize: 19, color: AppColors.green)),
                  ]),
                  if (phone) const SizedBox(width: 20) else const Spacer(),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('COLLECTION RATE', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
                    const SizedBox(height: 7),
                    Text('${collectionPct.toStringAsFixed(0)}%', style: AppTheme.kpiValue.copyWith(fontSize: 19)),
                  ]),
                ])),
                const SizedBox(height: 15),
                ClipRRect(borderRadius: BorderRadius.circular(4), child: Row(children: [
                  Expanded(flex: collected == 0 ? 1 : collected, child: Container(width: double.infinity, height: 8, color: collected == 0 ? context.pal.surface3 : AppColors.green)),
                  if (outstanding > 0) Expanded(flex: outstanding, child: Container(width: double.infinity, height: 8, color: AppColors.amber)),
                ])),
              ]),
            )),
            const SizedBox(width: 14),
            Expanded(flex: 10, child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('RECEIVABLE BY AGE', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
                const SizedBox(height: 10),
                ...agingRows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 58, child: Text(r.$1, style: AppTheme.bodySub.copyWith(fontSize: 11))),
                    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: r.$2 / maxAging, minHeight: 6, backgroundColor: context.pal.surface3, valueColor: AlwaysStoppedAnimation(r.$3)))),
                    const SizedBox(width: 10),
                    SizedBox(width: 58, child: Text(tshFromDouble(r.$2), textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.text))),
                  ]),
                )),
              ]),
            )),
          ]),
        ),
                        const SizedBox(height: 14),
                      ])),
                      ...(() {
                        final table = _InvoiceTable(items: _filtered, shown: _showCount, onLoadMore: () => setState(() => _showCount += _batch), onSelect: _showDetailModal, total: totalRaised, outstandingTotal: outstanding);
                        return phone ? table.phoneSlivers(context) : table.slivers(context, pad: pad);
                      })(),
                    ]),
        ),
      ]);
    });
  }
}

// ── Status chips ───────────────────────────────────────────────────────────────

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.current, required this.counts, required this.total, required this.onChanged});
  final PaymentStatus? current;
  final Map<PaymentStatus, int> counts;
  final int total;
  final ValueChanged<PaymentStatus?> onChanged;

  static const _statuses = [
    (PaymentStatus.pending,   'Pending'),
    (PaymentStatus.sent,      'Sent'),
    (PaymentStatus.partial,   'Partial'),
    (PaymentStatus.paid,      'Paid'),
    (PaymentStatus.overdue,   'Overdue'),
    (PaymentStatus.cancelled, 'Cancelled'),
  ];

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
    _chip(context, null, 'All', total),
    ..._statuses.map((s) => _chip(context, s.$1, s.$2, counts[s.$1] ?? 0)),
  ]);

  Widget _chip(BuildContext ctx, PaymentStatus? value, String label, int count) {
    final active = current == value;
    return GestureDetector(
      onTap: () => onChanged(active ? null : value),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.green.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: active ? AppColors.green.withValues(alpha: 0.5) : ctx.pal.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: AppTheme.bodySm.copyWith(fontSize: 12, color: active ? AppColors.green : ctx.pal.textMute)),
          const SizedBox(width: 6),
          Text('$count', style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: active ? AppColors.green : ctx.pal.textDim)),
        ]),
      ),
    );
  }
}

// ── Invoice table ──────────────────────────────────────────────────────────────

class _InvoiceTable {
  const _InvoiceTable({required this.items, required this.shown, required this.onLoadMore, required this.onSelect, required this.total, required this.outstandingTotal});
  final List<Invoice>          items;
  final int                    shown;
  final VoidCallback           onLoadMore;
  final ValueChanged<Invoice>  onSelect;
  final int total;
  final int outstandingTotal;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  // Column layout shared by header, rows and footer so everything lines up.
  // All proportional (flex) so the table always fits its width; the client
  // name ellipsizes and numbers scale down rather than overflow.
  static const int _fInv = 15, _fClient = 26, _fOrder = 13, _fMoney = 11, _fOut = 12, _fStatus = 11, _fDue = 12, _fAction = 9;
  static const double _gap = 14;

  // Single-line cell text that shrinks to fit a narrow column instead of
  // overflowing (used for money / dates).
  static Widget _fit(Widget child, {Alignment align = Alignment.centerRight}) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: align, child: child);

  // "03 Oct" + a relative note ("in 21 days" / "6 days late" / "settled").
  (String, String, Color?) _due(BuildContext context, Invoice inv) {
    final d = DateTime.tryParse(inv.dueDate);
    if (d == null) return ('—', 'not issued', null);
    final date = '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]}${d.year != DateTime.now().year ? ' ${d.year}' : ''}';
    if (inv.isPaid) return (date, 'settled', AppColors.green);
    final today = DateTime.now();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (days < 0) return (date, '${-days} day${days == -1 ? '' : 's'} late', AppColors.coral);
    if (days == 0) return (date, 'due today', AppColors.amber);
    return (date, 'in $days day${days == 1 ? '' : 's'}', null);
  }

  Widget _head(String t, {TextAlign align = TextAlign.left}) =>
      Text(t, textAlign: align, maxLines: 1, style: AppTheme.labelCaps.copyWith(fontSize: 10, letterSpacing: 1.1));

  /// Phone list: a card per invoice — client, number and order, status,
  /// what's still owed and when it's due.
  List<Widget> phoneSlivers(BuildContext context) {
    final n = shown < items.length ? shown : items.length;
    if (items.isEmpty) {
      return [SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('No invoices found', style: AppTheme.bodySub))))];
    }
    return [
      SliverList(delegate: SliverChildBuilderDelegate((context, i) {
        final inv = items[i];
        final (dueDate, dueNote, _) = _due(context, inv);
        return PhoneRecordCard(
          title: inv.displayName,
          subtitle: [inv.invoiceNumber, ?inv.salesOrderNumber].join(' · '),
          badge: _StatusBadge(inv.effectiveStatus),
          meta: ['due $dueDate ($dueNote)', 'total ${tshFromDouble(inv.total)}'],
          trailing: Text(inv.balanceDue > 0 ? tshFromDouble(inv.balanceDue) : 'Paid',
              style: AppTheme.bodyStrong.copyWith(fontSize: 14,
                  color: inv.balanceDue > 0 ? AppColors.amber : AppColors.green)),
          onTap: () => onSelect(inv),
        );
      }, childCount: n)),
      if (items.length > n)
        SliverToBoxAdapter(child: LoadMoreRow(shown: n, total: items.length,
            step: _InvoicesScreenState._batch, onTap: onLoadMore)),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Text('${tshFromDouble(total)} raised · ${tshFromDouble(outstandingTotal)} outstanding',
            style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
      )),
    ];
  }

  // Pieces for a CustomScrollView: the column header pins while the page
  // scrolls, rows are built lazily, footer closes the card.
  List<Widget> slivers(BuildContext context, {required double pad}) {
    final paidTotal = items.fold<int>(0, (s, i) => s + i.amountPaid);
    final visible = shown < items.length ? shown : items.length;
    final remaining = items.length - visible;
    final money = AppTheme.monoSm.copyWith(fontSize: 13);
    final side = BorderSide(color: context.pal.border);
    final header = Container(
      height: 44, padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(top: side, left: side, right: side, bottom: BorderSide(color: context.pal.divider)),
      ),
      child: Row(children: [
            Expanded(flex: _fInv, child: _head('INVOICE')),
            Expanded(flex: _fClient, child: _head('CLIENT')),
            Expanded(flex: _fOrder, child: _head('ORDER')),
            Expanded(flex: _fMoney, child: _fit(_head('TOTAL', align: TextAlign.right))),
            Expanded(flex: _fMoney, child: _fit(_head('PAID', align: TextAlign.right))),
            Expanded(flex: _fOut, child: _fit(_head('OUTSTANDING', align: TextAlign.right))),
            const SizedBox(width: _gap),
            Expanded(flex: _fStatus, child: _fit(_head('STATUS', align: TextAlign.right))),
            const SizedBox(width: _gap),
            Expanded(flex: _fDue, child: _head('DUE')),
            const Spacer(flex: _fAction),
          ]),
    );
    Widget rowFor(int i) {
                  final inv = items[i];
                  final st = inv.effectiveStatus;
                  final color = _badgeColor(context, st);
                  final (dueDate, dueNote, noteColor) = _due(context, inv);
                  final (actionLabel, actionDanger) = switch (st) {
                    PaymentStatus.paid || PaymentStatus.waived || PaymentStatus.cancelled => ('View', false),
                    PaymentStatus.partial => ('Record', false),
                    PaymentStatus.overdue => ('Remind', true),
                    _ => ('Remind', false),
                  };
      final row = InkWell(
                    onTap: () => onSelect(inv),
                    child: Container(
                      height: 64, padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(children: [
                        Expanded(flex: _fInv, child: Row(children: [
                          Container(width: 3, height: 28, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 14),
                          Expanded(child: Text(inv.invoiceNumber, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: AppTheme.monoSm.copyWith(fontSize: 12.5, color: context.pal.text))),
                        ])),
                        Expanded(flex: _fClient, child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(inv.displayName, style: AppTheme.bodySm.copyWith(fontSize: 14, color: context.pal.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                        )),
                        Expanded(flex: _fOrder, child: Text(inv.salesOrderNumber ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.textDim))),
                        Expanded(flex: _fMoney, child: _fit(Text(tshFromDouble(inv.total), maxLines: 1, style: money.copyWith(color: context.pal.text)))),
                        Expanded(flex: _fMoney, child: _fit(Text(tshFromDouble(inv.amountPaid), maxLines: 1,
                            style: money.copyWith(color: inv.amountPaid > 0 ? AppColors.green : context.pal.textDim)))),
                        Expanded(flex: _fOut, child: _fit(Text(tshFromDouble(inv.balanceDue), maxLines: 1,
                            style: money.copyWith(color: inv.balanceDue > 0 ? AppColors.amber : context.pal.textDim)))),
                        const SizedBox(width: _gap),
                        Expanded(flex: _fStatus, child: _fit(_StatusBadge(st))),
                        const SizedBox(width: _gap),
                        Expanded(flex: _fDue, child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _fit(Text(dueDate, maxLines: 1, style: AppTheme.monoXs.copyWith(fontSize: 12, color: context.pal.text)), align: Alignment.centerLeft),
                          const SizedBox(height: 2),
                          Text(dueNote, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodySub.copyWith(fontSize: 11, color: noteColor ?? context.pal.textMute)),
                        ])),
                        Expanded(flex: _fAction, child: Align(alignment: Alignment.centerRight, child: _fit(OutlinedButton(
                          onPressed: () => onSelect(inv),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            minimumSize: const Size(72, 34),
                            foregroundColor: actionDanger ? AppColors.coral : context.pal.text,
                            side: BorderSide(color: actionDanger ? AppColors.coral : context.pal.borderStrong),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(actionLabel, maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 12.5)),
                        )))),
                      ]),
                    ),
                  );
      return Container(
        decoration: BoxDecoration(
          color: context.pal.surface1,
          border: Border(left: side, right: side, bottom: BorderSide(color: context.pal.divider)),
        ),
        child: row,
      );
    }
    final footer = Container(
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        border: Border(left: side, right: side, bottom: side),
      ),
      child: Container(
          height: 58, padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(children: [
            Expanded(flex: _fInv, child: Text('TOTAL', style: AppTheme.labelCaps.copyWith(fontSize: 11, color: context.pal.text))),
            Expanded(flex: _fClient + _fOrder, child: Text('Outstanding is total − amount paid, computed per row', maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
            Expanded(flex: _fMoney, child: _fit(Text(tshFromDouble(total), maxLines: 1, style: money.copyWith(fontSize: 14, color: context.pal.text)))),
            Expanded(flex: _fMoney, child: _fit(Text(tshFromDouble(paidTotal), maxLines: 1, style: money.copyWith(fontSize: 14, color: AppColors.green)))),
            Expanded(flex: _fOut, child: _fit(Text(tshFromDouble(outstandingTotal), maxLines: 1, style: money.copyWith(fontSize: 14, color: AppColors.amber)))),
            const SizedBox(width: _gap),
            const Spacer(flex: _fStatus),
            const SizedBox(width: _gap),
            const Spacer(flex: _fDue + _fAction),
          ]),
        ),
    );
    return [
      SliverPersistentHeader(pinned: true, delegate: _PinnedBox(height: 44, pad: pad, child: header)),
      if (items.isEmpty)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          sliver: SliverToBoxAdapter(child: Container(
            height: 120, alignment: Alignment.center,
            decoration: BoxDecoration(color: context.pal.surface1, border: Border(left: side, right: side)),
            child: Text('No invoices found', style: AppTheme.bodySub),
          )),
        )
      else
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          sliver: SliverList(delegate: SliverChildBuilderDelegate((_, i) => rowFor(i), childCount: visible)),
        ),
      if (remaining > 0)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          sliver: SliverToBoxAdapter(child: LoadMoreRow(
            shown: visible, total: items.length, step: _InvoicesScreenState._batch, onTap: onLoadMore)),
        ),
      SliverPadding(padding: EdgeInsets.fromLTRB(pad, 0, pad, pad), sliver: SliverToBoxAdapter(child: footer)),
    ];
  }
}

/// Pinned sliver header of a fixed height, padded to the page gutter.
class _PinnedBox extends SliverPersistentHeaderDelegate {
  _PinnedBox({required this.height, required this.pad, required this.child});
  final double height, pad;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: context.pal.bg, padding: EdgeInsets.symmetric(horizontal: pad), child: child);
  @override
  bool shouldRebuild(_PinnedBox old) => old.child != child || old.pad != pad || old.height != height;
}

// Badge/marker colours for the invoice list (design: part paid = cyan,
// sent/pending = amber, overdue = coral, paid = green, draft-like = grey).
Color _badgeColor(BuildContext context, PaymentStatus s) => switch (s) {
  PaymentStatus.paid      => AppColors.green,
  PaymentStatus.partial   => AppColors.cyan,
  PaymentStatus.overdue   => AppColors.coral,
  PaymentStatus.sent      => AppColors.amber,
  PaymentStatus.pending   => AppColors.amber,
  PaymentStatus.waived    => AppColors.violet,
  PaymentStatus.cancelled => context.pal.textDim,
};

// ── Status badge ───────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final PaymentStatus status;
  @override
  Widget build(BuildContext context) {
    final color = _badgeColor(context, status);
    final label = status == PaymentStatus.partial ? 'PART PAID' : status.label.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, maxLines: 1, softWrap: false,
          style: AppTheme.monoXs.copyWith(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.1, color: color)),
    );
  }
}

// ── Invoice detail dialog ──────────────────────────────────────────────────────

/// Opens the invoice detail dialog from another screen (e.g. a customer's
/// invoice list). Returns true when the invoice changed.
///
/// Opens at once — from a cached copy, or the list row ([preview]) — and
/// swaps in the full invoice (line items, payments) when it arrives,
/// instead of waiting on the network before showing anything.
Future<bool> showInvoiceDetail(BuildContext context, int invoiceId, {Invoice? preview}) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _InvoiceDetailLoader(
        invoiceId: invoiceId, initial: InvoiceService.cachedById[invoiceId] ?? preview),
  );
  return changed == true;
}

class _InvoiceDetailLoader extends StatefulWidget {
  const _InvoiceDetailLoader({required this.invoiceId, this.initial});
  final int invoiceId;
  final Invoice? initial;
  @override
  State<_InvoiceDetailLoader> createState() => _InvoiceDetailLoaderState();
}

class _InvoiceDetailLoaderState extends State<_InvoiceDetailLoader> {
  late Invoice? _inv = widget.initial;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    InvoiceService.instance.get(widget.invoiceId).then((full) {
      if (mounted) setState(() { _inv = full; _loading = false; });
    }).catchError((Object e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showErrorToast(context, e);
      if (_inv == null) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inv = _inv;
    if (inv == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    return Stack(children: [
      // Rebuilt with the full invoice once it arrives.
      _InvoiceDetailDialog(key: ValueKey(_loading), inv: inv),
      if (_loading)
        const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
    ]);
  }
}

/// Record a payment against [inv] (All sales → Add payment). True when saved.
Future<bool> showRecordPayment(BuildContext context, Invoice inv) async =>
    await showDialog<bool>(context: context, builder: (_) => _PaymentModal(invoice: inv)) == true;

/// Credit notes for [inv] — issue one for returned goods (All sales →
/// Sell Return). True when something changed.
Future<bool> showCreditNotes(BuildContext context, Invoice inv) async =>
    await showDialog<bool>(context: context, builder: (_) => _CreditNotesDialog(invoice: inv)) == true;

class _InvoiceDetailDialog extends StatefulWidget {
  const _InvoiceDetailDialog({super.key, required this.inv});
  final Invoice inv;
  @override
  State<_InvoiceDetailDialog> createState() => _InvoiceDetailDialogState();
}

class _InvoiceDetailDialogState extends State<_InvoiceDetailDialog> {
  bool _acting = false;
  bool _sharing = false;

  Future<void> _viewPdf() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    await downloadPdf(context, () => InvoiceService.instance.pdfBytes(widget.inv.id), '${widget.inv.invoiceNumber}.pdf');
    if (mounted) setState(() => _sharing = false);
  }

  Future<void> _shareWhatsApp() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final inv = widget.inv;
      final url = await InvoiceService.instance.shareLink(inv.id);
      final message = 'Hello, here is invoice ${inv.invoiceNumber} from Hypermed Health Care.\n'
          'Total: ${_fmt(inv.total)}${inv.balanceDue > 0 ? ' (Balance due: ${_fmt(inv.balanceDue)})' : ' — Paid'}\n\n'
          'View / download: $url';
      await shareViaWhatsApp(phone: phoneDigitsFrom(inv.clientContact), message: message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _act(Future<dynamic> Function() fn) async {
    setState(() => _acting = true);
    try {
      await fn();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _acting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _pay() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PaymentModal(invoice: widget.inv),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _creditNotes() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _CreditNotesDialog(invoice: widget.inv),
    );
    if (changed == true && mounted) Navigator.pop(context, true);
  }

  Widget _infoTile(String label, String value) => SizedBox(
    width: 240,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10)),
        const SizedBox(height: 3),
        Text(value, style: AppTheme.bodySm),
      ]),
    ),
  );

  Widget _finRow(String label, int amount, {bool isTotal = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: isTotal ? AppTheme.bodyStrong : AppTheme.bodySub),
      Text(_fmt(amount), style: isTotal
          ? AppTheme.bodyStrong.copyWith(color: AppColors.amber, fontSize: 15)
          : AppTheme.bodySub),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final inv = widget.inv;
    final collectionPct = inv.total > 0 ? (inv.amountPaid / inv.total).clamp(0.0, 1.0) : 0.0;

    return Dialog(
      backgroundColor: context.pal.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 20, 0),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _statusColor(inv.status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Symbols.receipt_long, size: 18, color: _statusColor(inv.status)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inv.invoiceNumber,
                    style: AppTheme.pageTitle.copyWith(fontSize: 16)),
                const SizedBox(height: 2),
                Text(inv.displayName, style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ])),
              _StatusBadge(inv.effectiveStatus),
              const SizedBox(width: 12),
              if (_sharing)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else ...[
                Tooltip(
                  message: 'Download PDF',
                  child: GestureDetector(
                    onTap: _viewPdf,
                    child: Icon(Symbols.download, size: 18, color: context.pal.textDim),
                  ),
                ),
                const SizedBox(width: 14),
                Tooltip(
                  message: 'Share via WhatsApp',
                  child: GestureDetector(
                    onTap: _shareWhatsApp,
                    child: Icon(Symbols.share, size: 18, color: AppColors.teal),
                  ),
                ),
              ],
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Symbols.close, size: 18, color: context.pal.textDim),
              ),
            ]),
          ),

          // ── Collection progress ──
          if (inv.total > 0) Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Collected ${(collectionPct * 100).toStringAsFixed(0)}%',
                    style: AppTheme.bodySub.copyWith(fontSize: 11)),
                Text('${_fmt(inv.amountPaid)} of ${_fmt(inv.total)}',
                    style: AppTheme.bodySub.copyWith(fontSize: 11)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: collectionPct,
                  minHeight: 6,
                  backgroundColor: context.pal.surface3,
                  color: collectionPct >= 1 ? AppColors.teal : AppColors.amber,
                ),
              ),
            ]),
          ),

          Divider(height: 24, color: context.pal.border),

          // ── Body ──
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Info grid
              Wrap(spacing: 0, runSpacing: 0, children: [
                _infoTile('Client', inv.displayName),
                if (inv.salesOrderNumber != null)
                  _infoTile('Sales Order', inv.salesOrderNumber!),
                if (inv.clientContact != null)
                  _infoTile('Contact', inv.clientContact!),
                if (inv.clientEmail != null)
                  _infoTile('Email', inv.clientEmail!),
                if (inv.clientTin != null)
                  _infoTile('TIN', inv.clientTin!),
                _infoTile('Issue Date',
                    inv.issueDate.length >= 10 ? inv.issueDate.substring(0, 10) : inv.issueDate),
                _infoTile('Due Date',
                    inv.dueDate.length >= 10 ? inv.dueDate.substring(0, 10) : inv.dueDate),
                if (inv.payTermNumber != null)
                  _infoTile('Terms', '${inv.payTermNumber} ${inv.payTermType ?? 'days'}'),
                if (inv.shippingCharges > 0)
                  _infoTile('Delivery', _fmt(inv.shippingCharges)),
                _infoTile('Currency', inv.currency),
              ]),

              // Financials card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.pal.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.pal.border),
                ),
                child: Column(children: [
                  _finRow('Subtotal', inv.subtotal),
                  if (inv.taxAmount > 0) _finRow('Tax', inv.taxAmount),
                  const Divider(height: 16),
                  _finRow('Total', inv.total, isTotal: true),
                  if (inv.amountPaid > 0) ...[
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Paid', style: AppTheme.bodySub),
                      Text(_fmt(inv.amountPaid),
                          style: AppTheme.bodySub.copyWith(color: AppColors.teal)),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Balance Due', style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
                      Text(_fmt(inv.balanceDue),
                          style: AppTheme.bodyStrong.copyWith(
                            color: inv.balanceDue > 0 ? AppColors.coral : AppColors.teal,
                            fontSize: 13,
                          )),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(height: 20),

              // Line items
              Text('Line Items', style: AppTheme.bodyStrong),
              const SizedBox(height: 8),
              ...inv.lineItems.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.pal.surface2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: context.pal.border),
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.description, style: AppTheme.bodySm.copyWith(fontWeight: FontWeight.w500)),
                    // Unit · lot · expiry, as printed on the invoice PDF.
                    if (_lineFacts(item).isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(_lineFacts(item), maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: context.pal.textDim)),
                    ],
                  ])),
                  Text(
                    '${item.quantity.toStringAsFixed(item.quantity == item.quantity.truncate() ? 0 : 1)}'
                    ' × ${_fmt(item.unitPrice)}'
                    '${item.discount > 0 ? '  − ${_fmt(item.discount)} discount' : ''}',
                    style: AppTheme.bodySub.copyWith(fontSize: 11),
                  ),
                  const SizedBox(width: 12),
                  Text(_fmt(item.total),
                      style: AppTheme.bodySm.copyWith(
                          color: AppColors.amber, fontWeight: FontWeight.w600)),
                ]),
              )),

              // Instalment history — every payment against this invoice in
              // date order with the balance left after it (credit sales /
              // hire purchase are paid in pieces over months).
              if (inv.payments.isNotEmpty) ...[
                const SizedBox(height: 20),
                _InstalmentHistory(inv: inv),
              ],

              if (inv.notes != null) ...[
                const SizedBox(height: 16),
                Text('Notes', style: AppTheme.bodyStrong),
                const SizedBox(height: 4),
                Text(inv.notes!, style: AppTheme.bodySub),
              ],
            ]),
          )),

          // ── Footer actions ──
          if (inv.canSend || inv.canPay || inv.canCancel || inv.status != PaymentStatus.cancelled)
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.pal.border)),
              ),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (inv.canSend)
                  AppButton(
                    label: 'Send Invoice', icon: Symbols.send,
                    variant: BtnVariant.primary,
                    onPressed: _acting ? null
                        : () => _act(() => InvoiceService.instance.send(inv.id)),
                  ),
                if (inv.canPay)
                  AppButton(
                    label: 'Record Payment', icon: Symbols.payments,
                    variant: BtnVariant.primary,
                    onPressed: _acting ? null : _pay,
                  ),
                if (inv.status != PaymentStatus.cancelled)
                  AppButton(
                    label: 'Credit Note', icon: Symbols.receipt_long,
                    variant: BtnVariant.ghost,
                    onPressed: _acting ? null : _creditNotes,
                  ),
                if (inv.canCancel)
                  AppButton(
                    label: 'Cancel Invoice', icon: Symbols.cancel,
                    variant: BtnVariant.ghost,
                    onPressed: _acting ? null
                        : () => _act(() => InvoiceService.instance.cancel(inv.id)),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ── Record Payment modal ───────────────────────────────────────────────────────

class _PaymentModal extends StatefulWidget {
  const _PaymentModal({required this.invoice});
  final Invoice invoice;
  @override
  State<_PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<_PaymentModal> {
  final _amtCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  DateTime _paidAt = DateTime.now();
  final _noteCtrl= TextEditingController();
  String _method = 'cash';
  bool   _saving = false;

  @override
  void initState() {
    super.initState();
    _amtCtrl.text = widget.invoice.balanceDue.toString();
  }

  @override
  void dispose() {
    _amtCtrl.dispose(); _refCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amtCtrl.text.replaceAll(',', '')) ?? 0;
    if (amount <= 0 || _saving) return;
    setState(() => _saving = true);
    try {
      await InvoiceService.instance.recordPayment(widget.invoice.id, {
        'amount':         amount,
        'payment_method': _method,
        'reference':      _refCtrl.text.trim().isNotEmpty ? _refCtrl.text.trim() : null,
        'paid_at':        _paidAt.toIso8601String().substring(0, 10),
        'notes':          _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  // Hand-built card inside showDialog, not a Dialog — the Material wrapper
  // is what its TextFields need.
  Widget build(BuildContext context) => Material(type: MaterialType.transparency, child: GestureDetector(
    onTap: () => Navigator.of(context).pop(),
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 420,
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(children: [
                Icon(Symbols.payments, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text('Record Payment — ${widget.invoice.invoiceNumber}',
                    style: AppTheme.bodyStrong)),
                GestureDetector(onTap: () => Navigator.of(context).pop(),
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Balance due: ${_fmt(widget.invoice.balanceDue)}',
                  style: AppTheme.bodySub.copyWith(color: AppColors.coral, fontSize: 12)),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: _field('Amount *', _amtCtrl, context, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: LabeledDateField(
                    label: 'Date *', date: _paidAt,
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: _paidAt,
                          firstDate: DateTime(2020), lastDate: DateTime.now());
                      if (d != null) setState(() => _paidAt = d);
                    },
                  )),
                ]),
                const SizedBox(height: 12),
                LabeledDropdown<String>(
                  label: 'Payment method',
                  value: _method,
                  items: const ['cash', 'bank_transfer', 'mobile_money', 'cheque'],
                  displayBuilder: (v) => const {'cash': 'Cash', 'bank_transfer': 'Bank transfer',
                      'mobile_money': 'Mobile money', 'cheque': 'Cheque'}[v]!,
                  onChanged: (v) => setState(() => _method = v),
                ),
                const SizedBox(height: 12),
                _field('Reference / Transaction ID', _refCtrl, context,
                    hint: 'Cheque no., M-Pesa ref…'),
                const SizedBox(height: 12),
                _field('Notes', _noteCtrl, context, maxLines: 2),
              ]),
            ),
            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
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
                      : Text('Save Payment', style: AppTheme.bodyStrong.copyWith(
                          color: const Color(0xFF06120F), fontSize: 13)))),
                )),
              ]),
            ),
          ]),
        ),
      )),
    ),
  ));
}

Widget _field(String label, TextEditingController ctrl, BuildContext ctx,
    {String? hint, int maxLines = 1, bool numeric = false}) =>
  LabeledTextField(label: label, controller: ctrl, maxLines: maxLines,
      keyboardType: numeric ? TextInputType.number : TextInputType.text, hint: hint);

// ── Credit Notes dialog ──────────────────────────────────────────────────────

class _CreditNotesDialog extends StatefulWidget {
  const _CreditNotesDialog({required this.invoice});
  final Invoice invoice;
  @override
  State<_CreditNotesDialog> createState() => _CreditNotesDialogState();
}

class _CreditNotesDialogState extends State<_CreditNotesDialog> {
  List<CreditNote> _notes = [];
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await CreditNoteService.instance.list(widget.invoice.id);
      if (mounted) setState(() { _notes = list; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)))); }
    }
  }

  Future<void> _newCreditNote() async {
    final reasonCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final go = await showDialog<bool>(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: Text('New Credit Note', style: AppTheme.cardTitle),
      content: SizedBox(width: 340, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Balance due: ${_fmt(widget.invoice.balanceDue)}', style: AppTheme.bodySub.copyWith(fontSize: 12)),
        const SizedBox(height: 12),
        LabeledTextField(label: 'Reason', controller: reasonCtrl),
        const SizedBox(height: 12),
        LabeledTextField(label: 'Amount', controller: amountCtrl, keyboardType: TextInputType.number),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Create')),
      ],
    ));
    if (go != true) return;
    final amount = int.tryParse(amountCtrl.text.trim());
    if (reasonCtrl.text.trim().isEmpty || amount == null || amount <= 0) return;
    try {
      await CreditNoteService.instance.create(widget.invoice.id, reason: reasonCtrl.text.trim(), amount: amount);
      _changed = true;
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _approve(CreditNote n) async {
    try {
      await CreditNoteService.instance.approve(n.id);
      _changed = true;
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _apply(CreditNote n) async {
    try {
      await CreditNoteService.instance.apply(n.id);
      _changed = true;
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Color _statusColor(String s) => switch (s) {
    'draft'    => AppColors.textMute,
    'approved' => AppColors.amber,
    'applied'  => AppColors.teal,
    _          => AppColors.textMute,
  };

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: true,
    onPopInvokedWithResult: (didPop, _) {},
    child: Dialog(
      backgroundColor: context.pal.surface1,
      child: Container(
        width: 460,
        constraints: const BoxConstraints(maxHeight: 480),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Symbols.receipt_long, size: 18, color: AppColors.teal),
            const SizedBox(width: 10),
            Expanded(child: Text('Credit Notes — ${widget.invoice.invoiceNumber}', style: AppTheme.bodyStrong)),
            TextButton.icon(onPressed: _newCreditNote, icon: const Icon(Symbols.add, size: 16), label: const Text('New')),
            GestureDetector(onTap: () => Navigator.of(context).pop(_changed),
                child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
          ]),
          const Divider(height: 24),
          Flexible(
            child: _loading
                ? const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : _notes.isEmpty
                    ? Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('No credit notes on this invoice.', style: AppTheme.bodySub)))
                    : SingleChildScrollView(
                        child: Column(children: _notes.map((n) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.pal.border)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(n.creditNoteNumber, style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(color: _statusColor(n.status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                                child: Text(n.status, style: AppTheme.monoXs.copyWith(color: _statusColor(n.status), fontSize: 10)),
                              ),
                              const Spacer(),
                              Text(_fmt(n.amount), style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
                            ]),
                            const SizedBox(height: 4),
                            Text(n.reason, style: AppTheme.bodySm.copyWith(fontSize: 12)),
                            if (n.status == 'draft' || n.status == 'approved') ...[
                              const SizedBox(height: 8),
                              Wrap(spacing: 6, children: [
                                if (n.status == 'draft')
                                  TextButton(onPressed: () => _approve(n), child: const Text('Approve')),
                                if (n.status == 'approved')
                                  TextButton(onPressed: () => _apply(n), child: const Text('Apply')),
                              ]),
                            ],
                          ]),
                        )).toList()),
                      ),
          ),
        ]),
      ),
    ),
  );
}


class _InstalmentHistory extends StatelessWidget {
  const _InstalmentHistory({required this.inv});
  final Invoice inv;

  static DateTime? _date(String s) => DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s);

  @override
  Widget build(BuildContext context) {
    final pays = [...inv.payments]..sort((a, b) => a.paidAt.compareTo(b.paidAt));
    final paid = pays.fold<int>(0, (s, p) => s + p.amount);
    final pct = inv.total > 0 ? (paid / inv.total).clamp(0.0, 1.0) : 0.0;
    final last = _date(pays.last.paidAt);
    final sinceLast = last == null ? null : DateTime.now().difference(last).inDays;
    // Balance after each payment and days since the previous one, worked
    // out up front so rows don't depend on build order.
    final rows = <({Payment p, int balance, int? gap})>[];
    var running = inv.total;
    DateTime? prev;
    for (final p in pays) {
      running -= p.amount;
      final d = _date(p.paidAt);
      rows.add((p: p, balance: running < 0 ? 0 : running, gap: (prev != null && d != null) ? d.difference(prev).inDays : null));
      prev = d ?? prev;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Instalments', style: AppTheme.bodyStrong),
        const SizedBox(width: 8),
        Text('${pays.length} payment${pays.length == 1 ? '' : 's'} · ${(pct * 100).toStringAsFixed(0)}% paid',
            style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
        const Spacer(),
        if (inv.balanceDue > 0 && sinceLast != null)
          Text('last payment $sinceLast day${sinceLast == 1 ? '' : 's'} ago',
              style: AppTheme.bodySub.copyWith(fontSize: 11, color: sinceLast > 60 ? AppColors.coral : null)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
          value: pct, minHeight: 6, backgroundColor: context.pal.surface3, valueColor: AlwaysStoppedAnimation(AppColors.green))),
      const SizedBox(height: 10),
      for (var i = 0; i < rows.length; i++) Builder(builder: (context) {
        final (:p, :balance, :gap) = rows[i];
        final isDeposit = i == 0 && (p.notes ?? '').toLowerCase().startsWith('deposit');
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.pal.surface2,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: context.pal.border),
          ),
          child: Row(children: [
            Container(
              width: 26, height: 26, alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.teal.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Text('${i + 1}', style: AppTheme.monoXs.copyWith(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${isDeposit ? 'Deposit' : 'Instalment ${i + 1}'} · ${p.paidAt.length >= 10 ? p.paidAt.substring(0, 10) : p.paidAt}'
                  '${gap != null ? ' · $gap days after previous' : ''}',
                  style: AppTheme.bodySm.copyWith(fontSize: 12)),
              Text('${p.paymentNumber} · ${p.methodLabel}${p.reference != null ? ' · ${p.reference}' : ''}',
                  style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmt(p.amount), style: AppTheme.bodySm.copyWith(color: AppColors.teal, fontWeight: FontWeight.w600)),
              Text('balance ${_fmt(balance)}', style: AppTheme.bodySub.copyWith(fontSize: 10)),
            ]),
          ]),
        );
      }),
    ]);
  }
}

String _lineFacts(InvoiceLineItem item) => [
  if ((item.unitOfMeasure ?? '').isNotEmpty) item.unitOfMeasure!,
  if ((item.lotNumber ?? '').isNotEmpty) 'Lot ${item.lotNumber}',
  if (item.expiryDate != null && DateTime.tryParse(item.expiryDate!) != null)
    'Exp ${formatDate(DateTime.parse(item.expiryDate!))}',
].join(' · ');
