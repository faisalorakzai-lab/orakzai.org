import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AppPreferences {
  Future<bool> onboardingComplete();
  Future<void> setOnboardingComplete(bool value);
  Future<String?> language();
  Future<void> setLanguage(String value);
  Future<String?> appearance();
  Future<void> setAppearance(String value);

  factory AppPreferences.secure({FlutterSecureStorage? storage}) =
      SecureAppPreferences.new;
  factory AppPreferences.memory() = MemoryAppPreferences.new;
}

class SecureAppPreferences implements AppPreferences {
  SecureAppPreferences({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  static const _onboarding = 'orakzai.onboarding-complete.v1';
  static const _language = 'orakzai.interface-language.v1';
  static const _appearance = 'orakzai.appearance.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<bool> onboardingComplete() async =>
      await _storage.read(key: _onboarding) == 'true';
  @override
  Future<void> setOnboardingComplete(bool value) =>
      _storage.write(key: _onboarding, value: value.toString());
  @override
  Future<String?> language() => _storage.read(key: _language);
  @override
  Future<void> setLanguage(String value) =>
      _storage.write(key: _language, value: value);
  @override
  Future<String?> appearance() => _storage.read(key: _appearance);
  @override
  Future<void> setAppearance(String value) =>
      _storage.write(key: _appearance, value: value);
}

/// Explicitly injected in tests; the production constructor never falls back
/// to process memory when platform-protected storage is unavailable.
class MemoryAppPreferences implements AppPreferences {
  bool complete = false;
  String languageCode = 'en';
  String theme = 'system';
  @override
  Future<bool> onboardingComplete() async => complete;
  @override
  Future<void> setOnboardingComplete(bool value) async => complete = value;
  @override
  Future<String?> language() async => languageCode;
  @override
  Future<void> setLanguage(String value) async => languageCode = value;
  @override
  Future<String?> appearance() async => theme;
  @override
  Future<void> setAppearance(String value) async => theme = value;
}
