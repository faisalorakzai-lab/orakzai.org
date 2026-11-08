# Command 05 — Help Desk and Support Management

## Scope and status

This extends the existing Flutter application and Express/PostgreSQL backend.
It does not replace authentication, Community, Messaging, Services or Profile.
The five tabs remain Home | Community | Help Desk | Services | Profile.

Production readiness is **not** implied by passing development tests. No
production signing key, deployed API, SMTP or FCM connection is fabricated.
The earlier Samsung APK installation failure remains a separate unresolved item.

## Structure

- `backend/migrations/0006_helpdesk.sql`: Help Desk tables, role/permission grants,
  notification preference and notification kinds, default routing configuration,
  and four FAQs describing actual implemented policy. No requests, staff users,
  assignments, assistance outcomes or announcements are seeded.
- `backend/migrations/0007_helpdesk_guards.sql`: status/timestamp constraints and
  foreign-key lookup indexes.
- `backend/migrations/rollback/`: manual guarded rollback scripts.
- `backend/src/routes/helpdesk.ts`: authenticated, rate-limited REST routes.
- `backend/src/services/helpdesk-core.ts`: authorization, transitions, audit and
  transactional in-app notification integration.
- `helpdesk-service.ts`: requests, statistics, tracking, assignments/preferences.
- `helpdesk-conversation.ts`: replies, read receipts, notes and history.
- `helpdesk-storage.ts`: request-authorized development file storage.
- `backend/src/tests/helpdesk.test.ts`: actual PostgreSQL/HTTP integration tests.
- `lib/helpdesk/`: authenticated API adapter and focused Flutter screens.
- `lib/screens/help_desk_screen.dart`: Help Desk home, replacing the preview.
- `lib/app/app_shell.dart`: passes the existing account controller into Help Desk;
  tab labels/order and the other screens are unchanged.

## Roles and access policy

| Role | Requests | Assignments/content | Internal notes |
|---|---|---|---|
| Standard/verified member | Own only | No | Never |
| Support Agent / existing Support Officer | Own member requests and currently assigned staff cases | No | Assigned staff cases only |
| Support Manager | Entire authorized Help Desk queue | Yes | Yes |
| Help Desk Administrator | Entire authorized Help Desk queue | Yes | Yes |
| Existing Super Admin | Entire queue through new permission grants | Yes | Yes |

User and role tables are reused. New role slugs are `helpdesk_admin`,
`support_manager`, `support_agent`; permissions are `helpdesk:manage` and
`helpdesk:agent`. The trusted existing role-assignment administration must grant
roles; registration never grants a staff role. Do not run an insecure bootstrap
endpoint or distribute administrator credentials.

An agent loses access to a previous case when reassigned. Historical assignment
does not grant continuing access. Owners cannot be assigned to their own case.
Contact details are returned to authorized staff only for the member's selected
email/phone contact preference. Choosing email/phone does not send email/call.
Unauthorized case lookups, including tracking and files, return a generic 404.
The staff-note endpoint is separate; notes never enter member detail, conversation
or public status history payloads. Help Desk messages are not community chats.

## Workflow

All eleven categories and four priorities in the command are supported.
Title: 5–160 characters; description: 20–10,000; region: 2–100.
District, Qoum and village are optional free text up to 100 characters.
Contact preference: `in_app`, `email`, `phone`.
The database generates unique `ORK-<year>-<sequence>` references. Sequence gaps
are normal after rollback/testing; references do not imply successful assistance.

Allowed status transitions:

```
submitted         -> under_review, assigned, rejected
under_review      -> assigned, in_progress, waiting_for_member, resolved, rejected
assigned          -> under_review, in_progress, waiting_for_member, resolved, rejected
in_progress       -> waiting_for_member, resolved, rejected
waiting_for_member-> in_progress, resolved, rejected
resolved          -> in_progress (within seven days), closed
rejected          -> closed
closed            -> none
```

`assigned` requires an actual current assignee. Assignment changes submitted or
under-review cases to assigned; reassignment preserves an already active status.
Members cannot directly set statuses. They can reopen their own resolved request
within seven days, not closed/rejected cases. Staff use the same reopening time
window. Staff document requests put an eligible case into Waiting for Member;
the member's next reply resumes In Progress. Start review before asking for
documents on a newly submitted unassigned case. Final cases reject new replies
and uploads until an eligible reopening.

Statistics always query the authenticated owner's records. Pending includes
submitted/under-review/assigned/waiting; In Progress is separate. Resolved includes
resolved and closed-after-resolution cases, never a rejected case merely closed.
Rejected/unresolved closed cases still count in Total; the three subsets need not
sum to Total.

Emergency Assistance is a category, **not an emergency-response promise**.
The app instructs users in immediate danger to contact local emergency services.

## REST API

Base: the existing configured API URL followed by `/helpdesk`.
Every endpoint requires the existing verified active account Bearer session.
Errors retain `{ "error": { "code": "...", "message": "..." } }`.
UUIDs, enums, lengths, strict mutation bodies and array limits are validated.
JSON body limit is 64 KiB for Help Desk; other endpoints retain their 32 KiB limit.
Per-IP limits: 180 total Help Desk requests/minute, 30 writes/minute.

