import 'package:flutter/material.dart';
import '../../models/creditor.dart' show money, SupplierPayment;
import '../../services/creditor_service.dart';
import '../../widgets/finance/payment_request_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userRoleNotifier, userIdNotifier, hasCtoApprovalAuthority, hasTeamLeadAuthority,
    hasFinalMoneyAuthority, hasProcurementSalesStageAuthority, hasAccountantAuthority;
import '../../models/expense.dart';
import '../../models/per_diem_request.dart';
import '../../models/purchase_order.dart';
import '../../models/stock_out_request.dart';
import '../../services/expense_service.dart';
import '../../models/vendor.dart';
import '../../services/vendor_fee_service.dart';
import '../finance/vendor_fees_screen.dart' show showVendorFeeDetail;
import '../../services/per_diem_service.dart';
import '../../services/purchase_order_service.dart';
import '../../services/stock_out_request_service.dart';
import '../../services/fast_track_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/error_view.dart';
import 'per_diem_revise_dialog.dart';
import '../../widgets/common/labeled_field.dart';
import '../self_service/travel_plan_viewer.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key, this.initialTabIndex});
  final int? initialTabIndex;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
    length: 6, vsync: this,
    initialIndex: (widget.initialTabIndex ?? 0).clamp(0, 5),
  );

  static const _pendingPoStatuses = {
    'pending_sales_manager', 'pending_director_review',
    'pending_payment_initiation', 'pending_director_final',
  };

  List<StockOutRequest>  _stockOut = [];
  List<PerDiemRequest>   _perDiem  = [];
  List<Expense>          _expenses = [];
  List<PurchaseOrder>    _purchaseOrders = [];
  List<SupplierPayment>  _payments = [];
  String? _paymentsError;
  // Clearing & vendor fees waiting on this person: as the recorder's
  // manager (Patrick), as Finance or as the Director (2026-10-26).
  List<VendorFee>        _fees = [];
  String? _feesError;
  bool    _loading = true;
  // Per-tab load failure (e.g. a team_leader correctly lacks finance access
  // and can't see Expenses at all) — kept separate per tab so one 403
  // doesn't take the other three tabs down with it.
  String? _stockOutError;
  String? _perDiemError;
  String? _expensesError;
  String? _purchaseOrdersError;

  List<StockOutRequest> get _pendingStockOut =>
      _stockOut.where((r) => r.status == StockOutStatus.pending).toList();
  List<PerDiemRequest> get _pendingPerDiem =>
      _perDiem.where((r) =>
          r.isPendingTeamLead || r.isPendingCto || r.isPendingPayment || r.isPendingDirector).toList();
  List<Expense> get _pendingExpenses => _expenses.where(
      (e) => e.status == ExpenseStatus.pendingManager || e.status == ExpenseStatus.pendingCto || e.status == ExpenseStatus.pendingDirector
          || e.status == ExpenseStatus.pendingPayment || e.status == ExpenseStatus.pendingRelease).toList();
  /// An LPO's own payment is approved with the LPO (its final approval),
  /// so it's listed there, not here.
  List<SupplierPayment> get _standalonePayments {
    final finalStage = _purchaseOrders.where((po) => po.status == 'pending_director_final').map((po) => po.id).toSet();
    return _payments.where((p) => p.purchaseOrderId == null || !finalStage.contains(p.purchaseOrderId)).toList();
  }
  List<PurchaseOrder> get _pendingPurchaseOrders =>
      _purchaseOrders.where((po) => _pendingPoStatuses.contains(po.status)).toList();

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: seed each tab from its service's own
    // default-list cache (where one exists) so re-visiting Approvals
    // doesn't blank the whole four-tab view to a spinner while a
    // background refresh runs — same reasoning as MachineListScreen.
    // Stock-out has no matching cache: StockOutRequestService only caches
    // the fully unfiltered call, and this screen always fetches
    // status: 'pending', so that tab always starts empty until its own
    // fetch resolves, same as before.
    final perDiem = PerDiemService.cachedDefaultList;
    final expenses = ExpenseService.cachedDefaultList;
    final purchaseOrders = PurchaseOrderService.cachedDefaultList;
    if (perDiem != null) _perDiem = perDiem;
    if (expenses != null) _expenses = expenses;
    if (purchaseOrders != null) _purchaseOrders = purchaseOrders;
    if (perDiem != null || expenses != null || purchaseOrders != null) {
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() {
      if (_stockOut.isEmpty && _perDiem.isEmpty && _expenses.isEmpty && _purchaseOrders.isEmpty) {
        _loading = true;
      }
      _stockOutError = null; _perDiemError = null; _expensesError = null; _purchaseOrdersError = null;
    });
    // Each tab's resource loads independently — one tab lacking permission
    // (e.g. team_leader has no finance access, so Expenses 403s) must not
    // block the other three tabs the same user IS authorised to act on.
    await Future.wait([
      _loadStockOut(),
      _loadPerDiem(),
      _loadExpenses(),
      _loadPurchaseOrders(),
      _loadPayments(),
      _loadFees(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadStockOut() async {
    try {
      final v = await StockOutRequestService.instance.list(status: 'pending');
      if (mounted) setState(() => _stockOut = v);
    } catch (e) {
      if (mounted) setState(() { _stockOut = []; _stockOutError = friendlyError(e); });
    }
  }

  Future<void> _loadPerDiem() async {
    try {
      final v = await PerDiemService.instance.list();
      if (mounted) setState(() => _perDiem = v);
    } catch (e) {
      if (mounted) setState(() { _perDiem = []; _perDiemError = friendlyError(e); });
    }
  }

  Future<void> _loadExpenses() async {
    try {
      final v = await ExpenseService.instance.pending();
      if (mounted) setState(() => _expenses = v);
    } catch (e) {
      if (mounted) setState(() { _expenses = []; _expensesError = friendlyError(e); });
    }
  }

  Future<void> _loadPurchaseOrders() async {
    try {
      final v = await PurchaseOrderService.instance.list();
      if (mounted) setState(() => _purchaseOrders = v);
    } catch (e) {
      if (mounted) setState(() { _purchaseOrders = []; _purchaseOrdersError = friendlyError(e); });
    }
  }

  Future<void> _loadPayments() async {
    try {
      final p = await CreditorService.instance.payments(status: 'pending_director');
      if (mounted) setState(() { _payments = p; _paymentsError = null; });
    } catch (e) {
      if (mounted) setState(() => _paymentsError = friendlyError(e));
    }
  }

  Future<void> _loadFees() async {
    try {
      final f = await VendorFeeService.instance.waitingOnMe();
      if (mounted) setState(() { _fees = f; _feesError = null; });
    } catch (e) {
      if (mounted) setState(() => _feesError = friendlyError(e));
    }
  }

  Future<void> _approvePayment(SupplierPayment p) async {
    try {
      final done = await CreditorService.instance.approve(p.id);
      if (mounted) {
        showSuccessToast(context, done.fxDifferenceTzs == 0
            ? 'Approved and posted.'
            : 'Approved and posted — exchange ${done.fxDifferenceTzs > 0 ? 'loss' : 'gain'} ${money(done.fxDifferenceTzs.abs(), 'TZS')}.');
        _load();
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _rejectPayment(SupplierPayment p) async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _RejectReasonDialog(minLength: 5));
    if (reason == null) return;
    try {
      await CreditorService.instance.reject(p.id, reason);
      if (mounted) { showSuccessToast(context, 'Rejected.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _approveStockOut(StockOutRequest r) async {
    try {
      await StockOutRequestService.instance.approve(r.id);
      if (mounted) { showSuccessToast(context, 'Approved.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _rejectStockOut(StockOutRequest r) async {
    final reason = await showDialog<String>(context: context, builder: (_) => _RejectReasonDialog());
    if (reason == null) return;
    try {
      await StockOutRequestService.instance.reject(r.id, reason: reason.isEmpty ? null : reason);
      if (mounted) { showSuccessToast(context, 'Rejected.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _forwardPerDiem(PerDiemRequest r) async {
    try {
      await PerDiemService.instance.approveTeamLead(r.id);
      if (mounted) { showSuccessToast(context, 'Forwarded to CTO.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _rejectPerDiemTeamLead(PerDiemRequest r) async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _RejectReasonDialog(minLength: 10));
    if (reason == null) return;
    try {
      await PerDiemService.instance.rejectTeamLead(r.id, reason: reason);
      if (mounted) { showSuccessToast(context, 'Rejected.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _approvePerDiem(PerDiemRequest r) async {
    try {
      await PerDiemService.instance.approve(r.id);
      if (mounted) { showSuccessToast(context, 'Approved.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _rejectPerDiem(PerDiemRequest r) async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _RejectReasonDialog(minLength: 10));
    if (reason == null) return;
    try {
      await PerDiemService.instance.reject(r.id, reason: reason);
      if (mounted) { showSuccessToast(context, 'Rejected.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _initiatePerDiemPayment(PerDiemRequest r) async {
    final result = await showDialog<(String?, String?)>(context: context, builder: (_) => _InitiatePaymentDialog());
    if (result == null || !mounted) return;
    final account = await pickPaymentAccount(context, title: 'Paid from', note: 'The account the per diem money leaves from — it posts there when released.');
    if (account == null || !mounted) return;
    try {
      await PerDiemService.instance.initiatePayment(r.id, method: result.$1, reference: result.$2, paidFromAccountId: account.id);
      if (mounted) { showSuccessToast(context, 'Payment initiated — sent to Director for authorization.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _authorizePerDiemPayment(PerDiemRequest r) async {
    try {
      await PerDiemService.instance.markPaid(r.id);
      if (mounted) { showSuccessToast(context, 'Payment authorized — marked paid.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  // Section 8: CTO day-by-day editing.
  void _showRevisePerDiemDialog(PerDiemRequest r) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => PerDiemReviseDialog(
        request: r,
        onClose: () => Navigator.of(dialogCtx).pop(),
        onSaved: () {
          Navigator.of(dialogCtx).pop();
          if (mounted) { showSuccessToast(context, 'Travel plan updated.'); _load(); }
        },
      ),
    );
  }

  // Section 15.5: "Available to the requester, the approvers on that
  // plan, the CTO, finance and admins" — everyone who reaches this tab
  // already holds one of those authorities server-side (same gate as
  // show()), so no extra client-side check is needed here.
  Future<void> _downloadPerDiemPdf(PerDiemRequest r) => downloadPdf(
    context, () => PerDiemService.instance.pdfBytes(r.id), 'travel-plan-${r.id}.pdf',
  );

  Future<void> _downloadPerDiemXlsx(PerDiemRequest r) => downloadPdf(
    context, () => PerDiemService.instance.xlsxBytes(r.id), 'travel-plan-${r.id}.xlsx',
  );

  Future<void> _toggleEditGrant(PerDiemRequest r) async {
    try {
      if (r.hasActiveEditGrant) {
        await PerDiemService.instance.revokeEditAccess(r.id);
        if (mounted) showSuccessToast(context, 'Edit access revoked.');
      } else {
        await PerDiemService.instance.grantEditAccess(r.id);
        if (mounted) showSuccessToast(context, 'Edit access granted to ${r.userName ?? 'the technician'}.');
      }
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _approveTechnicianEdit(PerDiemRequest r, PerDiemRevision rev) async {
    try {
      await PerDiemService.instance.approveTechnicianEdit(r.id, rev.id);
      if (mounted) { showSuccessToast(context, 'Technician\'s edit applied.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _rejectTechnicianEdit(PerDiemRequest r, PerDiemRevision rev) async {
    try {
      await PerDiemService.instance.rejectTechnicianEdit(r.id, rev.id);
      if (mounted) { showSuccessToast(context, 'Proposed edit rejected.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _approveExpense(Expense e) async {
    try {
      await ExpenseService.instance.approve(e.id);
      if (mounted) { showSuccessToast(context, 'Approved.'); _load(); }
    } catch (err) {
      if (mounted) showErrorToast(context, err);
    }
  }

  Future<void> _escalateExpense(Expense e) async {
    try {
      await ExpenseService.instance.escalate(e.id);
      if (mounted) { showSuccessToast(context, 'Escalated to Director.'); _load(); }
    } catch (err) {
      if (mounted) showErrorToast(context, err);
    }
  }

  Future<void> _rejectExpense(Expense e) async {
    final reason = await showDialog<String>(context: context, builder: (_) => _RejectReasonDialog());
    if (reason == null) return;
    try {
      await ExpenseService.instance.reject(e.id, reason: reason.isEmpty ? null : reason);
      if (mounted) { showSuccessToast(context, 'Rejected.'); _load(); }
    } catch (err) {
      if (mounted) showErrorToast(context, err);
    }
  }

  Future<void> _initiateExpensePayment(Expense e) async {
    final result = await showDialog<(String?, String?)>(context: context,
        builder: (_) => const _InitiatePaymentDialog(methods: ['cash', 'bank', 'mobile_money']));
    if (result == null) return;
    try {
      await ExpenseService.instance.initiatePayment(e.id, paymentMethod: result.$1, reference: result.$2);
      if (mounted) { showSuccessToast(context, 'Payment initiated — awaiting release.'); _load(); }
    } catch (err) {
      if (mounted) showErrorToast(context, err);
    }
  }

  Future<void> _releaseExpensePayment(Expense e) async {
    try {
      await ExpenseService.instance.markPaid(e.id);
      if (mounted) { showSuccessToast(context, 'Payment released — marked paid.'); _load(); }
    } catch (err) {
      if (mounted) showErrorToast(context, err);
    }
  }

  /// The Director approves past the stages still open; Finance still pays.
  Future<void> _fastTrack(String type, int id, String what) async {
    final ok = await showDialog<bool>(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: Text('Approve now?', style: AppTheme.cardTitle),
      content: SizedBox(width: 360, child: Text(
        'This approves $what past every approval stage still open. The people whose turn it was are told. '
        'If money is paid, Finance still records the payment.',
        style: AppTheme.bodySm)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Approve now')),
      ],
    ));
    if (ok != true) return;
    try {
      await FastTrackService.instance.approveNow(type, id);
      if (mounted) { showSuccessToast(context, 'Approved.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _approvePoSalesStage(PurchaseOrder po) async {
    try {
      await PurchaseOrderService.instance.approveSalesManager(po.id);
      if (mounted) { showSuccessToast(context, 'Approved — sent to director review.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _rejectPoSalesStage(PurchaseOrder po) async {
    final reason = await showDialog<String>(context: context, builder: (_) => _RejectReasonDialog());
    if (reason == null) return;
    try {
      await PurchaseOrderService.instance.rejectSalesManager(po.id, reason: reason.isEmpty ? null : reason);
      if (mounted) { showSuccessToast(context, 'Rejected.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _approvePoDirectorReview(PurchaseOrder po) async {
    try {
      await PurchaseOrderService.instance.approveDirectorReview(po.id);
      if (mounted) { showSuccessToast(context, 'Approved — sent for payment initiation.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _rejectPoDirectorReview(PurchaseOrder po) async {
    final reason = await showDialog<String>(context: context, builder: (_) => _RejectReasonDialog());
    if (reason == null) return;
    try {
      await PurchaseOrderService.instance.rejectDirectorReview(po.id, reason: reason.isEmpty ? null : reason);
      if (mounted) { showSuccessToast(context, 'Rejected.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _initiatePoPayment(PurchaseOrder po) async {
    final body = await showPaymentRequestDialog(context,
        title: 'Pay ${po.poNumber}',
        creditorName: po.supplierName ?? 'Supplier',
        currency: po.currency,
        amount: (po.totalAmount - po.amountPaid).clamp(0, double.infinity).toDouble(),
        hint: 'Order total ${po.currency} ${po.totalAmount.toStringAsFixed(0)}. Pay all of it, a deposit, or approve it on credit.',
        allowOnCredit: true);
    if (body == null || !mounted) return;
    try {
      await PurchaseOrderService.instance.initiatePayment(po.id, body);
      if (mounted) {
        showSuccessToast(context, body['on_credit'] == true ? 'Sent to the Director to approve on credit.' : 'Payment initiated — sent for final approval.');
        _load();
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _approvePoDirectorFinal(PurchaseOrder po) async {
    try {
      await PurchaseOrderService.instance.approveDirectorFinal(po.id);
      if (mounted) { showSuccessToast(context, 'Fully approved — ready to send to supplier.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _rejectPoDirectorFinal(PurchaseOrder po) async {
    final reason = await showDialog<String>(context: context, builder: (_) => _RejectReasonDialog());
    if (reason == null) return;
    try {
      await PurchaseOrderService.instance.rejectDirectorFinal(po.id, reason: reason.isEmpty ? null : reason);
      if (mounted) { showSuccessToast(context, 'Rejected.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 28.0;
      return Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Approvals', style: AppTheme.pageTitle),
            const SizedBox(height: 4),
            Text('Requests waiting on your sign-off', style: AppTheme.bodySub),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          margin: EdgeInsets.symmetric(horizontal: pad),
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(AppColors.rLg),
            border: Border.all(color: context.pal.border),
          ),
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.teal,
            unselectedLabelColor: context.pal.textMute,
            indicatorColor: AppColors.teal,
            indicatorWeight: 2,
            labelStyle: AppTheme.bodyStrong.copyWith(fontSize: 12.5),
            unselectedLabelStyle: AppTheme.bodySm,
            tabs: [
              Tab(text: 'Stock-Out (${_pendingStockOut.length})'),
              Tab(text: 'Per Diem (${_pendingPerDiem.length})'),
              Tab(text: 'Expenses (${_pendingExpenses.length})'),
              Tab(text: 'Purchase Orders (${_pendingPurchaseOrders.length})'),
              Tab(text: 'Supplier Payments (${_standalonePayments.length})'),
              Tab(text: 'Clearing & Vendor Fees (${_fees.length})'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ValueListenableBuilder<String>(
                      valueListenable: userRoleNotifier,
                      builder: (_, role, _) => TabBarView(controller: _tab, children: [
                        _stockOutError != null
                            ? ErrorView(message: _stockOutError!, onRetry: _loadStockOut)
                            : _StockOutTab(requests: _pendingStockOut, pad: pad, onApprove: _approveStockOut, onReject: _rejectStockOut),
                        _perDiemError != null
                            ? ErrorView(message: _perDiemError!, onRetry: _loadPerDiem)
                            : _PerDiemTab(
                          requests: _pendingPerDiem, pad: pad, viewerRole: role,
                          onForward: _forwardPerDiem, onRejectTeamLead: _rejectPerDiemTeamLead,
                          onApprove: _approvePerDiem, onReject: _rejectPerDiem,
                          onInitiatePayment: _initiatePerDiemPayment,
                          onAuthorizePayment: _authorizePerDiemPayment,
                          onRevise: _showRevisePerDiemDialog,
                          onToggleEditGrant: _toggleEditGrant,
                          onApproveTechnicianEdit: _approveTechnicianEdit,
                          onRejectTechnicianEdit: _rejectTechnicianEdit,
                          onDownloadPdf: _downloadPerDiemPdf,
                          onDownloadXlsx: _downloadPerDiemXlsx,
                          onFastTrack: (r) => _fastTrack('per_diem', r.id, 'this travel plan'),
                        ),
                        _expensesError != null
                            ? ErrorView(message: _expensesError!, onRetry: _loadExpenses)
                            : _ExpenseTab(
                          expenses: _pendingExpenses, pad: pad, viewerRole: role,
                          onApprove: _approveExpense, onEscalate: _escalateExpense, onReject: _rejectExpense,
                          onInitiatePayment: _initiateExpensePayment, onReleasePayment: _releaseExpensePayment,
                          onFastTrack: (e) => _fastTrack('expense', e.id, 'this expense'),
                        ),
                        _purchaseOrdersError != null
                            ? ErrorView(message: _purchaseOrdersError!, onRetry: _loadPurchaseOrders)
                            : _PurchaseOrderTab(
                          orders: _pendingPurchaseOrders, pad: pad, viewerRole: role,
                          onApproveSalesStage: _approvePoSalesStage, onRejectSalesStage: _rejectPoSalesStage,
                          onApproveDirectorReview: _approvePoDirectorReview, onRejectDirectorReview: _rejectPoDirectorReview,
                          onInitiatePayment: _initiatePoPayment,
                          onApproveDirectorFinal: _approvePoDirectorFinal, onRejectDirectorFinal: _rejectPoDirectorFinal,
                          onFastTrack: (po) => _fastTrack('purchase_order', po.id, 'this purchase order'),
                        ),
                        _paymentsError != null
                            ? ErrorView(message: _paymentsError!, onRetry: _loadPayments)
                            : _SupplierPaymentTab(payments: _standalonePayments, pad: pad, viewerRole: role,
                                onApprove: _approvePayment, onReject: _rejectPayment),
                        _feesError != null
                            ? ErrorView(message: _feesError!, onRetry: _loadFees)
                            : _VendorFeeTab(fees: _fees, pad: pad,
                                onOpen: (f) => showVendorFeeDetail(context, f.id, onChanged: _loadFees).then((_) => _loadFees())),
                      ]),
                    ),
        ),
      ]);
    });
  }
}

/// Clearing & vendor fees waiting on the viewer — open one to act on it
/// (manager: approve/reject; Finance: request payment; Director: pay).
class _VendorFeeTab extends StatelessWidget {
  const _VendorFeeTab({required this.fees, required this.pad, required this.onOpen});
  final List<VendorFee> fees;
  final double pad;
  final ValueChanged<VendorFee> onOpen;

  @override
  Widget build(BuildContext context) {
    if (fees.isEmpty) {
      return Center(child: Text('No clearing or vendor fees waiting on you.', style: AppTheme.bodySub));
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 24),
      itemCount: fees.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final f = fees[i];
        return InkWell(
          onTap: () => onOpen(f),
          borderRadius: BorderRadius.circular(AppColors.rLg),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(AppColors.rLg),
                border: Border.all(color: context.pal.border)),
            child: Row(children: [
              Icon(Symbols.receipt_long, size: 20, color: AppColors.violet),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodyStrong.copyWith(fontSize: 13.5)),
                const SizedBox(height: 2),
                Text([f.vendorName ?? '—', if (f.createdBy != null) 'recorded by ${f.createdBy}', f.statusLabel ?? f.status.label].join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
              ])),
              const SizedBox(width: 10),
              Text(money(f.billedAmount, 'TZS'), style: AppTheme.monoSm.copyWith(fontSize: 13, color: context.pal.text)),
              const SizedBox(width: 6),
              Icon(Symbols.chevron_right, size: 18, color: context.pal.textDim),
            ]),
          ),
        );
      },
    );
  }
}

class _RejectReasonDialog extends StatefulWidget {
  // 0 (default) keeps every existing reject flow exactly as it was —
  // optional reason. Per-diem's two reject actions pass 10 (matching
  // PerDiemController's own required|min:10 validation) since the backend
  // rejects an under-length reason anyway; better to catch it here than
  // round-trip a 422.
  const _RejectReasonDialog({this.minLength = 0});
  final int minLength;

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _submit() {
    final text = _ctrl.text.trim();
    if (widget.minLength > 0 && text.length < widget.minLength) {
      setState(() => _error = 'Reason must be at least ${widget.minLength} characters.');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    title: Text('Reject Request', style: AppTheme.bodyStrong),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabeledTextField(
        label: widget.minLength > 0 ? 'Reason (required)' : 'Reason (optional)',
        controller: _ctrl, maxLines: 3,
      ),
      if (_error != null) ...[
        const SizedBox(height: 6),
        Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12)),
      ],
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      TextButton(onPressed: _submit, child: Text('Reject', style: TextStyle(color: AppColors.coral))),
    ],
  );
}

class _InitiatePaymentDialog extends StatefulWidget {
  // Per-Diem's payment_method enum is cash/bank_transfer/mobile_money/cheque;
  // Expense's is cash/bank/mobile_money (matches its existing payment_mode
  // vocabulary) — pass the caller's own list rather than hardcoding one.
  const _InitiatePaymentDialog({this.methods = const ['cash', 'bank_transfer', 'mobile_money', 'cheque']});
  final List<String> methods;

  @override
  State<_InitiatePaymentDialog> createState() => _InitiatePaymentDialogState();
}

class _InitiatePaymentDialogState extends State<_InitiatePaymentDialog> {
  late String _method = widget.methods.first;
  final _refCtrl = TextEditingController();

  @override
  void dispose() { _refCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    title: Text('Initiate Payment', style: AppTheme.bodyStrong),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabeledDropdown<String>(
        label: 'Payment method',
        value: _method,
        items: widget.methods,
        displayBuilder: (m) => m.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' '),
        onChanged: (v) => setState(() => _method = v),
      ),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Reference (optional)', controller: _refCtrl, hint: 'Transaction ID, cheque no., etc.'),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      TextButton(
        onPressed: () => Navigator.of(context).pop((_method, _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim())),
        child: Text('Initiate', style: TextStyle(color: AppColors.teal)),
      ),
    ],
  );
}

class _StockOutTab extends StatelessWidget {
  const _StockOutTab({required this.requests, required this.pad, required this.onApprove, required this.onReject});
  final List<StockOutRequest> requests;
  final double pad;
  final ValueChanged<StockOutRequest> onApprove;
  final ValueChanged<StockOutRequest> onReject;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(child: Text('No pending stock-out requests', style: TextStyle(color: context.pal.textMute)));
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(children: requests.map((r) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: context.pal.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(r.type == 'write_off' ? Symbols.delete_forever : Symbols.remove_circle,
                size: 16, color: r.type == 'write_off' ? AppColors.amber : AppColors.coral),
            const SizedBox(width: 8),
            Expanded(child: Text('${r.itemName ?? '—'} · ${r.quantity} unit(s)',
                style: AppTheme.bodyStrong.copyWith(fontSize: 13.5))),
          ]),
          const SizedBox(height: 8),
          Text('${r.type == 'write_off' ? 'Write-off' : 'Issue'} · ${r.locationName ?? '—'} · requested by ${r.requesterName ?? '—'}'
                  '${r.serviceTicketNumber != null ? ' · for ${r.serviceTicketNumber}' : ''}',
              style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
          if (r.reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r.reason, style: AppTheme.bodySub.copyWith(fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => onReject(r),
              child: Container(height: 36,
                decoration: BoxDecoration(border: Border.all(color: AppColors.coral.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('Reject', style: AppTheme.bodySm.copyWith(color: AppColors.coral)))),
            )),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: () => onApprove(r),
              child: Container(height: 36,
                decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('Approve', style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 12.5)))),
            )),
          ]),
        ]),
      )).toList()),
    );
  }
}

class _PerDiemTab extends StatelessWidget {
  const _PerDiemTab({
    required this.requests, required this.pad, required this.viewerRole,
    required this.onForward, required this.onRejectTeamLead,
    required this.onApprove, required this.onReject,
    required this.onInitiatePayment, required this.onAuthorizePayment,
    required this.onRevise, required this.onToggleEditGrant,
    required this.onApproveTechnicianEdit, required this.onRejectTechnicianEdit,
    required this.onDownloadPdf, required this.onDownloadXlsx,
    this.onFastTrack,
  });
  final ValueChanged<PerDiemRequest>? onFastTrack;
  final List<PerDiemRequest> requests;
  final double pad;
  final String viewerRole;
  final ValueChanged<PerDiemRequest> onForward;
  final ValueChanged<PerDiemRequest> onRejectTeamLead;
  final ValueChanged<PerDiemRequest> onApprove;
  final ValueChanged<PerDiemRequest> onReject;
  final ValueChanged<PerDiemRequest> onInitiatePayment;
  final ValueChanged<PerDiemRequest> onAuthorizePayment;
  // Section 8: CTO day-by-day editing + technician edit-grant toggle.
  final ValueChanged<PerDiemRequest> onRevise;
  final ValueChanged<PerDiemRequest> onToggleEditGrant;
  // Technician's proposed edit — CTO approve/reject, wired to the pending-
  // review notice below (was previously just a passive text notice).
  final void Function(PerDiemRequest, PerDiemRevision) onApproveTechnicianEdit;
  final void Function(PerDiemRequest, PerDiemRevision) onRejectTechnicianEdit;
  // Section 15.5: approvers are permitted viewers of the export too.
  final ValueChanged<PerDiemRequest> onDownloadPdf;
  final ValueChanged<PerDiemRequest> onDownloadXlsx;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(child: Text('No pending per-diem requests', style: TextStyle(color: context.pal.textMute)));
    }
    final canTeamLead = hasTeamLeadAuthority(viewerRole);
    final canCto = hasCtoApprovalAuthority(viewerRole);
    final canAccountant = hasAccountantAuthority(viewerRole);
    final canDirector = hasFinalMoneyAuthority(viewerRole);

    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(children: requests.map((r) {
        // Five real stages: requester -> team lead -> CTO -> finance
        // (initiates payment) -> Director (authorizes/marks paid) — each
        // shows the same full request to whoever's turn it is, so nobody
        // approves or rejects on a summary alone.
        final atTeamLead = r.isPendingTeamLead;
        final atCto = r.isPendingCto;
        final atPaymentInit = r.isPendingPayment;
        final atDirectorAuth = r.isPendingDirector;
        final stageColor = atTeamLead ? AppColors.amber
            : atCto ? AppColors.blue
            : atPaymentInit ? AppColors.violet
            : atDirectorAuth ? AppColors.teal
            : context.pal.textMute;
        final canActOnThis = atTeamLead ? canTeamLead
            : atCto ? canCto
            : atPaymentInit ? canAccountant
            // Either can release — the accountant, since the Director is
            // often busy, or the Director directly. Never the same person
            // who initiated payment (enforced server-side).
            : atDirectorAuth ? (canAccountant || canDirector)
            : false;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(AppColors.rLg),
            border: Border.all(color: context.pal.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Symbols.flight_takeoff, size: 16, color: AppColors.violet),
              const SizedBox(width: 8),
              Expanded(child: Text('${r.userName ?? '—'} · ${r.destination}',
                  style: AppTheme.bodyStrong.copyWith(fontSize: 13.5))),
              // Section 15.4: the whole plan in the template's layout.
              Tooltip(
                message: 'View plan',
                child: GestureDetector(
                  onTap: () => openTravelPlanViewer(context, r),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Symbols.description, size: 16, color: context.pal.textDim),
                  ),
                ),
              ),
              // Section 15.5: approvers are permitted export viewers too.
              GestureDetector(
                onTap: () => onDownloadPdf(r),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Symbols.picture_as_pdf, size: 16, color: context.pal.textDim),
                ),
              ),
              GestureDetector(
                onTap: () => onDownloadXlsx(r),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Symbols.table_chart, size: 16, color: context.pal.textDim),
                ),
              ),
              // Section 8: "the CTO can edit any active plan" — available
              // at every stage shown here (none of these are rejected/
              // cancelled/paid, which this list never shows anyway).
              if (canCto) ...[
                GestureDetector(
                  onTap: () => onRevise(r),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Symbols.edit_calendar, size: 16, color: context.pal.textDim),
                  ),
                ),
                GestureDetector(
                  onTap: () => onToggleEditGrant(r),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      r.hasActiveEditGrant ? Symbols.lock_open : Symbols.lock,
                      size: 16,
                      color: r.hasActiveEditGrant ? AppColors.amber : context.pal.textDim,
                    ),
                  ),
                ),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: stageColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(r.status.label, style: AppTheme.monoXs.copyWith(
                    color: stageColor, fontSize: 9.5)),
              ),
            ]),
            if (canCto && r.hasActiveEditGrant) ...[
              const SizedBox(height: 4),
              Text('Technician has edit access — tap the unlocked icon to revoke.',
                  style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: AppColors.amber)),
            ],
            const SizedBox(height: 8),
            Text('${r.startDate} → ${r.endDate}  ·  ${r.daysCount} day(s)  ·  TSh ${r.amount}',
                style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
            if (r.purpose != null && r.purpose!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(r.purpose!, style: AppTheme.bodySub.copyWith(fontSize: 12)),
            ],
            if (r.lines.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.pal.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: r.lines.asMap().entries.map((e) {
                    final l = e.value;
                    final place = [l.siteName, l.district, l.region]
                        .where((s) => s != null && s.isNotEmpty).join(', ');
                    // Full cost breakdown, not just the line total — the
                    // approver signs off on the composition, not just the
                    // number, so labor/per-diem/transport need to be visible
                    // individually, not collapsed.
                    final costParts = [
                      if (l.laborCost > 0) 'Labor ${l.laborCost}',
                      if (l.perDiemCost > 0) 'Per diem ${l.perDiemCost}',
                      if (l.transportFare > 0) 'Transport ${l.transportFare}',
                    ].join(' · ');
                    return Padding(
                      padding: EdgeInsets.only(bottom: e.key < r.lines.length - 1 ? 8 : 0),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 70, child: Text(l.date,
                            style: AppTheme.monoXs.copyWith(fontSize: 10.5))),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                              [l.activity, place.isEmpty ? null : place]
                                  .where((s) => s != null && s.isNotEmpty).join(' — '),
                              style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                          if (costParts.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(costParts, style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
                            ),
                        ])),
                        Text('TSh ${l.total}', style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
                      ]),
                    );
                  }).toList(),
                ),
              ),
            ],
            // Section 8: "every edit creates a revision" — shown to
            // everyone who can already see this request, same as the
            // payment trail below.
            if (r.wasEdited) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.pal.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('EDIT HISTORY', style: AppTheme.labelCaps.copyWith(fontSize: 9)),
                  const SizedBox(height: 6),
                  ...r.revisions.where((rev) => rev.status != 'pending_cto_approval').map((rev) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${rev.editorRole == 'cto' ? 'CTO' : 'Technician'} · ${rev.editedByName ?? '—'}: ${rev.reason}'
                      '${rev.status == 'rejected' ? ' (rejected)' : ''}',
                      style: AppTheme.bodySub.copyWith(fontSize: 11),
                    ),
                  )),
                ]),
              ),
            ],
            // Technician's proposed edit awaiting CTO review — "a
            // technician can never approve their own change" is
            // structurally true (they hold no CTO authority), so these
            // buttons are only ever shown to an actual CTO-tier viewer.
            if (r.revisions.any((rev) => rev.isPendingReview)) ...[
              const SizedBox(height: 10),
              Builder(builder: (context) {
                final pending = r.revisions.firstWhere((rev) => rev.isPendingReview);
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.blue.withValues(alpha: 0.25)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '${pending.editedByName ?? 'Technician'} proposed an edit: ${pending.reason}',
                      style: AppTheme.bodySm.copyWith(fontSize: 11.5, color: AppColors.blue),
                    ),
                    if (canCto) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        GestureDetector(
                          onTap: () => onApproveTechnicianEdit(r, pending),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(6)),
                            child: Text('Approve', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: const Color(0xFF06120F), fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => onRejectTechnicianEdit(r, pending),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(6)),
                            child: Text('Reject', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                          ),
                        ),
                      ]),
                    ],
                  ]),
                );
              }),
            ],
            if (r.adjustments.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ADJUSTMENTS (POST-PAYMENT)', style: AppTheme.labelCaps.copyWith(fontSize: 9, color: AppColors.amber)),
                  const SizedBox(height: 6),
                  ...r.adjustments.map((adj) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${adj.amount >= 0 ? '+' : ''}TSh ${adj.amount} — ${adj.reason}',
                      style: AppTheme.bodySm.copyWith(fontSize: 11.5, color: AppColors.amber),
                    ),
                  )),
                ]),
              ),
            ],
            if (r.paymentInitiatedByName != null) ...[
              // Once finance has initiated payment, CTO/Finance/Director all
              // see the same trail here — this replaces the WhatsApp-group
              // PDF exchange the team uses today, so it must never be gated
              // to only whoever's turn it currently is.
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.violet.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.violet.withValues(alpha: 0.25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      'Payment initiated by ${r.paymentInitiatedByName}'
                      '${r.paymentMethod != null ? ' · ${r.paymentMethod!.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ')}' : ''}'
                      '${r.paymentReference != null && r.paymentReference!.isNotEmpty ? ' · Ref: ${r.paymentReference}' : ''}',
                      style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: AppColors.violet)),
                  if (r.isPaid && r.paidByName != null) ...[
                    const SizedBox(height: 4),
                    Text('Marked paid by ${r.paidByName}${r.paidAt != null ? ' · ${r.paidAt}' : ''}',
                        style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: AppColors.teal)),
                  ],
                ]),
              ),
            ],
            if (canActOnThis) ...[
              const SizedBox(height: 12),
              Row(children: [
                if (atTeamLead || atCto) ...[
                  Expanded(child: GestureDetector(
                    onTap: () => atTeamLead ? onRejectTeamLead(r) : onReject(r),
                    child: Container(height: 36,
                      decoration: BoxDecoration(border: Border.all(color: AppColors.coral.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text('Reject', style: AppTheme.bodySm.copyWith(color: AppColors.coral)))),
                  )),
                  const SizedBox(width: 10),
                ],
                Expanded(child: GestureDetector(
                  onTap: () => atTeamLead ? onForward(r)
                      : atPaymentInit ? onInitiatePayment(r)
                      : atDirectorAuth ? onAuthorizePayment(r)
                      : onApprove(r),
                  child: Container(height: 36,
                    decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text(
                        atTeamLead ? 'Forward to CTO'
                            : atPaymentInit ? 'Initiate Payment'
                            : atDirectorAuth ? 'Money is out'
                            : 'Approve',
                        style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 12.5)))),
                )),
              ]),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                  atTeamLead ? 'Waiting on the team lead.'
                      : atCto ? 'Waiting on the CTO.'
                      : atPaymentInit ? 'Waiting on the accountant to initiate payment.'
                      : atDirectorAuth ? 'Waiting on the accountant or Director to release payment.'
                      : 'Waiting.',
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic)),
            ],
            if (onFastTrack != null && canDirector && atTeamLead)
              _FastTrackButton(onTap: () => onFastTrack!(r)),
          ]),
        );
      }).toList()),
    );
  }
}

