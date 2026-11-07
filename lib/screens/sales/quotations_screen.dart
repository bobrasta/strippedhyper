import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userRoleNotifier, hasSalesApprovalAuthority, hasSalesEditAuthority, hasSalesIssueQuotationAuthority;
import '../../models/inventory_item.dart';
import '../../models/inventory_lot.dart';
import '../../models/location.dart';
import '../../models/quotation.dart';
import '../../models/sales_lead.dart';
import '../../services/auth_service.dart';
import '../../services/inventory_service.dart';
import '../../services/location_service.dart';
import '../../services/quotation_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/tin.dart';
import '../../utils/pdf_download.dart';
import '../../utils/whatsapp_share.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/common/sliver_table.dart';
import '../../widgets/sales/terms_editor.dart';
import '../../widgets/sales/line_items.dart';

// ── Status colours ─────────────────────────────────────────────────────────────
Color _statusColor(String status) => switch (status) {
  'draft'     => AppColors.textDim,
  'sent'      => AppColors.blue,
  'accepted'  => AppColors.teal,
  'rejected'  => AppColors.coral,
  'expired'   => AppColors.amber,
  'converted' => AppColors.violet,
  _           => AppColors.textDim,
};

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtAmount(int tzs) {
  if (tzs >= 1000000) return 'TSh ${(tzs / 1e6).toStringAsFixed(1)}M';
  if (tzs >= 1000)    return 'TSh ${(tzs / 1000).toStringAsFixed(0)}K';
  return 'TSh $tzs';
}

class QuotationsScreen extends StatefulWidget {
  const QuotationsScreen({super.key});

  @override
  State<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends State<QuotationsScreen> {
  List<Quotation> _all      = [];
  List<Quotation> _filtered = [];
  bool            _loading  = true;
  String?         _error;
  String?         _statusFilter;
  // Rows render in batches of 120; totals/counts still cover the whole period.
  static const _batch = 120;
  int             _showCount = _batch;
  Period          _period = Period.defaultPeriod;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known quotation list immediately
    // on a return visit instead of blanking to a spinner, then quietly
    // refresh in the background.
    final cached = QuotationService.cachedDefaultList;
    if (cached != null) {
      _all = cached;
      _loading = false;
      _applyFilter();
    }
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  Future<void> _openBuilder({SalesLead? prefillFromLead}) async {
    final created = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => QuotationBuilderScreen(prefillFromLead: prefillFromLead),
    ));
    if (created == true) _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      if (_all.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final data = await QuotationService.instance.list(period: _period);
      if (!mounted) return;
      setState(() { _all = data; _loading = false; });
      _applyFilter();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _showCount = _batch;
      _filtered = _all.where((qt) {
        final matchStatus = _statusFilter == null || qt.status == _statusFilter;
        final matchSearch = q.isEmpty ||
            qt.clientName.toLowerCase().contains(q) ||
            qt.quotationNumber.toLowerCase().contains(q);
        return matchStatus && matchSearch;
      }).toList();
    });
  }

  Future<void> _showDetailModal(Quotation qt) async {
    final reload = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => QuotationDetailScreen(quotationId: qt.id),
    ));
    if (reload == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      LayoutBuilder(builder: (ctx, cst) {
        final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
        final phone = isPhoneWidth(cst.maxWidth);
        final converted = _all.where((q) => q.status == 'converted').length;
        final totalQuoted = _all.fold<int>(0, (s, q) => s + q.totalAmount);
        final openValue = _all.where((q) => q.status == 'sent' || q.status == 'accepted').fold<int>(0, (s, q) => s + q.totalAmount);
        final chips = _StatusChips(
          current: _statusFilter,
          counts: {for (final s in ['draft', 'sent', 'accepted', 'rejected', 'converted']) s: _all.where((q) => q.status == s).length},
          total: _all.length,
          onChanged: (s) { setState(() { _statusFilter = s; _applyFilter(); }); },
        );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (phone) PhonePageHeader(
            title: 'Quotations',
            subtitle: '${_all.length} quotations · ${tshFromDouble(totalQuoted)} quoted · $converted converted',
            primary: PageAction(label: 'New quotation', shortLabel: 'New', icon: Symbols.add, onPressed: () => _openBuilder()),
            search: SearchField(hint: 'Client or QT number…', controller: _searchCtrl),
            filters: [PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); })],
            bottom: chips,
          ) else Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Quotations', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                const SizedBox(height: 3),
                Text('${_all.length} quotations · ${tshFromDouble(totalQuoted)} quoted · $converted converted to orders', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ])),
              const SizedBox(width: 12),
              SearchField(width: 240, hint: 'Client or QT number…', controller: _searchCtrl),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: () => _openBuilder(), icon: const Icon(Symbols.add, size: 16), label: const Text('New quotation')),
            ]),
          ),
          if (!phone) ...[
          const SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Row(children: [
              Expanded(child: chips),
              const SizedBox(width: 8),
              PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
            ]),
          ),
          ],
          const SizedBox(height: 12),
          // Everything below the filters scrolls as one; the table header pins.
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                // A background refresh failing while stale-but-valid
                // cached data is already showing shouldn't blow that away.
                : _error != null && _all.isEmpty
                    ? ErrorView(message: _error!, onRetry: _load)
                    : Builder(builder: (context) {
                        final table = _QuotationTable(items: _filtered, shown: _showCount, onLoadMore: () => setState(() => _showCount += _batch), onSelect: _showDetailModal, openValue: openValue, convertedCount: converted, totalCount: _all.length);
                        return CustomScrollView(slivers: phone ? table.phoneSlivers(context) : table.slivers(context, pad: pad));
                      }),
          ),
        ]);
      }),
    ]);
  }
}

