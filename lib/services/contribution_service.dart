import 'package:dio/dio.dart';
import 'api_client.dart';

/// One person's counts in the period (GET /contributions).
class Contribution {
  Contribution(this.raw);
  final Map<String, dynamic> raw;
  int _n(String k) => (raw[k] as num?)?.toInt() ?? 0;

  int get id => _n('id');
  String get name => raw['name'] as String? ?? '';
  String get role => raw['role'] as String? ?? '';
  bool get isActive => raw['is_active'] != false;
  int get quotations => _n('quotations');
  int get quotationsInvoiced => _n('quotations_invoiced');
  int get invoicedValue => _n('invoiced_value');
  int get installations => _n('installations');
  int get services => _n('services');
  int get dealsWon => _n('deals_won');
  int metric(String key) => _n(key);
}

/// A record behind one number (GET /contributions/{user}/{metric}).
class ContributionItem {
  ContributionItem(this.raw);
  final Map<String, dynamic> raw;
  String get reference => raw['reference'] as String? ?? '—';
  String get title => raw['title'] as String? ?? '—';
  DateTime? get date => DateTime.tryParse(raw['date'] as String? ?? '');
  int? get value => (raw['value'] as num?)?.toInt();
  String? get invoice => raw['invoice'] as String?;
  String? get status => raw['status'] as String?;
}

class ContributionService {
  ContributionService._();
  static final instance = ContributionService._();
  final _dio = ApiClient.instance.dio;

  Map<String, dynamic> _map(Response res) => Map<String, dynamic>.from(ApiClient.unwrap(res) as Map);

  Future<List<Contribution>> list({Map<String, dynamic> query = const {}}) async {
    final d = _map(await _dio.get('/contributions', queryParameters: query));
    return [for (final p in (d['people'] as List? ?? [])) Contribution(Map<String, dynamic>.from(p as Map))];
  }

  Future<List<ContributionItem>> items(int userId, String metric, {Map<String, dynamic> query = const {}}) async {
    final d = _map(await _dio.get('/contributions/$userId/$metric', queryParameters: query));
    return [for (final i in (d['items'] as List? ?? [])) ContributionItem(Map<String, dynamic>.from(i as Map))];
  }
}
