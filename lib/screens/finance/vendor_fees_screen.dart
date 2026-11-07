import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userRoleNotifier, userIdNotifier, hasAccountantAuthority, hasDirectorAuthority, hasFinalMoneyAuthority;
import '../../models/vendor.dart';
import '../../services/vendor_fee_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../services/download_manager.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/finance/payment_request_dialog.dart';

// UI-hint approximations only, same fail-safe rule as the rest of this
// app's client-side role checks — the real gates are
// VendorFeeController/ReceiptController/DeliveryJobController's
// hasProcurementCreateAuthority()/hasLogisticsDeliverAuthority()/
// hasAccountantAuthority()/hasFinanceApprovalAuthority()/hasDirectorAuthority().
bool _isVendorOpsTier(String role) => hasDirectorAuthority(role) || const {
  'super_admin', 'admin', 'procurement_manager', 'logistics', 'accountant', 'finance_manager', 'finance',
}.contains(role);
// Mirrors VendorController::assertPaymentEditAccess — once a vendor exists,
// only Finance or a Director changes where it gets paid.
bool _canEditVendorPayment(String role) => hasDirectorAuthority(role) || const {
  'super_admin', 'admin', 'finance_manager', 'finance',
}.contains(role);
bool _canVerifyReceipts(String role) =>
    hasAccountantAuthority(role) || const {'finance_manager', 'finance'}.contains(role);

(Color, Color, String) _feeStatusStyle(VendorFeeStatus s) => switch (s) {
  VendorFeeStatus.paid            => (AppColors.teal, AppColors.tealSoft, 'Paid'),
  VendorFeeStatus.rejected        => (AppColors.coral, AppColors.coralSoft, 'Rejected'),
  VendorFeeStatus.readyForPayment => (AppColors.amber, AppColors.amberSoft, 'Ready for Payment'),
  VendorFeeStatus.pendingManager  => (AppColors.violet, AppColors.violet.withValues(alpha: 0.12), 'Awaiting manager'),
  VendorFeeStatus.pendingReceipt  => (AppColors.textMute, const Color(0x0AFFFFFF), 'Pending Receipt'),
};

class VendorFeesScreen extends StatefulWidget {
  const VendorFeesScreen({super.key});

  @override
  State<VendorFeesScreen> createState() => _VendorFeesScreenState();
}

