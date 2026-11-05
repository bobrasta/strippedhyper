/// Currencies a cost can be in (purchase order lines, inventory unit cost).
const kCostCurrencies = ['TZS', 'USD', 'EUR', 'GBP', 'CNY', 'INR', 'KES'];

/// A cost in its currency: "TSh 1.2M" for shillings, "USD 1,200" otherwise.
String costText(num v, String currency) {
  final c = currency.toUpperCase();
  if (c == 'TZS') return tshFromDouble(v);
  final whole = v.round().abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${v < 0 ? '-' : ''}$c $whole';
}

String formatDate(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')} '
      '${_months[dt.month - 1]} ${dt.year}';
}

String formatTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String tshShort(int n) {
  if (n >= 1000000000) return 'TSh ${(n / 1e9).toStringAsFixed(2)}B';
  if (n >= 1000000)    return 'TSh ${(n / 1e6).toStringAsFixed(1)}M';
  if (n >= 1000)       return 'TSh ${(n / 1e3).toStringAsFixed(0)}K';
  return 'TSh $n';
}

String tshFromDouble(num n) {
  if (n >= 1000000000) return 'TSh ${(n / 1e9).toStringAsFixed(2)}B';
  if (n >= 1000000)    return 'TSh ${(n / 1e6).toStringAsFixed(1)}M';
  if (n >= 1000)       return 'TSh ${(n / 1e3).toStringAsFixed(0)}K';
  return 'TSh ${n.toStringAsFixed(0)}';
}

/// Exact shillings with thousands separators — "TSh 170,000,000" — for
/// ledgers and statements, where a rounded "170.0M" won't reconcile.
String tshExact(num n) {
  final digits = n.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return '${n < 0 ? '-' : ''}TSh $b';
}

/// Accounting-style signed money: negatives in parentheses, no minus sign —
/// e.g. tshFromDouble(-9200000) => "TSh 9.2M" but tshSigned(-9200000) =>
/// "(TSh 9.2M)". Use wherever a figure can legitimately go negative (net
/// result, account balances) so it reads the way an accountant expects.
String tshSigned(num n) => n < 0 ? '(${tshFromDouble(n.abs())})' : tshFromDouble(n);

String timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24)   return '${diff.inHours}h ago';
  if (diff.inDays < 7)     return '${diff.inDays}d ago';
  return formatDate(dt);
}

/// A typed money amount: commas, spaces and "TSh" are ignored and decimals
/// are accepted ("350,000.50"), rounded to whole shillings — the books keep
/// TZS in shillings. Null when nothing usable was typed. (Stripping every
/// non-digit instead turned "350000.50" into 35,000,050.)
int? parseShillings(String text) {
  return double.tryParse(text.replaceAll(RegExp(r'[^0-9.\-]'), ''))?.round();
}
