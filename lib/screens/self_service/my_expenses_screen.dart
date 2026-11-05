// My Expenses (2026-10-24): everyone submits their own expenses, which go to
// their own manager first (users.manager_id), then to Finance to pay — or on
// to the Director for Director-only categories. The API serves only the
// caller's own here (?mine=1); the manager acts in Approvals.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/expense.dart';
import '../../services/expense_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/procurement/proc_widgets.dart';
import '../finance/expenses_screen.dart' show NewExpenseDialog;

ProcTone _tone(ExpenseStatus s) => switch (s) {
  ExpenseStatus.pendingManager || ExpenseStatus.pendingCto || ExpenseStatus.pendingDirector => ProcTone.amber,
  ExpenseStatus.pendingPayment || ExpenseStatus.pendingRelease => ProcTone.teal,
  ExpenseStatus.paid => ProcTone.green,
  ExpenseStatus.rejected => ProcTone.coral,
};

/// Where it is, in words the submitter understands.
String _where(Expense e) => switch (e.status) {
  ExpenseStatus.pendingManager => 'Waiting on ${e.approverName ?? 'your manager'}',
  ExpenseStatus.pendingCto => 'Waiting on the CTO',
  ExpenseStatus.pendingDirector => 'Waiting on the Director',
  ExpenseStatus.pendingPayment => 'Approved — Finance is preparing the payment',
  ExpenseStatus.pendingRelease => 'Payment initiated — waiting to be released',
  ExpenseStatus.paid => 'Paid${e.paidByName == null ? '' : ' by ${e.paidByName}'}',
  ExpenseStatus.rejected => 'Rejected${e.rejectionReason == null ? '' : ': ${e.rejectionReason}'}',
};

class MyExpensesScreen extends StatefulWidget {
  const MyExpensesScreen({super.key});
  @override
  State<MyExpensesScreen> createState() => _MyExpensesScreenState();
}

class _MyExpensesScreenState extends State<MyExpensesScreen> {
  Period _period = Period.defaultPeriod;
  List<Expense>? _rows;
  List<ExpenseCategory> _categories = const [];
  String? _error;
  bool _showCreate = false;

  @override
  void initState() {
    super.initState();
    _load();
    ExpenseService.instance.categories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((Object _) {});
  }

  Future<void> _load() async {
    try {
      final rows = await ExpenseService.instance.list(period: _period, mine: true);
      if (mounted) setState(() { _rows = rows; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final rows = _rows;
    if (rows == null) {
      return _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    int sum(bool Function(Expense) f) => rows.where(f).fold(0, (a, e) => a + e.grossAmount);
    bool waiting(Expense e) => const {ExpenseStatus.pendingManager, ExpenseStatus.pendingCto, ExpenseStatus.pendingDirector}.contains(e.status);
    bool approved(Expense e) => e.status == ExpenseStatus.pendingPayment || e.status == ExpenseStatus.pendingRelease;

    return Stack(children: [
      Container(
        color: pal.bg,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ProcPageHeader(
            title: 'My Expenses',
            subtitle: 'Your expenses go to your manager first, then to Finance to pay',
            actions: [
              ProcButton(label: 'New expense', icon: Symbols.add, tone: ProcTone.green,
                  onPressed: _categories.isEmpty ? null : () => setState(() => _showCreate = true)),
            ],
          ),
          Expanded(child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 14, 24, 24), children: [
              KpiStrip([
                KpiStripItem(Symbols.hourglass_top, ProcTone.amber, 'Waiting for approval', '${rows.where(waiting).length}',
                    tshFromDouble(sum(waiting))),
                KpiStripItem(Symbols.task_alt, ProcTone.teal, 'Approved, not paid yet', '${rows.where(approved).length}',
                    tshFromDouble(sum(approved))),
                KpiStripItem(Symbols.payments, ProcTone.green, 'Paid', '${rows.where((e) => e.status == ExpenseStatus.paid).length}',
                    tshFromDouble(sum((e) => e.status == ExpenseStatus.paid))),
              ]),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft,
                  child: PeriodSelector(value: _period, onChanged: (p) { setState(() { _period = p; _rows = null; }); _load(); })),
              const SizedBox(height: 14),
              if (rows.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
                  child: Text('No expenses in ${_period.label.toLowerCase()}.', textAlign: TextAlign.center,
                      style: AppTheme.bodySub.copyWith(color: pal.textDim)),
                )
              else
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
                  child: Column(children: [for (final e in rows) _row(context, e)]),
                ),
            ]),
          )),
        ]),
      ),
      if (_showCreate)
        NewExpenseDialog(
          categories: _categories,
          allowRecurring: false,
          onClose: () => setState(() => _showCreate = false),
          onSaved: () { setState(() => _showCreate = false); _load(); showSuccessToast(context, 'Sent to your manager for approval.'); },
        ),
    ]);
  }

  Widget _row(BuildContext context, Expense e) {
    final pal = context.pal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(e.name, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(tshFromDouble(e.grossAmount), style: procMono(context, color: pal.text)),
        ]),
        const SizedBox(height: 4),
        Text([e.categoryName ?? '—', e.expenseDate, if (e.reference != null) e.reference!].join(' · '),
            style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Row(children: [
          ProcTag(e.status.label, tone: _tone(e.status), small: true),
          const SizedBox(width: 8),
          Expanded(child: Text(_where(e), style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute),
              maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      ]),
    );
  }
}