// ── Status filter chips ────────────────────────────────────────────────────────

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.current, required this.counts, required this.total, required this.onChanged});
  final String? current;
  final Map<String, int> counts;
  final int total;
  final ValueChanged<String?> onChanged;

  static const _statuses = [
    ('draft', 'Draft'), ('sent', 'Sent'), ('accepted', 'Accepted'),
    ('rejected', 'Rejected'), ('converted', 'Converted'),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        _chip(context, null, 'All', total),
        const SizedBox(width: 8),
        ...(_statuses.expand((s) => [_chip(context, s.$1, s.$2, counts[s.$1] ?? 0), const SizedBox(width: 8)])),
      ],
    ),
  );

  Widget _chip(BuildContext ctx, String? value, String label, int count) {
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

// ── Quotation table ────────────────────────────────────────────────────────────

class _QuotationTable {
  const _QuotationTable({required this.items, required this.shown, required this.onLoadMore, required this.onSelect, required this.openValue, required this.convertedCount, required this.totalCount});
  final List<Quotation> items;
  final int shown;
  final VoidCallback onLoadMore;
  final ValueChanged<Quotation> onSelect;
  final int openValue;
  final int convertedCount;
  final int totalCount;

  String _validNote(Quotation qt) {
    if (qt.status == 'converted') return 'order raised';
    if (qt.validUntil == null) return '';
    final d = DateTime.tryParse(qt.validUntil!);
    if (d == null) return '';
    final days = d.difference(DateTime.now()).inDays;
    if (days < 0) return 'expired';
    return 'in $days days';
  }

  /// Phone list: a card per quotation, load-more, then the totals line.
  List<Widget> phoneSlivers(BuildContext context) {
    final n = shown < items.length ? shown : items.length;
    final total = items.fold<int>(0, (s, q) => s + q.totalAmount);
    if (items.isEmpty) {
      return [SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('No quotations found', style: AppTheme.bodySub))))];
    }
    return [
      SliverList(delegate: SliverChildBuilderDelegate((context, i) {
        final qt = items[i];
        final note = _validNote(qt);
        return PhoneRecordCard(
          title: qt.clientName,
          subtitle: [qt.quotationNumber, ?qt.clientContact].join(' · '),
          badge: _StatusBadge(qt.status, qt.statusLabel),
          lead: qt.needsApproval ? Icon(Symbols.hourglass_top, size: 18, color: AppColors.amber) : null,
          meta: [
            qt.createdAt.length >= 10 ? qt.createdAt.substring(0, 10) : qt.createdAt,
            if (qt.validUntil != null) 'valid to ${qt.validUntil}${note.isEmpty ? '' : ' ($note)'}',
          ],
          amount: tshFromDouble(qt.totalAmount),
          onTap: () => onSelect(qt),
        );
      }, childCount: n)),
      if (items.length > n)
        SliverToBoxAdapter(child: LoadMoreRow(shown: n, total: items.length,
            step: _QuotationsScreenState._batch, onTap: onLoadMore)),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Text('${tshFromDouble(total)} quoted · $convertedCount of $totalCount converted · '
            '${tshFromDouble(openValue)} still open', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
      )),
    ];
  }

  // Slivers for the page's single scroll view: pinned column header, lazy
  // rows, footer at the end (see sliverTable).
  List<Widget> slivers(BuildContext context, {required double pad}) {
    final total = items.fold<int>(0, (s, q) => s + q.totalAmount);
    return sliverTable(
      context,
      pad: pad,
      headerHeight: 38,
      header: Container(
          height: 38, padding: const EdgeInsets.symmetric(horizontal: 16),
          color: context.pal.surface2,
          child: Row(children: [
            SizedBox(width: 130, child: Text('QT NUMBER', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 3, child: Text('CLIENT', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(child: Text('AMOUNT', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(child: Text('STATUS', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(child: Text('CREATED', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(child: Text('VALID UNTIL', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            const SizedBox(width: 56),
          ]),
        ),
      itemCount: shown < items.length ? shown : items.length,
      totalCount: items.length,
      loadStep: _QuotationsScreenState._batch,
      onLoadMore: onLoadMore,
      emptyText: 'No quotations found',
      itemBuilder: (context, i) {
                  final qt = items[i];
                  final color = _statusColor(qt.status);
                  final note = _validNote(qt);
                  return GestureDetector(
                    onTap: () => onSelect(qt),
                    child: Container(
                      height: 56, padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        SizedBox(width: 130, child: Row(children: [
                          Container(width: 3, height: 26, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 9),
                          Expanded(child: Text(qt.quotationNumber, style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.textMute))),
                        ])),
                        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Row(children: [
                            if (qt.needsApproval) ...[Icon(Symbols.hourglass_top, size: 12, color: AppColors.amber), const SizedBox(width: 4)],
                            Flexible(child: Text(qt.clientName, style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ]),
                          if (qt.clientContact != null) Text(qt.clientContact!, style: AppTheme.bodySub.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                        Expanded(child: Text(tshFromDouble(qt.totalAmount), textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 13))),
                        Expanded(child: Align(alignment: Alignment.centerRight, child: _StatusBadge(qt.status, qt.statusLabel))),
                        Expanded(child: Text(qt.createdAt.length >= 10 ? qt.createdAt.substring(0, 10) : qt.createdAt, style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.textDim))),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(qt.validUntil ?? '—', style: AppTheme.monoXs.copyWith(fontSize: 11)),
                          if (note.isNotEmpty) Text(note, style: AppTheme.bodySub.copyWith(fontSize: 10, color: note == 'expired' ? AppColors.coral : context.pal.textDim)),
                        ])),
                        SizedBox(width: 56, child: Align(alignment: Alignment.centerRight, child: OutlinedButton(
                          onPressed: () => onSelect(qt),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 26)),
                          child: Text(qt.status == 'sent' ? 'Chase' : 'View', style: const TextStyle(fontSize: 11)),
                        ))),
                      ]),
                    ),
                  );
      },
      footer: Container(
          height: 46, padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: context.pal.surface2, border: Border(top: BorderSide(color: context.pal.divider))),
          child: Row(children: [
            SizedBox(width: 130, child: Text('TOTAL QUOTED', style: AppTheme.labelCaps.copyWith(fontSize: 10))),
            Expanded(flex: 3, child: Text('$convertedCount of $totalCount converted · ${tshFromDouble(openValue)} of pipeline still open', style: AppTheme.bodySub.copyWith(fontSize: 11))),
            Expanded(child: Text(tshFromDouble(total), textAlign: TextAlign.right, style: AppTheme.bodyStrong.copyWith(fontSize: 13.5))),
            const Expanded(child: SizedBox()), const Expanded(child: SizedBox()), const Expanded(child: SizedBox()), const SizedBox(width: 56),
          ]),
        ),
    );
  }
}

// ── Status badge ───────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status, this.label);
  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}


// ── Quotation detail (full page) ────────────────────────────────────────────────

const _docStages = ['draft', 'sent', 'accepted', 'converted'];

class QuotationDetailScreen extends StatefulWidget {
  const QuotationDetailScreen({super.key, required this.quotationId});
  final int quotationId;

  @override
  State<QuotationDetailScreen> createState() => _QuotationDetailScreenState();
}

class _QuotationDetailScreenState extends State<QuotationDetailScreen> {
  Quotation? _qt;
  bool _loading = true;
  bool _acting = false;
  bool _sharing = false;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known version of this exact quotation instantly if
    // we have one cached, then quietly refresh.
    final cached = QuotationService.cachedById[widget.quotationId];
    if (cached != null) { _qt = cached; _loading = false; }
    _load();
  }

  @override
  void didUpdateWidget(QuotationDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.quotationId != widget.quotationId) {
      // A different quotation — must not keep showing the previous one's
      // data under the new ID. Seed from that ID's own cache entry (which
      // may be null), then refresh.
      final cached = QuotationService.cachedById[widget.quotationId];
      setState(() { _qt = cached; _loading = cached == null; _error = null; });
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      if (_qt == null) _loading = true;
      _error = null;
    });
    try {
      final qt = await QuotationService.instance.get(widget.quotationId);
      if (mounted) setState(() { _qt = qt; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _viewPdf() async {
    if (_sharing || _qt == null) return;
    setState(() => _sharing = true);
    await downloadPdf(context, () => QuotationService.instance.pdfBytes(_qt!.id), '${_qt!.quotationNumber}.pdf');
    if (mounted) setState(() => _sharing = false);
  }

  Future<void> _shareWhatsApp() async {
    if (_sharing || _qt == null) return;
    setState(() => _sharing = true);
    try {
      final qt = _qt!;
      final url = await QuotationService.instance.shareLink(qt.id);
      final message = 'Hello, here is your quotation ${qt.quotationNumber} from Hypermed Health Care.\n'
          'Total: ${_fmtAmount(qt.totalAmount)}\n\nView / download: $url';
      await shareViaWhatsApp(phone: phoneDigitsFrom(qt.clientContact), message: message);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _act(Future<dynamic> Function() fn) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await fn();
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _rejectApproval() async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: const Text('Reject this quotation?'),
        content: SizedBox(width: 340, child: LabeledTextField(
          label: 'Reason', controller: reasonCtrl, maxLines: 3, hint: 'Recorded against the approval…',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: Text('Reject', style: TextStyle(color: AppColors.coral))),
        ],
      ),
    );
    if (confirm != true) return;
    await _act(() => QuotationService.instance.rejectApproval(_qt!.id,
        reason: reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : null));
  }

  Future<void> _convert() async {
    final qt = _qt!;
    DateTime? deliveryDate;
    int? locationId;
    List<Location> locations = [];
    String? loadError;
    try {
      locations = await LocationService.instance.list();
      if (locations.isNotEmpty) locationId = locations.first.id;
    } catch (e) {
      loadError = friendlyError(e);
    }
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: ctx.pal.surface1,
          title: Text('Convert to Sales Order', style: AppTheme.bodyStrong),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Convert ${qt.quotationNumber} into a Sales Order?', style: AppTheme.bodySm),
            const SizedBox(height: 12),
            if (loadError != null)
              Text(loadError, style: AppTheme.bodySub.copyWith(color: AppColors.coral))
            else ...[
              LabeledDropdown<int?>(
                label: 'Ship from location',
                value: locationId,
                items: locations.map<int?>((l) => l.id).toList(),
                displayBuilder: (id) => locations.firstWhere((l) => l.id == id).name,
                onChanged: (v) => setS(() => locationId = v),
              ),
            ],
            const SizedBox(height: 12),
            SalesDateField(
              label: 'Expected Delivery Date', selected: deliveryDate, firstDate: DateTime.now(),
              onPicked: (d) => setS(() => deliveryDate = d),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: locationId == null ? null : () => Navigator.pop(ctx, true),
                child: Text('Convert', style: TextStyle(color: AppColors.teal))),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted || locationId == null) return;
    await _act(() => QuotationService.instance.convert(
          qt.id, locationId: locationId!,
          expectedDeliveryDate: deliveryDate != null ? _isoDate(deliveryDate!) : null,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final qt = _qt;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) Navigator.of(context).pop(_changed); },
      child: Scaffold(
        backgroundColor: context.pal.bg,
        appBar: AppBar(
          backgroundColor: context.pal.surface1,
          foregroundColor: context.pal.text,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 4,
          title: qt == null ? const Text('Quotation') : Row(mainAxisSize: MainAxisSize.min, children: [
            Text(qt.quotationNumber, style: AppTheme.bodyStrong.copyWith(fontSize: 15)),
            const SizedBox(width: 8),
            _StatusBadge(qt.status, qt.statusLabel),
            if (qt.approvalStatus != 'not_required') ...[
              const SizedBox(width: 6),
              _StatusBadge(qt.approvalStatus == 'pending' ? 'pending' : qt.approvalStatus,
                  qt.approvalStatus == 'pending' ? 'approval pending' : 'approval ${qt.approvalStatus}'),
            ],
            const SizedBox(width: 12),
            Flexible(child: Text(
              '${qt.clientName}${qt.clientTin != null ? ' · TIN ${qt.clientTin}' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySub.copyWith(fontSize: 12))),
          ]),
          actions: qt == null ? null : [
            if (_sharing)
              const Padding(padding: EdgeInsets.only(right: 12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
            else ...[
              IconButton(onPressed: _viewPdf, icon: const Icon(Symbols.picture_as_pdf, size: 18), tooltip: 'PDF'),
              IconButton(onPressed: _shareWhatsApp, icon: const Icon(Symbols.share, size: 18), tooltip: 'Share link'),
            ],
            // Engineers prepare quotations; Sales converts them.
            if (hasSalesEditAuthority(userRoleNotifier.value))
              OutlinedButton.icon(
                onPressed: qt.status == 'accepted' ? _convert : null,
                icon: const Icon(Symbols.shopping_cart, size: 14),
                label: const Text('Convert to order'),
              ),
            const SizedBox(width: 16),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            // A background refresh erroring while stale-but-valid cached
            // data is already showing shouldn't blow that away — only the
            // "genuinely nothing to show" case surfaces the error screen.
            : qt == null
                ? (_error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : const SizedBox.shrink())
                : LayoutBuilder(builder: (ctx, cst) {
                        final wide = cst.maxWidth >= 900;
                        final left = _leftColumn(context, qt);
                        final right = SizedBox(width: wide ? 372 : double.infinity, child: _rightColumn(context, qt));
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: wide
                              ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  Expanded(child: left), const SizedBox(width: 16), right,
                                ]))
                              : Column(children: [left, const SizedBox(height: 16), right]),
                        );
                      }),
      ),
    );
  }

  Widget _leftColumn(BuildContext context, Quotation qt) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _stageCard(context, 'DOCUMENT STATUS',
            qt.status == 'rejected' ? -1 : _docStages.indexOf(qt.status), _docStages,
            (s) => s[0].toUpperCase() + s.substring(1))),
        if (qt.approvalStatus != 'not_required') ...[
          const SizedBox(width: 13),
          Expanded(child: _stageCard(context, 'APPROVAL STATUS — SEPARATE TRACK',
              qt.approvalStatus == 'pending' ? 0 : (qt.approvalStatus == 'approved' ? 1 : -1),
              const ['pending', 'approved', 'rejected'],
              (s) => s[0].toUpperCase() + s.substring(1), accent: AppColors.violet)),
        ],
      ]),
      const SizedBox(height: 13),
      Container(
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Symbols.receipt_long, size: 14, color: AppColors.teal),
                const SizedBox(width: 8),
                Expanded(child: Text('Quoted lines', style: AppTheme.bodyStrong.copyWith(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
                if (qt.discountAmount > 0 && qt.subtotal > 0)
                  Text('discount ${(qt.discountAmount / qt.subtotal * 100).toStringAsFixed(0)}%',
                      style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textMute)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(flex: 3, child: Text('ITEM', style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
                SizedBox(width: 44, child: Text('QTY', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: Text('UNIT', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
                const SizedBox(width: 8),
                SizedBox(width: 56, child: Text('DISC', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
                const SizedBox(width: 8),
                SizedBox(width: 96, child: Text('TOTAL', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
              ]),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
              ...qt.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(flex: 3, child: Text(item.description, style: AppTheme.bodySm.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  SizedBox(width: 44, child: Text('${item.quantity}', textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 12))),
                  const SizedBox(width: 8),
                  SizedBox(width: 90, child: Text(_fmtAmount(item.unitPrice), textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 12, color: context.pal.textDim))),
                  const SizedBox(width: 8),
                  SizedBox(width: 76, child: Text(
                      item.discountAmount > 0 ? '-${_fmtAmount(item.discountAmount)}' : item.discountPercent > 0 ? '${item.discountPercent.toStringAsFixed(0)}%' : '—',
                      textAlign: TextAlign.right,
                      style: AppTheme.monoXs.copyWith(fontSize: 11, color: item.discountAmount > 0 || item.discountPercent > 0 ? AppColors.amber : context.pal.textMute))),
                  const SizedBox(width: 8),
                  SizedBox(width: 96, child: Text(_fmtAmount(item.totalPrice), textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 12.5))),
                ]),
              )),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(color: context.pal.surface2, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14))),
            child: Row(children: [
              Expanded(child: Text('TOTAL QUOTED', style: AppTheme.labelCaps.copyWith(fontSize: 10.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Text(_fmtAmount(qt.totalAmount), style: AppTheme.kpiValue.copyWith(fontSize: 16)),
            ]),
          ),
        ]),
      ),
    ],
  );

  Widget _stageCard(BuildContext context, String title, int currentIdx, List<String> stages, String Function(String) label, {Color? accent}) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: accent != null ? accent.withValues(alpha: 0.05) : context.pal.surface1,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: accent != null ? accent.withValues(alpha: 0.28) : context.pal.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textMute)),
      const SizedBox(height: 9),
      Row(children: stages.asMap().entries.map((e) {
        final reached = currentIdx >= 0 && e.key <= currentIdx;
        final color = accent ?? AppColors.teal;
        return Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: reached ? color : context.pal.surface2,
              border: Border.all(color: reached ? color : context.pal.border, width: 1.5),
            )),
            if (e.key < stages.length - 1)
              Expanded(child: Container(width: double.infinity, height: 2, color: (currentIdx >= 0 && e.key < currentIdx) ? color : context.pal.border)),
          ]),
          const SizedBox(height: 5),
          Text(label(e.value), style: AppTheme.bodySub.copyWith(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]));
      }).toList()),
    ]),
  );

  Widget _rightColumn(BuildContext context, Quotation qt) {
    final isManager = hasSalesApprovalAuthority(userRoleNotifier.value);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (qt.approvalStatus == 'pending' && isManager) ...[
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: AppColors.violet.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.violet.withValues(alpha: 0.4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Symbols.verified, size: 15, color: AppColors.violet),
              const SizedBox(width: 8),
              Expanded(child: Text('Approval required', style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Text('sales.approve_order', style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute)),
            ]),
            const SizedBox(height: 9),
            Text(qt.approvalReason ?? 'This quotation needs manager approval before it can be sent to the client.',
                style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
            const SizedBox(height: 11),
            if (_acting)
              const Center(child: Padding(padding: EdgeInsets.all(6), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
            else
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => _act(() => QuotationService.instance.approve(qt.id)),
                    icon: const Icon(Symbols.check, size: 13), label: const Text('Approve'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: _rejectApproval,
                    icon: const Icon(Symbols.close, size: 13), label: const Text('Reject'))),
              ]),
          ]),
        ),
        const SizedBox(height: 14),
      ] else if (qt.approvalStatus == 'pending' && !isManager) ...[
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: AppColors.violet.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.violet.withValues(alpha: 0.28))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Symbols.hourglass_top, size: 16, color: AppColors.violet),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Awaiting sales_manager approval', style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
              const SizedBox(height: 4),
              Text('Read-only for you — only a sales manager can approve or reject.', style: AppTheme.bodySub.copyWith(fontSize: 11)),
            ])),
          ]),
        ),
        const SizedBox(height: 14),
      ] else if (qt.approvalStatus == 'rejected') ...[
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: AppColors.coral.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.coral.withValues(alpha: 0.3))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Symbols.cancel, size: 16, color: AppColors.coral),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rejected${qt.approvedByName != null ? ' by ${qt.approvedByName}' : ''}', style: AppTheme.bodySm.copyWith(fontSize: 12.5, color: AppColors.coral)),
              if (qt.rejectionReason != null) ...[
                const SizedBox(height: 4),
                Text(qt.rejectionReason!, style: AppTheme.bodySub.copyWith(fontSize: 11)),
              ],
            ])),
          ]),
        ),
        const SizedBox(height: 14),
      ],

      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CLIENT RESPONSE', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
          const SizedBox(height: 10),
          Row(children: [
            Icon(qt.status == 'accepted' ? Symbols.thumb_up : qt.status == 'rejected' ? Symbols.thumb_down : Symbols.schedule,
                size: 14, color: qt.status == 'accepted' ? AppColors.green : qt.status == 'rejected' ? AppColors.coral : context.pal.textMute),
            const SizedBox(width: 9),
            Expanded(child: Text(
              qt.status == 'accepted' ? 'Accepted${qt.acceptedAt != null ? ' · ${formatDate(DateTime.tryParse(qt.acceptedAt!) ?? DateTime.now())}' : ''}'
                  : qt.status == 'rejected' ? 'Rejected by client'
                  : 'No response recorded yet',
              style: AppTheme.bodySub.copyWith(fontSize: 11.5),
            )),
          ]),
          if (qt.status == 'sent' && hasSalesIssueQuotationAuthority(userRoleNotifier.value)) ...[
            const SizedBox(height: 11),
            _acting
                ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => _act(() => QuotationService.instance.accept(qt.id)),
                        icon: const Icon(Symbols.thumb_up, size: 12), label: const Text('Record accept'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(onPressed: () => _act(() => QuotationService.instance.reject(qt.id)),
                        icon: const Icon(Symbols.thumb_down, size: 12), label: const Text('Record reject'))),
                  ]),
          ],
        ]),
      ),
      const SizedBox(height: 14),

      if (qt.status == 'draft') ...[
        Row(children: [
          Expanded(child: _acting
              ? const SizedBox(height: 36, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
              : hasSalesIssueQuotationAuthority(userRoleNotifier.value)
                  ? FilledButton.icon(onPressed: () => _act(() => QuotationService.instance.send(qt.id)),
                      icon: const Icon(Symbols.send, size: 14), label: const Text('Send to client'))
                  // Prepared by an engineer: Sales was notified and sends it.
                  : Text('Sales sends it to the client — they have been notified.',
                      style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textMute))),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _acting ? null : () => _act(() => QuotationService.instance.delete(qt.id)),
              icon: Icon(Symbols.delete, size: 14, color: AppColors.coral), label: Text('Delete', style: TextStyle(color: AppColors.coral))),
        ]),
        const SizedBox(height: 14),
      ],

      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TRAIL', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
          const SizedBox(height: 11),
          ..._trail(qt).map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(e.$1, size: 12, color: e.$2),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(e.$3, style: AppTheme.bodySm.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (e.$5 != null) Text(formatDate(e.$5!), style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textMute)),
                ]),
                if (e.$4 != null) Text(e.$4!, style: AppTheme.bodySub.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),
          )),
        ]),
      ),
    ]);
  }

  // Real trail built entirely from timestamped fields already on the
  // record — created_at, sent_at, approved_at/rejection_reason,
  // accepted_at, and the linked sales order's created_at. No separate
  // audit-log table exists for quotations, so a client-side rejection has
  // no dedicated timestamp — falls back to updated_at for that one case.
  List<(IconData, Color, String, String?, DateTime?)> _trail(Quotation qt) {
    final events = <(IconData, Color, String, String?, DateTime?)>[
      (Symbols.add_circle, AppColors.textDim, 'Created${qt.createdByName != null ? ' by ${qt.createdByName}' : ''}', null, DateTime.tryParse(qt.createdAt)),
    ];
    if (qt.sentAt != null) {
      events.add((Symbols.send, AppColors.blue, 'Issued to client', 'PDF and share link generated', DateTime.tryParse(qt.sentAt!)));
    }
    if (qt.approvalStatus == 'approved' && qt.approvedAt != null) {
      events.add((Symbols.verified, AppColors.violet, 'Approved${qt.approvedByName != null ? ' by ${qt.approvedByName}' : ''}', qt.approvalReason, DateTime.tryParse(qt.approvedAt!)));
    } else if (qt.approvalStatus == 'rejected' && qt.approvedAt != null) {
      events.add((Symbols.cancel, AppColors.coral, 'Approval rejected${qt.approvedByName != null ? ' by ${qt.approvedByName}' : ''}', qt.rejectionReason, DateTime.tryParse(qt.approvedAt!)));
    }
    if (qt.acceptedAt != null) {
      events.add((Symbols.thumb_up, AppColors.green, 'Client accepted', null, DateTime.tryParse(qt.acceptedAt!)));
    } else if (qt.status == 'rejected') {
      events.add((Symbols.thumb_down, AppColors.coral, 'Rejected by client', null, qt.updatedAt != null ? DateTime.tryParse(qt.updatedAt!) : null));
    }
    if (qt.salesOrderId != null) {
      events.add((Symbols.shopping_cart, AppColors.teal, 'Converted to sales order', null, qt.convertedAt != null ? DateTime.tryParse(qt.convertedAt!) : null));
    }
    events.sort((a, b) => (a.$5 ?? DateTime(2000)).compareTo(b.$5 ?? DateTime(2000)));
    return events.reversed.toList();
  }
}

