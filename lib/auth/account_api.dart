import 'dart:typed_data';

import 'auth_api.dart';

/// Owner-scoped account operations. The server derives ownership from the
/// authenticated session; callers never supply another member's identifier.
class AccountApi {
  AccountApi(this.auth);
  final AuthApi auth;

  Future<Map<String, dynamic>> get(String path) =>
      auth.requestAuthorized('GET', '/users/me/$path');
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      auth.requestAuthorized('POST', '/users/me/$path', body: body);
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      auth.requestAuthorized('PATCH', '/users/me/$path', body: body);
  Future<Map<String, dynamic>> delete(String path) =>
      auth.requestAuthorized('DELETE', '/users/me/$path');

  Future<Uint8List?> avatar() => auth.requestAuthorizedBytes('/users/me/photo');
  Future<void> uploadAvatar(Uint8List png) async {
    await auth.uploadAuthorized(
      '/users/me/photo',
      png,
      'avatar.png',
      'image/png',
    );
  }

  Future<void> markNotificationRead(String id) =>
      auth.requestAuthorized('POST', '/community/notifications/$id/read');
}
