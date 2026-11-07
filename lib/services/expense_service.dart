import '../models/expense.dart';
import 'api_client.dart';
import '../widgets/common/period_filter.dart';

class ExpenseService {
  ExpenseService._();
  static final instance = ExpenseService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see InventoryService for the full
  // reasoning. cachedDefaultList only covers the unfiltered query.
  static List<ExpenseCategory>? cachedCategories;
  static List<Expense>? cachedDefaultList;
  static final Map<int, Expense> cachedById = {};

  Future<List<ExpenseCategory>> categories() async {
    final res = await _dio.get('/expense-categories');
    final (data, _) = ApiClient.unwrapList(res);
    final cats = data.map((j) => ExpenseCategory.fromJson(j as Map<String, dynamic>)).toList();
    cachedCategories = cats;
    return cats;
  }

  /// [mine]: only the caller's own (My Expenses), even for Finance.
  Future<List<Expense>> list({int? categoryId, String? paymentMode, String? dateFrom, String? dateTo, String? search, Period? period, bool mine = false}) async {
    final res = await _dio.get('/expenses', queryParameters: {
      ...?period?.query,
      if (mine) 'mine': 1,
      'category_id':  ?categoryId,
      'payment_mode': ?paymentMode,
      'date_from':    ?dateFrom,
      'date_to':      ?dateTo,
      'search':       ?search,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final expenses = data.map((j) => Expense.fromJson(j as Map<String, dynamic>)).toList();
    if (!mine && categoryId == null && paymentMode == null && dateFrom == null && dateTo == null && search == null && (period?.isDefault ?? false)) {
      cachedDefaultList = expenses;
    }
    return expenses;
  }

  /// The Approvals queue: every expense still waiting on someone, from any
  /// date (the server limits it to what the caller may see). The plain list
  /// is the 50 newest, which hid pending ones from Finance and the Director
  /// behind already-paid expenses.
  Future<List<Expense>> pending() async {
    final res = await _dio.get('/expenses', queryParameters: {'pending': 1, 'per_page': 2000});
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((j) => Expense.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Expense> get(int id) async {
    final res = await _dio.get('/expenses/$id');
    final expense = Expense.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[expense.id] = expense;
    return expense;
  }

  Future<Expense> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/expenses', data: data);
    return Expense.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Expense> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/expenses/$id', data: data);
    return Expense.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _dio.delete('/expenses/$id');

  Future<Expense> approve(int id) async {
    final res = await _dio.post('/expenses/$id/approve');
    return Expense.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Expense> escalate(int id, {String? reason}) async {
    final res = await _dio.post('/expenses/$id/escalate', data: {'escalation_reason': reason});
    return Expense.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Expense> reject(int id, {String? reason}) async {
    final res = await _dio.post('/expenses/$id/reject', data: {'rejection_reason': reason});
    return Expense.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Expense> initiatePayment(int id, {String? paymentMethod, String? reference}) async {
    final res = await _dio.post('/expenses/$id/initiate-payment', data: {
      'payment_method':    paymentMethod,
      'payment_reference': reference,
    });
    return Expense.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Expense> markPaid(int id) async {
    final res = await _dio.post('/expenses/$id/mark-paid');
    return Expense.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Expense> stopRecurring(int id) async {
    final res = await _dio.post('/expenses/$id/stop-recurring');
    return Expense.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> setCategoryRequiresDirector(int categoryId, bool value) =>
      _dio.put('/expense-categories/$categoryId', data: {'requires_director_approval': value});

  Future<ExpenseCategory> createCategory(Map<String, dynamic> data) async {
    final res = await _dio.post('/expense-categories', data: data);
    return ExpenseCategory.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  // data may explicitly include 'parent_id': null to move a subcategory
  // back to top-level — pass a plain map (not the ?-omit convenience) so
  // an explicit null actually reaches the server as null, not omitted.
  Future<ExpenseCategory> updateCategoryDetails(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/expense-categories/$id', data: data);
    return ExpenseCategory.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> deleteCategory(int id) => _dio.delete('/expense-categories/$id');
}