class _VendorFeesScreenState extends State<VendorFeesScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<VendorFee>   _fees = [];
  List<DeliveryJob> _jobs = [];
  List<Vendor>      _vendors = [];
  bool    _loading = true;
  String? _error;

  bool _showCreateFee = false;
  bool _showCreateJob = false;
  bool _showVendorForm = false;
  Vendor? _editingVendor;
  VendorFee? _openFee;
  DeliveryJob? _openJob;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // Stale-while-revalidate — same reasoning as InventoryItemsScreen's own
    // fix: show the last-known bundle instantly on a fresh mount (this
    // widget isn't kept alive across navigation), then quietly refresh.
    final cached = VendorFeeService.cachedFees;
    if (cached != null) {
      _fees = cached;
      _jobs = VendorFeeService.cachedDeliveryJobs ?? [];
      _vendors = VendorFeeService.cachedVendors ?? [];
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      // Only show the blank/shimmer state when there's genuinely nothing
      // to show yet — a background refresh of an already-populated bundle
      // (or a return visit seeded from the cache above) updates silently.
      if (_fees.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        VendorFeeService.instance.fees(),
        VendorFeeService.instance.deliveryJobs(),
        VendorFeeService.instance.vendors(includeInactive: true),
      ]);
      if (mounted) setState(() {
        _fees = results[0] as List<VendorFee>;
        _jobs = results[1] as List<DeliveryJob>;
        _vendors = results[2] as List<Vendor>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = userRoleNotifier.value;
    final opsTier = _isVendorOpsTier(role);

    return Stack(children: [
      Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: LayoutBuilder(builder: (context, cst) => isPhoneWidth(cst.maxWidth)
              // Phones: "Record fee" stays a button, the two "New …" go in a menu.
              ? Row(children: [
                  Expanded(child: Text('Vendors', style: AppTheme.pageTitle)),
                  if (opsTier) ...[
                    PopupMenuButton<String>(
                      tooltip: 'More actions',
                      color: context.pal.surface1,
                      icon: Icon(Symbols.more_vert, size: 20, color: context.pal.textMute),
                      onSelected: (v) => setState(() {
                        if (v == 'vendor') { _editingVendor = null; _showVendorForm = true; }
                        if (v == 'job') _showCreateJob = true;
                      }),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'vendor', child: Text('New vendor', style: AppTheme.bodySm)),
                        PopupMenuItem(value: 'job', child: Text('New job', style: AppTheme.bodySm)),
                      ],
                    ),
                    AppButton(label: 'Record fee', icon: Symbols.add, variant: BtnVariant.primary, small: true,
                      onPressed: () => setState(() => _showCreateFee = true)),
                  ],
                ])
              : Row(children: [
            Expanded(child: Text('Vendors', style: AppTheme.pageTitle, maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (opsTier) ...[
              AppButton(label: 'New vendor', icon: Symbols.add, variant: BtnVariant.ghost, small: true,
                onPressed: () => setState(() { _editingVendor = null; _showVendorForm = true; })),
              const SizedBox(width: 8),
              AppButton(label: 'New job', icon: Symbols.add, variant: BtnVariant.ghost, small: true,
                onPressed: () => setState(() => _showCreateJob = true)),
              const SizedBox(width: 8),
              AppButton(label: 'Record fee', icon: Symbols.add, variant: BtnVariant.primary, small: true,
                onPressed: () => setState(() => _showCreateFee = true)),
            ],
          ])),
        ),
        const SizedBox(height: 8),
        TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [Tab(text: 'Vendor Fees'), Tab(text: 'Delivery Jobs'), Tab(text: 'Vendors')],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              // A background refresh failing while stale-but-valid cached
              // data is already showing shouldn't blow that away — only
              // "genuinely nothing to show" surfaces the error screen.
              : _error != null && _fees.isEmpty
                  ? ErrorView(message: _error!, onRetry: _load)
                  : TabBarView(controller: _tab, children: [
                      _feesTab(opsTier),
                      _jobsTab(opsTier),
                      _vendorsTab(opsTier),
                    ]),
        ),
      ]),
      if (_showCreateFee)
        _CreateFeeDialog(
          vendors: _vendors,
          deliveryJobs: _jobs.where((j) => j.status == 'delivered' && j.feeId == null).toList(),
          onClose: () => setState(() => _showCreateFee = false),
          onSaved: () { setState(() => _showCreateFee = false); _load(); },
        ),
      if (_showCreateJob)
        _CreateJobDialog(
          deliveryVendors: _vendors.where((v) => v.type == 'delivery' || v.type == 'courier').toList(),
          onClose: () => setState(() => _showCreateJob = false),
          onSaved: () { setState(() => _showCreateJob = false); _load(); },
        ),
      if (_showVendorForm)
        _VendorFormDialog(
          vendor: _editingVendor,
          onClose: () => setState(() => _showVendorForm = false),
          onSaved: () { setState(() => _showVendorForm = false); _load(); },
        ),
      if (_openFee != null)
        _FeeDetailDialog(
          feeId: _openFee!.id,
          onClose: () => setState(() => _openFee = null),
          onChanged: _load,
        ),
      if (_openJob != null)
        _JobDetailDialog(
          jobId: _openJob!.id,
          onClose: () => setState(() => _openJob = null),
          onChanged: _load,
        ),
    ]);
  }

  Widget _feesTab(bool opsTier) {
    if (_fees.isEmpty) {
      return const Center(child: Text('No vendor fees recorded yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _fees.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final f = _fees[i];
        final (fg, bg, label) = _feeStatusStyle(f.status);
        return _Card(
          onTap: () => setState(() => _openFee = f),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.vendorName ?? '—', style: AppTheme.bodyStrong),
              const SizedBox(height: 2),
              Text(f.description, style: AppTheme.bodySub.copyWith(color: AppColors.textMute)),
              if (f.deliveryJob != null) ...[
                const SizedBox(height: 2),
                Text('Job ${f.deliveryJob!.jobNumber}', style: AppTheme.monoSm.copyWith(fontSize: 11, color: AppColors.textMute)),
              ],
            ])),
            Text(tshFromDouble(f.billedAmount), style: AppTheme.bodyStrong),
            const SizedBox(width: 16),
            _Chip(fg: fg, bg: bg, label: label),
          ]),
        );
      },
    );
  }

  Widget _jobsTab(bool opsTier) {
    if (_jobs.isEmpty) {
      return const Center(child: Text('No delivery jobs recorded yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final j = _jobs[i];
        return _Card(
          onTap: () => setState(() => _openJob = j),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(j.jobNumber, style: AppTheme.monoSm.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(j.destination ?? '—', style: AppTheme.bodySub.copyWith(color: AppColors.textMute)),
            ])),
            _Chip(
              fg: j.hasDeliveryNote ? AppColors.teal : AppColors.amber,
              bg: j.hasDeliveryNote ? AppColors.tealSoft : AppColors.amberSoft,
              label: j.hasDeliveryNote ? 'Note attached' : 'No note',
            ),
          ]),
        );
      },
    );
  }

  Widget _vendorsTab(bool opsTier) {
    if (_vendors.isEmpty) {
      return const Center(child: Text('No vendors on file yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _vendors.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final v = _vendors[i];
        return _Card(
          onTap: opsTier ? () => setState(() { _editingVendor = v; _showVendorForm = true; }) : null,
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.name, style: AppTheme.bodyStrong),
              const SizedBox(height: 2),
              Text(v.typeLabel, style: AppTheme.bodySub.copyWith(color: AppColors.textMute)),
            ])),
            _Chip(
              fg: v.isActive ? AppColors.teal : AppColors.textMute,
              bg: v.isActive ? AppColors.tealSoft : const Color(0x0AFFFFFF),
              label: v.isActive ? 'Active' : 'Inactive',
            ),
          ]),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.pal.surface1,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: context.pal.border)),
        child: child,
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.fg, required this.bg, required this.label});
  final Color fg;
  final Color bg;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: fg.withValues(alpha: 0.3))),
    child: Text(label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w500)),
  );
}

class _DialogShell extends StatelessWidget {
  const _DialogShell({required this.title, required this.icon, required this.onClose, required this.body, this.width = 460, this.footer});
  final String title;
  final IconData icon;
  final VoidCallback onClose;
  final Widget body;
  final double width;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onClose,
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(scroll: false, child: GestureDetector(
        onTap: () {},
        child: Container(
          width: width,
          constraints: const BoxConstraints(maxHeight: 640),
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
                Icon(icon, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: AppTheme.bodyStrong)),
                GestureDetector(onTap: onClose, child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: body)),
            if (footer != null)
              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: footer!),
          ]),
        ),
      )),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: AppTheme.labelCaps.copyWith(fontSize: 10)),
  );
}

/// Compact Settings-style field for the goods-list rows (item / serial / qty).
class _InlineField extends StatelessWidget {
  const _InlineField({required this.controller, required this.hint, this.number = false});
  final TextEditingController controller;
  final String hint;
  final bool number;
  @override
  Widget build(BuildContext context) => LabeledTextField(label: '', controller: controller, keyboardType: number ? TextInputType.number : null, hint: hint);
}

// ── Create Vendor Fee ────────────────────────────────────────────────────

class _CreateFeeDialog extends StatefulWidget {
  const _CreateFeeDialog({required this.vendors, required this.deliveryJobs, required this.onClose, required this.onSaved});
  final List<Vendor> vendors;
  final List<DeliveryJob> deliveryJobs;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  @override
  State<_CreateFeeDialog> createState() => _CreateFeeDialogState();
}

