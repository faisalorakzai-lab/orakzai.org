import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../account/account_strings.dart';
import '../auth/app_preferences.dart';
import '../auth/auth_controller.dart';
import '../screens/auth_flow_screen.dart';
import '../screens/community_screen.dart';
import '../screens/help_desk_screen.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/services_screen.dart';
import 'app_language.dart';
import 'app_theme.dart';

class OrakzaiApp extends StatefulWidget {
  const OrakzaiApp({this.authController, this.preferences, super.key});
  final AuthController? authController;
  final AppPreferences? preferences;

  @override
  State<OrakzaiApp> createState() => _OrakzaiAppState();
}

enum _StartPage {
  splash,
  onboarding,
  signIn,
  restoreFailed,
  storageFailed,
  app,
}

class _OrakzaiAppState extends State<OrakzaiApp> {
  late final AuthController _auth = widget.authController ?? AuthController();
  late final AppPreferences _prefs =
      widget.preferences ?? AppPreferences.secure();
  _StartPage _page = _StartPage.splash;
  AppLanguage _language = AppLanguage.english;
  ThemeMode _themeMode = ThemeMode.system;
  bool _onboardingSeen = false;
  bool _reviewingOnboarding = false;
  bool _bootBusy = false;
  int _tab = 0;

  String _t(String key, [Map<String, String>? args]) =>
      AccountStrings.text(_language, key, args);

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    unawaited(_boot());
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    if (widget.authController == null) _auth.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    if (_bootBusy) return;
    setState(() => _bootBusy = true);
    try {
      final saved = await Future.wait<String?>([
        _prefs.language(),
        _prefs.appearance(),
      ]);
      final done = await _prefs.onboardingComplete();
      _language = AppLanguageDetails.fromCode(saved[0]);
      _themeMode = switch (saved[1]) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      await Future.wait<void>([
        _auth.loadCapabilities(),
        _auth.restoreSession(),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;
      _onboardingSeen = done;
      setState(
        () => _page = switch (_auth.status) {
          AuthStatus.signedIn => _StartPage.app,
          AuthStatus.restoreFailed => _StartPage.restoreFailed,
          _ => done ? _StartPage.signIn : _StartPage.onboarding,
        },
      );
    } catch (_) {
      if (mounted) setState(() => _page = _StartPage.storageFailed);
    } finally {
      if (mounted) setState(() => _bootBusy = false);
    }
  }

  void _onAuthChanged() {
    if (!mounted || _page == _StartPage.splash) return;
    if (_reviewingOnboarding) return;
    if (_auth.isAuthenticated && _page != _StartPage.app) {
      setState(() {
        _tab = 0;
        _page = _StartPage.app;
      });
    } else if (!_auth.isAuthenticated && _page == _StartPage.app) {
      setState(() {
        _tab = 0;
        _page = _onboardingSeen ? _StartPage.signIn : _StartPage.onboarding;
      });
    } else if (_auth.status == AuthStatus.restoreFailed &&
        _page != _StartPage.app) {
      setState(() => _page = _StartPage.restoreFailed);
    }
  }

  Future<void> _chooseLanguage(AppLanguage language) async {
    setState(() => _language = language);
    try {
      await _prefs.setLanguage(language.code);
    } catch (_) {
      if (mounted) setState(() => _page = _StartPage.storageFailed);
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final key = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    try {
      await _prefs.setAppearance(key);
    } catch (_) {
      if (mounted) setState(() => _page = _StartPage.storageFailed);
    }
  }

  Future<void> _finishOnboarding() async {
    try {
      await _prefs.setOnboardingComplete(true);
      if (!mounted) return;
      _onboardingSeen = true;
      setState(() {
        _page = _reviewingOnboarding
            ? _auth.isAuthenticated
                  ? _StartPage.app
                  : _StartPage.signIn
            : _StartPage.signIn;
        _reviewingOnboarding = false;
      });
    } catch (_) {
      if (mounted) setState(() => _page = _StartPage.storageFailed);
    }
  }

  void _reviewIntro() {
    setState(() {
      _reviewingOnboarding = true;
      _page = _StartPage.onboarding;
    });
  }

  void _openTab(int index) => setState(() => _tab = index);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ORAKZAI.ORG',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      locale: _language.locale,
      supportedLocales: const [Locale('en'), Locale('ur'), Locale('ps')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => LanguageScope(
        language: _language,
        child: Directionality(
          textDirection: _language.isRightToLeft
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: switch (_page) {
          _StartPage.splash => _BrandedSplash(key: const ValueKey('splash')),
          _StartPage.onboarding => _Onboarding(
            key: const ValueKey('onboarding'),
            language: _language,
            onLanguageChanged: _chooseLanguage,
            onFinish: _finishOnboarding,
          ),
          _StartPage.signIn => _AuthenticationGate(
            key: const ValueKey('sign-in'),
            language: _language,
            auth: _auth,
            onLanguageChanged: _chooseLanguage,
          ),
          _StartPage.restoreFailed => _RecoveryScreen(
            key: const ValueKey('restore-failed'),
            title: _t('restoreErrorTitle'),
            message: _t('restoreErrorBody'),
            busy: _bootBusy,
            onRetry: _boot,
          ),
          _StartPage.storageFailed => _RecoveryScreen(
            key: const ValueKey('storage-failed'),
            title: _t('prefsErrorTitle'),
            message: _t('prefsErrorBody'),
            busy: _bootBusy,
            onRetry: _boot,
          ),
          _StartPage.app => _AuthenticatedApp(
            key: const ValueKey('authenticated-app'),
            tab: _tab,
            language: _language,
            themeMode: _themeMode,
            auth: _auth,
            onTab: _openTab,
            onLanguage: _chooseLanguage,
            onTheme: _setTheme,
            onReviewOnboarding: _reviewIntro,
          ),
        },
      ),
    );
  }
}

class _BrandedSplash extends StatelessWidget {
  const _BrandedSplash({super.key});
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F1),
      body: Center(
        child: Semantics(
          label: 'ORAKZAI.ORG — THE DIGITAL COMMUNITY NETWORK',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: reduce ? 1 : .76, end: 1),
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 680),
                curve: Curves.easeOutCubic,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Image.asset(
                  'assets/images/orakzai_emblem.png',
                  width: 112,
                  height: 112,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),
              Image.asset(
                'assets/brand/orakzai_wordmark.png',
                width: 245,
                height: 90,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 5),
              const Text(
                'THE DIGITAL COMMUNITY NETWORK',
                textAlign: TextAlign.center,
                style: TextStyle(
                  letterSpacing: 1.7,
                  fontSize: 10,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'ONE IDENTITY. ONE NETWORK. A SHARED FUTURE.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.goldDeep),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Onboarding extends StatefulWidget {
  const _Onboarding({
    required this.language,
    required this.onLanguageChanged,
    required this.onFinish,
    super.key,
  });
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onFinish;
  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  final PageController _pages = PageController();
  int _index = 0;
  bool _busy = false;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  String _t(String key) => AccountStrings.text(widget.language, key);

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['ob1Title', 'ob2Title', 'ob3Title'];
    final descriptions = ['ob1Body', 'ob2Body', 'ob3Body'];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.public_rounded, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _t('tagline'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  PopupMenuButton<AppLanguage>(
                    tooltip: _t('chooseLanguage'),
                    initialValue: widget.language,
                    onSelected: widget.onLanguageChanged,
                    itemBuilder: (_) => AppLanguage.values
                        .map(
                          (language) => PopupMenuItem(
                            value: language,
                            child: Text(language.displayName),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: Text(
                        widget.language.displayName,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _busy ? null : _finish,
                  child: Text(_t('skip')),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemCount: 3,
                  itemBuilder: (context, index) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 246,
                        height: 246,
                        decoration: BoxDecoration(
                          color: AppColors.navyDeep,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.gold, width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x18322306),
                              blurRadius: 24,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(42),
                        child: Image.asset(
                          'assets/images/orakzai_emblem.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.diversity_3_rounded,
                            size: 88,
                            color: AppColors.onDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: 38),
                      Text(
                        _t(titles[index]),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Text(
                          _t(descriptions[index]),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: AppColors.muted, height: 1.55),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        AccountStrings.text(widget.language, 'onboardingStep', {
                          'n': '${index + 1}',
                        }),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppColors.goldDeep,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: i == _index ? 22 : 7,
                    height: 7,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: i == _index ? AppColors.navy : AppColors.line,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _index == 2
                            ? _finish()
                            : _pages.nextPage(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                              ),
                  child: Text(_t(_index == 2 ? 'getStarted' : 'continue')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthenticationGate extends StatelessWidget {
  const _AuthenticationGate({
    required this.language,
    required this.auth,
    required this.onLanguageChanged,
    super.key,
  });
  final AppLanguage language;
  final AuthController auth;
  final ValueChanged<AppLanguage> onLanguageChanged;
  @override
  Widget build(BuildContext context) {
    String t(String key) => AccountStrings.text(language, key);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 34, 22, 20),
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/brand/orakzai_wordmark.png',
                          width: 242,
                          height: 86,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.language_rounded,
                              size: 19,
                              color: AppColors.navy,
                            ),
                            const SizedBox(width: 6),
                            PopupMenuButton<AppLanguage>(
                              tooltip: t('chooseLanguage'),
                              onSelected: onLanguageChanged,
                              itemBuilder: (_) => AppLanguage.values
                                  .map(
                                    (item) => PopupMenuItem(
                                      value: item,
                                      child: Text(item.displayName),
                                    ),
                                  )
                                  .toList(),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  language.displayName,
                                  style: const TextStyle(
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          t('signInSubtitle'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 22),
                        AuthFlowScreen(auth: auth, language: language),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryScreen extends StatelessWidget {
  const _RecoveryScreen({
    required this.title,
    required this.message,
    required this.busy,
    required this.onRetry,
    super.key,
  });
  final String title, message;
  final bool busy;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/orakzai_emblem.png',
                  width: 92,
                  height: 92,
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: busy ? null : onRetry,
                  child: Text(
                    busy
                        ? '…'
                        : AccountStrings.text(
                            LanguageScope.of(context),
                            'retry',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AuthenticatedApp extends StatelessWidget {
  const _AuthenticatedApp({
    required this.tab,
    required this.language,
    required this.themeMode,
    required this.auth,
    required this.onTab,
    required this.onLanguage,
    required this.onTheme,
    required this.onReviewOnboarding,
    super.key,
  });
  final int tab;
  final AppLanguage language;
  final ThemeMode themeMode;
  final AuthController auth;
  final ValueChanged<int> onTab;
  final ValueChanged<AppLanguage> onLanguage;
  final ValueChanged<ThemeMode> onTheme;
  final VoidCallback onReviewOnboarding;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: auth,
    builder: (context, _) {
      if (!auth.isAuthenticated || auth.user == null) {
        return const SizedBox.shrink();
      }
      return Scaffold(
        body: IndexedStack(
          index: tab,
          children: [
            HomeScreen(
              language: language,
              authController: auth,
              onOpenHelpDesk: () => onTab(2),
              onOpenCommunity: () => onTab(1),
              onOpenProfile: () => onTab(4),
              isActive: tab == 0,
            ),
            CommunityScreen(
              authController: auth,
              onOpenProfile: () => onTab(4),
            ),
            HelpDeskScreen(authController: auth, onOpenProfile: () => onTab(4)),
            const ServicesScreen(),
            ProfileScreen(
              language: language,
              authController: auth,
              onLanguageChanged: onLanguage,
              onAppearanceChanged: onTheme,
              appearance: themeMode,
              onReviewOnboarding: onReviewOnboarding,
              onOpenHelpDesk: () => onTab(2),
            ),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: onTab,
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.goldWash,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              _destination(
                context,
                Icons.home_outlined,
                Icons.home_rounded,
                'home',
              ),
              _destination(
                context,
                Icons.people_outline_rounded,
                Icons.people_rounded,
                'community',
              ),
              _destination(
                context,
                Icons.support_agent_outlined,
                Icons.support_agent_rounded,
                'helpDesk',
              ),
              _destination(
                context,
                Icons.grid_view_outlined,
                Icons.grid_view_rounded,
                'services',
              ),
              _destination(
                context,
                Icons.person_outline_rounded,
                Icons.person_rounded,
                'profile',
              ),
            ],
          ),
        ),
      );
    },
  );

  NavigationDestination _destination(
    BuildContext context,
    IconData idle,
    IconData selected,
    String key,
  ) => NavigationDestination(
    icon: Icon(idle),
    selectedIcon: Icon(selected),
    label: AppCopy.text(language, key),
  );
}
