# Command 04 — Android cloud build and release preparation

## Status

**Update: an actual checking APK has now been built locally and verified.**

- Current direct APK: `generated-artifacts/downloads/orakzai-test-compat.apk`
  (70,075,172 bytes). This supersedes the original checking APK/ZIP after a phone
  rejected the original package.
- Application ID `org.orakzai.app`, version 1.0.0 / code 2.
- Android 7+ (SDK 24), ARM32 and ARM64; debug-signed, not a Play Store release.
- APK signatures v2/v3 and the full archive validation passed. The debug variant
  now uses compressed native libraries with Android extraction enabled; production
  packaging is unchanged. The earlier APK passed signature/alignment checks but
  had native-library ZIP extra-field errors in unzip validation. The new archive
  has no such validation errors. This is not proof of the phone's exact rejection
  cause; actual phone/emulator installation remains unverified.
- SHA-256: `f4921d5ac4428ee4718e44069ab06a7c88bf113e50e2f15f501d7cfff35d3640`.
- API configuration retains the development emulator URL. Phone login/chat require
  rebuilding with a reachable backend; this APK is for checking the existing UI.

Java and Android SDK were installed after the initial Command 04 checks.
The initial release APK/AAB attempts stopped at `No Android SDK found`; those
historical failures do not describe the subsequent successful debug APK build.
Cloud compilation and release APK/AAB generation remain unverified.

No GitHub push, workflow dispatch, production deployment, Play Store upload,
production database query, real SMTP delivery or device test was performed.
Help Desk and Command 03 features were not rebuilt.

## Project and toolchain

| Setting | Inspected / prepared value |
| --- | --- |
| Flutter entry point | `lib/main.dart` |
| Application ID / namespace | `org.orakzai.app`, preserved |
| App version | `1.0.0+1`, preserved; increase build number for subsequent Play uploads |
| Flutter / Dart | Flutter stable 3.32.0 / Dart 3.8.0 |
| Cloud runner | Ubuntu 22.04 |
| Java | Temurin JDK 17; Java/Kotlin bytecode target 17 |
| Gradle wrapper | 8.13 |
| Android Gradle Plugin | 8.13.2 |
| Kotlin Gradle Plugin | 2.2.20 |
| Android compile / target SDK | 36 / 36 |
| Minimum Android SDK | 24 (Android 7), required by installed audio_session |
| NDK | 27.0.12077973 |
| Explicit build tools / CMake | 35.0.0 / 3.22.1 |

The original AGP 8.7.3 / Gradle 8.12 / Kotlin 2.1.0 configuration was below
requirements of already-installed plugins. In particular, share_plus 12.0.2
documents Java 17, Kotlin 2.2.0, AGP >=8.12.1 and Gradle >=8.13.
flutter_secure_storage 10.3.4 uses compile SDK 36 and minimum SDK 23;
record_android 1.5.2 uses Kotlin 2.2.20. The prepared configuration aligns these
requirements; actual Gradle/plugin compatibility remains pending the first cloud
compile and Android device testing. Target SDK changes also need Android 16
behavior testing. Play policy compliance, native library 16 KB page alignment and
Play Console acceptance have not been verified.

Gradle heap is capped at 2 GB with one worker and in-process Kotlin compilation.
The local Gradle cache was moved from RAM-backed home storage into disk-backed,
ignored workspace storage to prevent OOM kills. The successful build also required
correcting Java class references in the Gradle script and invalid splash drawable
color attributes; neither change redesigns the app.

## Workflow locations and repository layout

- Workspace repository: `.github/workflows/android-release.yml`.
- Standalone Flutter repository export: `orakzai.org/.github/workflows/android-release.yml`.

The two workflows intentionally have the same behavior. Keep them synchronized.
GitHub only discovers workflows under the **Git repository root**
`.github/workflows/`; a nested workflow alone is not discovered.
If publishing only the contents of `orakzai.org/` to the standalone app repository,
its included `.github/` directory must be included too. If pushing this whole
workspace, the workspace-root workflow is already in the correct location.
The workflow locates Flutter at root or in `orakzai.org/`.

The manual workflow:

1. Checks out source with read-only repository permissions.
2. Requires a public HTTPS API URL, installs Java, Flutter and Android components.
3. Resolves packages, runs analysis and Flutter tests.
4. Builds release APK and AAB from `lib/main.dart`.
5. Verifies nonempty ZIP archives; signed builds additionally verify APK/AAB signatures.
6. Uploads the binaries and SHA-256 checksums only after successful verification.
7. Uploads diagnostic logs even after failure and removes the temporary keystore.

