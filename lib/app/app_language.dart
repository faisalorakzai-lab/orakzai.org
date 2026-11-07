enum AppLanguage { english, urdu, pashto }

extension AppLanguageDetails on AppLanguage {
  String get displayName => switch (this) {
    AppLanguage.english => 'English',
    AppLanguage.urdu => 'اردو',
    AppLanguage.pashto => 'پښتو',
  };

  bool get isRightToLeft => this != AppLanguage.english;
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
      'guest': 'Guest preview',
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
