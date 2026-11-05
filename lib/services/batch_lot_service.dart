import '../models/batch_lot.dart';
import 'api_client.dart';

class BatchLotService {
  BatchLotService._();
  static final instance = BatchLotService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. Keyed by item id — listForItem() has no filter params, so
  // every call is effectively the "unfiltered" query for that item.
  static final Map<int, List<BatchLot>> cachedByItemId = {};

  Future<List<BatchLot>> listForItem(int inventoryItemId) async {
    final res = await _dio.get('/inventory/$inventoryItemId/batches');
    final (data, _) = ApiClient.unwrapList(res);
    final lots = data.map((j) => BatchLot.fromJson(j as Map<String, dynamic>)).toList();
    cachedByItemId[inventoryItemId] = lots;
    return lots;
  }

  Future<BatchLot> create(int inventoryItemId, Map<String, dynamic> data) async {
    final res = await _dio.post('/inventory/$inventoryItemId/batches', data: data);
    return BatchLot.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<BatchLot> update(int inventoryItemId, int batchLotId, Map<String, dynamic> data) async {
    final res = await _dio.put('/inventory/$inventoryItemId/batches/$batchLotId', data: data);
    return BatchLot.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> delete(int inventoryItemId, int batchLotId) =>
      _dio.delete('/inventory/$inventoryItemId/batches/$batchLotId');
}
