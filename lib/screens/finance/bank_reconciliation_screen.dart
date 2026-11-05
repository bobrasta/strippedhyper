import 'dart:io' show Platform;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/bank_reconciliation.dart';
import '../../services/bank_reconciliation_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/responsive.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/phone_layout.dart';

class BankReconciliationScreen extends StatefulWidget {
  const BankReconciliationScreen({super.key});

  @override
  State<BankReconciliationScreen> createState() => _BankReconciliationScreenState();
}

class _BankReconciliationScreenState extends State<BankReconciliationScreen> {
  List<BankReconciliation> _recons = [];
  bool    _loading = true;
  String? _error;
  bool    _showCreate = false;
  BankReconciliation? _selected;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — same reasoning as MachineListScreen's own
    // fix: show the last-known list instantly on a fresh mount (this widget
    // isn't kept alive across navigation), then quietly refresh.
    final cached = BankReconciliationService.cachedDefaultList;
    if (cached != null) { _recons = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      // Only show the blank/shimmer state when there's genuinely nothing
      // to show yet — a background refresh of an already-populated list
      // (or a return visit seeded from the cache above) updates silently.
      if (_recons.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final recons = await BankReconciliationService.instance.list();
      if (!mounted) return;
      setState(() { _recons = recons; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _openDetail(BankReconciliation r) async {
    try {
      final fresh = await BankReconciliationService.instance.get(r.id);
      if (mounted) setState(() => _selected = fresh);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      return _ReconciliationDetail(
        recon: _selected!,
        onBack: () => setState(() => _selected = null),
        onChanged: (r) => setState(() => _selected = r),
      );
    }

    return Stack(children: [
      LayoutBuilder(builder: (ctx, cst) {
        final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
        return RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(pad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Bank Reconciliation', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                  const SizedBox(height: 3),
                  Text('Match bank statements to system records', style: AppTheme.bodySub.copyWith(fontSize: 12)),
                ])),
                FilledButton.icon(onPressed: () => setState(() => _showCreate = true), icon: const Icon(Symbols.add, size: 16), label: const Text('New reconciliation')),
              ]),
              const SizedBox(height: 20),
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 48), child: CircularProgressIndicator(strokeWidth: 2)))
              // A background refresh failing while stale-but-valid cached
              // data is already showing shouldn't blow that away — only the
              // "genuinely nothing to show" case surfaces the error screen.
              else if (_error != null && _recons.isEmpty)
                ErrorView(message: _error!, onRetry: _load)
              else if (_recons.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('No reconciliations yet', style: TextStyle(color: context.pal.textMute))))
              else
                AdaptiveColumns(wideCols: 2, mediumCols: 2, narrowCols: 1, children: _recons.map((r) => _ReconCard(
                  recon: r, onTap: () => _openDetail(r),
                )).toList()),
            ]),
          ),
        );
      }),
      if (_showCreate)
        _NewReconDialog(
          onClose: () => setState(() => _showCreate = false),
          onSaved: () { setState(() => _showCreate = false); _load(); },
        ),
    ]);
  }
}

class _ReconCard extends StatelessWidget {
  const _ReconCard({required this.recon, required this.onTap});
  final BankReconciliation recon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final diff = recon.totals.difference;
    final ok = diff == 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: context.pal.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Symbols.account_balance, size: 16, color: context.pal.textMute),
            const SizedBox(width: 8),
            Expanded(child: Text('${recon.periodFrom} → ${recon.periodTo}', style: AppTheme.bodyStrong.copyWith(fontSize: 13))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (recon.isComplete ? AppColors.teal : AppColors.amber).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(recon.isComplete ? 'Complete' : 'Draft', style: AppTheme.bodySub.copyWith(
                  fontSize: 11, color: recon.isComplete ? AppColors.teal : AppColors.amber, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _MiniStat(label: 'Statement', value: tshFromDouble(recon.statementClosingBalance))),
            Expanded(child: _MiniStat(label: 'Reconciled', value: tshFromDouble(recon.totals.reconciledBalance))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Icon(ok ? Symbols.check_circle : Symbols.error, size: 14, color: ok ? AppColors.teal : AppColors.coral),
            const SizedBox(width: 6),
            Text(ok ? 'Matches' : 'Off by ${tshFromDouble(diff.abs())}',
                style: AppTheme.bodySub.copyWith(fontSize: 12, color: ok ? AppColors.teal : AppColors.coral)),
          ]),
        ]),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
    const SizedBox(height: 3),
    Text(value, style: AppTheme.monoSm.copyWith(fontSize: 12.5)),
  ]);
}

// ── New Reconciliation Dialog ────────────────────────────────────────────────

class _NewReconDialog extends StatefulWidget {
  const _NewReconDialog({required this.onClose, required this.onSaved});
  final VoidCallback onClose;
  final VoidCallback onSaved;

  @override
  State<_NewReconDialog> createState() => _NewReconDialogState();
}

