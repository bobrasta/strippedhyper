import '../models/tax_rate.dart';
import 'api_client.dart';

class TaxRateService {
  TaxRateService._();
  static final instance = TaxRateService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. list() takes no filters, so it always caches. Not currently
  // wired into any screen: both call sites (expenses_screen.dart and
  // vendor_bills_screen.dart's "New …" dialogs) are one-shot modal loads,
  // not a repeatedly-navigated list/detail screen — the dialog's dropdown
  // already renders instantly via a static 0%/18% fallback while this
  // resolves, so there's no blank-to-spinner symptom to fix there.
  static List<TaxRate>? cachedList;

  Future<List<TaxRate>> list() async {
    final res = await _dio.get('/tax-rates');
    final (data, _) = ApiClient.unwrapList(res);
    final rates = data.map((j) => TaxRate.fromJson(j as Map<String, dynamic>)).toList();
    cachedList = rates;
    return rates;
  }
}