| Method/path | Action |
|---|---|
| GET `/home` | Own statistics, live Help Desk capabilities, notification preference |
| GET `/metadata` | Categories, priorities, statuses and reopen window |
| GET `/notifications` | Paginated own in-app updates, filtered by current case access |
| POST `/notifications/:id/read` | Mark an authorized own Help Desk update read |
| GET `/requests` | Own paginated/searchable/filterable requests |
| POST `/requests` | Submit title/category/description/priority/geography/contactPreference |
| GET `/requests/:id` | Authorized request details and available capabilities |
| PATCH `/requests/:id` | Member reopen: `{ "action": "reopen" }` |
| GET `/track/:reference` | Authorized tracking, never public case search |
| GET `/requests/:id/messages` | Paginated private conversation |
| POST `/requests/:id/messages` | Member reply: body, optional attachmentIds |
| POST `/requests/:id/messages/read` | Explicit read acknowledgement: messageIds |
| GET/POST `/requests/:id/attachments` | Authorized list/upload (`multipart file`) |
| GET `/requests/:id/attachments/:attachmentId/content` | Authorized download, no public URL |
| GET `/requests/:id/history` | Paginated status events and assignment history |
| PATCH `/requests/:id/preferences` | Per-account case mute: `{ "muted": true }` |
| PATCH `/preferences` | Existing preference table: `{ "enabled": true }` |
| GET `/departments` | Active configured routing departments |
| GET `/admin/requests` | Manager queue / agent's currently assigned cases |
| GET `/admin/staff` | Manager-only active staff directory |
| POST `/admin/requests/:id/assign` | Manager-only staffId and departmentId |
| PATCH `/admin/requests/:id/status` | Authorized staff status and optional reason |
| GET/POST `/admin/requests/:id/notes` | Authorized staff notes; create with body |
| POST `/admin/requests/:id/reply` | Staff body, attachmentIds, requestDocuments |
| GET `/faqs`, `/announcements` | Paginated published knowledge content |
| POST `/admin/faqs`, `/admin/announcements` | Manager publish with title and body |
| POST `/admin/departments` | Manager configure department by name |

List query: `limit` (1–100, default 20), `offset` (0–100000).
Request lists also support `search`, `category`, `priority`, `status`.
Responses use `items`, `total`, `limit`, `offset`. Create/detail endpoints wrap
their record in `request`, reply in `message`, upload in `attachment`.
History also includes an independently offset/limited `assignments` array.

## Private files and notifications

The existing file signature/type validator is reused. Files are nonempty,
maximum 25 MiB, assigned random server-side storage keys, SHA-256 recorded, with
restricted directory/file permissions. Help Desk bytes live under a separate
`helpdesk/` subdirectory of the existing development media directory. They are
not community `media_objects` and cannot be linked into public posts/chats.
Download requires both request and attachment authorization and sends
`Cache-Control: private, no-store`, `Content-Disposition: attachment`, `nosniff`.
Attachments linked into a message must belong to the same request and uploader;
cross-case linking, duplicates and reusing an already linked file are rejected.

Production file access/upload fails closed with 503 until a real private storage
adapter is implemented. File signatures are **not malware scanning, complete
document parsing, or a promise that a document is safe to open**. Antivirus,
quarantine, object lifecycle/orphan cleanup, retention and production encryption/
access controls still require deployment work. Temporary device downloads are
private app-cache copies; a user can choose to open them in another app.

Submission persists the request before uploading selected files. A failed
attachment upload must be shown explicitly; the existing request is not
resubmitted and files can be retried through its Attachments screen.

Submitted/assigned/status/reply/document-request/resolved/closed events are stored
in the existing `community_notifications` table with Help Desk-specific kinds.
The existing notification preferences table gets `helpdesk_updates`; per-request
mutes are separate and owner-scoped. Transactions commit before Socket.IO
notification publication. Persisted in-app events work without claiming external
push delivery. No FCM, SMTP, production Socket.IO adapter/presence or email/call
delivery is claimed by this milestone.

## Run and verify

From the workspace:

```sh
pnpm --dir orakzai.org/backend migrate
pnpm --dir orakzai.org/backend typecheck
pnpm --dir orakzai.org/backend test
pnpm --dir orakzai.org/backend dev
cd orakzai.org
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=ORAKZAI_API_BASE_URL=http://10.0.2.2:3001/api
```

The emulator alias is development-only. A physical phone must use an explicitly
configured reachable API URL; production/release builds require the existing
explicit HTTPS API configuration. Do not invent a production endpoint.
Required environment settings remain documented in the existing backend
configuration/example files; do not copy real secret values into docs or Git.

The `Orakzai Flutter Backend` workflow runs the actual Flutter backend on 3001,
not the older preview stub API. Use the existing registration/email-verification
development flow for a temporary test member. Grant staff roles only through a
trusted administrator; never self-assign roles. Submit a request, retain its
reference, track/reply/upload, assign as staff, request documents, review history,
resolve/reopen/close, and confirm a second member cannot read any part of it.

Migrations are ordered and transactionally recorded by the existing runner.
It remains development-only. Apply production schema changes through a reviewed
production migration process with backup, not by bypassing the guard. Manual
rollback scripts refuse data-bearing cases, notifications, custom knowledge/
departments or assigned new staff roles. They are not an automatic recovery
strategy for a live database. Prefer a forward fix if users have begun using it.

Tests use temporary explicitly labelled verification accounts/requests and real
SQL/HTTP, then delete their fixtures. They do not seed organization activity.
Migration replay/rollback checks use a separate disposable database schema.
Final exact test counts, screenshots and current security findings are recorded
in the final verification report, not inferred from source existence.
