# Orakzai — The Digital Community Network

Native Flutter Android app foundation for Orakzai.org.

## Current milestone

- Flutter project configured for Android with application ID `org.orakzai.app`.
- Premium navy, gold and light-surface theme, branded launcher placeholder and splash screen.
- Five independent destinations: Home, Community, Help Desk, Services and Profile.
- Search, category filters, local save feedback, language selection, request-form validation and information dialogs.
- Public program descriptions are based on the SonOfOrakzai organization website. They describe published focus areas, not confirmed service availability.
- Sign-up, login, email verification, password reset, session refresh and private profile editing are implemented against the included REST API and PostgreSQL schema. Production email delivery still needs SMTP configuration.
- Community messaging, push notifications and Help Desk submission remain preview-only. Google sign-in, wallet sign-in and profile-photo uploads are not configured.
- No member totals, verified memberships or assistance outcomes are invented.

## Authentication foundation

The backend provides registration, email/phone login, email verification, password reset, rotating refresh tokens, server-checked sessions, profile editing, permissions, organization roles and audit records. Development migrations apply only to the Replit development database; use Replit's database Publish flow to move its schema to production.

```sh
pnpm install
pnpm --filter @orakzai/backend migrate
pnpm --filter @orakzai/backend dev
pnpm --filter @orakzai/backend test
```

The backend listens on port `3001`. Android emulator builds use `http://10.0.2.2:3001/api` by default. Use `--dart-define=ORAKZAI_API_BASE_URL=https://your-api.example/api` for a deployed HTTPS API. Development verification/reset codes are shown only when `AUTH_DEV_MODE=true` outside production. For production, configure `SMTP_URL`, `SMTP_FROM`, a strong `ACCESS_TOKEN_SECRET` (or the existing `SESSION_SECRET`), `DATABASE_URL`, and `CORS_ORIGINS`. Never commit real credentials.

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
