import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orakzai_app/app/app_theme.dart';
import 'package:orakzai_app/home/hero_banner.dart';
import 'package:orakzai_app/home/hero_carousel.dart';

Widget carousel({
  bool active = true,
  bool reduce = false,
  bool accessible = false,
  bool ticker = true,
  List<HomeHeroBanner> banners = homeHeroBanners,
  ValueChanged<HomeBannerDestination>? navigate,
  double scale = 1,
}) => MaterialApp(theme: AppTheme.light, home: Scaffold(
  body: MediaQuery(data: MediaQueryData(
    disableAnimations: reduce, accessibleNavigation: accessible,
    textScaler: TextScaler.linear(scale)),
    child: TickerMode(enabled: ticker, child: SingleChildScrollView(
      child: HeroCarousel(banners: banners, active: active,
        onDestination: navigate ?? (_) {}))))));

int page(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!.round();

void finish(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

void main() {
  testWidgets('pause and resume controls stop and restart automatic movement', (tester) async {
    finish(tester);
    await tester.pumpWidget(carousel());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Pause automatic banners'));
    await tester.tap(find.byTooltip('Pause automatic banners'));
    await tester.pump(const Duration(seconds: 8));
    expect(page(tester), 0);
    await tester.tap(find.byTooltip('Resume automatic banners'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 600));
    expect(page(tester), 1);
  });
  testWidgets('automatically advances after four seconds, not before', (tester) async {
    finish(tester);
    await tester.pumpWidget(carousel());
    await tester.pumpAndSettle();
    expect(page(tester), 0);
    await tester.pump(const Duration(milliseconds: 3900));
    expect(page(tester), 0);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(page(tester), 1);
  });

  testWidgets('manual horizontal swipe changes banner and restarts the reading interval', (tester) async {
    finish(tester);
    await tester.pumpWidget(carousel());
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-440, 0));
    await tester.pumpAndSettle();
    expect(page(tester), 1);
    await tester.pump(const Duration(seconds: 2));
    expect(page(tester), 1);
  });

  testWidgets('banner CTA dispatches its actual typed destination', (tester) async {
    finish(tester);
    HomeBannerDestination? destination;
    await tester.pumpWidget(carousel(navigate: (value) => destination = value));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open Community'));
    await tester.tap(find.text('Open Community'));
    expect(destination, HomeBannerDestination.community);
  });

  testWidgets('indicator selection is manual and wraps from last banner', (tester) async {
    finish(tester);
    await tester.pumpWidget(carousel());
    await tester.pumpAndSettle();
    final target = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Show banner 5 of 5');
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(page(tester), 4);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 600));
    expect(page(tester), 0);
  });

  for (final mode in ['off-tab', 'reduced-motion', 'accessible-navigation', 'ticker-off']) {
    testWidgets('$mode disables automatic movement but keeps manual swipe', (tester) async {
      finish(tester);
      await tester.pumpWidget(carousel(
        active: mode != 'off-tab', reduce: mode == 'reduced-motion',
        accessible: mode == 'accessible-navigation', ticker: mode != 'ticker-off'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 9));
      expect(page(tester), 0);
      await tester.drag(find.byType(PageView), const Offset(-440, 0));
      await tester.pumpAndSettle();
      expect(page(tester), 1);
    });
  }

  testWidgets('touch hold pauses movement and disposal cancels timers', (tester) async {
    finish(tester);
    await tester.pumpWidget(carousel());
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(find.byType(PageView)));
    await tester.pump(const Duration(seconds: 6));
    expect(page(tester), 0);
    await gesture.up();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('background lifecycle pauses and foreground resumes', (tester) async {
    finish(tester);
    await tester.pumpWidget(carousel());
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 8));
    expect(page(tester), 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 600));
    expect(page(tester), 1);
  });

  for (final width in [320.0, 412.0, 900.0]) {
    testWidgets('photo banner and native copy avoid overflow at width $width with enlarged text', (tester) async {
      finish(tester);
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(carousel(active: false, scale: 2.5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final image = tester.widgetList<Image>(find.byType(Image)).first;
      expect(image.fit, BoxFit.cover);
      expect(tester.getSize(find.byType(PageView)).width, lessThanOrEqualTo(width));
      expect(tester.getSize(find.byType(Image).first).width, lessThanOrEqualTo(width));
    });
  }

  testWidgets('empty and single-banner catalogs do not schedule auto paging', (tester) async {
    finish(tester);
    await tester.pumpWidget(carousel(banners: const []));
    expect(find.byType(PageView), findsNothing);
    await tester.pumpWidget(carousel(banners: [homeHeroBanners.first]));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 8));
    expect(page(tester), 0);
  });

  testWidgets('active banner copy and actions are real native widgets', (tester) async {
    finish(tester);
    await tester.pumpWidget(carousel(active: false));
    await tester.pumpAndSettle();
    expect(find.text(homeHeroBanners.first.heading!), findsOneWidget);
    expect(find.text(homeHeroBanners.first.subtitle!), findsOneWidget);
    expect(find.text(homeHeroBanners.first.ctaLabel!), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('active Home uses five clean photos, not the old text-covered posters', () {
    expect(homeHeroBanners, hasLength(5));
    for (final banner in homeHeroBanners) {
      expect(banner.imageAsset, startsWith('assets/images/home_photos/'));
      expect(banner.heading, isNotEmpty);
      expect(banner.subtitle, isNotEmpty);
      expect(banner.fit, BoxFit.cover);
      expect(banner.isPlaceholder, isFalse);
    }
  });
}