class _ExpenseTab extends StatelessWidget {
  const _ExpenseTab({
    required this.expenses, required this.pad, required this.viewerRole,
    required this.onApprove, required this.onEscalate, required this.onReject,
    required this.onInitiatePayment, required this.onReleasePayment,
    this.onFastTrack,
  });
  final ValueChanged<Expense>? onFastTrack;
  final List<Expense> expenses;
  final double pad;
  final String viewerRole;
  final ValueChanged<Expense> onApprove;
  final ValueChanged<Expense> onEscalate;
  final ValueChanged<Expense> onReject;
  final ValueChanged<Expense> onInitiatePayment;
  final ValueChanged<Expense> onReleasePayment;

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return Center(child: Text('No pending expenses', style: TextStyle(color: context.pal.textMute)));
    }
    final canCto = hasCtoApprovalAuthority(viewerRole);
    final canDirector = hasFinalMoneyAuthority(viewerRole);
    final canAccountant = hasAccountantAuthority(viewerRole);

    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(children: expenses.map((e) {
        final atManager = e.status == ExpenseStatus.pendingManager;
        final atCto = e.status == ExpenseStatus.pendingCto;
        final atDirector = e.status == ExpenseStatus.pendingDirector;
        final atPaymentInit = e.status == ExpenseStatus.pendingPayment;
        final atRelease = e.status == ExpenseStatus.pendingRelease;
        // If flagged for Director, CTO can only escalate (approve would 422 server-side).
        final mustEscalate = atCto && e.requiresDirectorApproval;
        // The submitter's own manager (or the Director over them).
        final canActOnThis = atManager ? (e.approverId == userIdNotifier.value || canDirector)
            : atCto ? canCto
            : atDirector ? canDirector
            : atPaymentInit ? canAccountant
            // Either can release — the accountant, since the Director is
            // often busy, or the Director directly. Never the same person
            // who initiated payment (enforced server-side).
            : atRelease ? (canAccountant || canDirector)
            : false;
        final stageColor = atManager ? AppColors.blue
            : atCto ? AppColors.amber
            : atDirector ? AppColors.violet
            : atPaymentInit ? AppColors.blue
            : atRelease ? AppColors.teal
            : context.pal.textMute;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(AppColors.rLg),
            border: Border.all(color: context.pal.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Symbols.receipt_long, size: 16, color: AppColors.coral),
              const SizedBox(width: 8),
              Expanded(child: Text('${e.name} · TSh ${e.grossAmount}',
                  style: AppTheme.bodyStrong.copyWith(fontSize: 13.5))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: stageColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(e.status.label, style: AppTheme.monoXs.copyWith(
                    color: stageColor, fontSize: 9.5)),
              ),
            ]),
            const SizedBox(height: 8),
            Text('${e.categoryName ?? '—'} · ${e.expenseDate} · by ${e.createdByName ?? '—'}'
                '${atManager && e.approverName != null ? ' · their manager: ${e.approverName}' : ''}',
                style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
            if (atManager && e.requiresDirectorApproval) ...[
              const SizedBox(height: 6),
              Text('After the manager, this goes on to the Director: ${e.escalationReason ?? 'Director approval required.'}',
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.violet)),
            ],
            if (mustEscalate) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                ),
                child: Text(e.escalationReason ?? 'Requires Director approval.',
                    style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.amber)),
              ),
            ],
            if (e.paymentInitiatedByName != null) ...[
              // Once the accountant has initiated payment, everyone sees the
              // same trail here — mirrors the Per-Diem tab's equivalent panel.
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.blue.withValues(alpha: 0.25)),
                ),
                child: Text('Payment initiated by ${e.paymentInitiatedByName}',
                    style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: AppColors.blue)),
              ),
            ],
            if (canActOnThis) ...[
              const SizedBox(height: 12),
              Row(children: [
                if (atManager || atCto || atDirector) ...[
                  Expanded(child: GestureDetector(
                    onTap: () => onReject(e),
                    child: Container(height: 36,
                      decoration: BoxDecoration(border: Border.all(color: AppColors.coral.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text('Reject', style: AppTheme.bodySm.copyWith(color: AppColors.coral)))),
                  )),
                  const SizedBox(width: 10),
                ],
                Expanded(child: GestureDetector(
                  onTap: () => atPaymentInit ? onInitiatePayment(e)
                      : atRelease ? onReleasePayment(e)
                      : mustEscalate ? onEscalate(e)
                      : onApprove(e),
                  child: Container(height: 36,
                    decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text(
                        atPaymentInit ? 'Initiate Payment'
                            : atRelease ? 'Money is out'
                            : mustEscalate ? 'Escalate to Director'
                            // A team leader filters: passing it sends it to their manager.
                            : atManager && e.approverIsFilter && e.approverId == userIdNotifier.value
                                ? 'Pass to ${e.nextApproverName ?? 'manager'}'
                            : 'Approve',
                        style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 12.5)))),
                )),
              ]),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                  atManager ? 'Waiting on ${e.approverName ?? 'their manager'}.'
                      : atCto ? 'Waiting on CTO.'
                      : atDirector ? 'Waiting on the Director.'
                      : atPaymentInit ? 'Waiting on the accountant to initiate payment.'
                      : atRelease ? 'Waiting on the accountant or Director to release payment.'
                      : 'Waiting.',
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic)),
            ],
            if (onFastTrack != null && canDirector && (atManager || atCto))
              _FastTrackButton(onTap: () => onFastTrack!(e)),
          ]),
        );
      }).toList()),
    );
  }
}