class _NewReconDialogState extends State<_NewReconDialog> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to   = DateTime.now();
  final _balanceCtrl = TextEditingController();
  bool    _saving = false;
  String? _error;

  @override
  void dispose() { _balanceCtrl.dispose(); super.dispose(); }

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> _save() async {
    if (_saving) return;
    final balance = int.tryParse(_balanceCtrl.text.replaceAll(',', ''));
    if (balance == null) { setState(() => _error = 'Enter the statement closing balance.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await BankReconciliationService.instance.create({
        'period_from': _iso(_from), 'period_to': _iso(_to),
        'currency': 'TZS', 'statement_closing_balance': balance,
      });
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context, initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020), lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => isFrom ? _from = picked : _to = picked);
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
          width: 440,
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
                Icon(Symbols.account_balance, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text('New Reconciliation', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose, child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12)),
                  ),
                ],
                Row(children: [
                  Expanded(child: _DateField(label: 'Period From', date: _from, onTap: () => _pickDate(true))),
                  const SizedBox(width: 14),
                  Expanded(child: _DateField(label: 'Period To', date: _to, onTap: () => _pickDate(false))),
                ]),
                const SizedBox(height: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LabeledTextField(label: 'Statement closing balance (TSh)', controller: _balanceCtrl, keyboardType: TextInputType.number, hint: '0'),
                ]),
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
                      : Text('Create', style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 13)))))),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LabeledDateField(label: label, date: date, onTap: onTap);
}

// ── Reconciliation Detail ────────────────────────────────────────────────────

class _ReconciliationDetail extends StatefulWidget {
  const _ReconciliationDetail({required this.recon, required this.onBack, required this.onChanged});
  final BankReconciliation recon;
  final VoidCallback onBack;
  final ValueChanged<BankReconciliation> onChanged;

  @override
  State<_ReconciliationDetail> createState() => _ReconciliationDetailState();
}

class _ReconciliationDetailState extends State<_ReconciliationDetail> {
  bool _busy = false;

  Future<void> _importCsv() async {
    if (Platform.isAndroid) {
      showErrorToast(context, Exception('CSV import isn\'t available on Android in this build — use the desktop app instead.'));
      return;
    }
    final result = await FilePicker.pickFiles(allowMultiple: false, withData: false, type: FileType.custom, allowedExtensions: ['csv']);
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    final file = result.files.first;
    setState(() => _busy = true);
    try {
      await BankReconciliationService.instance.importStatement(widget.recon.id, file.path!, file.name);
      final fresh = await BankReconciliationService.instance.get(widget.recon.id);
      widget.onChanged(fresh);
      if (mounted) showSuccessToast(context, 'Statement imported and auto-matched.');
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _autoMatch() async {
    setState(() => _busy = true);
    try {
      final fresh = await BankReconciliationService.instance.autoMatch(widget.recon.id);
      widget.onChanged(fresh);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unmatch(int lineId) async {
    try {
      final fresh = await BankReconciliationService.instance.unmatchLine(widget.recon.id, lineId);
      widget.onChanged(fresh);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _complete() async {
    setState(() => _busy = true);
    try {
      final fresh = await BankReconciliationService.instance.complete(widget.recon.id);
      widget.onChanged(fresh);
      if (mounted) showSuccessToast(context, 'Reconciliation completed.');
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reopen() async {
    setState(() => _busy = true);
    try {
      final fresh = await BankReconciliationService.instance.reopen(widget.recon.id);
      widget.onChanged(fresh);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recon = widget.recon;
    final t = recon.totals;
    final ok = t.difference == 0;
    final matched = recon.lines.where((l) => l.isMatched).length;
    final unmatched = recon.lines.length - matched;
    final matchedPct = recon.lines.isEmpty ? 0.0 : matched / recon.lines.length;

    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      return SingleChildScrollView(
        padding: EdgeInsets.all(pad),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            GestureDetector(
              onTap: widget.onBack,
              child: Container(
                width: 28, height: 28, alignment: Alignment.center,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: context.pal.border)),
                child: Icon(Symbols.arrow_back, size: 15, color: context.pal.textMute),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('${recon.periodFrom} → ${recon.periodTo}', style: AppTheme.pageTitle.copyWith(fontSize: 20)),
                const SizedBox(width: 9),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: (recon.isComplete ? AppColors.green : AppColors.amber).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
                  child: Text(recon.isComplete ? 'COMPLETE' : 'DRAFT', style: AppTheme.monoXs.copyWith(fontSize: 9, color: recon.isComplete ? AppColors.green : AppColors.amber)),
                ),
              ]),
              const SizedBox(height: 3),
              Text('${recon.lines.length} line${recon.lines.length == 1 ? '' : 's'} · $matched matched by rule', style: AppTheme.bodySub.copyWith(fontSize: 12)),
            ])),
            if (!recon.isComplete) ...[
              OutlinedButton.icon(onPressed: _busy ? null : _importCsv, icon: const Icon(Symbols.upload_file, size: 15), label: const Text('Re-import CSV')),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _autoMatch,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.violet, side: BorderSide(color: AppColors.violet.withValues(alpha: 0.5))),
                icon: const Icon(Symbols.auto_awesome, size: 15), label: const Text('Auto-match'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: (_busy || !ok) ? null : _complete, icon: const Icon(Symbols.lock, size: 15), label: const Text('Complete')),
            ] else
              OutlinedButton.icon(onPressed: _busy ? null : _reopen, icon: const Icon(Symbols.lock_open, size: 15), label: const Text('Reopen')),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
            decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _reconStat('Statement balance', tshFromDouble(t.statementClosingBalance), context.pal.text, 21)),
                Expanded(child: _reconStat('Ledger balance', tshFromDouble(t.cashBookBalance), context.pal.text, 21)),
                Expanded(child: _reconStat('Matched', tshFromDouble(t.reconciledBalance), AppColors.green, 21)),
                Expanded(child: _reconStat('Difference', tshSigned(t.difference), ok ? AppColors.green : AppColors.coral, 24)),
              ]),
              const SizedBox(height: 15),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: Row(children: [
                Expanded(flex: matched == 0 ? 1 : matched, child: Container(width: double.infinity, height: 8, color: matched == 0 ? context.pal.surface3 : AppColors.green)),
                if (unmatched > 0) Expanded(flex: unmatched, child: Container(width: double.infinity, height: 8, color: AppColors.coral)),
              ])),
              const SizedBox(height: 9),
              Text('$matched matched · $unmatched unmatched · ${(matchedPct * 100).toStringAsFixed(0)}% complete', style: AppTheme.bodySub.copyWith(fontSize: 11)),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: context.pal.surface1,
              borderRadius: BorderRadius.circular(AppColors.rLg),
              border: Border.all(color: context.pal.border),
            ),
            child: HScrollTable(minWidth: 700, child: _LinesTable(
              lines: recon.lines,
              onUnmatch: _unmatch,
            )),
          ),
          if (!ok) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: AppColors.coral.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.coral.withValues(alpha: 0.24))),
              child: Row(children: [
                Icon(Symbols.warning, size: 15, color: AppColors.coral),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Off by ${tshFromDouble(t.difference.abs())} — $unmatched statement line${unmatched == 1 ? '' : 's'} still need${unmatched == 1 ? 's' : ''} a ledger match before this can be completed.',
                  style: AppTheme.bodySm.copyWith(fontSize: 12),
                )),
              ]),
            ),
          ],
        ]),
      );
    });
  }

  Widget _reconStat(String label, String value, Color color, double size) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
    const SizedBox(height: 6),
    Text(value, style: AppTheme.kpiValue.copyWith(fontSize: size, color: color)),
  ]);
}

