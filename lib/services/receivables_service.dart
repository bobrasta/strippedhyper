import 'package:dio/dio.dart';
import 'api_client.dart';

/// Credit sales / hire purchase tracking (GET /receivables, statement,
/// lump "Pay due"). Plain maps — these are report shapes, not entities.
class ReceivablesService {
  ReceivablesService._();
  static final instance = ReceivablesService._();
  final _dio = ApiClient.instance.dio;

  static Map<String, dynamic>? cachedDefault;

  /// {summary: {...}, data: [customer rows]}
  /// [asAt] (yyyy-mm-dd, past): balances as they stood at the end of that
  /// day — payments by the date they were paid. Null = today.
  Future<Map<String, dynamic>> list({String? search, String? dateFrom, String? dateTo, String? asAt}) async {
    final res = await _dio.get('/receivables', queryParameters: {
      'search': ?search,
      'date_from': ?dateFrom,
      'date_to': ?dateTo,
      'as_at': ?asAt,
    });
    final body = Map<String, dynamic>.from(res.data as Map);
    if (search == null && asAt == null) cachedDefault = body;
    return body;
  }

  Future<Map<String, dynamic>> statement({int? hospitalId, String? clientName, String? dateFrom, String? dateTo}) async {
    final res = await _dio.get('/receivables/statement', queryParameters: {
      'hospital_id': ?hospitalId,
      'client_name': ?(hospitalId == null ? clientName : null),
      'date_from': ?dateFrom,
      'date_to': ?dateTo,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// The same statement as a PDF on the company letterhead.
  Future<List<int>> statementPdfBytes({int? hospitalId, String? clientName, String? dateFrom, String? dateTo}) async {
    final res = await _dio.get<List<int>>('/receivables/statement/pdf',
        queryParameters: {
          'hospital_id': ?hospitalId,
          'client_name': ?(hospitalId == null ? clientName : null),
          'date_from': ?dateFrom,
          'date_to': ?dateTo,
        },
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 2)));
    return res.data!;
  }

  /// The same statement as an Excel workbook (Ledger + Invoice Status sheets).
  Future<List<int>> statementXlsxBytes({int? hospitalId, String? clientName, String? dateFrom, String? dateTo}) async {
    final res = await _dio.get<List<int>>('/receivables/statement/xlsx',
        queryParameters: {
          'hospital_id': ?hospitalId,
          'client_name': ?(hospitalId == null ? clientName : null),
          'date_from': ?dateFrom,
          'date_to': ?dateTo,
        },
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 2)));
    return res.data!;
  }

  /// Lump payment applied to the customer's oldest invoices first.
  Future<Map<String, dynamic>> pay({
    int? hospitalId,
    String? clientName,
    required int amount,
    required String method,
    required String paidAt,
    String? reference,
    String? notes,
  }) async {
    final res = await _dio.post('/receivables/pay', data: {
      'hospital_id': ?hospitalId,
      'client_name': ?(hospitalId == null ? clientName : null),
      'amount': amount,
      'payment_method': method,
      'paid_at': paidAt,
      'reference': ?reference,
      'notes': ?notes,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}
