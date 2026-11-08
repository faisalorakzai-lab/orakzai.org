import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orakzai_app/app/app_language.dart';
import 'package:orakzai_app/app/app_shell.dart';
import 'package:orakzai_app/app/app_theme.dart';
import 'package:orakzai_app/auth/app_user.dart';
import 'package:orakzai_app/auth/app_preferences.dart';
import 'package:orakzai_app/auth/auth_api.dart';
import 'package:orakzai_app/auth/auth_controller.dart';
import 'package:orakzai_app/auth/token_store.dart';
import 'package:orakzai_app/data/program_area.dart';
import 'package:orakzai_app/home/hero_carousel.dart';
import 'package:orakzai_app/home/home_api.dart';
import 'package:orakzai_app/home/home_controller.dart';
import 'package:orakzai_app/home/home_search_screen.dart';
import 'package:orakzai_app/screens/home_screen.dart';

/// Deterministic widget/unit-test double, never used by the actual app.
class TestHomeApi extends HomeApi {
  TestHomeApi() : super(auth: AuthApi(tokenStore: MemoryTokenStore()));
  int calls = 0;
  bool failStats = false;
  Completer<Map<String, dynamic>>? pendingStats;
  @override
  Future<Map<String, dynamic>> statistics() async {
    calls++;
    if (pendingStats != null) return pendingStats!.future;
    if (failStats) throw Exception('Statistics test outage');
    return {
      'accessiblePosts': 7,
      'accessibleAnnouncements': 2,
      'joinedGroups': 3,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> feed({
    bool announcementsOnly = false,
    String? search,
    int limit = 3,
  }) async {
    calls++;
    return [];
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> search(String query) async {
    calls++;
    return {'posts': [], 'groups': [], 'members': []};
  }
}

AuthController account({bool signedIn = false}) {
  final auth = AuthController(api: AuthApi(tokenStore: MemoryTokenStore()));
  auth.status = signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  if (signedIn) {
    auth.user = const AppUser(
      id: 'test-only-member',
      email: '',
      phone: '',
      emailVerified: true,
      accountStatus: 'active',
      profile: {'fullName': 'Test Member'},
      regionAssignments: [],
    );
  }
  return auth;
}

class _SignedInRootAuth extends AuthController {
  _SignedInRootAuth() : super(api: AuthApi(tokenStore: MemoryTokenStore()));

  @override
  Future<void> loadCapabilities() async {
    capabilities = const {
      'registrationAvailable': false,
      'passwordResetAvailable': false,
      'developmentMode': true,
      'providers': {'google': false, 'apple': false, 'wallet': false},
      'legal': {'termsUrl': null, 'privacyUrl': null, 'version': null},
      'deletionAvailable': false,
      'membershipAvailable': false,
      'applicationsAvailable': false,
    };
  }

  @override
  Future<void> restoreSession() async {
    user = const AppUser(
      id: '00000000-0000-4000-8000-000000000001',
      email: 'home-widget@example.invalid',
      phone: '+923001234567',
      emailVerified: true,
      accountStatus: 'active',
      profile: {'fullName': 'Home Widget'},
      regionAssignments: [],
    );
    status = AuthStatus.signedIn;
    notifyListeners();
  }
}

void main() {
  test(
    'shared visual theme preserves bundled typefaces and readable contrast',
    () {
      final theme = AppTheme.light;
      expect(theme.scaffoldBackgroundColor, AppColors.canvas);
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Manrope');
      expect(
        theme.chipTheme.labelStyle!.fontFamilyFallback,
        contains('NotoSansArabic'),
      );
      expect(
        theme.navigationBarTheme.labelTextStyle!
            .resolve({})!
            .fontFamilyFallback,
        contains('NotoSansArabic'),
      );
      double contrast(Color a, Color b) {
        final first = a.computeLuminance(), second = b.computeLuminance();
        return ((first > second ? first : second) + .05) /
            ((first > second ? second : first) + .05);
      }

      expect(
        contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(theme.colorScheme.onSurface, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  testWidgets(
    'compact phone Home exposes the primary request action without scrolling',
    (tester) async {
      final auth = _SignedInRootAuth();
      addTearDown(auth.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        OrakzaiApp(
          authController: auth,
          preferences: MemoryAppPreferences()..complete = true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      // The photo hero grows with the actual font metrics; the meaningful
      // constraint is that the request action remains visible and tappable.
      expect(
        tester.getSize(find.byType(PageView)).width,
        lessThanOrEqualTo(412),
      );
      final action = find.text('Submit a request');
      final navTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
      expect(tester.getBottomRight(action).dy, lessThan(navTop));
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('signed-out Home does not fetch private records', () async {
    final auth = account(), api = TestHomeApi();
    final home = HomeController(auth: auth, api: api);
    await home.refresh();
    expect(api.calls, 0);
    expect(home.statistics.data, isNull);
    home.dispose();
    auth.dispose();
  });

  test(
    'one failed section stays explicit without dropping successful sections',
    () async {
      final auth = account(signedIn: true),
          api = TestHomeApi()..failStats = true;
      final home = HomeController(auth: auth, api: api);
      await home.refresh();
      expect(home.statistics.error, contains('Statistics test outage'));
      expect(home.statistics.data, isNull);
      expect(home.updates.data, isEmpty);
      expect(home.announcements.data, isEmpty);
      home.dispose();
      auth.dispose();
    },
  );

  test('logout clears records and ignores an old in-flight response', () async {
    final auth = account(signedIn: true), api = TestHomeApi();
    final pending = Completer<Map<String, dynamic>>();
    api.pendingStats = pending;
    final home = HomeController(auth: auth, api: api);
    auth.status = AuthStatus.signedOut;
    auth.user = null;
    auth.notifyListeners();
    pending.complete({
      'accessiblePosts': 99,
      'accessibleAnnouncements': 1,
      'joinedGroups': 2,
    });
    await Future<void>.delayed(Duration.zero);
    expect(home.statistics.data, isNull);
    expect(home.updates.data, isNull);
    home.dispose();
    auth.dispose();
  });

  testWidgets(
    'real Home route banner CTAs open Community, Programs and Help Desk',
    (tester) async {
      final auth = _SignedInRootAuth();
      addTearDown(auth.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        OrakzaiApp(
          authController: auth,
          preferences: MemoryAppPreferences()..complete = true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(HeroCarousel), findsOneWidget);
      expect(find.text('PREVIEW'), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      await tester.ensureVisible(find.text('Open Community').first);
      await tester.tap(find.text('Open Community').hitTestable().first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await tester.tap(find.text('HOME'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      Finder indicator(int index) => find.byWidgetPredicate(
        (w) =>
            w is Semantics && w.properties.label == 'Show banner $index of 5',
      );
      await tester.ensureVisible(indicator(2).first);
      await tester.tap(indicator(2).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Read program areas').first);
      await tester.tap(find.text('Read program areas').hitTestable());
      await tester.pumpAndSettle();
      final programY = tester
          .getTopLeft(find.text(publicProgramAreas.first.title))
          .dy;
      expect(programY, greaterThanOrEqualTo(0));
      expect(programY, lessThan(500));
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tester.ensureVisible(indicator(3).first);
      await tester.tap(indicator(3).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open Help Desk').first);
      await tester.tap(find.text('Open Help Desk').hitTestable());
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      await tester.tap(find.text('HOME'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Submit a request'));
      await tester.tap(find.text('Submit a request'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 412.0, 900.0]) {
    testWidgets(
      'actual Home layout supports $width and 2x text through all sections',
      (tester) async {
        final auth = account();
        addTearDown(auth.dispose);
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: HomeScreen(
                  language: AppLanguage.english,
                  authController: auth,
                  onOpenHelpDesk: () {},
                  onOpenCommunity: () {},
                  onOpenProfile: () {},
                  isActive: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -1800),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'global search searches public programs without fabricating live results',
    (tester) async {
      final auth = account(), api = TestHomeApi();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeSearchScreen(auth: auth, api: api),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('home-global-search-input')),
        'education',
      );
      await tester.pumpAndSettle();
      expect(find.text('Member search requires sign-in'), findsOneWidget);
      expect(api.calls, 0);
      expect(find.text('Education & Global Scholarships'), findsOneWidget);
    },
  );
}
