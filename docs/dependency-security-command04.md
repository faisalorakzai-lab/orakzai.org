# Command 04 dependency security report

## Scope and actual results

Two separate pnpm workspaces exist:

1. `orakzai.org/` — Flutter source and `@orakzai/backend`.
2. Workspace root — legacy Expo artifact, API preview, sandbox and code-generation
   libraries. These dependencies are not the Flutter Android binary dependencies.

The direct app audit initially reported 0 critical, 5 high, 15 moderate, 1 low
advisories. Its **final `pnpm audit --json` reports zero at every severity**.
The full-workspace scanner still reports **1 high and 2 moderate**. These are
unresolved root-workspace dependencies, not a clean whole-project security result.
An audit reports known advisories, not a guarantee that software is secure.

## Remediation applied, with dependency paths

| Dependency path | Before → after / handling |
| --- | --- |
| `orakzai.org/backend > nodemailer` | 7.0.13 → 10.4.0. No safe compatible 7.x fix for all reported advisories. Major upgrade tested separately with backend typecheck and 9 existing integration tests; new real MIME stream rendering test added. Live SMTP remains untested. |
| `orakzai.org/backend > zod` | 3.25.76 → 4.6.6. Major upgrade tested separately after Nodemailer checks passed, including backend typecheck and 9 existing integration tests; new strict-schema/coercion/error-shape regression test added. Source imports use Zod 4, not vulnerable `zod/v3`. |
| `orakzai.org/backend > express > body-parser` | Already resolved to safe 2.4.0 at inspection. Express manifest baseline moved from ^5.1.0 to ^5.3.0; compatible refresh retained 5.3.0. |
| `artifacts/api-server > express > body-parser` | 2.3.0 → 2.4.0, compatible transitive resolution. Addresses GHSA-27r3-jxmh-p828 compressed-body process crash. |
| `artifacts/api-server > express > qs` and `express > body-parser > qs` | 6.16.0 → 6.17.1, compatible transitive resolution. |
| `lib/api-spec > orval > @scalar/openapi-parser > @scalar/openapi-validator > @scalar/json-schema-validator > ajv > fast-uri` | 3.1.8 → 3.1.9, compatible update, also inherited by ajv-formats / ajv-draft-04 branches. |
| `lib/api-spec > orval > @scalar/json-magic > undici` | Old exact parent dependency pinned vulnerable 7.29.1. Updated direct parent Orval 8.41.0 → 8.46.0, rather than forcing a transitive major override. Result: json-magic 0.16.1 → undici 7.30.1. |
| `lib/api-spec > orval > @scalar/openapi-parser > @scalar/json-magic > undici` | Updated parent branch resolves json-magic 0.18.0 → undici 8.12.3. Parent's compatible update selects its own supported dependency; no blanket undici override used. |
| `lib/api-spec > orval > @orval/zod` and `@scalar/types > zod` | Vulnerable 4.6.5 removed through parent update; now 4.6.7. |

Final backend: 11 tests passed, typecheck passed. Root workspace shared-library
and leaf typechecks passed after lockfile and Orval updates. Root generated-code
runtime functionality and a complete Expo journey were not tested. The root Expo
install still warns about a missing `@react-native/metro-config` peer; this is not
part of the Flutter release build and was not silently “fixed” with a framework upgrade.

## Remaining dependency advisories — exact paths

### High: Zod 3.25.76, GHSA-mrhx-c7xc-m3w5

Affected root-workspace paths:

- `artifacts/api-server > @workspace/api-zod (lib/api-zod) > zod`.
- `artifacts/api-server > @workspace/db (lib/db) > zod`.
- `lib/db > drizzle-zod@0.8.3 > zod` peer dependency.
- `artifacts/mockup-sandbox > zod`.
- `artifacts/orakzai-app > zod`.
- `artifacts/orakzai-app > zod-validation-error@3.5.4 > zod` peer dependency.

Root catalog pins Zod ^3.25.76. The scanner recommends >=4.6.6.
Do not blindly change the shared catalog: generated schemas, database validation,
Zod error helpers and the legacy Expo application require a coordinated migration
and tests. This major upgrade is **not** applied to those separate products.
The standalone Flutter app backend has already migrated and has no such finding.

### Moderate: Glob 13.0.7, GHSA-3g3m-2fjr-6pw4

- `artifacts/orakzai-app > expo@58.0.23 > @expo/cli@58.1.19 > glob@13.0.7`.
- `artifacts/orakzai-app > expo@58.0.23 > @expo/fingerprint@0.21.9 > glob@13.0.7`.
- Expo-dependent peer branches inherit the same toolchain.

Fix requires Glob >=14.0.2. The scanner describes continued filesystem traversal
after AbortSignal cancellation. Do not force an untested major Glob override into
the Expo CLI. Upgrade/test its parent toolchain in the existing security follow-up.

### Moderate: Minimatch 10.2.6, GHSA-g3hv-75wg-m249

- The two Glob paths above → `minimatch@10.2.6`.
- `artifacts/orakzai-app > expo > @expo/fingerprint > minimatch@10.2.6`.

Fix requires Minimatch >=11.0.1. Pattern amplification can exhaust resources.
This is likewise unresolved in the separate legacy Expo tooling.

## SAST triage: 3 HIGH flags, not 3 confirmed exploitable vulnerabilities

1. `artifacts/orakzai-app/server/serve.js:77` — manifest file path from platform.
   Router restricts platform to the literals `ios` or `android` before calling
   the helper. This substantially limits the reported input path. No exploit was
   demonstrated; keep the finding visible pending a focused server review.
2. Same file `:121` — static file read. Normalization and a prefix containment
   check exist, but prefix-string checks are weaker than canonical containment
   and do not address symlink escapes. This legacy Expo server is outside the
   Flutter app repository; it was not redesigned. Treat as unresolved hardening,
   not evidence that Flutter private media is public.
3. `orakzai.org/backend/src/services/auth-service.ts:236` — static bcrypt hash.
   Reviewed the branch: this is a dummy comparison when no user is found, used
   for timing equalization before returning invalid credentials. It is not a
   real account password, authentication key or active credential. Classified
   as a false-positive secret flag; no actual credential is reproduced here.

SAST was rerun after remediation and still reports all 3. They were not hidden
or suppressed to claim a clean scan. The privacy/dataflow scanner completed with
zero findings. Real production penetration tests and integration validation have
not been performed.

## Release decision

Do not call the entire workspace “security cleared”. The app dependency audit is
clean at scan time, but unresolved root findings and unverified production
integrations remain. Existing production-media, sign-in/alerts and high-risk
dependency follow-ups already cover these areas; no duplicate task is needed.