class _CreateFeeDialogState extends State<_CreateFeeDialog> {
  Vendor? _vendor;
  DeliveryJob? _job;
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _descCtrl.dispose(); _amountCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_saving || _vendor == null || _descCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Vendor and description are required.');
      return;
    }
    final amount = parseShillings(_amountCtrl.text);
    if (amount == null || amount < 1) { setState(() => _error = 'Enter a valid billed amount.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await VendorFeeService.instance.createFee(
        vendorId: _vendor!.id, deliveryJobId: _job?.id,
        description: _descCtrl.text.trim(), billedAmount: amount,
      );
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) => _DialogShell(
    title: 'Record vendor fee',
    icon: Symbols.receipt_long,
    onClose: widget.onClose,
    footer: Row(children: [
      const Spacer(),
      AppButton(label: 'Cancel', variant: BtnVariant.ghost, onPressed: widget.onClose),
      const SizedBox(width: 8),
      AppButton(label: _saving ? 'Saving…' : 'Save', variant: BtnVariant.primary, onPressed: _saving ? null : _save),
    ]),
    body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_error != null) ...[
        Container(width: double.infinity, padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
          child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12))),
      ],
      LabeledDropdown<Vendor?>(
        label: 'Vendor',
        value: _vendor,
        items: [null, ...widget.vendors],
        displayBuilder: (v) => v == null ? 'Select…' : '${v.name} (${v.typeLabel})',
        onChanged: (v) => setState(() => _vendor = v),
      ),
      const SizedBox(height: 14),
      LabeledDropdown<DeliveryJob?>(
        label: 'Delivery job · USIRI only, optional',
        value: _job,
        items: [null, ...widget.deliveryJobs],
        displayBuilder: (j) => j == null ? 'Not linked' : j.jobNumber,
        onChanged: (j) => setState(() => _job = j),
      ),
      const SizedBox(height: 14),
      LabeledTextField(label: 'Description', controller: _descCtrl),
      const SizedBox(height: 14),
      LabeledTextField(label: 'Billed amount (TZS)', controller: _amountCtrl, keyboardType: TextInputType.number),
    ]),
  );
}

// ── Vendor Fee detail ────────────────────────────────────────────────────

/// A vendor/clearing fee's detail with its actions, from anywhere (Approvals).
Future<void> showVendorFeeDetail(BuildContext context, int feeId, {VoidCallback? onChanged}) => showDialog<void>(
  context: context,
  barrierColor: Colors.transparent,
  builder: (c) => Material(type: MaterialType.transparency, child: _FeeDetailDialog(
    feeId: feeId, onClose: () => Navigator.pop(c), onChanged: onChanged ?? () {})),
);

class _FeeDetailDialog extends StatefulWidget {
  const _FeeDetailDialog({required this.feeId, required this.onClose, required this.onChanged});
  final int feeId;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  @override
  State<_FeeDetailDialog> createState() => _FeeDetailDialogState();
}

