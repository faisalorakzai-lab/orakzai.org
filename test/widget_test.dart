import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orakzai_app/app/app_shell.dart';
import 'package:orakzai_app/auth/app_preferences.dart';
import 'package:orakzai_app/auth/app_user.dart';
import 'package:orakzai_app/auth/auth_api.dart';
import 'package:orakzai_app/auth/auth_controller.dart';
import 'package:orakzai_app/auth/token_store.dart';

class _RestoredAuth extends AuthController {
  _RestoredAuth({required this.authenticated})
    : super(api: AuthApi(tokenStore: MemoryTokenStore()));

  final bool authenticated;

  @override
  Future<void> loadCapabilities() async {
    capabilities = {
      'registrationAvailable': true,
      'passwordResetAvailable': false,
      'developmentMode': true,
      'providers': const {'google': false, 'apple': false, 'wallet': false},
      'legal': const {
        'termsUrl': null,
        'privacyUrl': null,
        'version': 'development-notice-v1',
      },
      'deletionAvailable': false,
      'membershipAvailable': false,
      'applicationsAvailable': false,
    };
    notifyListeners();
  }

  @override
  Future<void> restoreSession() async {
    if (authenticated) {
      user = AppUser(
        id: '00000000-0000-4000-8000-000000000007',
        email: 'widget@example.invalid',
        phone: '+923001234567',
        emailVerified: true,
        accountStatus: 'active',
        profile: {
          'fullName': 'Widget Test',
          'privacy': const <String, dynamic>{},
        },
        regionAssignments: const [],
      );
      status = AuthStatus.signedIn;
    } else {
      user = null;
      status = AuthStatus.signedOut;
    }
    notifyListeners();
  }
}

Widget testApp({
  bool authenticated = false,
  MemoryAppPreferences? preferences,
}) {
  final controller = _RestoredAuth(authenticated: authenticated);
  addTearDown(controller.dispose);
  return OrakzaiApp(
    authController: controller,
    preferences: preferences ?? MemoryAppPreferences(),
  );
}

Finder navigationLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  testWidgets('first launch shows onboarding without opening private tabs', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('One Community, One Identity.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(PageView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('onboarding skip is persisted before showing sign in', (
    tester,
  ) async {
    final preferences = MemoryAppPreferences();
    await tester.pumpWidget(testApp(preferences: preferences));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(preferences.complete, isTrue);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Email or phone number'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restored account sees all five unchanged app destinations', (
    tester,
  ) async {
    final preferences = MemoryAppPreferences()..complete = true;
    await tester.pumpWidget(
      testApp(authenticated: true, preferences: preferences),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    for (final label in const [
      'HOME',
      'COMMUNITY',
      'HELP DESK',
      'SERVICES',
      'PROFILE',
    ]) {
      expect(navigationLabel(label), findsOneWidget);
    }
    expect(find.text('Google sign-in · not configured'), findsNothing);
    expect(find.text('Wallet sign-in · not configured'), findsNothing);
    await tester.tap(navigationLabel('PROFILE'));
    await tester.pumpAndSettle();
    expect(find.text('Widget Test'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a signed-out visit after onboarding cannot open private tabs', (
    tester,
  ) async {
    final preferences = MemoryAppPreferences()..complete = true;
    await tester.pumpWidget(testApp(preferences: preferences));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Email or phone number'), findsOneWidget);
    expect(find.text('One Community, One Identity.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
