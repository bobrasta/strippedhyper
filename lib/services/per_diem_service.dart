import 'package:dio/dio.dart';
import '../models/per_diem_request.dart';
import 'api_client.dart';

class PerDiemService {
  PerDiemService._();
  static final instance = PerDiemService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. cachedDefaultList only covers the unfiltered query.
  static List<PerDiemRequest>? cachedDefaultList;
  static final Map<int, PerDiemRequest> cachedById = {};

  Future<List<PerDiemRequest>> list({String? status}) async {
    final res = await _dio.get('/per-diem-requests', queryParameters: {
      'status': ?status,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final requests = data.map((j) => PerDiemRequest.fromJson(j as Map<String, dynamic>)).toList();
    if (status == null) cachedDefaultList = requests;
    return requests;
  }

  Future<PerDiemRequest> show(int id) async {
    final res = await _dio.get('/per-diem-requests/$id');
    final request = PerDiemRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[request.id] = request;
    return request;
  }

  // Section 7: "can open details and download the plan as a PDF."
  Future<List<int>> pdfBytes(int id) async {
    final res = await _dio.get<List<int>>('/per-diem-requests/$id/pdf', options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  // Section 15.5: same layout/data as the PDF, reproducing the approved
  // WORKPLAN template cell-for-cell (see PerDiemXlsxExportService).
  Future<List<int>> xlsxBytes(int id) async {
    final res = await _dio.get<List<int>>('/per-diem-requests/$id/xlsx', options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  Future<PerDiemRequest> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/per-diem-requests', data: data);
    return PerDiemRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PerDiemRequest> approveTeamLead(int id) async {
    final res = await _dio.post('/per-diem-requests/$id/approve-team-lead');
    return PerDiemRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  // rejection_reason is required server-side (min 10 chars) — no self-
  // approval and no un-reasoned rejection are both enforced in
  // PerDiemController now, so this is never optional in practice despite
  // the nullable type (callers must prompt before calling).
  Future<PerDiemRequest> rejectTeamLead(int id, {required String reason}) async {
    final res = await _dio.post('/per-diem-requests/$id/reject-team-lead', data: {'rejection_reason': reason});
    return PerDiemRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PerDiemRequest> approve(int id) async {
    final res = await _dio.post('/per-diem-requests/$id/approve');
    return PerDiemRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PerDiemRequest> reject(int id, {required String reason}) async {
    final res = await _dio.post('/per-diem-requests/$id/reject', data: {'rejection_reason': reason});
    return PerDiemRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PerDiemRequest> cancel(int id, {required String reason}) async {
    final res = await _dio.post('/per-diem-requests/$id/cancel', data: {'cancellation_reason': reason});
    return PerDiemRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  /// Finance's step — prepares the payment but doesn't move money on their
  /// own authority. Director's markPaid() below is the actual release.
  Future<PerDiemRequest> initiatePayment(int id, {String? method, String? reference, int? paidFromAccountId}) async {
    final res = await _dio.post('/per-diem-requests/$id/initiate-payment', data: {
      'payment_method':    ?method,
      'payment_reference': ?reference,
      'paid_from_account_id': ?paidFromAccountId,
    });
    return PerDiemRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  /// Director's final authorization — only reachable once finance has
  /// initiated payment.
  Future<PerDiemRequest> markPaid(int id) async {
    final res = await _dio.post('/per-diem-requests/$id/mark-paid');
    return PerDiemRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  // Section 8: CTO day-by-day editing — sends the full day list every time
  // (no from_seq_no), which correctly covers all three spec modes (single
  // day, add/remove days) since the server always recomputes from what's
  // submitted; only loses the "provably untouched earlier days" optimization,
  // not correctness.
  Future<PerDiemRequest> revise(int id, {required String reason, required List<PerDiemLine> lines}) async {
    final res = await _dio.post('/per-diem-requests/$id/revise', data: {
      'reason': reason,
      'lines': lines.map((l) => l.toJson()).toList(),
    });
    return PerDiemRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PerDiemEditGrant> grantEditAccess(int id, {String? expiresAt}) async {
    final res = await _dio.post('/per-diem-requests/$id/edit-grants', data: {
      'expires_at': ?expiresAt,
    });
    return PerDiemEditGrant.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> revokeEditAccess(int id) => _dio.delete('/per-diem-requests/$id/edit-grants');

  // A technician's edit never takes effect on its own — it's stored as a
  // PerDiemRevision (status pending_cto_approval) and only applied once the
  // CTO approves it below. Same field shape as revise() (reason + full day
  // list), just a different endpoint and outcome.
  Future<void> proposeEdit(int id, {required String reason, required List<PerDiemLine> lines}) async {
    await _dio.post('/per-diem-requests/$id/propose-edit', data: {
      'reason': reason,
      'lines': lines.map((l) => l.toJson()).toList(),
    });
  }

  Future<void> approveTechnicianEdit(int planId, int revisionId) =>
      _dio.post('/per-diem-requests/$planId/revisions/$revisionId/approve');

  Future<void> rejectTechnicianEdit(int planId, int revisionId) =>
      _dio.post('/per-diem-requests/$planId/revisions/$revisionId/reject');
}
