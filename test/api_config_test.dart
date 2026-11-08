import 'package:flutter_test/flutter_test.dart';
import 'package:orakzai_app/config/api_config.dart';

void main() {
  test('development retains emulator configuration', () {
    expect(resolveApiBaseUrl(production: false), 'http://10.0.2.2:3001/api');
  });
  test('release requires explicit public HTTPS API configuration', () {
    for (final url in [
      '',
      'http://api.example.org/api',
      'https://10.0.2.2/api',
      'https://localhost/api',
      'https://127.0.0.1/api',
      'https://192.168.1.1/api',
      'https://172.16.0.1/api',
      'https://user:password@api.example.org/api',
    ]) {
      expect(
        () => resolveApiBaseUrl(configured: url, production: true),
        throwsStateError,
      );
    }
    expect(
      resolveApiBaseUrl(
        configured: 'https://api.example.org/api/',
        production: true,
      ),
      'https://api.example.org/api',
    );
  });
}
