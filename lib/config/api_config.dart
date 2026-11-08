import 'package:flutter/foundation.dart';

String resolveApiBaseUrl({
  String configured = const String.fromEnvironment('ORAKZAI_API_BASE_URL'),
  bool production = kReleaseMode,
}) {
  final value = configured.trim();
  if (value.isEmpty && !production) return 'http://10.0.2.2:3001/api';
  final uri = Uri.tryParse(value);
  final host = uri?.host.toLowerCase() ?? '';
  final local =
      host == 'localhost' ||
      host == '::1' ||
      host == '0.0.0.0' ||
      host.startsWith('127.') ||
      host.startsWith('10.') ||
      host.startsWith('192.168.') ||
      host == '169.254.169.254' ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host);
  if (uri == null ||
      !uri.hasAuthority ||
      host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (production
          ? uri.scheme != 'https' || local
          : !['http', 'https'].contains(uri.scheme))) {
    throw StateError(
      'Set ORAKZAI_API_BASE_URL to an explicit public HTTPS production API URL.',
    );
  }
  return value.replaceFirst(RegExp(r'/+$'), '');
}