class _FeeDetailDialogState extends State<_FeeDetailDialog> {
  VendorFee? _fee;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — same reasoning as InventoryService's screen
    // cache: this dialog is a fresh widget/State every time it's opened (it
    // only exists in the tree while `_openFee != null`), so seed from the
    // last-known fetch of this exact fee if we have one.
    final cached = VendorFeeService.cachedFeeById[widget.feeId];
    if (cached != null) { _fee = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_fee == null) _loading = true;
      _error = null;
    });
    try {
      final fee = await VendorFeeService.instance.fee(widget.feeId);
      if (mounted) setState(() { _fee = fee; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _uploadReceipt() async {
    final fee = _fee;
    if (fee == null) return;
    setState(() => _busy = true);
    final attached = await attachVendorReceipt(context, fee.id, issuerHint: fee.vendorName,
        amountHint: fee.billedAmount - fee.receiptsTotal);
    if (mounted) setState(() => _busy = false);
    if (attached && mounted) { await _load(); widget.onChanged(); }
  }

  Future<void> _verifyReceipt(VendorReceipt r) async {
    setState(() => _busy = true);
    try {
      await VendorFeeService.instance.verifyReceipt(widget.feeId, r.id);
      if (mounted) { showSuccessToast(context, 'Receipt verified.'); await _load(); widget.onChanged(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewReceipt(VendorReceipt r) async {
    final name = r.fileName ?? 'receipt-${r.receiptNumber}.pdf';
    if (name.toLowerCase().endsWith('.pdf')) {
      return downloadPdf(context, () => VendorFeeService.instance.receiptFile(widget.feeId, r.id), name);
    }
    // A photo: save it and open it in the PC's own viewer.
    try {
      final bytes = await VendorFeeService.instance.receiptFile(widget.feeId, r.id);
      final file = await DownloadManager.instance.save(bytes, name);
      await launchUrl(Uri.file(file.path));
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  // Admin: correct the details and/or replace the file (user, 2026-10-26).
  Future<void> _editReceipt(VendorReceipt r) async {
    final data = await showDialog<Map<String, dynamic>>(context: context,
        builder: (_) => _ReceiptUploadDialog(existing: r, issuerHint: r.issuerName, amountHint: r.amount));
    if (data == null || !mounted) return;
    String? path, fileName;
    if (data['replace_file'] == true) {
      FilePickerResult? res;
      try {
        res = await FilePicker.pickFiles(allowMultiple: false, withData: false,
            type: FileType.custom, allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg']);
      } catch (e) {
        if (mounted) showErrorToast(context, Exception('Couldn\'t open the file picker: $e'));
        return;
      }
      if (res == null || res.files.isEmpty || res.files.first.path == null) return;
      path = res.files.first.path;
      fileName = res.files.first.name;
    }
    setState(() => _busy = true);
    try {
      await VendorFeeService.instance.updateReceipt(widget.feeId, r.id, {
        for (final k in ['receipt_type', 'receipt_number', 'issuer_name', 'issuer_tin', 'receipt_date', 'amount']) k: data[k],
      }, filePath: path, fileName: fileName);
      if (mounted) { showSuccessToast(context, 'Receipt updated.'); await _load(); widget.onChanged(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteReceipt(VendorReceipt r) async {
    setState(() => _busy = true);
    try {
      await VendorFeeService.instance.deleteReceipt(widget.feeId, r.id);
      if (mounted) { showSuccessToast(context, 'Receipt removed.'); await _load(); widget.onChanged(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitForPayment() async {
    setState(() => _busy = true);
    try {
      await VendorFeeService.instance.submitForPayment(widget.feeId);
      if (mounted) { showSuccessToast(context, 'Submitted for payment approval.'); await _load(); widget.onChanged(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final ref = await showDialog<String>(context: context, builder: (_) => const _PaymentReferenceDialog());
    if (ref == null || ref.trim().isEmpty || !mounted) return;
    final account = await pickPaymentAccount(context, title: 'Paid from',
        note: 'The bank account the fee is paid from — it posts there and clears the vendor\'s ledger.');
    if (account == null) return;
    setState(() => _busy = true);
    try {
      await VendorFeeService.instance.approve(widget.feeId, paymentReference: ref.trim(), paidFromAccountId: account.id);
      if (mounted) { showSuccessToast(context, 'Payment approved.'); await _load(); widget.onChanged(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // The recorder's manager (Patrick) approves first, then it goes to Finance.
  Future<void> _managerApprove() async {
    setState(() => _busy = true);
    try {
      await VendorFeeService.instance.managerApprove(widget.feeId);
      if (mounted) { showSuccessToast(context, 'Approved — sent to Finance to request payment.'); await _load(); widget.onChanged(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _managerReject() async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _ReasonDialog(title: 'Reject vendor fee', minLength: 10));
    if (reason == null || reason.trim().length < 10) return;
    setState(() => _busy = true);
    try {
      await VendorFeeService.instance.managerReject(widget.feeId, reason: reason.trim());
      if (mounted) { showSuccessToast(context, 'Rejected — the recorder was told why.'); await _load(); widget.onChanged(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _ReasonDialog(title: 'Reject vendor fee', minLength: 10));
    if (reason == null || reason.trim().length < 10) return;
    setState(() => _busy = true);
    try {
      await VendorFeeService.instance.reject(widget.feeId, reason: reason.trim());
      if (mounted) { showSuccessToast(context, 'Vendor fee rejected.'); await _load(); widget.onChanged(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = userRoleNotifier.value;
    final opsTier = _isVendorOpsTier(role);
    final canVerify = _canVerifyReceipts(role);
    final canSubmit = hasAccountantAuthority(role);
    final canApproveReject = hasFinalMoneyAuthority(role);
    final fee = _fee;

    return _DialogShell(
      title: fee?.description ?? 'Vendor fee',
      icon: Symbols.receipt_long,
      onClose: widget.onClose,
      width: 560,
      footer: fee == null ? null : Row(children: [
        if (fee.status == VendorFeeStatus.pendingManager && (fee.approverId == userIdNotifier.value || hasDirectorAuthority(role))) ...[
          AppButton(label: 'Approve', variant: BtnVariant.primary, icon: Symbols.check, onPressed: _busy ? null : _managerApprove),
          const SizedBox(width: 8),
          AppButton(label: 'Reject', variant: BtnVariant.danger, icon: Symbols.close, onPressed: _busy ? null : _managerReject),
        ],
        if (fee.status == VendorFeeStatus.pendingReceipt && canSubmit)
          AppButton(label: 'Submit for Payment', variant: BtnVariant.primary, icon: Symbols.check,
            onPressed: (_busy || !fee.isPayable) ? null : _submitForPayment),
        if (fee.status == VendorFeeStatus.readyForPayment && canApproveReject) ...[
          AppButton(label: 'Money is out', variant: BtnVariant.primary, icon: Symbols.check, onPressed: _busy ? null : _approve),
          const SizedBox(width: 8),
          AppButton(label: 'Reject', variant: BtnVariant.danger, icon: Symbols.close, onPressed: _busy ? null : _reject),
        ],
        const Spacer(),
        AppButton(label: 'Close', variant: BtnVariant.ghost, onPressed: widget.onClose),
      ]),
      body: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          // A background refresh failing while stale-but-valid cached data
          // is already showing shouldn't blow that away — only "genuinely
          // nothing to show" (fee == null) surfaces the error text.
          : fee == null
              ? Text(_error ?? 'Not found', style: TextStyle(color: AppColors.coral))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(fee.vendorName ?? '—', style: AppTheme.bodyStrong)),
                    Text(tshFromDouble(fee.billedAmount), style: AppTheme.bodyStrong),
                  ]),
                  const SizedBox(height: 4),
                  Builder(builder: (_) {
                    final (fg, bg, label) = _feeStatusStyle(fee.status);
                    return _Chip(fg: fg, bg: bg, label: fee.statusLabel ?? label);
                  }),
                  if (fee.receiptFollowUp != null) ...[
                    const SizedBox(height: 12),
                    Container(width: double.infinity, padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(8)),
                      child: Text(fee.receiptFollowUp!, style: TextStyle(color: AppColors.amber, fontSize: 12.5))),
                  ],
                  if (fee.paymentBlockReason != null) ...[
                    const SizedBox(height: 12),
                    Container(width: double.infinity, padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(8)),
                      child: Text(fee.paymentBlockReason!, style: TextStyle(color: AppColors.amber, fontSize: 12.5))),
                  ],
                  if (fee.rejectionReason != null) ...[
                    const SizedBox(height: 12),
                    Container(width: double.infinity, padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
                      child: Text('Rejected by ${fee.rejectedBy ?? '—'} — ${fee.rejectionReason}', style: TextStyle(color: AppColors.coral, fontSize: 12.5))),
                  ],
                  if (fee.paymentReference != null) ...[
                    const SizedBox(height: 12),
                    Container(width: double.infinity, padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(8)),
                      child: Text('Paid by ${fee.paidBy ?? '—'} · Ref ${fee.paymentReference}', style: TextStyle(color: AppColors.teal, fontSize: 12.5))),
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: Text('RECEIPTS', style: AppTheme.labelCaps.copyWith(fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    // Clearing fees are paid first, so their receipt can come in after payment.
                    if (opsTier && (fee.status == VendorFeeStatus.pendingReceipt || fee.status == VendorFeeStatus.pendingManager ||
                        (fee.receiptAfterPayment && fee.status != VendorFeeStatus.rejected && fee.receiptsTotal < fee.billedAmount)))
                      AppButton(label: 'Attach', icon: Symbols.add, variant: BtnVariant.ghost, small: true, onPressed: _busy ? null : _uploadReceipt),
                  ]),
                  const SizedBox(height: 8),
                  if (fee.receipts.isEmpty)
                    Text('No receipts attached yet.', style: TextStyle(color: AppColors.textMute, fontSize: 13))
                  else
                    ...fee.receipts.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.pal.border)),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${r.receiptType.toUpperCase()} · ${r.receiptNumber}', style: AppTheme.monoSm.copyWith(fontSize: 12)),
                            Text('${r.issuerName} · ${tshFromDouble(r.amount)}', style: TextStyle(color: AppColors.textMute, fontSize: 11.5)),
                          ])),
                          if (r.fileName != null)
                            IconButton(icon: const Icon(Symbols.visibility, size: 16), onPressed: () => _viewReceipt(r), tooltip: 'View receipt'),
                          // Admin: correct or replace any receipt; remove a verified one (e.g. uploaded twice).
                          if (hasDirectorAuthority(role)) ...[
                            IconButton(icon: const Icon(Symbols.edit, size: 16), onPressed: _busy ? null : () => _editReceipt(r), tooltip: 'Edit / replace'),
                            if (r.verified)
                              IconButton(icon: Icon(Symbols.delete, size: 16, color: AppColors.coral), onPressed: _busy ? null : () => _deleteReceipt(r), tooltip: 'Remove'),
                          ],
                          if (r.verified)
                            _Chip(fg: AppColors.teal, bg: AppColors.tealSoft, label: 'Verified')
                          else ...[
                            _Chip(fg: AppColors.amber, bg: AppColors.amberSoft, label: 'Unverified'),
                            if (canVerify)
                              IconButton(icon: const Icon(Symbols.check, size: 16), onPressed: _busy ? null : () => _verifyReceipt(r), tooltip: 'Verify'),
                            if (opsTier)
                              IconButton(icon: Icon(Symbols.delete, size: 16, color: AppColors.coral), onPressed: _busy ? null : () => _deleteReceipt(r), tooltip: 'Remove'),
                          ],
                        ]),
                      ),
                    )),
                ]),
    );
  }
}

/// Attach a receipt to a vendor fee: its details, then the file. Also used
/// on a shipment's clearing fee (Shipments → Clearing fee → Attach receipt).
/// True when one was attached.
Future<bool> attachVendorReceipt(BuildContext context, int feeId, {String? issuerHint, int? amountHint}) async {
  final data = await showDialog<Map<String, dynamic>>(context: context,
      builder: (_) => _ReceiptUploadDialog(issuerHint: issuerHint, amountHint: amountHint));
  if (!context.mounted || data == null) return false;
  if (Platform.isAndroid) {
    showErrorToast(context, Exception('File uploads aren\'t available on Android in this build.'));
    return false;
  }
  // Some Windows PCs fail to open the file dialog; say so instead of doing nothing.
  FilePickerResult? result;
  try {
    result = await FilePicker.pickFiles(allowMultiple: false, withData: false,
        type: FileType.custom, allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg']);
  } catch (e) {
    if (context.mounted) showErrorToast(context, Exception('Couldn\'t open the file picker: $e'));
    return false;
  }
  if (result == null || result.files.isEmpty) return false;
  if (result.files.first.path == null) {
    if (context.mounted) showErrorToast(context, Exception('That file can\'t be read from here — save it to the PC (e.g. Documents) and pick it again.'));
    return false;
  }
  try {
    await VendorFeeService.instance.uploadReceipt(
      feeId, result.files.first.path!, result.files.first.name,
      receiptType: data['receipt_type'], receiptNumber: data['receipt_number'],
      issuerName: data['issuer_name'], issuerTin: data['issuer_tin'],
      receiptDate: data['receipt_date'], amount: data['amount'],
    );
    if (context.mounted) showSuccessToast(context, 'Receipt attached — Finance verifies it next.');
    return true;
  } catch (e) {
    if (context.mounted) showErrorToast(context, e);
    return false;
  }
}

class _ReceiptUploadDialog extends StatefulWidget {
  const _ReceiptUploadDialog({this.issuerHint, this.amountHint, this.existing});
  /// Editing this receipt (admin) rather than attaching a new one.
  final VendorReceipt? existing;
  final String? issuerHint;
  /// What's still to be covered by receipts — filled in for the user.
  final int? amountHint;

  @override
  State<_ReceiptUploadDialog> createState() => _ReceiptUploadDialogState();
}

class _ReceiptUploadDialogState extends State<_ReceiptUploadDialog> {
  late String _type = widget.existing?.receiptType ?? 'efd';
  late final _numberCtrl = TextEditingController(text: widget.existing?.receiptNumber ?? '');
  bool _replaceFile = false;
  late final _issuerCtrl = TextEditingController(text: widget.issuerHint ?? '');
  late final _tinCtrl = TextEditingController(text: widget.existing?.issuerTin ?? '');
  late DateTime _date = DateTime.tryParse(widget.existing?.receiptDate ?? '') ?? DateTime.now();
  late final _amountCtrl = TextEditingController(
      text: (widget.amountHint ?? 0) > 0 ? widget.amountHint.toString() : '');
  String? _error;

  @override
  void dispose() { _numberCtrl.dispose(); _issuerCtrl.dispose(); _tinCtrl.dispose(); _amountCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Attach receipt' : 'Edit receipt'),
    content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabeledDropdown<String>(
        label: 'Receipt type',
        value: _type,
        items: const ['efd', 'other'],
        displayBuilder: (v) => v == 'efd' ? 'EFD' : 'Other',
        onChanged: (v) => setState(() => _type = v),
      ),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Receipt number', controller: _numberCtrl),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Issuer name', controller: _issuerCtrl),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Issuer TIN (optional)', controller: _tinCtrl),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Amount (TZS)', controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true), hint: 'e.g. 350,000.50'),
      const SizedBox(height: 8),
      Row(children: [
        Text('Date: ${_date.toIso8601String().substring(0, 10)}'),
        const Spacer(),
        TextButton(onPressed: () async {
          final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (picked != null) setState(() => _date = picked);
        }, child: const Text('Change')),
      ]),
      if (widget.existing != null)
        CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, value: _replaceFile,
            onChanged: (v) => setState(() => _replaceFile = v ?? false),
            title: Text('Replace the file (${widget.existing!.fileName ?? 'none'})', style: AppTheme.bodySm)),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
      ],
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () {
        final amount = parseShillings(_amountCtrl.text);
        // Say what's missing — the button used to do nothing at all.
        final problem = _numberCtrl.text.trim().isEmpty ? 'Enter the receipt number.'
            : _issuerCtrl.text.trim().isEmpty ? 'Enter who issued the receipt.'
            : amount == null || amount < 1 ? 'Enter the amount on the receipt.'
            : null;
        if (problem != null) { setState(() => _error = problem); return; }
        Navigator.pop(context, {
          'receipt_type': _type, 'receipt_number': _numberCtrl.text.trim(), 'issuer_name': _issuerCtrl.text.trim(),
          'issuer_tin': _tinCtrl.text.trim().isEmpty ? null : _tinCtrl.text.trim(),
          'receipt_date': _date.toIso8601String().substring(0, 10), 'amount': amount,
          'replace_file': _replaceFile,
        });
      }, child: Text(widget.existing == null ? 'Pick file & attach' : (_replaceFile ? 'Pick new file & save' : 'Save'))),
    ],
  );
}

class _PaymentReferenceDialog extends StatefulWidget {
  const _PaymentReferenceDialog();
  @override
  State<_PaymentReferenceDialog> createState() => _PaymentReferenceDialogState();
}

class _PaymentReferenceDialogState extends State<_PaymentReferenceDialog> {
  final _ctrl = TextEditingController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Money is out — approve and release payment'),
    content: SizedBox(width: 380, child: LabeledTextField(label: 'Transfer reference', controller: _ctrl)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Money is out')),
    ],
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, this.minLength = 0});
  final String title;
  final int minLength;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _ctrl = TextEditingController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(width: 380, child: LabeledTextField(label: widget.minLength > 0 ? 'Reason (min. ${widget.minLength} characters)' : 'Reason', controller: _ctrl, maxLines: 3)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Confirm')),
    ],
  );
}

// ── Delivery jobs ────────────────────────────────────────────────────────

class _CreateJobDialog extends StatefulWidget {
  const _CreateJobDialog({required this.deliveryVendors, required this.onClose, required this.onSaved});
  final List<Vendor> deliveryVendors;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  @override
  State<_CreateJobDialog> createState() => _CreateJobDialogState();
}

class _CreateJobDialogState extends State<_CreateJobDialog> {
  final _numberCtrl = TextEditingController();
  Vendor? _vendor;
  final _destCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final List<_GoodsLineControllers> _lines = [_GoodsLineControllers()];
  bool _saving = false;
  String? _error;

  @override
  void initState() { super.initState(); _vendor = widget.deliveryVendors.isNotEmpty ? widget.deliveryVendors.first : null; }

  @override
  void dispose() {
    _numberCtrl.dispose(); _destCtrl.dispose(); _addressCtrl.dispose();
    for (final l in _lines) { l.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _vendor == null || _numberCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Job number and vendor are required.');
      return;
    }
    final goods = _lines.where((l) => l.itemCtrl.text.trim().isNotEmpty).map((l) => DeliveryGoodsLine(
      item: l.itemCtrl.text.trim(),
      serial: l.serialCtrl.text.trim().isEmpty ? null : l.serialCtrl.text.trim(),
      quantity: int.tryParse(l.qtyCtrl.text.trim()) ?? 1,
    )).toList();
    if (goods.isEmpty) { setState(() => _error = 'Add at least one goods line.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await VendorFeeService.instance.createDeliveryJob(
        jobNumber: _numberCtrl.text.trim(), vendorId: _vendor!.id,
        destinationName: _destCtrl.text.trim().isEmpty ? null : _destCtrl.text.trim(),
        destinationAddress: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        goodsList: goods,
      );
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) => _DialogShell(
    title: 'New delivery job',
    icon: Symbols.local_shipping,
    onClose: widget.onClose,
    footer: Row(children: [
      const Spacer(),
      AppButton(label: 'Cancel', variant: BtnVariant.ghost, onPressed: widget.onClose),
      const SizedBox(width: 8),
      AppButton(label: _saving ? 'Saving…' : 'Create job', variant: BtnVariant.primary, onPressed: _saving ? null : _save),
    ]),
    body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_error != null) ...[
        Container(width: double.infinity, padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
          child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12))),
      ],
      if (widget.deliveryVendors.isEmpty)
        Text('No delivery or courier vendors yet — add one first.', style: TextStyle(color: AppColors.amber, fontSize: 12.5)),
      LabeledTextField(label: 'Job number', controller: _numberCtrl),
      const SizedBox(height: 14),
      LabeledDropdown<Vendor?>(
        label: 'Vendor · USIRI / delivery / courier',
        value: _vendor,
        items: [null, ...widget.deliveryVendors],
        displayBuilder: (v) => v == null ? 'Select…' : v.name,
        onChanged: (v) => setState(() => _vendor = v),
      ),
      const SizedBox(height: 14),
      LabeledTextField(label: 'Destination name', controller: _destCtrl),
      const SizedBox(height: 14),
      LabeledTextField(label: 'Destination address', controller: _addressCtrl, maxLines: 2),
      const SizedBox(height: 14),
      const _FieldLabel('Goods list'),
      ..._lines.map((l) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(flex: 2, child: _InlineField(controller: l.itemCtrl, hint: 'Item')),
          const SizedBox(width: 8),
          Expanded(child: _InlineField(controller: l.serialCtrl, hint: 'Serial')),
          const SizedBox(width: 8),
          SizedBox(width: 60, child: _InlineField(controller: l.qtyCtrl, hint: 'Qty', number: true)),
          IconButton(icon: const Icon(Symbols.close, size: 16), onPressed: () => setState(() => _lines.remove(l))),
        ]),
      )),
      AppButton(label: 'Add item', icon: Symbols.add, variant: BtnVariant.ghost, small: true,
        onPressed: () => setState(() => _lines.add(_GoodsLineControllers()))),
    ]),
  );
}

