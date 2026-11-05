import 'package:dio/dio.dart';
import '../models/vendor.dart';
import 'api_client.dart';

class VendorFeeService {
  VendorFeeService._();
  static final instance = VendorFeeService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. cachedVendors/cachedFees/cachedDeliveryJobs only cover their
  // unfiltered query (the only shape VendorFeesScreen ever calls them with);
  // the *ById maps back the fee/job detail dialogs, keyed by the numeric id
  // passed into fee()/deliveryJob() (matching their own returned object's
  // .id, which is genuinely int here — see VendorFee/DeliveryJob models).
  static List<Vendor>? cachedVendors;
  static List<VendorFee>? cachedFees;
  static final Map<int, VendorFee> cachedFeeById = {};
  static List<DeliveryJob>? cachedDeliveryJobs;
  static final Map<int, DeliveryJob> cachedJobById = {};

  Future<List<Vendor>> vendors({String? type, bool includeInactive = false}) async {
    final res = await _dio.get('/vendors', queryParameters: {
      'type': ?type,
      if (includeInactive) 'include_inactive': 1,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => Vendor.fromJson(j as Map<String, dynamic>)).toList();
    if (type == null) cachedVendors = list;
    return list;
  }

  Future<Vendor> createVendor(Map<String, dynamic> data) async {
    final res = await _dio.post('/vendors', data: data);
    return Vendor.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Vendor> updateVendor(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/vendors/$id', data: data);
    return Vendor.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<List<VendorFee>> fees({String? status, int? vendorId}) async {
    final res = await _dio.get('/vendor-fees', queryParameters: {
      'status': ?status,
      'vendor_id': ?vendorId,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => VendorFee.fromJson(j as Map<String, dynamic>)).toList();
    if (status == null && vendorId == null) cachedFees = list;
    return list;
  }

  Future<VendorFee> fee(int id) async {
    final res = await _dio.get('/vendor-fees/$id');
    final f = VendorFee.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedFeeById[id] = f;
    return f;
  }

  Future<VendorFee> createFee({required int vendorId, int? deliveryJobId, required String description, required int billedAmount}) async {
    final res = await _dio.post('/vendor-fees', data: {
      'vendor_id': vendorId,
      'delivery_job_id': ?deliveryJobId,
      'description': description,
      'billed_amount': billedAmount,
    });
    return VendorFee.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  /// Fees waiting on the caller: as the recorder's manager, as Finance or as the Director.
  Future<List<VendorFee>> waitingOnMe() async {
    final res = await _dio.get('/vendor-fees', queryParameters: {'waiting_on_me': 1});
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((j) => VendorFee.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<VendorFee> managerApprove(int id) async {
    final res = await _dio.post('/vendor-fees/$id/manager-approve');
    return VendorFee.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<VendorFee> managerReject(int id, {required String reason}) async {
    final res = await _dio.post('/vendor-fees/$id/manager-reject', data: {'rejection_reason': reason});
    return VendorFee.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<VendorFee> submitForPayment(int id) async {
    final res = await _dio.post('/vendor-fees/$id/submit-for-payment');
    return VendorFee.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<VendorFee> approve(int id, {required String paymentReference, int? paidFromAccountId}) async {
    final res = await _dio.post('/vendor-fees/$id/approve', data: {'payment_reference': paymentReference, 'paid_from_account_id': ?paidFromAccountId});
    return VendorFee.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<VendorFee> reject(int id, {required String reason}) async {
    final res = await _dio.post('/vendor-fees/$id/reject', data: {'rejection_reason': reason});
    return VendorFee.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> uploadReceipt(int feeId, String filePath, String fileName, {
    required String receiptType, required String receiptNumber, required String issuerName,
    String? issuerTin, required String receiptDate, required int amount,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      'receipt_type': receiptType,
      'receipt_number': receiptNumber,
      'issuer_name': issuerName,
      'issuer_tin': ?issuerTin,
      'receipt_date': receiptDate,
      'amount': amount,
    });
    await _dio.post('/vendor-fees/$feeId/receipts', data: formData);
  }

  /// The attached receipt file (PDF or photo).
  Future<List<int>> receiptFile(int feeId, int receiptId) async {
    final res = await _dio.get<List<int>>('/vendor-fees/$feeId/receipts/$receiptId/file',
        options: Options(responseType: ResponseType.bytes));
    return res.data ?? [];
  }

  /// Correct a receipt's details and/or replace its file (admin, or the
  /// uploader while unverified).
  Future<void> updateReceipt(int feeId, int receiptId, Map<String, dynamic> fields, {String? filePath, String? fileName}) async {
    final form = FormData.fromMap({
      ...fields,
      if (filePath != null) 'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    await _dio.post('/vendor-fees/$feeId/receipts/$receiptId', data: form);
  }

  Future<void> verifyReceipt(int feeId, int receiptId) =>
      _dio.post('/vendor-fees/$feeId/receipts/$receiptId/verify');

  Future<void> deleteReceipt(int feeId, int receiptId) =>
      _dio.delete('/vendor-fees/$feeId/receipts/$receiptId');

  Future<List<DeliveryJob>> deliveryJobs({String? status, int? vendorId}) async {
    final res = await _dio.get('/delivery-jobs', queryParameters: {
      'status': ?status,
      'vendor_id': ?vendorId,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => DeliveryJob.fromJson(j as Map<String, dynamic>)).toList();
    if (status == null && vendorId == null) cachedDeliveryJobs = list;
    return list;
  }

  Future<DeliveryJob> deliveryJob(int id) async {
    final res = await _dio.get('/delivery-jobs/$id');
    final j = DeliveryJob.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedJobById[id] = j;
    return j;
  }

  Future<DeliveryJob> createDeliveryJob({
    required String jobNumber, required int vendorId, String? destinationName,
    String? destinationAddress, required List<DeliveryGoodsLine> goodsList,
  }) async {
    final res = await _dio.post('/delivery-jobs', data: {
      'job_number': jobNumber,
      'vendor_id': vendorId,
      'destination_name': ?destinationName,
      'destination_address': ?destinationAddress,
      'goods_list': goodsList.map((g) => g.toJson()).toList(),
    });
    return DeliveryJob.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> uploadDeliveryNote(int jobId, String filePath, String fileName, {
    required String receiverName, required String deliveryDate, required List<DeliveryGoodsLine> deliveredGoods,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      'receiver_name': receiverName,
      'delivery_date': deliveryDate,
      for (var i = 0; i < deliveredGoods.length; i++) ...{
        'delivered_items[$i][item]': deliveredGoods[i].item,
        'delivered_items[$i][serial]': ?deliveredGoods[i].serial,
        'delivered_items[$i][quantity]': deliveredGoods[i].quantity,
      },
    });
    await _dio.post('/delivery-jobs/$jobId/delivery-note', data: formData);
  }
}
