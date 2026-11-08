import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'app_user.dart';
import 'token_store.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthApi {
  AuthApi({TokenStore? tokenStore, http.Client? client, String? baseUrl})
    : _tokenStore = tokenStore ?? SecureTokenStore(),
      _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? resolveApiBaseUrl();

  final TokenStore _tokenStore;
  final http.Client _client;
  final String _baseUrl;
  final MemoryTokenStore _memoryTokens = MemoryTokenStore();
  bool _rememberSession = true;
  Future<void>? _refreshInFlight;
  void Function()? onSessionExpired;
  TokenStore get _tokens => _rememberSession ? _tokenStore : _memoryTokens;

  String get apiBaseUrl => _baseUrl;

  Future<String?> readAccessToken() => _tokens.readAccessToken();

  Future<void> refreshSession() => _refreshSession();

  Future<Map<String, dynamic>> requestAuthorized(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) {
    return _authorizedRequest(method, path, body: body);
  }

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    String country = '',
    String region = '',
    String district = '',
    bool acceptedTerms = false,
  }) {
    return _publicRequest('POST', '/auth/register', {
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'password': password,
      'country': country,
      'region': region,
      'district': district,
      'acceptedTerms': acceptedTerms,
    });
  }

  Future<void> verifyEmail({
    required String email,
    required String code,
  }) async {
    await _publicRequest('POST', '/auth/verify-email', {
      'email': email,
      'code': code,
    });
  }

  Future<String?> resendVerification(String email) async {
    final response = await _publicRequest('POST', '/auth/resend-verification', {
      'email': email,
    });
    return response['devVerificationCode'] as String?;
  }

  Future<String?> forgotPassword(String email) async {
    final response = await _publicRequest('POST', '/auth/forgot-password', {
      'email': email,
    });
    return response['devResetCode'] as String?;
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _publicRequest('POST', '/auth/reset-password', {
      'email': email,
      'code': code,
      'newPassword': newPassword,
    });
  }

  Future<void> login({
    required String identifier,
    required String password,
    bool rememberSession = true,
  }) async {
    final response = await _publicRequest('POST', '/auth/login', {
      'identifier': identifier,
      'password': password,
    });
    _rememberSession = rememberSession;
    if (!rememberSession) await _tokenStore.clear();
    await _saveTokenPair(response);
  }

  Future<AppUser> getCurrentUser() async {
    final response = await _authorizedRequest('GET', '/users/me');
    final userJson = _asMap(response['user']);
    return AppUser.fromJson(userJson);
  }

  Future<Map<String, dynamic>> getPermissions() {
    return _authorizedRequest('GET', '/users/me/permissions');
  }

  Future<AppUser> updateProfile(Map<String, dynamic> updates) async {
    final response = await _authorizedRequest(
      'PATCH',
      '/users/me',
      body: updates,
    );
    return AppUser.fromJson(_asMap(response['user']));
  }

  Future<void> logout() async {
    try {
      await _authorizedRequest('POST', '/auth/logout', body: const {});
    } finally {
      await clearSession();
    }
  }

  Future<void> clearSession() async {
    await _tokenStore.clear();
    await _memoryTokens.clear();
  }

  Future<Map<String, dynamic>> capabilities() =>
      _publicRequest('GET', '/auth/capabilities');

  Future<Uint8List?> requestAuthorizedBytes(String path) async {
    final response = await _authorizedRaw('GET', path);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) _decode(response);
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> uploadAuthorized(
    String path,
    List<int> bytes,
    String fileName,
    String contentType,
  ) async {
    final response = await _authorizedRaw(
      'POST',
      path,
      bytes: bytes,
      contentType: contentType,
    );
    return _decode(response);
  }

  Future<http.Response> _authorizedRaw(
    String method,
    String path, {
    List<int>? bytes,
    String? contentType,
  }) async {
    Future<http.Response> send() async {
      final token = await readAccessToken();
      if (token == null) {
        onSessionExpired?.call();
        throw const AuthApiException(
          'UNAUTHENTICATED',
          'Sign in.',
          statusCode: 401,
        );
      }
      try {
        final request = http.Request(method, Uri.parse('$_baseUrl$path'));
        request.headers['Authorization'] = 'Bearer $token';
        if (bytes != null) {
          request.headers['Content-Type'] =
              contentType ?? 'application/octet-stream';
          request.bodyBytes = bytes;
        }
        return await http.Response.fromStream(
          await _client.send(request).timeout(const Duration(seconds: 20)),
        ).timeout(const Duration(seconds: 20));
      } catch (error) {
        if (error is AuthApiException) rethrow;
        throw const AuthApiException('NETWORK_ERROR', 'Connection failed.');
      }
    }

    var response = await send();
    if (response.statusCode == 401) {
      await _refreshSession();
      response = await send();
      if (response.statusCode == 401) {
        await clearSession();
        onSessionExpired?.call();
      }
    }
    return response;
  }

  Future<Map<String, dynamic>> _publicRequest(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final response = await _send(method, path, body: body);
    return _decode(response);
  }

  Future<Map<String, dynamic>> _authorizedRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final accessToken = await _tokens.readAccessToken();
    if (accessToken == null) {
      throw const AuthApiException(
        'UNAUTHENTICATED',
        'Please sign in to continue.',
        statusCode: 401,
      );
    }

    var response = await _send(
      method,
      path,
      body: body,
      accessToken: accessToken,
    );
    if (response.statusCode == 401 && path != '/auth/refresh') {
      try {
        await _refreshSession();
        final freshAccessToken = await _tokens.readAccessToken();
        if (freshAccessToken != null) {
          response = await _send(
            method,
            path,
            body: body,
            accessToken: freshAccessToken,
          );
        }
      } on AuthApiException catch (error) {
        if (error.statusCode == 401) {
          await clearSession();
          onSessionExpired?.call();
        }
        rethrow;
      }
    }
    if (response.statusCode == 401) {
      await clearSession();
      onSessionExpired?.call();
    }
    return _decode(response);
  }

  Future<void> _refreshSession() {
    if (_refreshInFlight != null) return _refreshInFlight!;
    final future = _performRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<void> _performRefresh() async {
    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken == null) {
      await clearSession();
      onSessionExpired?.call();
      throw const AuthApiException(
        'SESSION_EXPIRED',
        'Your session expired. Please sign in again.',
        statusCode: 401,
      );
    }
    final response = await _send(
      'POST',
      '/auth/refresh',
      body: {'refreshToken': refreshToken},
    );
    try {
      final tokens = _decode(response);
      await _saveTokenPair(tokens);
    } on AuthApiException catch (error) {
      if (error.statusCode == 401) {
        await clearSession();
        onSessionExpired?.call();
      }
      rethrow;
    }
  }

  Future<void> _saveTokenPair(Map<String, dynamic> response) async {
    final accessToken = response['accessToken'];
    final refreshToken = response['refreshToken'];
    if (accessToken is! String || refreshToken is! String) {
      throw const AuthApiException(
        'INVALID_TOKEN_RESPONSE',
        'The server returned an invalid session.',
      );
    }
    await _tokens.writeTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final url = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    final encodedBody = body == null ? null : jsonEncode(body);

    try {
      switch (method) {
        case 'GET':
          return await _client
              .get(url, headers: headers)
              .timeout(const Duration(seconds: 15));
        case 'POST':
          return await _client
              .post(url, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 15));
        case 'PATCH':
          return await _client
              .patch(url, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 15));
        case 'DELETE':
          return await _client
              .delete(url, headers: headers)
              .timeout(const Duration(seconds: 15));
        default:
          throw ArgumentError.value(
            method,
            'method',
            'Unsupported HTTP method.',
          );
      }
    } catch (error) {
      if (error is AuthApiException) rethrow;
      throw const AuthApiException(
        'NETWORK_ERROR',
        'Could not reach the ORAKZAI.ORG service. Check your connection and try again.',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 204 || response.body.isEmpty) return const {};
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const AuthApiException(
        'INVALID_SERVER_RESPONSE',
        'The service returned an unexpected response.',
      );
    }
    final json = _asMap(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _asMap(json['error']);
      throw AuthApiException(
        error['code'] as String? ?? 'REQUEST_FAILED',
        error['message'] as String? ?? 'The request could not be completed.',
        statusCode: response.statusCode,
      );
    }
    return json;
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  void dispose() => _client.close();
}