class _GoodsLineControllers {
  final itemCtrl = TextEditingController();
  final serialCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  void dispose() { itemCtrl.dispose(); serialCtrl.dispose(); qtyCtrl.dispose(); }
}

class _JobDetailDialog extends StatefulWidget {
  const _JobDetailDialog({required this.jobId, required this.onClose, required this.onChanged});
  final int jobId;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  @override
  State<_JobDetailDialog> createState() => _JobDetailDialogState();
}

class _JobDetailDialogState extends State<_JobDetailDialog> {
  DeliveryJob? _job;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — same reasoning as InventoryService's screen
    // cache: this dialog is a fresh widget/State every time it's opened (it
    // only exists in the tree while `_openJob != null`), so seed from the
    // last-known fetch of this exact job if we have one.
    final cached = VendorFeeService.cachedJobById[widget.jobId];
    if (cached != null) { _job = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_job == null) _loading = true;
      _error = null;
    });
    try {
      final job = await VendorFeeService.instance.deliveryJob(widget.jobId);
      if (mounted) setState(() { _job = job; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _uploadNote() async {
    final job = _job;
    if (job == null) return;
    final data = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _DeliveryNoteDialog(goodsList: job.goodsList));
    if (!mounted || data == null) return;
    if (Platform.isAndroid) {
      showErrorToast(context, Exception('File uploads aren\'t available on Android in this build.'));
      return;
    }
    final result = await FilePicker.pickFiles(allowMultiple: false, withData: false);
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    setState(() => _busy = true);
    try {
      await VendorFeeService.instance.uploadDeliveryNote(
        job.id, result.files.first.path!, result.files.first.name,
        receiverName: data['receiver_name'], deliveryDate: data['delivery_date'],
        deliveredGoods: data['delivered_goods'] as List<DeliveryGoodsLine>,
      );
      if (mounted) { showSuccessToast(context, 'Delivery note attached.'); await _load(); widget.onChanged(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final opsTier = _isVendorOpsTier(userRoleNotifier.value);
    final job = _job;
    return _DialogShell(
      title: job?.jobNumber ?? 'Delivery job',
      icon: Symbols.local_shipping,
      onClose: widget.onClose,
      width: 520,
      footer: Row(children: [
        if (job != null && !job.hasDeliveryNote && opsTier)
          AppButton(label: 'Attach delivery note', icon: Symbols.add, variant: BtnVariant.primary, onPressed: _busy ? null : _uploadNote),
        const Spacer(),
        AppButton(label: 'Close', variant: BtnVariant.ghost, onPressed: widget.onClose),
      ]),
      body: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          // A background refresh failing while stale-but-valid cached data
          // is already showing shouldn't blow that away — only "genuinely
          // nothing to show" (job == null) surfaces the error text.
          : job == null
              ? Text(_error ?? 'Not found', style: TextStyle(color: AppColors.coral))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(job.vendorName ?? '—', style: AppTheme.bodyStrong),
                  Text(job.destination ?? '—', style: TextStyle(color: AppColors.textMute, fontSize: 13)),
                  if (job.feeId != null) ...[
                    const SizedBox(height: 8),
                    Text('Already billed (fee #${job.feeId}).', style: TextStyle(color: AppColors.teal, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 16),
                  Text('GOODS LIST', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
                  const SizedBox(height: 8),
                  ...job.goodsList.map((g) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${g.item} × ${g.quantity}${g.serial != null ? ' (${g.serial})' : ''}', style: const TextStyle(fontSize: 13)),
                  )),
                  const SizedBox(height: 16),
                  Text('DELIVERY NOTE', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
                  const SizedBox(height: 8),
                  if (job.hasDeliveryNote) ...[
                    Text('Received by ${job.deliveryNoteReceiverName ?? '—'} on ${job.deliveryNoteDate ?? '—'}', style: const TextStyle(fontSize: 13)),
                    if (job.deliveryNoteGoodsMismatch)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Container(width: double.infinity, padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(8)),
                        child: Text('The delivered goods list doesn\'t match the job\'s original goods list — review before paying.', style: TextStyle(color: AppColors.amber, fontSize: 12.5)))),
                  ] else
                    Text('No delivery note attached yet — required before this job\'s fee can be paid.', style: TextStyle(color: AppColors.textMute, fontSize: 13)),
                ]),
    );
  }
}

class _DeliveryNoteDialog extends StatefulWidget {
  const _DeliveryNoteDialog({required this.goodsList});
  final List<DeliveryGoodsLine> goodsList;

  @override
  State<_DeliveryNoteDialog> createState() => _DeliveryNoteDialogState();
}

class _DeliveryNoteDialogState extends State<_DeliveryNoteDialog> {
  final _receiverCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  late final List<_GoodsLineControllers> _lines = widget.goodsList.isEmpty
      ? [_GoodsLineControllers()]
      : widget.goodsList.map((g) {
          final c = _GoodsLineControllers();
          c.itemCtrl.text = g.item;
          c.serialCtrl.text = g.serial ?? '';
          c.qtyCtrl.text = g.quantity.toString();
          return c;
        }).toList();

  @override
  void dispose() { _receiverCtrl.dispose(); for (final l in _lines) { l.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Attach signed delivery note'),
    content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabeledTextField(label: "Receiver's full name", controller: _receiverCtrl),
      const SizedBox(height: 8),
      Row(children: [
        Text('Date: ${_date.toIso8601String().substring(0, 10)}'),
        const Spacer(),
        TextButton(onPressed: () async {
          final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (picked != null) setState(() => _date = picked);
        }, child: const Text('Change')),
      ]),
      const SizedBox(height: 8),
      const Text('Delivered goods'),
      ..._lines.map((l) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(flex: 2, child: _InlineField(controller: l.itemCtrl, hint: 'Item')),
          const SizedBox(width: 6),
          Expanded(child: _InlineField(controller: l.serialCtrl, hint: 'Serial')),
          const SizedBox(width: 6),
          SizedBox(width: 50, child: _InlineField(controller: l.qtyCtrl, hint: 'Qty', number: true)),
        ]),
      )),
    ]))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () {
        if (_receiverCtrl.text.trim().isEmpty) return;
        final goods = _lines.where((l) => l.itemCtrl.text.trim().isNotEmpty).map((l) => DeliveryGoodsLine(
          item: l.itemCtrl.text.trim(), serial: l.serialCtrl.text.trim().isEmpty ? null : l.serialCtrl.text.trim(),
          quantity: int.tryParse(l.qtyCtrl.text.trim()) ?? 1,
        )).toList();
        Navigator.pop(context, {
          'receiver_name': _receiverCtrl.text.trim(),
          'delivery_date': _date.toIso8601String().substring(0, 10),
          'delivered_goods': goods,
        });
      }, child: const Text('Pick file & attach')),
    ],
  );
}

