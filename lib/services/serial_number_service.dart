import '../models/serial_number.dart';
import 'api_client.dart';

class SerialNumberService {
  SerialNumberService._();
  static final instance = SerialNumberService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. Keyed by item id, only for the unfiltered (status == null) query.
  static final Map<int, List<SerialNumber>> cachedByItemId = {};

  Future<List<SerialNumber>> listForItem(int inventoryItemId, {String? status}) async {
    final res = await _dio.get('/inventory/$inventoryItemId/serials', queryParameters: {
      'status': ?status,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final serials = data.map((j) => SerialNumber.fromJson(j as Map<String, dynamic>)).toList();
    if (status == null) cachedByItemId[inventoryItemId] = serials;
    return serials;
  }

  Future<SerialNumber> create(int inventoryItemId, Map<String, dynamic> data) async {
    final res = await _dio.post('/inventory/$inventoryItemId/serials', data: data);
    return SerialNumber.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<SerialNumber> update(int inventoryItemId, int serialId, Map<String, dynamic> data) async {
    final res = await _dio.put('/inventory/$inventoryItemId/serials/$serialId', data: data);
    return SerialNumber.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> delete(int inventoryItemId, int serialId) =>
      _dio.delete('/inventory/$inventoryItemId/serials/$serialId');
}
