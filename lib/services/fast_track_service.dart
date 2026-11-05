import 'api_client.dart';

/// The Director's "Approve now": approves a pending request past every
/// stage still open (POST /approvals/fast-track). Finance still records
/// payments, so money requests stop at "awaiting payment".
class FastTrackService {
  FastTrackService._();
  static final instance = FastTrackService._();
  final _dio = ApiClient.instance.dio;

  /// [type]: purchase_order, expense, per_diem, vendor_fee, requisition,
  /// leave, stock_out, quotation, sales_order, credit_note, vendor_bill,
  /// payroll_run, salary_adjustment. Returns the record's new status.
  Future<String?> approveNow(String type, int id) async {
    final res = await _dio.post('/approvals/fast-track', data: {'type': type, 'id': id});
    return (ApiClient.unwrap(res) as Map<String, dynamic>)['status'] as String?;
  }
}
