import '../models/supplier.dart';
import 'api_client.dart';

class SupplierService {
  SupplierService._();
  static final instance = SupplierService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. cachedDefaultList only covers the unfiltered query.
  static List<Supplier>? cachedDefaultList;
  static final Map<int, Supplier> cachedById = {};

  Future<List<Supplier>> list({String? search, String? type}) async {
    final res = await _dio.get('/suppliers', queryParameters: {
      'search': ?search,
      'type':   ?type,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final suppliers = data.map((j) => Supplier.fromJson(j as Map<String, dynamic>)).toList();
    if (search == null && type == null) cachedDefaultList = suppliers;
    return suppliers;
  }

  Future<Supplier> get(int id) async {
    final res = await _dio.get('/suppliers/$id');
    final supplier = Supplier.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[supplier.id] = supplier;
    return supplier;
  }

  Future<Supplier> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/suppliers', data: data);
    return Supplier.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Supplier> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/suppliers/$id', data: data);
    return Supplier.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> deactivate(int id) => _dio.delete('/suppliers/$id');

  Future<void> addItem(int supplierId, Map<String, dynamic> data) =>
      _dio.post('/suppliers/$supplierId/items', data: data);

  Future<void> removeItem(int supplierId, int inventoryItemId) =>
      _dio.delete('/suppliers/$supplierId/items/$inventoryItemId');
}
