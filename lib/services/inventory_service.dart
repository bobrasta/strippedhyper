import '../models/inventory_item.dart';
import '../models/inventory_item_history.dart';
import '../models/inventory_lot.dart';
import 'api_client.dart';

class InventoryService {
  InventoryService._();
  static final instance = InventoryService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache (survives widget disposal, unlike
  // State fields) — see MachineService for the full reasoning. Scoped to
  // the default/unfiltered catalog query only; a filtered/searched list
  // still shows the normal loading state.
  static List<InventoryItem>? cachedDefaultList;
  static final Map<int, InventoryItem> cachedById = {};

  Future<List<InventoryItem>> list({
    String? category,
    bool? lowStock,
    String? search,
    bool? createsMachineRecord,
  }) async {
    final data = await ApiClient.getAllPages(_dio, '/inventory', query: {
      'category_id': ?category,
      if (lowStock == true) 'low_stock': 'true',
      'search':   ?search,
      if (createsMachineRecord != null) 'creates_machine_record': createsMachineRecord.toString(),
      // Screens that call this load the full catalog once and paginate/filter
      // locally, so fetch every page — the API caps per_page at 1000 and the
      // catalog is past that since the Clickhuduma import.
    });
    final items = data.map((j) => InventoryItem.fromJson(j as Map<String, dynamic>)).toList();
    if (category == null && lowStock != true && search == null && createsMachineRecord == null) {
      cachedDefaultList = items;
    }
    return items;
  }

  /// Unexpired lots with stock left, grouped by product id, soonest expiry
  /// first — for the product search on the sale / invoice / quotation forms.
  Future<Map<int, List<InventoryLot>>> openLots() async {
    final res = await _dio.get('/inventory-lots');
    final out = <int, List<InventoryLot>>{};
    for (final j in ApiClient.unwrap(res) as List) {
      final lot = InventoryLot.fromJson(j as Map<String, dynamic>);
      (out[lot.itemId] ??= []).add(lot);
    }
    return out;
  }

  Future<InventoryItem> get(int id) async {
    final res = await _dio.get('/inventory/$id');
    final item = InventoryItem.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[item.id] = item;
    return item;
  }

  Future<InventoryItem> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/inventory', data: data);
    return InventoryItem.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  /// Creates a minimal, uncatalogued item on the fly (e.g. a part discovered
  /// mid-service that isn't in the catalog yet). Flagged `needs_review` so
  /// inventory admin can fill in the real SKU/cost/category later.
  Future<InventoryItem> quickCreate(String name, {String? costCurrency}) async {
    final res = await _dio.post('/inventory/quick-create', data: {'name': name, 'cost_currency': ?costCurrency});
    return InventoryItem.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<InventoryItem> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/inventory/$id', data: data);
    return InventoryItem.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> deactivate(int id) => _dio.delete('/inventory/$id');

  Future<List<SerialHistoryEntry>> history(int id) async {
    final res = await _dio.get('/inventory/$id/history');
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((j) => SerialHistoryEntry.fromJson(j as Map<String, dynamic>)).toList();
  }
}
