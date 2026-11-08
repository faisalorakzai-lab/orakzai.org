# Command 05 verification report

## Delivered implementation

Help Desk now uses the existing authenticated Flutter application and PostgreSQL/
Express backend. The preview-only form is replaced. Home, Community, Help Desk,
Services and Profile tabs keep their original names/order. Services development
and Community/Messaging reconstruction were not started.

| Area | Implementation and evidence |
|---|---|
| Dashboard | Real owner-scoped totals, pending/in-progress/resolved counts; role-aware staff entry and in-app update inbox |
| Submission | All eleven categories, four priorities, requested geography/contact fields, unique DB reference, backend validation |
| Supporting files | Form selection, explicit partial-upload failure/retry, private file list/download, same-request message linking |
| Tracking | Own requests, title/reference search, category/status/priority filters, authorized reference lookup |
| Conversation | Member/staff replies, timestamps, paginated messages, attachment links, explicit read acknowledgement |
| Staff queue | Real queue, agent-assignment restrictions, manager assignment/reassignment, status/reason changes |
| Privacy | Owner/manager/current-agent authorization, no member internal-note payloads, preferred contact only |
| History | Status transitions and assignment records with timestamps/responsible users; separate security audit events |
| Policy | Valid status graph; seven-day resolved-request reopening, terminal reply/upload restrictions |
| Knowledge | Published FAQ and announcement lists; manager publication and department configuration |
| Notifications | Seven persisted Help Desk event kinds, existing preference table, own-request mutes, private inbox/read action |
| Database | Eleven support tables, UUID/FK/check/unique constraints, indexes and DB sequence references |
| Flutter | All fourteen requested screens reachable through the Help Desk workflow, plus private notifications |

The four seeded FAQs describe actual system behavior, and General Support is
default routing configuration. No applications, assistance outcomes, members,
staff accounts, announcements or case-status updates are seeded as organization
activity.

## Exact automated checks actually run

Final coherent verification run, 8 November 2026:

| Check | Result |
|---|---|
| Backend TypeScript `typecheck` | Passed |
| Backend Vitest suites | **33 passed, 0 failed, 4 files** |
| Help Desk integration cases within that total | **22 passed** |
| Existing backend regression cases within that total | **11 passed** |
| Flutter dependency resolution | Passed; existing locked versions retained |
| Flutter analysis | **No issues found** |
| Flutter test suite | **12 passed, 0 failed** |
| Additional live-API Flutter rendering/submission smoke check | **1 passed, 0 failed; five screen captures** |
| Development migration application | Passed through `0007_helpdesk_guards` |
| Fresh migration replay | Passed in an isolated disposable PostgreSQL schema |
| Guard rollback/reapply + base rollback | Passed in that isolated schema |
| Destructive rollback refusal with existing records | Passed; actual support records preserved |
| Changed source whitespace check | Passed |

The initial Flutter run found an off-screen test tap, not a failed backend save.
The test now waits for the scroll/layout frame before tapping; the complete
Flutter suite subsequently passed. Live rendering also found and fixed an FAQ
ExpansionTile intrinsic-height overflow and a request-detail geography field
mismatch. Both now have focused regression tests, and the live submission/
details capture asserts the location returned by the real API. Earlier preliminary counts are superseded by
the final counts above.

The integration tests execute real HTTP handlers and PostgreSQL queries using
temporary explicitly labelled test users and requests, then remove them. Flutter
widget tests use test-only API doubles to verify UI states; those are not used as
evidence of production connectivity or real organization activity.

Covered scenarios: request validation/submission, concurrent unique references,
own statistics, authenticated tracking, unauthorized ID/reference access,
pagination/filtering, manager assignment, role escalation rejection, invalid
assignee rejection, status graph, internal-note privacy, document requests,
member/staff replies, read status, private PDF/image bytes, unsupported/empty/
oversized files, unauthorized downloads, cross-request file linking, notification
preferences and mutes, former-agent revocation, reopening expiry, closed replies,
audit/status/assignment history, knowledge publication, department configuration,
private notification read ownership, constraints/indexes and rollback safety.

## Security results

All three requested scanner types ran successfully. Results are workspace-wide,
not a production penetration test or a Flutter/Dart security certification.

### Dependencies

**0 critical, 1 high, 2 moderate**, unchanged legacy/shared-workspace findings:

