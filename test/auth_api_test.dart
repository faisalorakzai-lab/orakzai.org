import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orakzai_app/auth/auth_api.dart';
import 'package:orakzai_app/auth/token_store.dart';

void main() {
  test(
    'refreshes tokens once and retries a protected profile request',
    () async {
      final store = MemoryTokenStore();
      await store.writeTokens(
        accessToken: 'expired-access-token',
        refreshToken: 'old-refresh-token-value',
      );

      final client = MockClient((request) async {
        if (request.url.path == '/api/users/me' &&
            request.headers['Authorization'] == 'Bearer expired-access-token') {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'UNAUTHENTICATED',
                'message': 'Please sign in again.',
              },
            }),
            401,
          );
        }
        if (request.url.path == '/api/auth/refresh') {
          expect(
            jsonDecode(request.body)['refreshToken'],
            'old-refresh-token-value',
          );
          return http.Response(
            jsonEncode({
              'accessToken': 'fresh-access-token',
              'refreshToken': 'rotated-refresh-token-value',
              'tokenType': 'Bearer',
              'expiresIn': 600,
            }),
            200,
          );
        }
        if (request.url.path == '/api/users/me' &&
            request.headers['Authorization'] == 'Bearer fresh-access-token') {
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'user-id',
                'email': 'member@example.org',
                'phone': '+923001234567',
                'emailVerified': true,
                'accountStatus': 'active',
                'profile': {
                  'fullName': 'Verified Test Member',
                  'memberId': null,
                  'skills': <String>[],
                  'privacy': <String, bool>{},
                },
                'regionAssignments': <Object>[],
              },
            }),
            200,
          );
        }
        return http.Response(
          '{"error":{"code":"UNEXPECTED","message":"Unexpected request"}}',
          500,
        );
      });

      final api = AuthApi(
        tokenStore: store,
        client: client,
        baseUrl: 'https://api.example.org/api',
      );
      final user = await api.getCurrentUser();

      expect(user.fullName, 'Verified Test Member');
      expect(await store.readAccessToken(), 'fresh-access-token');
      expect(await store.readRefreshToken(), 'rotated-refresh-token-value');
      api.dispose();
    },
  );
}