class _LinesTable extends StatelessWidget {
  const _LinesTable({required this.lines, required this.onUnmatch});
  final List<BankStatementLine> lines;
  final ValueChanged<int> onUnmatch;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('No statement lines imported yet', style: TextStyle(color: context.pal.textMute))),
      );
    }
    return Table(
      columnWidths: const {0: FixedColumnWidth(90), 1: FlexColumnWidth(2.5), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1), 4: FlexColumnWidth(1), 5: FixedColumnWidth(80)},
      children: [
        TableRow(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
          children: ['Date', 'Description', 'Debit', 'Credit', 'Match', ''].map((h) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(h.toUpperCase(), style: AppTheme.monoXs.copyWith(fontWeight: FontWeight.w500)),
          )).toList(),
        ),
        ...lines.asMap().entries.map((e) {
          final l = e.value;
          return TableRow(
            decoration: BoxDecoration(
              color: l.isMatched ? null : AppColors.coral.withValues(alpha: 0.05),
              border: e.key == lines.length - 1 ? null : Border(bottom: BorderSide(color: context.pal.divider)),
            ),
            children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 3, height: 22, decoration: BoxDecoration(color: l.isMatched ? AppColors.green : AppColors.coral, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 9),
                Text(l.txnDate, style: AppTheme.monoXs),
              ])),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text(l.description, style: AppTheme.bodySm.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text(l.debit > 0 ? tshFromDouble(l.debit) : '—', style: AppTheme.monoSm.copyWith(fontSize: 12))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text(l.credit > 0 ? tshFromDouble(l.credit) : '—', style: AppTheme.monoSm.copyWith(fontSize: 12))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(l.isMatched ? Symbols.check_circle : Symbols.radio_button_unchecked, size: 15, color: l.isMatched ? AppColors.green : AppColors.coral),
                const SizedBox(width: 6),
                Text(l.isMatched ? 'matched' : 'unmatched', style: AppTheme.bodySub.copyWith(fontSize: 11, color: l.isMatched ? AppColors.green : AppColors.coral)),
              ])),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: l.isMatched
                    ? GestureDetector(
                        onTap: () => onUnmatch(l.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(6)),
                          child: Text('Unmatch', style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        }),
      ],
    );
  }
}
