# Actual Flutter Home redesign — implementation and verification

> The visual presentation below is historical. The current photo-led native
> Flutter implementation is documented in [Home UI foundation](home-ui-foundation.md).

## Current approved visual direction: Emerald & Ivory

The user rejected the initial poster-heavy presentation and selected Emerald &
Ivory. The current real Flutter implementation uses an ivory canvas, deep emerald
actions, restrained gold accents and bundled weight-specific Manrope fonts.
Bundled Noto Sans Arabic fallback preserves existing Urdu/Pashto glyphs. Both
font families and their SIL license texts are local assets; there is no runtime
Google Fonts dependency.

Home now places welcome/search and primary support actions before a compact
editorial carousel. At 412×915, the request action is available without scrolling.
The supplied artwork appears as a whole thumbnail alongside native text and CTA,
not as a full-screen poster. Tapping artwork opens a zoomable full-poster viewer.
The shared theme also styles the real Community, Help Desk, existing Services
catalogue and Profile/sign-in screens, without adding Services functionality.

## Actual application route

Entry point: `lib/main.dart` → `OrakzaiApp` in `lib/app/app_shell.dart` →
the `IndexedStack` child at index **0**, `HomeScreen` in
`lib/screens/home_screen.dart`.

This is the existing native Flutter application's real Home tab. No Expo page,
HTML prototype, canvas mockup, or replacement navigation shell was used.
The five navigation destinations and their order remain:
**Home | Community | Help Desk | Services | Profile**.

The shared PREVIEW badge was removed. Misleading “Guest preview”, “private preview
form” and device-preference preview wording were removed or corrected without
changing the underlying features. Actual private-media/document preview tools
are not preview-only app navigation and remain intact.

## Implemented Home sections

| Section | Implementation and source |
|---|---|
| Organization header | Existing official local emblem and existing brand tokens; no PREVIEW badge |
| Hero | Five user-supplied posters in the native reusable carousel |
| Welcome | Nonprofit introduction and authenticated member's first name when available |
| Global search | Approved public program descriptions, plus authenticated posts, groups and members through existing API clients |
| Emergency Help | Explicit non-emergency-response warning, then actual private Help Desk form with emergency category; guests go to Profile |
| Submit a request | Actual authenticated Help Desk request form, not a preview form |
| Organization announcements | Existing authorized community announcement feed; loading/empty/error/sign-in states |
| Programs and services | Existing approved public website program information and detail dialogs; no claim of current bookable service availability |
| Community statistics | Real database totals of visible updates, visible announcements and the member's active joined groups |
| Latest updates | Existing authorized community feed; refresh on Home return and pull-to-refresh |
| Opportunities | Explicit unconnected-source state; no fabricated jobs, scholarships, dates or campaigns |

Search requires 2–80 characters, the shared limit supported by all three existing
live search sources. Each live result category is bounded to ten matches; users
are told to refine broad searches. Program information remains searchable without
sign-in. Members can open existing post/group/member routes from live matches.
No new public private-record search endpoint was introduced.

## Carousel implementation

- Native `PageView` and `PageController`; default automatic interval **4 seconds**.
- Smooth 560 ms eased slide animation; manual horizontal swipe and accessible
  indicator buttons.
- Pause/resume control; pauses while touched or focused, off the Home tab,
  backgrounded, route-covered or ticker-disabled.
- Reduced motion and accessible-navigation settings disable automatic movement.
  Manual indicator changes use immediate paging when reduced motion is requested.
- Timer, page controller and lifecycle observer are cleaned up on disposal.
- CTA destinations use `HomeBannerDestination`; the Home widget maps them to
  actual existing tabs, the authenticated Help Desk form, Profile, or Programs.
- CTA layout measures the actual scaled label rather than assuming a fixed
  height. Indicators provide 48-pixel interaction targets.
- `HomeHeroBanner` supports optional heading, subtitle, CTA, asset/HTTPS image,
  crop alignment, fit, semantic description and aspect ratio.
- Poster thumbnails use square frames and `BoxFit.contain`, with CTA beside or
  below according to available space, never obscuring their typography. Generic banners can use
  `BoxFit.cover` and text overlays.
- Built-in Flutter image caching, bounded decode size, next-image pre-caching,
  loading and image-error states; no new package dependency.
- Four explicitly labelled placeholder entries remain available for future
  missing-artwork slots, but **the default application uses the supplied artwork**.

### Active artwork

| App asset | User-supplied original | Destination |
|---|---|---|
| `assets/images/home/community.jpg` | `c694a680-dae6-11f1-87e1-19f033365390_1794130462281.jpg` | Community |
| `assets/images/home/education.jpg` | `c6940a40-dae6-11f1-87e1-19f033365390_1794130462301.jpg` | Programs |
| `assets/images/home/care.jpg` | `c692aab0-dae6-11f1-87e1-19f033365390_1794130462261.jpg` | Help Desk |
| `assets/images/home/youth.jpg` | `ea8a9540-dae6-11f1-87e1-19f033365390_1794130462239.jpg` | Programs |
| `assets/images/home/together.jpg` | `774a61e0-dae7-11f1-87e1-19f033365390_1794130462024.jpg` | Community |

The five other supplied images remain untouched in `attached_assets` as
alternatives. Original uploads were PNG-encoded despite their `.jpg` filenames.
The five bundled derivatives are genuine optimized 1280×1280 JPEGs, approximately
**2 MiB combined instead of 26 MiB**, without cropping or adding campaign claims.
Original files remain unchanged.

