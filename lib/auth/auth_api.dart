import 'dart:convert';

import 'package:http/http.dart' as http;

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
      _baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'ORAKZAI_API_BASE_URL',
            defaultValue: 'http://10.0.2.2:3001/api',
          );

  final TokenStore _tokenStore;
  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) {
    return _publicRequest('POST', '/auth/register', {
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'password': password,
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
  }) async {
    final response = await _publicRequest('POST', '/auth/login', {
      'identifier': identifier,
      'password': password,
    });
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
      await _tokenStore.clear();
    }
  }

  Future<void> clearSession() => _tokenStore.clear();

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
    final accessToken = await _tokenStore.readAccessToken();
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
        final freshAccessToken = await _tokenStore.readAccessToken();
        if (freshAccessToken != null) {
          response = await _send(
            method,
            path,
            body: body,
            accessToken: freshAccessToken,
          );
        }
      } on AuthApiException {
        await _tokenStore.clear();
        rethrow;
      }
    }
    return _decode(response);
  }

  Future<void> _refreshSession() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) {
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
    final tokens = _decode(response);
    await _saveTokenPair(tokens);
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
    await _tokenStore.writeTokens(
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