class _PurchaseOrderTab extends StatelessWidget {
  const _PurchaseOrderTab({
    required this.orders, required this.pad, required this.viewerRole,
    required this.onApproveSalesStage, required this.onRejectSalesStage,
    required this.onApproveDirectorReview, required this.onRejectDirectorReview,
    required this.onInitiatePayment,
    required this.onApproveDirectorFinal, required this.onRejectDirectorFinal,
    this.onFastTrack,
  });
  final ValueChanged<PurchaseOrder>? onFastTrack;
  final List<PurchaseOrder> orders;
  final double pad;
  final String viewerRole;
  final ValueChanged<PurchaseOrder> onApproveSalesStage;
  final ValueChanged<PurchaseOrder> onRejectSalesStage;
  final ValueChanged<PurchaseOrder> onApproveDirectorReview;
  final ValueChanged<PurchaseOrder> onRejectDirectorReview;
  final ValueChanged<PurchaseOrder> onInitiatePayment;
  final ValueChanged<PurchaseOrder> onApproveDirectorFinal;
  final ValueChanged<PurchaseOrder> onRejectDirectorFinal;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(child: Text('No pending purchase orders', style: TextStyle(color: context.pal.textMute)));
    }
    final canSalesStage = hasProcurementSalesStageAuthority(viewerRole);
    final canDirector   = hasFinalMoneyAuthority(viewerRole);
    final canAccountant = hasAccountantAuthority(viewerRole);

    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(children: orders.map((po) {
        final stageColor = AppColors.amber;
        final (canActOnThis, waitingOn, onApprove, onReject, approveLabel) = switch (po.status) {
          'pending_sales_manager' =>
            (canSalesStage, 'the sales manager', onApproveSalesStage, onRejectSalesStage, 'Approve'),
          'pending_director_review' =>
            (canDirector, 'the director', onApproveDirectorReview, onRejectDirectorReview, 'Approve'),
          'pending_payment_initiation' =>
            (canAccountant, 'the accountant', onInitiatePayment, null, 'Initiate Payment'),
          'pending_director_final' =>
            (canDirector, 'the director', onApproveDirectorFinal, onRejectDirectorFinal, 'Money is out'),
          _ => (false, 'someone else', null, null, ''),
        };

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(AppColors.rLg),
            border: Border.all(color: context.pal.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Symbols.local_shipping, size: 16, color: AppColors.violet),
              const SizedBox(width: 8),
              Expanded(child: Text('${po.poNumber} · ${po.supplierName ?? '—'}',
                  style: AppTheme.bodyStrong.copyWith(fontSize: 13.5))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: stageColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(po.statusLabel, style: AppTheme.monoXs.copyWith(
                    color: stageColor, fontSize: 9.5)),
              ),
            ]),
            const SizedBox(height: 8),
            Text('${po.currency} ${po.totalAmount.toStringAsFixed(0)}  ·  ordered by ${po.orderedByName ?? '—'}',
                style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
            if (po.items.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(po.items.map((i) => '${i.itemName ?? '—'} ×${i.quantityOrdered}').join(', '),
                  style: AppTheme.bodySub.copyWith(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (po.status == 'pending_director_final') ...[
              const SizedBox(height: 6),
              Builder(builder: (context) {
                final p = po.pendingPayment;
                final text = po.onCredit
                    ? 'On credit — no payment now; ${po.supplierName ?? 'the supplier'} is paid later against their invoice.'
                    : p == null
                        ? 'No payment details.'
                        : 'Pay ${money(num.tryParse('${p['amount']}') ?? 0, '${p['currency']}')}'
                          '${'${p['currency']}' == 'TZS' ? '' : ' @ ${p['exchange_rate']}'}'
                          ' from ${(p['paid_from'] as Map?)?['name'] ?? 'the bank'}'
                          '${p['reference'] != null ? ' · ${p['reference']}' : ''}';
                return Text(text, style: AppTheme.bodySm.copyWith(fontSize: 12.5, color: AppColors.teal));
              }),
            ],
            if (canActOnThis) ...[
              const SizedBox(height: 12),
              Row(children: [
                if (onReject != null) ...[
                  Expanded(child: GestureDetector(
                    onTap: () => onReject(po),
                    child: Container(height: 36,
                      decoration: BoxDecoration(border: Border.all(color: AppColors.coral.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text('Reject', style: AppTheme.bodySm.copyWith(color: AppColors.coral)))),
                  )),
                  const SizedBox(width: 10),
                ],
                Expanded(child: GestureDetector(
                  onTap: () => onApprove!(po),
                  child: Container(height: 36,
                    decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text(approveLabel,
                        style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 12.5)))),
                )),
              ]),
            ] else ...[
              const SizedBox(height: 8),
              Text('Waiting on $waitingOn.',
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic)),
            ],
            if (onFastTrack != null && canDirector && (po.status == 'pending_sales_manager' || po.status == 'draft'))
              _FastTrackButton(onTap: () => onFastTrack!(po)),
          ]),
        );
      }).toList()),
    );
  }
}

