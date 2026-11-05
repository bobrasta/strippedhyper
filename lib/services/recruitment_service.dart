import 'package:dio/dio.dart';
import '../models/recruitment.dart';
import 'api_client.dart';

export '../models/recruitment.dart';

class RecruitmentService {
  RecruitmentService._();
  static final instance = RecruitmentService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning.
  static List<Vacancy>? cachedDefaultVacancies; // vacancies() — no status filter
  static List<Applicant>? cachedTalentPool;     // applicants(talentPool: true)
  static final Map<int, List<Application>> cachedPipelineByVacancyId = {};

  Future<List<Vacancy>> vacancies({String? status}) async {
    final res = await _dio.get('/vacancies', queryParameters: {'status': ?status});
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => Vacancy.fromJson(j as Map<String, dynamic>)).toList();
    if (status == null) cachedDefaultVacancies = list;
    return list;
  }

  Future<Vacancy> createVacancy(Map<String, dynamic> data) async {
    final res = await _dio.post('/vacancies', data: data);
    return Vacancy.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Vacancy> updateVacancy(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/vacancies/$id', data: data);
    return Vacancy.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<List<Application>> pipeline(int vacancyId) async {
    final res = await _dio.get('/vacancies/$vacancyId/applications');
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => Application.fromJson(j as Map<String, dynamic>)).toList();
    cachedPipelineByVacancyId[vacancyId] = list;
    return list;
  }

  Future<Application> applyToVacancy(int vacancyId, int applicantId) async {
    final res = await _dio.post('/vacancies/$vacancyId/applications', data: {'applicant_id': applicantId});
    return Application.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Application> updateStage(int applicationId, String status, {String? notes}) async {
    final res = await _dio.put('/applications/$applicationId/stage', data: {'status': status, 'notes': ?notes});
    return Application.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Interview> scheduleInterview(int applicationId, Map<String, dynamic> data) async {
    final res = await _dio.post('/applications/$applicationId/interviews', data: data);
    return Interview.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<List<Applicant>> applicants({bool? talentPool, String? skill, String? search}) async {
    final res = await _dio.get('/applicants', queryParameters: {
      if (talentPool == true) 'talent_pool': 'true',
      'skill': ?skill,
      'search': ?search,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => Applicant.fromJson(j as Map<String, dynamic>)).toList();
    if (talentPool == true && skill == null && search == null) cachedTalentPool = list;
    return list;
  }

  Future<Applicant> applicant(int id) async {
    final res = await _dio.get('/applicants/$id');
    return Applicant.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Applicant> createApplicant(Map<String, dynamic> data) async {
    final res = await _dio.post('/applicants', data: data);
    return Applicant.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Applicant> updateApplicant(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/applicants/$id', data: data);
    return Applicant.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<ApplicantCvVersion> uploadCv(int applicantId, String filePath, String fileName) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final res = await _dio.post('/applicants/$applicantId/cv', data: formData);
    return ApplicantCvVersion.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