All build commands use Bash pipeline failure propagation, so `tee` does not hide
failed commands. Android compilation is not skipped to produce a false success.
A failure before compilation uploads an outcome log; the GitHub run also retains
the complete step console logs.

## Required repository configuration

Open the target GitHub repository → Settings → Secrets and variables → Actions.
Do **not** paste signing material into chat or commit it.

### Repository secrets for a signed build

| Secret | Value to supply privately |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Single-line Base64 encoding of the existing upload keystore bytes |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Upload key alias in that keystore |
| `ANDROID_KEY_PASSWORD` | Private key password |

Availability of these GitHub secrets is **not verified** and none was invented or
created. They are GitHub repository secrets, not automatically transferred from
workspace secrets.

- All four present: decode to a temporary file with permissions 0600. Gradle
  reads passwords from the step environment, not a committed properties file.
  Wrong passwords or aliases fail the build.
- None present: build unsigned release archives, explicitly labelled
  `unsigned-NOT-PLAY-STORE`. An unsigned APK is not directly installable.
  An unsigned AAB is not a signed Play Store upload. No debug-key fallback exists.
- Some present: fail rather than silently downgrade to unsigned.
- Existing local signing remains supported through ignored `android/key.properties`.
  Keystores and key.properties are ignored by Git.

Use the correct existing upload key for an already-registered Play app. Do not
replace an established key casually. For a new app, generate an upload key
privately with trusted Java keytool, retain an encrypted backup, and configure
Play App Signing. No key has been generated here.

### Non-secret API configuration

Set repository **variable** `ORAKZAI_API_BASE_URL` to the real backend URL including
its `/api` prefix, or enter that URL in the manual run's `api_url` field.
No production URL is provided by this project preparation.
Do not use the public content website URL unless it actually hosts this backend.

The workflow passes:

```sh
flutter build apk --release --target lib/main.dart \
  --dart-define="ORAKZAI_API_BASE_URL=$API_URL"
flutter build appbundle --release --target lib/main.dart \
  --dart-define="ORAKZAI_API_BASE_URL=$API_URL"
```

Workflow preflight and Gradle release configuration reject missing/non-HTTPS API
configuration and common local/emulator addresses. Dart validates configuration
at startup as another safeguard. Development retains the Android emulator URL
only outside release mode. There is no release fallback to `10.0.2.2`.
This is URL validation, **not verification that the endpoint exists or is healthy**.
The endpoint and TLS certificate need a real health check and mobile access test.

## Phone instructions and exact artifact locations

1. First commit/push the source and root workflow to the intended GitHub repository.
   This preparation has not performed that push.
2. On your phone open
   `https://github.com/faisalorakzai-lab/orakzai.org/actions`.
   Sign in with repository access. Enable Actions if disabled.
3. Open **Android release** → **Run workflow**. If the mobile page hides controls,
   use your browser's Desktop site view. Choose the branch, provide the real API
   URL if the repository variable is unset, and start the run.
4. Open the run and follow the logs. A red run is a failure, not a completed APK.
5. After a successful run, scroll to **Artifacts** and download:
   - `android-signed-<run_number>`, or
   - `android-unsigned-NOT-PLAY-STORE-<run_number>`.
6. The artifact ZIP contains:
   - `orakzai-signed.apk` and `orakzai-signed.aab`, or the corresponding
     `orakzai-unsigned-NOT-PLAY-STORE.apk/.aab` files;
   - `SHA256SUMS`.
   A successful run's Summary also provides the actual artifact download link.
7. Diagnostic download: `android-build-logs-<run_number>`, including `apk.log`,
   `aab.log`, analysis/tests logs and integrity/signature verification logs when
   those steps ran. Artifact retention is 14 days.

The future run page is
`https://github.com/faisalorakzai-lab/orakzai.org/actions/runs/<actual_run_id>`.
No cloud run ID exists from this work, so a direct GitHub artifact download link
cannot yet be provided. The checking APK ZIP above was delivered separately.
The paths below describe **future release outputs**, not existing downloads:

- APK: `build/app/outputs/flutter-apk/app-release.apk` (unsigned Gradle alternative:
  `build/app/outputs/apk/release/app-release-unsigned.apk`).
- AAB: `build/app/outputs/bundle/release/app-release.aab`.