To replace/order banners, edit `homeHeroBanners` in `lib/home/hero_banner.dart`.
Put new local files under the registered `assets/images/home/` asset directory.
For landscape artwork, set the appropriate aspect ratio and fit. Carousel
implementation changes are not necessary. Bundled artwork requires a new app
build; this is not a remotely managed campaign CMS.

## API and privacy

Added **GET `/api/community/summary`** because the existing API did not expose
aggregate community counts. It requires existing authentication and returns:

```json
{
  "accessiblePosts": "<actual nonnegative database integer>",
  "accessibleAnnouncements": "<actual nonnegative database integer>",
  "joinedGroups": "<actual nonnegative database integer>",
  "scope": "authorized_user"
}
```

The illustrated type descriptions above are not sample organization figures.
Counts use the **same shared post-access SQL predicate as the existing feed**:
published status, blocking, authorship, regional assignments and private-group
membership. Group totals include only the current member's active memberships in
active groups. Responses are `Cache-Control: private, no-store`.

These are not global membership, donation, assistance-outcome or worldwide
organization totals. No schema migration was needed. No fake records or
statistics were added.

`HomeController` loads each section independently, clears records on logout or
account switch and rejects stale in-flight responses. A failed section displays
an explicit retry state rather than silently substituting zero.

## Verification actually run

| Check | Result |
|---|---|
| Flutter package resolution | Passed; no new third-party package |
| `flutter analyze` | No issues |
| Existing and new Flutter tests | **38 passed, 0 failed** |
| Backend TypeScript check | Passed |
| Existing and updated backend tests | **34 passed, 0 failed** |
| Additional real-API actual-root capture smoke test | **1 passed, 0 failed; 8 captures** |
| Source whitespace check | Passed |
| Backend restart/logs | Running on port 3001 without startup errors |

Carousel tests cover automatic timing, manual swipe, typed CTA dispatch,
indicators/wraparound, pause/resume, touch pause/disposal, background/foreground,
off-tab behavior, ticker mode, reduced motion, accessible navigation and empty/
single-image catalogs. Responsive checks run at **320, 412 and 900** logical-pixel
widths, with enlarged text (2× full Home and 2.5× poster carousel).

The root-route test renders `OrakzaiApp`, verifies all five destinations, opens
Community and Help Desk using actual banner CTAs, verifies the Programs CTA's
scroll target and checks that the guest Submit shortcut opens Profile.
Controller tests check guest gating, independent failures and stale-response
discard after logout. Search's guest state and approved program matching are
tested. Deterministic widget/unit tests use explicitly test-only API doubles;
these are not evidence that a production API is deployed.

The backend summary integration test uses real PostgreSQL and authenticated HTTP
requests, including private announcements, published/removed records, blocking,
private groups and active/left memberships. Its fixtures are removed afterward.
Existing authentication, Community, Messaging and Help Desk regressions pass.

### Screenshot evidence

Eight images show the actual `OrakzaiApp` widget tree:
phone Home, the education slide, authorized live statistics, tablet Home,
Community, Help Desk, the existing Services catalogue and Profile sign-in.
They were rendered using Flutter's engine with real development HTTP/PostgreSQL
responses, including actual live search response shapes. No fake feed or count
adapter is used in that smoke test. The temporary verification account is removed
after capture.

**These are Flutter-rendered actual-application captures, not Android device or
emulator screenshots.** The development test account legitimately had zero
visible updates, announcements and groups; these are not worldwide totals.

No new APK/AAB build, successful device installation or Samsung compatibility
fix is claimed for this UI request. Previously downloaded APKs cannot update
themselves to include these source changes.

## Main created and modified files

New:
- `lib/home/hero_banner.dart`
- `lib/home/hero_carousel.dart`
- `lib/home/home_api.dart`
- `lib/home/home_controller.dart`
- `lib/home/home_search_screen.dart`
- `lib/home/home_sections.dart`
- `test/home_carousel_test.dart`
- `test/home_test.dart`
- Five images under `assets/images/home/`
- This report

Modified:
- `lib/screens/home_screen.dart`
- `lib/app/app_shell.dart`
- `lib/widgets/app_components.dart`
- `lib/app/app_language.dart`
- `lib/screens/profile_screen.dart` — wording only
- `lib/data/program_area.dart` — preview wording only
- `pubspec.yaml` — local asset directory
- `test/widget_test.dart` — navigation finders scoped to the navigation bar
- `backend/src/services/feed-service.ts` — authorized summary
- `backend/src/routes/community.ts` — authenticated no-store summary route
- `backend/src/tests/community.test.ts` — summary visibility/aggregate checks

## Run and test

```sh
pnpm --dir orakzai.org/backend dev
pnpm --dir orakzai.org/backend typecheck
pnpm --dir orakzai.org/backend test
cd orakzai.org
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=ORAKZAI_API_BASE_URL=https://YOUR-VERIFIED-API/api
```

`YOUR-VERIFIED-API` is a configuration placeholder, **not an invented deployed
endpoint**. Existing Android emulator debug configuration can use its local
development backend; a physical phone needs a reachable API URL. Existing release
HTTPS configuration requirements are preserved.

## Remaining requirements and boundaries

- No artwork is missing for the initial five-slide carousel. Different ordering,
  alternative posters and campaign-specific CTA destinations can be configured.
- An official opportunities source is not connected; the section explicitly says
  so instead of listing invented openings.
- Existing production API/storage/SMTP/FCM requirements are unchanged and are not
  claimed operational by this redesign.
- No Community/Messaging rebuild, Services implementation or Profile feature
  expansion was performed. No GitHub push or app publication was attempted.