// ── Quotation builder (full page) ───────────────────────────────────────────────

class QuotationBuilderScreen extends StatefulWidget {
  const QuotationBuilderScreen({super.key, this.prefillFromLead});
  final SalesLead? prefillFromLead;

  @override
  State<QuotationBuilderScreen> createState() => _QuotationBuilderScreenState();
}

class _QuotationBuilderScreenState extends State<QuotationBuilderScreen> {
  final _clientCtrl  = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _notesCtrl   = TextEditingController();
  final _tinCtrl     = TextEditingController();
  final _terms       = TermsController();
  DateTime? _validUntil;
  String _currency   = 'TZS';
  bool   _saving     = false;
  final _lines = [LineItemEntry(), LineItemEntry()];
  List<InventoryItem> _invItems = [];
  Map<int, List<InventoryLot>> _lots = const {};
  Map<String, String> _errors  = {};
  // The creator's own discount ceiling — mirrors ApprovalService::evaluate()
  // server-side, which compares this same field against the quotation's
  // overall effective discount (discountAmount/subtotal), not any single
  // line's percentage. Null while loading or if the account has no ceiling
  // set (max_discount_percent nullable = no cap).
  double? _maxDiscountPercent;

  @override
  void initState() {
    super.initState();
    InventoryService.instance.openLots().then((lots) {
      if (mounted) setState(() => _lots = lots);
    }).catchError((_) {});
    InventoryService.instance.list().then((items) {
      if (mounted) setState(() => _invItems = items);
    });
    AuthService.instance.getProfile().then((profile) {
      final v = profile?['max_discount_percent'];
      if (mounted && v != null) setState(() => _maxDiscountPercent = (v as num).toDouble());
    });
    final lead = widget.prefillFromLead;
    if (lead != null) {
      _clientCtrl.text  = lead.hospital;
      _contactCtrl.text = lead.contact;
      if (lead.contactEmail != null) _emailCtrl.text = lead.contactEmail!;
    }
    for (final l in _lines) { _attachLineListeners(l); }
    _terms.load().then((_) { if (mounted) setState(() {}); });
  }

