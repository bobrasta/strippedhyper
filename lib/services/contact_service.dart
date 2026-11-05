import '../models/contact.dart';
import 'api_client.dart';

class ContactService {
  ContactService._();
  static final instance = ContactService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. cachedDefaultList only covers the unfiltered query.
  static List<Contact>? cachedDefaultList;
  static final Map<int, Contact> cachedById = {};

  Future<List<Contact>> list({String? hospital, String? tag}) async {
    final res = await _dio.get('/contacts', queryParameters: {
      'hospital': ?hospital,
      'tag': ?tag,
      'per_page': 120,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final contacts = data.map((j) => Contact.fromJson(j as Map<String, dynamic>)).toList();
    if (hospital == null && tag == null) cachedDefaultList = contacts;
    return contacts;
  }

  Future<Contact> get(int id) async {
    final res = await _dio.get('/contacts/$id');
    final contact = Contact.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[contact.id] = contact;
    return contact;
  }

  Future<Contact> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/contacts', data: data);
    return Contact.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Contact> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/contacts/$id', data: data);
    return Contact.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> addInteraction(int id, Map<String, dynamic> data) =>
      _dio.post('/contacts/$id/interactions', data: data);
}
