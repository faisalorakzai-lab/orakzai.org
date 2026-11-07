# Google Play readiness checklist

This app has an Android project and the requested application ID (`org.orakzai.app`), but it is not ready to upload yet.

## Before building a release

1. Install Android Studio and the Android SDK on a Flutter-capable machine.
2. Run `flutter doctor` and resolve the Android toolchain warnings.
3. Confirm the current Google Play target API level and policy requirements.
4. Generate an upload key and keep it outside the repository.
5. Copy `android/key.properties.example` to `android/key.properties` and fill it locally. `android/key.properties` and key files are git-ignored.
6. Replace demonstration copy with organization-approved content and confirm the availability of every listed service.
7. Connect and test real authentication, assistance intake, data storage, moderation and privacy controls before claiming those features work.
8. Prepare a privacy policy, Data safety answers, content rating, store listing, screenshots and support contact.
9. Test the signed Android release on supported devices before uploading through Google Play Console.

## Build command

After Android SDK and signing are configured:

```sh
flutter build appbundle --release
```

The signing configuration intentionally does not fall back to Android's debug key. No production signing key or Play Console access is included in this repository.

## Current app behavior

- The five primary screens and local preview interactions work without a server.
- The Help Desk form validates input, then explicitly tells the user that no request was sent or stored.
- Community groups, private messages, authentication, member profiles and notifications are not connected.
- Public program descriptions are reference information only; availability and outcomes are not verified by this app.