A signed APK can be installed for device testing after reviewing the source and
signature. An AAB is intended for Play Console/internal testing, not direct phone
installation. A signed build alone is not evidence that production integrations work.

## Checks actually executed

| Check | Actual result |
| --- | --- |
| `flutter pub get` | Passed before the system-tool refresh |
| `flutter analyze` | Passed, no issues |
| `flutter test` | 7 passed, including new release API-configuration tests |
| Compatible backend dependency update + typecheck/tests | Passed: 9 existing tests |
| Nodemailer major upgrade alone + typecheck/tests | Passed: 9 existing tests |
| Zod major upgrade separately + typecheck/tests | Passed: 9 existing tests |
| Final backend typecheck and tests | Passed: 11 tests in 3 files |
| Workspace `pnpm run typecheck` after compatible remediation | Passed |
| `actionlint` on both workflows | Passed after shell glob warning was fixed |
| `git diff --check` | Passed |
| App backend `pnpm audit --json` | 0 critical/high/moderate/low findings |
| Full-workspace dependency scanner | 0 critical, 1 high, 2 moderate, 0 low |
| SAST | Completed; 3 HIGH flags requiring the triage below |
| Privacy/dataflow scanner | Completed; 0 findings |
| Local release APK | Failed: Android SDK unavailable; no artifact |
| Local release AAB | Failed: Android SDK unavailable; no artifact |
| Subsequent local debug APK | Passed after SDK installation and minimal native-build fixes; delivered in ZIP |
| GitHub cloud workflow | Not dispatched; no remote build verified |
| Android runtime / signing / Play upload | Not run |

Backend tests use a real development Postgres database and disposable accounts,
not production data. The new Nodemailer test renders an actual MIME message via
its in-memory stream transport; it does **not** prove real SMTP delivery.
The new Zod test checks strict input rejection, error issue shape and coercion.

## Production integration blockers

| Area | What remains before production |
| --- | --- |
| Private S3-compatible media | Production media access currently fails closed. Implement an actual provider adapter, private bucket/endpoint/region credentials, least-privilege service identity, short-lived authorized access, ACL rechecks, lifecycle/deletion and backup policy. Verify upload/download and revoked access for image/video/document/voice files against real storage. Setting credentials alone does not implement the adapter. |
| SMTP | Provide trusted TLS SMTP transport and verified sender through `SMTP_URL` / `SMTP_FROM`; set `AUTH_DEV_MODE=false`. Test real registration verification, resend and password-reset delivery, expiry and abuse controls. No real email has been sent in these checks. |
| FCM | Configure Firebase Android app for `org.orakzai.app`, native Firebase configuration, Android notification permission/channel handling, device-token registration/rotation and secure server credentials. Implement/verify server delivery, preferences/mutes and foreground/background/terminated behavior. Not connected by this work. |
| Socket.IO scaling | Current realtime/presence is single-process. Implement a shared adapter (for example Redis), shared/expiring presence and session revocation propagation; configure TLS proxy upgrades and load balancing. Test two backend instances, reconnect and revoked sessions. |
| Retention | Agree organization/legal policy. `COMMUNITY_DELETED_CONTENT_RETENTION_DAYS=0` disables purge. Production deletion also requires `COMMUNITY_RETENTION_PURGE_CONFIRM=true`. Configure a controlled scheduler, dry-run review, backups and storage/database cleanup coordination. No production purge was run. |
| Production Postgres | Confirm the actual database target, schema migration history, foreign keys/indexes/constraints, least-privilege access, encryption, backups/restore, connection budgets and monitoring. Development tests do not verify production. The current migrate script is development-oriented; establish a reviewed production migration procedure rather than running it blindly. |
| Release access | Publish the workflow source to GitHub, configure a verified production backend URL and signing secrets, then run cloud compilation. No working GitHub write connection or secret availability is assumed. |
| Store readiness | Device tests, privacy policy/data safety, moderation policies, screenshots/listing, Play Console access and review, current target-API requirements and native library compatibility remain release gates. |

The current main Android manifest declares INTERNET but not RECORD_AUDIO or
CAMERA. Existing voice/camera functionality therefore needs a focused Android
permission review and real-device validation before release; it has not been
claimed operational by this cloud-build preparation.

See [dependency-security-command04.md](dependency-security-command04.md) for
exact dependency paths and unresolved scanner findings. No production integration
is represented as connected solely because its future configuration is documented.
