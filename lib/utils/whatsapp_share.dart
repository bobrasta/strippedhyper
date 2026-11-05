import 'package:url_launcher/url_launcher.dart';

/// Best-effort phone extraction from a free-text contact field — returns
/// digits only (no leading +) if it looks like a real phone number,
/// otherwise null so the WhatsApp contact picker is left open-ended.
String? phoneDigitsFrom(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 9 ? digits : null;
}

/// Opens WhatsApp (app or web fallback) with [message] pre-filled, addressed
/// to [phone] if given (digits only, no leading +) or left blank so the user
/// picks a contact themselves.
Future<void> shareViaWhatsApp({String? phone, required String message}) async {
  final uri = Uri.parse('https://wa.me/${phone ?? ''}?text=${Uri.encodeComponent(message)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
