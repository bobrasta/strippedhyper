/// Tanzania (TRA) taxpayer identification number: 9 digits, written
/// 123-456-789. Mirrors App\Support\Tin on the API.
String? normalizeTin(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 9) return null;
  return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
}

/// Validation message for a required client TIN, or null when valid.
String? tinError(String input) {
  if (input.trim().isEmpty) return 'Client TIN is required';
  if (!RegExp(r'^\s*\d{3}[\s-]?\d{3}[\s-]?\d{3}\s*$').hasMatch(input)) return 'TIN must be 9 digits (e.g. 123-456-789)';
  return null;
}
