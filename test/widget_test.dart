import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orakzai_app/app/app_shell.dart';
import 'package:orakzai_app/auth/auth_api.dart';
import 'package:orakzai_app/auth/auth_controller.dart';
import 'package:orakzai_app/auth/token_store.dart';

Widget createTestApp() {
  final auth = AuthController(api: AuthApi(tokenStore: MemoryTokenStore()));
  addTearDown(auth.dispose);
  return OrakzaiApp(authController: auth);
}

void main() {
  testWidgets('shows the five primary destinations', (tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('COMMUNITY'), findsOneWidget);
    expect(find.text('HELP DESK'), findsOneWidget);
    expect(find.text('SERVICES'), findsOneWidget);
    expect(find.text('PROFILE'), findsOneWidget);
  });

  testWidgets('can navigate to community and help desk', (tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('COMMUNITY'));
    await tester.pumpAndSettle();
    expect(find.text('Suggested group topics'), findsOneWidget);

    await tester.tap(find.text('HELP DESK'));
    await tester.pumpAndSettle();
    expect(find.text('What do you need help with?'), findsOneWidget);
    expect(find.text('Private by design'), findsOneWidget);
  });

  testWidgets('help desk preview does not submit user information', (
    tester,
  ) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('HELP DESK'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'I need information about education support.',
    );
    await tester.ensureVisible(find.text('Preview request'));
    await tester.tap(find.text('Preview request'));
    await tester.pumpAndSettle();

    expect(find.text('Preview only'), findsOneWidget);
    expect(find.textContaining('Nothing was sent'), findsOneWidget);
  });

  testWidgets('profile opens sign-in and account creation forms', (
    tester,
  ) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('PROFILE'));
    await tester.pumpAndSettle();

    expect(find.text('Email or phone number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Google sign-in · not configured'), findsOneWidget);
    expect(find.text('Wallet sign-in · not configured'), findsOneWidget);

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
  });
}