/// Payments to suppliers/vendors waiting on the Director (LPO payments
/// show here too). Approving posts them from the chosen account.
class _SupplierPaymentTab extends StatelessWidget {
  const _SupplierPaymentTab({required this.payments, required this.pad, required this.viewerRole,
    required this.onApprove, required this.onReject});
  final List<SupplierPayment> payments;
  final double pad;
  final String viewerRole;
  final ValueChanged<SupplierPayment> onApprove;
  final ValueChanged<SupplierPayment> onReject;

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return Center(child: Text('No payments waiting for approval', style: TextStyle(color: context.pal.textMute)));
    }
    final canDirector = hasFinalMoneyAuthority(viewerRole);
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(children: payments.map((p) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: context.pal.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Symbols.payments, size: 16, color: AppColors.teal),
            const SizedBox(width: 8),
            Expanded(child: Text('${p.number} · ${p.creditorName}',
                style: AppTheme.bodyStrong.copyWith(fontSize: 13.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          Text(
            '${money(p.amount, p.currency)}${p.currency == 'TZS' ? '' : ' @ ${p.rate} = ${money(p.amountTzs, 'TZS')}'}',
            style: AppTheme.bodySm.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text([
            'From ${p.paidFrom ?? 'the bank'}',
            if (p.poNumber != null) 'LPO ${p.poNumber}',
            if (p.billRef != null) 'invoice ${p.billRef}',
            if (p.reference != null) p.reference!,
            if (p.initiatedBy != null) 'asked by ${p.initiatedBy}',
          ].join(' · '), style: AppTheme.bodySub.copyWith(fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
          if (p.notes != null) ...[
            const SizedBox(height: 4),
            Text(p.notes!, style: AppTheme.bodySub.copyWith(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
          if (canDirector) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.coral, side: BorderSide(color: AppColors.coral.withValues(alpha: 0.4))),
                onPressed: () => onReject(p), child: const Text('Reject'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: () => onApprove(p), child: const Text('Money is out'))),
            ]),
          ] else ...[
            const SizedBox(height: 8),
            Text('Waiting on the Director.', style: AppTheme.bodySub.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic)),
          ],
        ]),
      )).toList()),
    );
  }
}


/// The Director's "Approve now (skip stages)" on a card waiting on someone else.
class _FastTrackButton extends StatelessWidget {
  const _FastTrackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.teal.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Symbols.bolt, size: 15, color: AppColors.teal),
          const SizedBox(width: 6),
          Flexible(child: Text('Approve now (skip stages)', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySm.copyWith(color: AppColors.teal, fontSize: 12.5))),
        ]),
      ),
    ),
  );
}
