import '../models/stock_movement.dart';
import 'api_client.dart';
import '../widgets/common/period_filter.dart';

class StockMovementService {
  StockMovementService._();
  static final instance = StockMovementService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. cachedDefaultList covers the fully-unfiltered (no item, no
  // type) query used by the audit-trail screen; cachedByItemId covers the
  // per-item unfiltered (type == null) query used by an item's Movements tab.
  static List<StockMovement>? cachedDefaultList;
  static final Map<int, List<StockMovement>> cachedByItemId = {};

  Future<List<StockMovement>> list({int? inventoryItemId, String? type, Period? period}) async {
    final res = await _dio.get('/stock-movements', queryParameters: {
      ...?period?.query,
      'inventory_item_id': ?inventoryItemId,
      'type':              ?type,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final movements = data.map((j) => StockMovement.fromJson(j as Map<String, dynamic>)).toList();
    if (type == null) {
      if (inventoryItemId == null) {
        if (period?.isDefault ?? false) cachedDefaultList = movements;
      } else {
        cachedByItemId[inventoryItemId] = movements;
      }
    }
    return movements;
  }

  Future<StockMovement> record({
    required int inventoryItemId,
    required int locationId,
    required String type,
    required int quantity,
    int?    toLocationId, // required by the API when type == 'transfer'
    int?    unitCost,
    String? currency,
    String? notes,
    String? batchNumber,
    String? expiryDate,
  }) async {
    final res = await _dio.post('/stock-movements', data: {
      'inventory_item_id': inventoryItemId,
      'location_id':       locationId,
      'to_location_id': ?toLocationId,
      'type':              type,
      'quantity':          quantity,
      'unit_cost':    ?unitCost,
      'currency':     ?currency,
      'notes':        ?notes,
      'batch_number': ?batchNumber,
      'expiry_date':  ?expiryDate,
    });
    return StockMovement.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