// ── Vendor form ──────────────────────────────────────────────────────────

class _VendorFormDialog extends StatefulWidget {
  const _VendorFormDialog({required this.onClose, required this.onSaved, this.vendor});
  final Vendor? vendor;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  @override
  State<_VendorFormDialog> createState() => _VendorFormDialogState();
}

class _VendorFormDialogState extends State<_VendorFormDialog> {
  late final _nameCtrl = TextEditingController(text: widget.vendor?.name ?? '');
  late String _type = widget.vendor?.type ?? 'clearing';
  late final _tinCtrl = TextEditingController(text: widget.vendor?.tin ?? '');
  late String? _accountType = widget.vendor?.paymentAccountType;
  late final _accountNameCtrl = TextEditingController(text: widget.vendor?.paymentAccountName ?? '');
  late final _accountNumberCtrl = TextEditingController(text: widget.vendor?.paymentAccountNumber ?? '');
  late final _bankNameCtrl = TextEditingController(text: widget.vendor?.paymentBankName ?? '');
  late final _contactNameCtrl = TextEditingController(text: widget.vendor?.contactName ?? '');
  late final _contactPhoneCtrl = TextEditingController(text: widget.vendor?.contactPhone ?? '');
  late final _contactEmailCtrl = TextEditingController(text: widget.vendor?.contactEmail ?? '');
  late bool _isActive = widget.vendor?.isActive ?? true;
  bool _saving = false;
  String? _error;
  // New vendors take payment details from whoever adds them; after that, Finance.
  late final bool _paymentEditable = widget.vendor == null || _canEditVendorPayment(userRoleNotifier.value);

