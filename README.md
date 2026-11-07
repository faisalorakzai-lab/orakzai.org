# Orakzai — The Digital Community Network

Native Flutter Android app foundation for Orakzai.org.

## Current milestone

- Flutter project configured for Android with application ID `org.orakzai.app`.
- Premium navy, gold and light-surface theme, branded launcher placeholder and splash screen.
- Five independent destinations: Home, Community, Help Desk, Services and Profile.
- Search, category filters, local save feedback, language selection, request-form validation and information dialogs.
- Public program descriptions are based on the SonOfOrakzai organization website. They describe published focus areas, not confirmed service availability.
- All sample interactions are labeled as preview-only. Authentication, messaging, push notifications and request submission are not connected.
- No member totals, verified memberships or assistance outcomes are invented.

## Run and verify

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

To run an Android build, install Flutter and the Android SDK, then accept the Android SDK licenses:

```sh
flutter doctor
flutter doctor --android-licenses
```

## Project structure

```text
lib/
  app/       App shell, localization-ready copy and theme
  data/      Public program information and demo categories
  screens/   Home, Community, Help Desk, Services and Profile
  widgets/   Shared branded UI components
android/     Native Android configuration and release signing setup
test/        Widget tests for the first milestone
```

## Release status

This is a development foundation, not a Play Store release. Android SDK/build tools were not present in the Replit environment when this milestone was prepared. Before release, configure a private upload key, set up `android/key.properties` from `android/key.properties.example`, verify the current Google Play target SDK requirements, test on Android devices, and complete the Play Console listing and policy forms. Never commit signing keys or secrets.

See [PLAY_STORE_READINESS.md](PLAY_STORE_READINESS.md) for the release checklist.
