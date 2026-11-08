import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../auth/auth_api.dart';

class HelpDeskApi {
  HelpDeskApi({required AuthApi auth, Dio? dio})
      : _auth = auth,
        _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 45), sendTimeout: const Duration(minutes: 2)));
  final AuthApi _auth;
  final Dio _dio;
  static const categories = <String,String>{
    'general_inquiry':'General Inquiry','technical_support':'Technical Support',
    'education_assistance':'Education Assistance','healthcare_assistance':'Healthcare Assistance',
    'employment_assistance':'Employment Assistance','business_support':'Business Support',
    'social_welfare':'Social Welfare','membership_support':'Membership Support',
    'complaints':'Complaints','emergency_assistance':'Emergency Assistance','other':'Other',
  };
  static const statuses = <String,String>{
    'submitted':'Submitted','under_review':'Under Review','assigned':'Assigned',
    'in_progress':'In Progress','waiting_for_member':'Waiting for Member',
    'resolved':'Resolved','closed':'Closed','rejected':'Rejected',
  };
  static const priorities = <String,String>{'low':'Low','normal':'Normal','high':'High','urgent':'Urgent'};
  Future<Map<String,dynamic>> get(String path, {Map<String,String>? query}) =>
    _auth.requestAuthorized('GET', '/helpdesk${Uri(path:path,queryParameters:query).toString()}');
  Future<Map<String,dynamic>> post(String path, Map<String,dynamic> body) =>
    _auth.requestAuthorized('POST','/helpdesk$path',body:body);
  Future<Map<String,dynamic>> patch(String path, Map<String,dynamic> body) =>
    _auth.requestAuthorized('PATCH','/helpdesk$path',body:body);

  Future<T> _binary<T>(Future<T> Function(String token) send) async {
    var token=await _auth.readAccessToken();
    if(token==null) throw const AuthApiException('UNAUTHENTICATED','Please sign in.');
    try { return await send(token); }
    on DioException catch(e) {
      if(e.response?.statusCode==401) {
        await _auth.refreshSession();
        token=await _auth.readAccessToken();
        if(token!=null) {
          try { return await send(token); }
          on DioException catch(retry) { throw _message(retry); }
        }
      }
      throw _message(e);
    }
  }
  AuthApiException _message(DioException e) {
    final data=e.response?.data;
    final error=data is Map ? data['error'] : null;
    return AuthApiException('HELPDESK_REQUEST_FAILED',
      error is Map ? error['message']?.toString() ?? 'The file request failed.'
        : 'The file request failed. Check your connection and retry.',
      statusCode:e.response?.statusCode);
  }
  Future<Map<String,dynamic>> upload(String requestId, Uint8List bytes, String name) =>
    _binary((token) async {
      final response=await _dio.post<Map<String,dynamic>>('${_auth.apiBaseUrl}/helpdesk/requests/$requestId/attachments',
        data:FormData.fromMap({'file':MultipartFile.fromBytes(bytes,filename:name)}),
        options:Options(headers:{'Authorization':'Bearer $token'}));
      return response.data ?? <String,dynamic>{};
    });
  Future<Uint8List> download(String requestId,String attachmentId) =>
    _binary((token) async {
      final response=await _dio.get<List<int>>('${_auth.apiBaseUrl}/helpdesk/requests/$requestId/attachments/$attachmentId/content',
        options:Options(responseType:ResponseType.bytes,headers:{'Authorization':'Bearer $token'}));
      return Uint8List.fromList(response.data ?? <int>[]);
    });
}
