import 'package:flutter/widgets.dart';

import '../account/account_strings.dart';

enum AppLanguage { english, urdu, pashto }

extension AppLanguageDetails on AppLanguage {
  String get displayName => switch (this) {
    AppLanguage.english => 'English',
    AppLanguage.urdu => 'اردو',
    AppLanguage.pashto => 'پښتو',
  };

  bool get isRightToLeft => this != AppLanguage.english;

  String get code => switch (this) {
    AppLanguage.english => 'en',
    AppLanguage.urdu => 'ur',
    AppLanguage.pashto => 'ps',
  };

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
    (language) => language.code == code,
    orElse: () => AppLanguage.english,
  );
}

class AppCopy {
  const AppCopy._();

  static const Map<AppLanguage, Map<String, String>> _strings = {
    AppLanguage.english: {
      'home': 'HOME',
      'community': 'COMMUNITY',
      'helpDesk': 'HELP DESK',
      'services': 'SERVICES',
      'profile': 'PROFILE',
      'homeTitle': 'A community connected by purpose',
      'homeSubtitle': 'One Identity. One Network. A Shared Future.',
      'emergency': 'Emergency help',
      'shareProblem': 'Share a problem',
      'search': 'Search programs and services',
      'language': 'Language',
      'guest': 'Guest',
    },
    AppLanguage.urdu: {
      'home': 'ہوم',
      'community': 'کمیونٹی',
      'helpDesk': 'مدد',
      'services': 'خدمات',
      'profile': 'پروفائل',
      'homeTitle': 'مقصد سے جڑی ہوئی کمیونٹی',
      'homeSubtitle': 'ایک شناخت۔ ایک نیٹ ورک۔ ایک مشترکہ مستقبل۔',
      'emergency': 'ہنگامی مدد',
      'shareProblem': 'مسئلہ بیان کریں',
      'search': 'پروگرام اور خدمات تلاش کریں',
      'language': 'زبان',
      'guest': 'مہمان پیش نظارہ',
    },
    AppLanguage.pashto: {
      'home': 'کور',
      'community': 'ټولنه',
      'helpDesk': 'مرسته',
      'services': 'خدمتونه',
      'profile': 'پروفایل',
      'homeTitle': 'د ګډ هدف لپاره تړلې ټولنه',
      'homeSubtitle': 'یو هویت. یو شبکه. ګډ راتلونکی.',
      'emergency': 'بیړنۍ مرسته',
      'shareProblem': 'ستونزه شریکه کړئ',
      'search': 'پروګرامونه او خدمتونه ولټوئ',
      'language': 'ژبه',
      'guest': 'د مېلمه مخکتنه',
    },
  };

  static String text(AppLanguage language, String key) {
    return _strings[language]?[key] ??
        _strings[AppLanguage.english]![key] ??
        key;
  }
}

/// Makes the active language available to every route so that account and
/// authentication screens rebuild immediately when the member switches it.
class LanguageScope extends InheritedWidget {
  const LanguageScope({
    required this.language,
    required super.child,
    super.key,
  });

  final AppLanguage language;

  static AppLanguage of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()?.language ??
      AppLanguage.english;

  @override
  bool updateShouldNotify(LanguageScope oldWidget) =>
      oldWidget.language != language;
}

/// Translate an account/auth/launch key for the current context.
String tr(BuildContext context, String key, [Map<String, String>? args]) =>
    AccountStrings.text(LanguageScope.of(context), key, args);
