import 'package:flutter/foundation.dart';

import 'app_user.dart';
import 'auth_api.dart';

enum AuthStatus { restoring, signedOut, signedIn }

class AuthController extends ChangeNotifier {
  AuthController({AuthApi? api}) : _api = api ?? AuthApi();

  final AuthApi _api;
  AuthStatus status = AuthStatus.restoring;
  AppUser? user;
  List<String> roles = const [];
  List<String> permissions = const [];
  String? lastDevelopmentCode;
  String? lastDevelopmentCodePurpose;

  bool get isAuthenticated => status == AuthStatus.signedIn && user != null;

  Future<void> restoreSession() async {
    try {
      user = await _api.getCurrentUser();
      await _loadPermissions();
      status = AuthStatus.signedIn;
    } catch (_) {
      await _api.clearSession();
      user = null;
      roles = const [];
      permissions = const [];
      status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final response = await _api.register(
      fullName: fullName,
      email: email,
      phone: phone,
      password: password,
    );
    lastDevelopmentCode = response['devVerificationCode'] as String?;
    lastDevelopmentCodePurpose = 'email verification';
    notifyListeners();
  }

  Future<void> verifyEmail({
    required String email,
    required String code,
  }) async {
    await _api.verifyEmail(email: email, code: code);
    lastDevelopmentCode = null;
    lastDevelopmentCodePurpose = null;
    notifyListeners();
  }

  Future<void> resendVerification(String email) async {
    lastDevelopmentCode = await _api.resendVerification(email);
    lastDevelopmentCodePurpose = 'email verification';
    notifyListeners();
  }

  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    await _api.login(identifier: identifier, password: password);
    user = await _api.getCurrentUser();
    await _loadPermissions();
    status = AuthStatus.signedIn;
    lastDevelopmentCode = null;
    lastDevelopmentCodePurpose = null;
    notifyListeners();
  }

  Future<void> requestPasswordReset(String email) async {
    lastDevelopmentCode = await _api.forgotPassword(email);
    lastDevelopmentCodePurpose = 'password reset';
    notifyListeners();
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _api.resetPassword(
      email: email,
      code: code,
      newPassword: newPassword,
    );
    lastDevelopmentCode = null;
    lastDevelopmentCodePurpose = null;
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> updates) async {
    user = await _api.updateProfile(updates);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } finally {
      user = null;
      roles = const [];
      permissions = const [];
      status = AuthStatus.signedOut;
      notifyListeners();
    }
  }

  Future<void> _loadPermissions() async {
    final result = await _api.getPermissions();
    roles = (result['roles'] as List? ?? const []).whereType<String>().toList();
    permissions = (result['permissions'] as List? ?? const [])
        .whereType<String>()
        .toList();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}
