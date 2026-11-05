import '../models/credit_note.dart';
import 'api_client.dart';

export '../models/credit_note.dart';

class CreditNoteService {
  CreditNoteService._();
  static final instance = CreditNoteService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. list() is always scoped to one invoice (no unfiltered
  // "default" variant), so it's cached by that invoice id rather than as a
  // single default list. Not currently wired into any screen's loading gate
  // — its only caller is a one-shot dialog load (_CreditNotesDialog), not a
  // repeatedly-navigated screen — but kept consistent with the rest of this
  // service group.
  static final Map<int, List<CreditNote>> cachedByInvoiceId = {};

  Future<List<CreditNote>> list(int invoiceId) async {
    final res = await _dio.get('/invoices/$invoiceId/credit-notes');
    final (data, _) = ApiClient.unwrapList(res);
    final notes = data.map((j) => CreditNote.fromJson(j as Map<String, dynamic>)).toList();
    cachedByInvoiceId[invoiceId] = notes;
    return notes;
  }

  Future<CreditNote> create(int invoiceId, {required String reason, required int amount}) async {
    final res = await _dio.post('/invoices/$invoiceId/credit-notes', data: {'reason': reason, 'amount': amount});
    return CreditNote.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<CreditNote> approve(int id) async {
    final res = await _dio.post('/credit-notes/$id/approve');
    return CreditNote.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<CreditNote> apply(int id) async {
    final res = await _dio.post('/credit-notes/$id/apply');
    return CreditNote.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
