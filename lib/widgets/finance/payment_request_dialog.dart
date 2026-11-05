import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/creditor.dart';
import '../../services/creditor_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../common/labeled_field.dart';

/// What Finance fills in to ask for a payment: the amount in the creditor's
/// currency, the exchange rate, the bank/cash account it leaves from, date
/// and the bank reference. The Director approves it before it posts.
///
/// [allowOnCredit] (LPOs) adds "On credit": the supplier is paid later
/// against their invoice, so no payment is made now.
/// Returns the request body for the API, or null when cancelled.
Future<Map<String, dynamic>?> showPaymentRequestDialog(
  BuildContext context, {
  required String title,
  required String creditorName,
  required String currency,
  double? amount,
  String? hint,
  bool allowOnCredit = false,
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogCtx) => _PaymentRequestDialog(
        title: title, creditorName: creditorName, currency: currency.toUpperCase(),
        amount: amount, hint: hint, allowOnCredit: allowOnCredit,
      ),
    );

/// Just the account picker (vendor fees, per diem): returns the chosen
/// account, or null when cancelled.
Future<PaymentAccount?> pickPaymentAccount(BuildContext context, {required String title, String? note}) =>
    showDialog<PaymentAccount>(context: context, builder: (dialogCtx) => _AccountOnlyDialog(title: title, note: note));

class _PaymentRequestDialog extends StatefulWidget {
  const _PaymentRequestDialog({required this.title, required this.creditorName, required this.currency,
    this.amount, this.hint, this.allowOnCredit = false});
  final String title;
  final String creditorName;
  final String currency;
  final double? amount;
  final String? hint;
  final bool allowOnCredit;

  @override
  State<_PaymentRequestDialog> createState() => _PaymentRequestDialogState();
}

class _PaymentRequestDialogState extends State<_PaymentRequestDialog> {
  late final _amount = TextEditingController(text: widget.amount == null ? '' : _plain(widget.amount!));
  final _rate = TextEditingController();
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  bool _onCredit = false;
  List<PaymentAccount>? _accounts;
  PaymentAccount? _account;
  String? _error;

  bool get _foreign => widget.currency != 'TZS';

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  static double? _num(String s) => double.tryParse(s.replaceAll(',', '').trim());

  @override
  void initState() {
    super.initState();
    CreditorService.instance.accounts().then((a) {
      if (mounted) setState(() => _accounts = a);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = friendlyError(e));
    });
  }

  @override
  void dispose() {
    for (final c in [_amount, _rate, _ref, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_onCredit) {
      Navigator.of(context).pop({'on_credit': true});
      return;
    }
    final amount = _num(_amount.text);
    final rate = _num(_rate.text);
    final err = amount == null || amount <= 0
        ? 'Enter the amount.'
        : _foreign && (rate == null || rate <= 0)
            ? 'Enter the exchange rate (TZS per ${widget.currency}).'
            : _account == null
                ? 'Pick the account the money is paid from.'
                : null;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final d = _date;
    Navigator.of(context).pop({
      'amount': amount,
      if (_foreign) 'exchange_rate': rate,
      'paid_from_account_id': _account!.id,
      'payment_date': '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      if (_ref.text.trim().isNotEmpty) 'reference': _ref.text.trim(),
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final amount = _num(_amount.text);
    final rate = _num(_rate.text);
    final tzs = amount != null && (!_foreign || rate != null) ? (amount * (_foreign ? rate! : 1)).round() : null;

    return AlertDialog(
      backgroundColor: pal.surface1,
      title: Row(children: [
        Icon(Symbols.payments, size: 18, color: AppColors.teal),
        const SizedBox(width: 10),
        Expanded(child: Text(widget.title, style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.creditorName} · ${widget.currency}', style: AppTheme.bodySub.copyWith(color: pal.textMute)),
          if (widget.hint != null) ...[
            const SizedBox(height: 4),
            Text(widget.hint!, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim)),
          ],
          const SizedBox(height: 12),
          if (widget.allowOnCredit) ...[
            LabeledDropdown<bool>(
              label: 'How is it paid',
              value: _onCredit,
              items: const [false, true],
              displayBuilder: (v) => v ? 'On credit — pay the supplier later against their invoice' : 'Pay now (deposit or full amount)',
              onChanged: (v) => setState(() { _onCredit = v; _error = null; }),
            ),
            const SizedBox(height: 12),
          ],
          if (!_onCredit) ...[
            LabeledTextField(label: 'Amount (${widget.currency})', controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
            if (_foreign) ...[
              const SizedBox(height: 12),
              LabeledTextField(label: 'Exchange rate (TZS per ${widget.currency})', controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true), hint: 'e.g. 2655',
                  onChanged: (_) => setState(() {})),
            ],
            if (tzs != null && _foreign) ...[
              const SizedBox(height: 6),
              Text('= ${money(tzs, 'TZS')}', style: AppTheme.bodySub.copyWith(fontSize: 12, color: AppColors.teal)),
            ],
            const SizedBox(height: 12),
            _accounts == null
                ? const LinearProgressIndicator(minHeight: 2)
                : LabeledDropdown<PaymentAccount?>(
                    label: 'Paid from',
                    value: _account,
                    items: [null, ..._accounts!],
                    displayBuilder: (a) => a?.label ?? 'Select the bank, cash or mobile-money account…',
                    onChanged: (a) => setState(() { _account = a; _error = null; }),
                  ),
            const SizedBox(height: 12),
            LabeledDateField(
              label: 'Payment date',
              date: _date,
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _date,
                    firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 60)));
                if (d != null && mounted) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 12),
            LabeledTextField(label: 'Bank reference · optional', controller: _ref, hint: 'TT / transfer no., cheque no.'),
            const SizedBox(height: 12),
            LabeledTextField(label: 'Notes · optional', controller: _notes, maxLines: 2),
          ],
          const SizedBox(height: 10),
          Text(_onCredit
              ? 'The Director approves the order on credit; the supplier\'s invoice then shows on their ledger until it\'s paid.'
              : 'The Director approves it before it\'s posted to the books and the creditor\'s ledger.',
              style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
          ],
        ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(_onCredit ? 'Ask to approve on credit' : 'Send for approval')),
      ],
    );
  }
}

class _AccountOnlyDialog extends StatefulWidget {
  const _AccountOnlyDialog({required this.title, this.note});
  final String title;
  final String? note;
  @override
  State<_AccountOnlyDialog> createState() => _AccountOnlyDialogState();
}

class _AccountOnlyDialogState extends State<_AccountOnlyDialog> {
  List<PaymentAccount>? _accounts;
  PaymentAccount? _account;
  String? _error;

  @override
  void initState() {
    super.initState();
    CreditorService.instance.accounts().then((a) {
      if (mounted) setState(() => _accounts = a);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = friendlyError(e));
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    title: Text(widget.title, style: AppTheme.bodyStrong),
    content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.note != null) ...[
        Text(widget.note!, style: AppTheme.bodySub.copyWith(fontSize: 12, color: context.pal.textMute)),
        const SizedBox(height: 12),
      ],
      _accounts == null
          ? const LinearProgressIndicator(minHeight: 2)
          : LabeledDropdown<PaymentAccount?>(
              label: 'Paid from',
              value: _account,
              items: [null, ..._accounts!],
              displayBuilder: (a) => a?.label ?? 'Select the bank, cash or mobile-money account…',
              onChanged: (a) => setState(() { _account = a; _error = null; }),
            ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
      ],
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        onPressed: () => _account == null ? setState(() => _error = 'Pick the account.') : Navigator.of(context).pop(_account),
        child: const Text('Continue'),
      ),
    ],
  );
}