  String get _paymentSummary {
    final parts = [
      switch (_accountType) { 'bank' => 'Bank', 'mobile_money' => 'Mobile money', _ => '' },
      _accountNameCtrl.text, _accountNumberCtrl.text, _bankNameCtrl.text,
    ].where((x) => x.trim().isNotEmpty);
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _tinCtrl.dispose(); _accountNameCtrl.dispose(); _accountNumberCtrl.dispose();
    _bankNameCtrl.dispose(); _contactNameCtrl.dispose(); _contactPhoneCtrl.dispose(); _contactEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _nameCtrl.text.trim().isEmpty) { setState(() => _error = 'Name is required.'); return; }
    setState(() { _saving = true; _error = null; });
    final data = {
      'name': _nameCtrl.text.trim(), 'type': _type,
      'tin': _tinCtrl.text.trim().isEmpty ? null : _tinCtrl.text.trim(),
      if (_paymentEditable) ...{
        'payment_account_type': _accountType,
        'payment_account_name': _accountNameCtrl.text.trim().isEmpty ? null : _accountNameCtrl.text.trim(),
        'payment_account_number': _accountNumberCtrl.text.trim().isEmpty ? null : _accountNumberCtrl.text.trim(),
        'payment_bank_name': _bankNameCtrl.text.trim().isEmpty ? null : _bankNameCtrl.text.trim(),
      },
      'contact_name': _contactNameCtrl.text.trim().isEmpty ? null : _contactNameCtrl.text.trim(),
      'contact_phone': _contactPhoneCtrl.text.trim().isEmpty ? null : _contactPhoneCtrl.text.trim(),
      'contact_email': _contactEmailCtrl.text.trim().isEmpty ? null : _contactEmailCtrl.text.trim(),
      if (widget.vendor != null) 'is_active': _isActive,
    };
    try {
      if (widget.vendor != null) {
        await VendorFeeService.instance.updateVendor(widget.vendor!.id, data);
      } else {
        await VendorFeeService.instance.createVendor(data);
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) => _DialogShell(
    title: widget.vendor != null ? 'Edit vendor' : 'Add vendor',
    icon: Symbols.local_shipping,
    onClose: widget.onClose,
    footer: Row(children: [
      const Spacer(),
      AppButton(label: 'Cancel', variant: BtnVariant.ghost, onPressed: widget.onClose),
      const SizedBox(width: 8),
      AppButton(label: _saving ? 'Saving…' : 'Save', variant: BtnVariant.primary, onPressed: _saving ? null : _save),
    ]),
    body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_error != null) ...[
        Container(width: double.infinity, padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
          child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12))),
      ],
      LabeledTextField(label: 'Name', controller: _nameCtrl),
      const SizedBox(height: 14),
      LabeledDropdown<String>(
        label: 'Type',
        value: _type,
        items: const ['clearing', 'delivery', 'courier', 'other'],
        displayBuilder: (v) => switch (v) {
          'clearing' => 'Clearing / transit',
          'delivery' => 'Delivery',
          'courier' => 'Courier — clears and delivers (DHL, FedEx…)',
          _ => 'Other',
        },
        onChanged: (v) => setState(() => _type = v),
      ),
      const SizedBox(height: 14),
      LabeledTextField(label: 'Tin', controller: _tinCtrl),
      const SizedBox(height: 14),
      if (_paymentEditable) ...[
        LabeledDropdown<String?>(
          label: 'Payment account type',
          value: _accountType,
          items: const [null, 'bank', 'mobile_money'],
          displayBuilder: (v) => switch (v) { 'bank' => 'Bank', 'mobile_money' => 'Mobile money', _ => '—' },
          onChanged: (v) => setState(() => _accountType = v),
        ),
        const SizedBox(height: 14),
        LabeledTextField(label: 'Account name', controller: _accountNameCtrl),
        const SizedBox(height: 14),
        LabeledTextField(label: 'Account number', controller: _accountNumberCtrl),
        const SizedBox(height: 14),
        LabeledTextField(label: 'Bank name', controller: _bankNameCtrl),
      ] else ...[
        LabeledStaticField(label: 'Payment account', value: _paymentSummary),
        const SizedBox(height: 4),
        Text('Only Finance or a Director can change where an existing vendor is paid.',
            style: TextStyle(fontSize: 11, color: context.pal.textDim)),
      ],
      const SizedBox(height: 14),
      LabeledTextField(label: 'Contact name', controller: _contactNameCtrl),
      const SizedBox(height: 14),
      LabeledTextField(label: 'Contact phone', controller: _contactPhoneCtrl),
      const SizedBox(height: 14),
      LabeledTextField(label: 'Contact email', controller: _contactEmailCtrl),
      if (widget.vendor != null) ...[
        const SizedBox(height: 14),
        Row(children: [
          Checkbox(value: _isActive, onChanged: (v) => setState(() => _isActive = v ?? true)),
          const Text('Active'),
        ]),
      ],
    ]),
  );
}