  // Fields don't otherwise trigger a rebuild as you type (the onChanged
  // passed into _LineItemRow is only wired to the item picker) — attach
  // listeners so the discount-ceiling banner and totals stay live.
  void _attachLineListeners(LineItemEntry l) {
    l.qtyCtrl.addListener(_recalc);
    l.priceCtrl.addListener(_recalc);
    l.discCtrl.addListener(_recalc);
  }

  void _recalc() { if (mounted) setState(() {}); }

  int get _subtotal => _lines.fold(0, (s, l) => s + l.gross);

  // Per-line TSh discounts (user, 2026-10-02).
  int get _discountAmount => _lines.fold(0, (s, l) => s + l.discount);

  double get _effectiveDiscountPercent => _subtotal > 0 ? (_discountAmount / _subtotal * 100) : 0;

  bool get _overDiscountCeiling =>
      _maxDiscountPercent != null && _effectiveDiscountPercent > _maxDiscountPercent!;

  @override
  void dispose() {
    _clientCtrl.dispose(); _contactCtrl.dispose();
    _emailCtrl.dispose();  _notesCtrl.dispose(); _tinCtrl.dispose();
    _terms.dispose();
    for (final l in _lines) { l.dispose(); }
    super.dispose();
  }

  bool _validate() {
    final errs = <String, String>{};
    if (_clientCtrl.text.trim().isEmpty) errs['client'] = 'Client name is required';
    final tinErr = tinError(_tinCtrl.text);
    if (tinErr != null) errs['tin'] = tinErr;
    final validLines = _lines.where((l) => l.descCtrl.text.trim().isNotEmpty).toList();
    if (validLines.isEmpty) errs['items'] = 'Add at least one line item with a description';
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      if (l.descCtrl.text.trim().isEmpty) continue; // empty rows are ignored
      final price = int.tryParse(l.priceCtrl.text.replaceAll(',', ''));
      if (price == null || price <= 0) errs['price_$i'] = 'Enter a valid price for item ${i + 1}';
      final qty = int.tryParse(l.qtyCtrl.text);
      if (qty == null || qty <= 0) errs['qty_$i'] = 'Enter a valid quantity for item ${i + 1}';
      final disc = l.discCtrl.text.trim();
      if (disc.isNotEmpty && int.tryParse(disc.replaceAll(',', '')) == null) {
        errs['items'] = 'Enter the discount for item ${i + 1} in TSh, e.g. 5000';
      } else if (l.discount < 0 || l.net < 0) {
        errs['items'] = 'The discount on item ${i + 1} is more than the line amount';
      }
    }
    setState(() => _errors = errs);
    return errs.isEmpty;
  }

  Future<Quotation?> _create() async {
    if (!_validate()) return null;
    final validLines = _lines.where((l) => l.descCtrl.text.trim().isNotEmpty).toList();
    return QuotationService.instance.create({
      'lead_id':        widget.prefillFromLead?.id,
      'client_name':    _clientCtrl.text.trim(),
      'client_contact': _contactCtrl.text.trim().isNotEmpty ? _contactCtrl.text.trim() : null,
      'client_email':   _emailCtrl.text.trim().isNotEmpty   ? _emailCtrl.text.trim()   : null,
      'client_tin':     normalizeTin(_tinCtrl.text),
      'valid_until':    _validUntil != null ? _isoDate(_validUntil!) : null,
      'currency':       _currency,
      'notes':          _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      'term_items':     _terms.toJson(),
      'items': validLines.map((l) => {
        'inventory_item_id': l.selectedItem?.id,
        'description':       l.descCtrl.text.trim(),
        'unit_of_measure':   l.uomCtrl.text.trim().isNotEmpty ? l.uomCtrl.text.trim() : 'pcs',
        'quantity':          int.tryParse(l.qtyCtrl.text) ?? 1,
        'unit_price':        int.tryParse(l.priceCtrl.text.replaceAll(',', '')) ?? 0,
        'discount_percent':  0,
        'discount_amount':   l.discount,
      }).toList(),
    });
  }

  // "Issue to client" chains create() + send() so a within-ceiling quotation
  // reaches the client in one action. Over the ceiling, send() would just
  // 422 immediately (ApprovalService blocks it server-side), so that case
  // only ever offers "Submit for approval" — create() alone, staying a
  // draft with approval_status=pending until a manager approves it from
  // the Quotations list.
  Future<void> _save({required bool issue}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final created = await _create();
      if (created == null) { setState(() => _saving = false); return; }
      if (issue) await QuotationService.instance.send(created.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      if (mounted) {
        final msg = e.toString();
        if (msg.contains('422') || msg.toLowerCase().contains('validation')) {
          setState(() => _errors = {'_server': 'Please check your inputs and try again.'});
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final over = _maxDiscountPercent != null && _subtotal > 0 && _overDiscountCeiling;
    return Scaffold(
      backgroundColor: context.pal.bg,
      appBar: AppBar(
        backgroundColor: context.pal.surface1,
        foregroundColor: context.pal.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 4,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('New quotation', style: AppTheme.bodyStrong.copyWith(fontSize: 15)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(5)),
            child: Text('draft', style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textMute)),
          ),
          if (widget.prefillFromLead != null) ...[
            const SizedBox(width: 10),
            Text('Converted from LEAD-${widget.prefillFromLead!.id.toString().padLeft(4, '0')}',
                style: AppTheme.bodySub.copyWith(fontSize: 11)),
          ],
        ]),
        actions: [
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _save(issue: false),
            icon: const Icon(Symbols.save, size: 14),
            label: Text(over ? 'Submit for approval' : 'Save draft'),
          ),
          const SizedBox(width: 8),
          if (!over && hasSalesIssueQuotationAuthority(userRoleNotifier.value))
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(issue: true),
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Symbols.send, size: 14),
              label: const Text('Issue to client'),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: LayoutBuilder(builder: (ctx, cst) {
        final wide = cst.maxWidth >= 900;
        final left = _leftColumn(context);
        final right = SizedBox(width: wide ? 340 : double.infinity, child: _rightColumn(context, over));
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          // Top-aligned, not IntrinsicHeight+stretch: text fields' intrinsic
          // height estimate runs under their laid-out height (focus halo),
          // which overflowed the left column by a fraction of a pixel.
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: left), const SizedBox(width: 16), right,
                ])
              : Column(children: [left, const SizedBox(height: 16), right]),
        );
      }),
    );
  }

  Widget _leftColumn(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_errors.containsKey('_server'))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.coral.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Symbols.error_outline, size: 14, color: AppColors.coral),
              const SizedBox(width: 8),
              Text(_errors['_server']!, style: TextStyle(fontSize: 12, color: AppColors.coral)),
            ]),
          ),
        ),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CLIENT', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
          const SizedBox(height: 11),
          Row(children: [
            Expanded(flex: 2, child: _formField('Client name *', _clientCtrl, 'Client or company', context,
                error: _errors['client'],
                onChanged: (_) { if (_errors.containsKey('client')) setState(() => _errors.remove('client')); })),
            const SizedBox(width: 12),
            Expanded(child: _formField('Client TIN *', _tinCtrl, '123-456-789', context,
                error: _errors['tin'],
                onChanged: (_) { if (_errors.containsKey('tin')) setState(() => _errors.remove('tin')); })),
            const SizedBox(width: 12),
            Expanded(child: _formField('Contact', _contactCtrl, 'Contact name', context)),
            const SizedBox(width: 12),
            Expanded(child: _formField('Email', _emailCtrl, 'client@company.tz', context)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Symbols.playlist_add, size: 14, color: AppColors.amber),
                const SizedBox(width: 8),
                Text('Line items', style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
                if (_errors.containsKey('items')) ...[
                  const SizedBox(width: 8),
                  Text(_errors['items']!, style: TextStyle(fontSize: 11, color: AppColors.coral)),
                ],
                const Spacer(),
                Text('picker draws from inventory · ${_lines.length} line${_lines.length == 1 ? '' : 's'}',
                    style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textMute)),
              ]),
              const SizedBox(height: 11),
              Row(children: [
                Expanded(flex: 3, child: Text('ITEM', style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
                SizedBox(width: kLineQtyW, child: Text('QTY', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
                const SizedBox(width: 8),
                SizedBox(width: kLinePriceW, child: Text('UNIT PRICE', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
                const SizedBox(width: 8),
                SizedBox(width: kLineDiscW, child: Text('DISCOUNT (TSH)', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
                const SizedBox(width: 8),
                SizedBox(width: kLineTotalW, child: Text('LINE TOTAL', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
                const SizedBox(width: 22),
              ]),
              Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
              ..._lines.asMap().entries.map((e) => LineItemTableRow(
                entry: e.value,
                invItems: _invItems,
                lots: _lots,
                onRemove: _lines.length > 1
                    ? () => setState(() { _lines[e.key].dispose(); _lines.removeAt(e.key); })
                    : null,
                onChanged: () => setState(() {}),
              )),
              GestureDetector(
                onTap: () => setState(() {
                  final l = LineItemEntry();
                  _attachLineListeners(l);
                  _lines.add(l);
                }),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  height: 32,
                  decoration: BoxDecoration(border: Border.all(color: context.pal.border, style: BorderStyle.solid), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Symbols.search, size: 13, color: context.pal.textDim),
                    const SizedBox(width: 7),
                    Text('Add item from inventory…', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                  ]),
                ),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
            decoration: BoxDecoration(color: context.pal.surface2, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: SalesDateField(
                label: 'Valid until', selected: _validUntil, firstDate: DateTime.now(),
                onPicked: (d) => setState(() => _validUntil = d),
              )),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: _formField('Notes', _notesCtrl, 'Printed on the quotation', context)),
              const SizedBox(width: 14),
              SizedBox(width: 90, child: _dropField('Currency', _currency, const ['TZS', 'USD', 'EUR', 'KES'],
                  (v) => setState(() => _currency = v), context)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: TermsEditor(controller: _terms),
      ),
    ],
  );

  Widget _rightColumn(BuildContext context, bool over) {
    final ceilColor = _maxDiscountPercent == null ? AppColors.green : (over ? AppColors.amber : AppColors.green);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_maxDiscountPercent != null) ...[
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: ceilColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ceilColor.withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(over ? Symbols.warning : Symbols.check_circle, size: 15, color: ceilColor),
              const SizedBox(width: 8),
              Expanded(child: Text('Your discount ceiling', style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Text('max_discount_percent', style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textMute)),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text('${_effectiveDiscountPercent.toStringAsFixed(0)}%', style: AppTheme.kpiValue.copyWith(fontSize: 26, color: ceilColor)),
              const SizedBox(width: 8),
              Text('of ${_maxDiscountPercent!.toStringAsFixed(0)}% allowed', style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.textMute)),
            ]),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: _maxDiscountPercent! > 0
                    ? (_effectiveDiscountPercent / _maxDiscountPercent!).clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 8, backgroundColor: context.pal.surface2,
                valueColor: AlwaysStoppedAnimation(ceilColor),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              over
                  ? 'Over your ceiling by ${(_effectiveDiscountPercent - _maxDiscountPercent!).toStringAsFixed(1)} points. Issuing still works, but this quotation will need sales_manager approval before the client can accept it.'
                  : 'Within your ceiling. This quotation issues straight to the client with no approval step.',
              style: AppTheme.bodySub.copyWith(fontSize: 11),
            ),
          ]),
        ),
        const SizedBox(height: 14),
      ],

      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TOTALS', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
          const SizedBox(height: 10),
          _totalsRow(context, 'Subtotal', tshFromDouble(_subtotal.toDouble())),
          _totalsRow(context, 'Discount', '- ${tshFromDouble(_discountAmount.toDouble())}', color: AppColors.amber),
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
          _totalsRow(context, 'TOTAL', tshFromDouble((_subtotal - _discountAmount).toDouble()), big: true),
        ]),
      ),
      const SizedBox(height: 14),

      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('WHAT HAPPENS ON ISSUE', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
          const SizedBox(height: 12),
          _issueStep(context, Symbols.send, over ? AppColors.textDim : AppColors.green,
              over ? 'Stays a draft' : 'Status → sent',
              over ? 'Submitted for approval instead — the client sees nothing until a manager approves it.' : 'Client gets the PDF and a share link.'),
          _issueStep(context, Symbols.verified, over ? AppColors.amber : AppColors.green,
              over ? 'Approval → pending' : 'Approval → not required',
              over ? 'Needs sales_manager sign-off — visible on the Quotations list until then.' : 'Within your ceiling, so no manager step is created.'),
          _issueStep(context, Symbols.lock, AppColors.violet, 'Price locks',
              'Line prices and discounts freeze on the document once it leaves draft.'),
          _issueStep(context, Symbols.block, context.pal.textDim, 'Order stays blocked',
              'Convert to order only unlocks once the client accepts.', last: true),
        ]),
      ),
    ]);
  }

  Widget _totalsRow(BuildContext context, String label, String value, {Color? color, bool big = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text(label, style: big
          ? AppTheme.labelCaps.copyWith(fontSize: 10.5)
          : AppTheme.bodySub.copyWith(fontSize: 11.5)),
      const SizedBox(width: 8),
      Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
      const SizedBox(width: 8),
      Text(value, style: (big ? AppTheme.kpiValue.copyWith(fontSize: 18) : AppTheme.monoSm.copyWith(fontSize: 12.5))
          .copyWith(color: color ?? context.pal.text)),
    ]),
  );

  Widget _issueStep(BuildContext context, IconData icon, Color color, String title, String note, {bool last = false}) => Padding(
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

// ── Small field helpers ────────────────────────────────────────────────────────

Widget _formField(String label, TextEditingController ctrl, String hint, BuildContext ctx,
    {int maxLines = 1, String? error, ValueChanged<String>? onChanged}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabeledTextField(label: label, controller: ctrl, maxLines: maxLines, onChanged: onChanged, hint: hint, hasError: error != null),
      if (error != null) ...[
        const SizedBox(height: 3),
        Text(error, style: TextStyle(fontSize: 11, color: AppColors.coral)),
      ],
    ]);

Widget _dropField(String label, String value, List<String> items,
    ValueChanged<String> onChanged, BuildContext ctx) =>
    LabeledDropdown<String>(label: label, value: value, items: items, displayBuilder: (v) => v, onChanged: onChanged);