- **High:** root-workspace Zod 3.25.76, `GHSA-mrhx-c7xc-m3w5`. Paths include
  shared `api-zod`, `lib/db`/`drizzle-zod`, the mockup sandbox and older Expo app.
  The actual Flutter backend already uses **Zod 4.6.6**.
- **Moderate:** Glob 13.0.7, `GHSA-3g3m-2fjr-6pw4`, under the older Expo CLI/
  fingerprint tooling. Requires a tested major upgrade to 14.0.2+.
- **Moderate:** Minimatch 10.2.6, `GHSA-g3hv-75wg-m249`, in that tooling chain.
  Requires a tested major upgrade to 11.0.1+.

These unrelated dependency graphs were not blindly upgraded or replaced during
Help Desk work. Existing task #8 addresses launch dependency risk. Exact prior
paths/triage remain in `dependency-security-command04.md`.

### Static analysis

**3 HIGH flags**, all pre-existing; no new Help Desk file flagged:

- Two file-path flags in `artifacts/orakzai-app/server/serve.js` (77 and 121).
  Platform allow-listing and path checks exist, but canonical/symlink containment
  hardening remains unresolved in that older server.
- The bcrypt flag in `backend/src/services/auth-service.ts` is the non-account
  dummy password comparison used for timing equalization, not a live secret.
  It remains visible rather than being suppressed to claim a clean scan.

Privacy/dataflow scan: **0 findings**. This does not prove all possible privacy
or security issues are absent. No production credential was fabricated.

## Missing production integrations and known limitations

1. **Private object storage:** Help Desk uses the documented restricted local
   development adapter. Production file operations return 503 until a real
   private provider is implemented and verified. Existing private-storage work
   now explicitly includes Help Desk case authorization.
2. **Malware/retention:** MIME signatures and size checks are not antivirus or
   complete file-format safety analysis. Quarantine, malware scanning, object
   lifecycle/orphan cleanup and an approved support-data retention policy are
   needed for production.
3. **Production API/database:** No deployed HTTPS API endpoint or production DB
   migration was invented or asserted. Development schema/tests are verified;
   production backup/schema verification and a reviewed migration remain needed.
4. **SMTP:** Real verification/reset email delivery remains unverified. Selecting
   an email/phone contact preference does not itself send email or make a call.
5. **FCM:** Push is not claimed. Stored in-app notifications and existing local
   Socket.IO publication are separate from external push delivery.
6. **Multi-instance realtime:** A production shared Socket.IO adapter, distributed
   presence and retention jobs remain deployment work. This milestone does not
   change ordinary community messaging.
7. **Read semantics:** Request-message read acknowledgements describe a loaded
   conversation page, not proof each off-screen message was read by a human.
8. **Staff selection:** The active staff dropdown currently uses a bounded
   directory of up to 500 staff; request/message/history/content lists paginate.
9. **Device/release status:** A real universal **debug** APK was generated, with
   ARM32, ARM64 and x86_64 libraries, minimum Android 7/API 24. ZIP validation and
   APK v2/v3 signatures passed. This is not a Play Store-signed release or AAB.
   The previous Samsung installation failure is not assumed resolved merely
   because an APK builds or another device accepts it.

The Android 11 software emulator booted, but its APK installation exceeded the
180-second limit. **Installation and launch are unverified**, not passed. No
native device screenshot or all-phone compatibility claim is made.

Five screenshots were produced by Flutter's renderer using the actual production
screen widgets, real development HTTP requests and real PostgreSQL responses:
Home, Submit Request, Request Details, Staff Dashboard, FAQs. These are
**Flutter-rendered verification captures, not Android device screenshots**.
The smoke check submitted a temporary request through the actual Flutter form,
confirmed one persisted request and its generated reference, and verified that
the saved region appears in Request Details. Home shows zero before submission;
the staff queue shows one after submission. Verification data is explicitly
labelled and removed afterward; it is not seeded organization activity.

## Files, API and run instructions

See `helpdesk-command05.md` for the project tree, role matrix, transition graph,
complete REST table, file/privacy behavior and exact commands.

The actual Flutter backend is available in the configured
`Orakzai Flutter Backend` workflow on port 3001. The older preview stub API is not
the Flutter authentication/Help Desk backend.

For a physical phone, provide a reachable API URL. The debug emulator alias
`10.0.2.2:3001` is not reachable from a physical phone. Release builds retain the
existing explicit HTTPS `ORAKZAI_API_BASE_URL` requirement. No testing URL is
presented as a production API.
