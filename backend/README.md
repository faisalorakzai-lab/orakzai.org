# ORAKZAI.ORG authentication API

This package is the first server-side authentication foundation for the Flutter app. It uses PostgreSQL, parameterized SQL, bcrypt password hashing, short-lived JWT access tokens, rotating opaque refresh tokens, email codes and server-side role/permission checks.

## Local development

From the `orakzai.org` repository root:

```sh
pnpm install
cp backend/.env.example backend/.env
pnpm --filter @orakzai/backend migrate
pnpm --filter @orakzai/backend dev
```

Set `DATABASE_URL` and a random `SESSION_SECRET` of at least 32 bytes in `backend/.env`. On Replit, use the managed development database and the existing `SESSION_SECRET`; never copy credential values into source files. `AUTH_DEV_MODE=true` returns a development-only verification/reset code in the API response and does not send email. The development code is disabled whenever `NODE_ENV=production`.

Test the local development flow:

```sh
pnpm --filter @orakzai/backend test
```

The test suite registers a uniquely named temporary account, verifies it, tests phone/email login, profile permissions, refresh rotation, logout and password reset, then removes that account. Tests require the development database to be configured.

## Flutter connection

The Android emulator default is `http://10.0.2.2:3001/api`. For a phone or release build, set the API to an HTTPS backend:

```sh
flutter run --dart-define=ORAKZAI_API_BASE_URL=https://api.example.org/api
```

The Flutter app stores tokens with Android secure storage. A release build must not use the emulator-only default URL.

## Endpoints

All routes are under `/api`.

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/auth/register` | Create an account and send an email verification code |
| `POST` | `/auth/login` | Sign in with email or E.164 phone plus password |
| `POST` | `/auth/logout` | Revoke the current session |
| `POST` | `/auth/refresh` | Rotate a refresh token and return a new token pair |
| `POST` | `/auth/forgot-password` | Request a password reset code; response is generic |
| `POST` | `/auth/reset-password` | Validate a code and set a new password |
| `POST` | `/auth/verify-email` | Verify an email using a one-time code |
| `POST` | `/auth/resend-verification` | Resend a verification code with a generic response |
| `GET` | `/users/me` | Read the signed-in user's private profile |
| `PATCH` | `/users/me` | Update only allowed profile/privacy fields |
| `GET` | `/users/me/permissions` | Read roles and permissions computed by the server |
| `POST` | `/admin/users/:userId/roles` | Assign a role with the `roles:assign` permission |
| `PATCH` | `/admin/users/:userId/member-id` | Assign a unique organization member ID with permission |
| `GET` | `/health` | Health check |

All protected routes require `Authorization: Bearer <accessToken>`. Registration accepts `fullName`, `email`, `phone`, and `password`; phone must use E.164 format such as `+923001234567`. Passwords require at least 12 characters, a letter and a number.

## Database tables

`migrations/0001_auth_foundation.sql` defines:

- `users`, `user_profiles`, and `user_sessions`
- `roles`, `permissions`, `user_roles`, and `role_permissions`
- `regions`, `districts`, `qoums`, `villages`, and `user_region_assignments`
- `verification_requests` and `audit_logs`

IDs are UUIDs. Email/phone, usernames, member IDs, role slugs and permission keys have uniqueness constraints. Refresh tokens and one-time verification/reset codes are stored only as SHA-256 hashes. Passwords use bcrypt. Profile edits cannot set roles or member IDs; those changes require separate server-side permissions.

The eight requested roles are seeded. New signups receive only `standard_member`; email verification does not claim or grant verified organizational membership. Role assignment is never exposed to the account owner. To bootstrap the first verified Super Admin in development, set `BOOTSTRAP_SUPER_ADMIN_EMAIL` for an already email-verified account and run:

```sh
pnpm --filter @orakzai/backend exec tsx src/scripts/promote-super-admin.ts
```

This bootstrap command refuses production and refuses to add a second Super Admin.

## Configuration still required for production

- `SMTP_URL` and `SMTP_FROM` for real verification and password-reset delivery. Without them, production auth email operations fail explicitly.
- A stable secret (`ACCESS_TOKEN_SECRET` or `SESSION_SECRET`, at least 32 bytes).
- An HTTPS deployment URL in `ORAKZAI_API_BASE_URL` and allowed browser origins in `CORS_ORIGINS`.
- A private image-storage provider before profile-photo upload can be offered. The current profile accepts a photo URL only.
- Real Google OAuth credentials and wallet-provider configuration before those disabled integration points can be enabled.
- An organization-controlled, verified process for assigning member IDs and elevated roles.

For a Replit-managed production database, apply development schema changes through the platform's Publish schema flow. `src/db/migrate.ts` intentionally refuses to migrate when `NODE_ENV=production`.
