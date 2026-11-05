import '../models/customer.dart';
import 'api_client.dart';

class CustomerService {
  CustomerService._();
  static final instance = CustomerService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning.
  static List<Customer>? cachedList;
  static final Map<int, Customer> cachedById = {};

  Future<List<Customer>> list() async {
    final res = await _dio.get('/customers');
    final (data, _) = ApiClient.unwrapList(res);
    return cachedList = data.map((j) => Customer.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Customer> get(int id) async {
    final res = await _dio.get('/customers/$id');
    return cachedById[id] = Customer.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
