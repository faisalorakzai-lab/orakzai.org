# Account, authentication and member profile API

The existing bearer-token authentication middleware protects every
`/api/users/me/*` endpoint. The user identifier is always taken from the
validated server-side session; clients cannot choose an account owner.

## Public capabilities

`GET /api/auth/capabilities` returns the configuration available to this
deployment: registration/email delivery, password reset, providers, account
deletion retention, legal URLs, profile-avatar storage, and optional
membership/application records. Provider flags are false unless both the
native and server-side verification paths exist. No Google, Apple, wallet,
push-notification, or membership record is simulated.

## Owner-scoped endpoints

| Method and path | Result |
| --- | --- |
| `GET /api/users/me/sessions` | Active owner sessions; excludes all credentials |
| `DELETE /api/users/me/sessions/:id` | Revokes an owner session and disconnects it |
| `POST /api/users/me/change-password` | Requires `{currentPassword,newPassword}`; revokes other sessions |
| `POST /api/users/me/delete-account` | Requires `{currentPassword,confirmation:true}` and configured retention |
| `POST /api/users/me/data-export` | Requires current password; returns a private owner-data JSON export |
| `GET /api/users/me/activity?page=N` | Paginated account audit activity |
| `GET /api/users/me/community/:kind?page=N` | Owner-only groups, posts, comments, saved posts, contributions, notifications or helpdesk requests |
| `GET/PATCH /api/users/me/notification-preferences` | Existing community notification settings |
| `GET /api/users/me/blocked-users` | Owner's blocked-user list |
| `DELETE /api/users/me/blocked-users/:id` | Removes only an owner-created block |
| `GET /api/users/me/photo` | Authenticated private PNG response, `no-store` |
| `POST /api/users/me/photo` | Raw cropped `image/png`; checked and stored in private development storage |
| `DELETE /api/users/me/photo` | Removes the owner's photo reference |
| `PATCH /api/users/me` | Existing allowlist extended with self-reported location fields |

List responses use `{items,nextPage}` and pages of 20 where pagination
applies. Account sections use live database records; an empty response is
shown as empty, not filled with example data. Posts/comments in inaccessible
private groups are filtered through the existing post-access check.

### Registration requirements

`POST /api/auth/register` now accepts `fullName,email,phone,password,country,
region,district,acceptedTerms`. Country and affirmative terms acceptance are
required. Region and district are optional self-reported profile fields and
never create regional permission grants. Registration is only advertised when
verification delivery and production legal URLs/version are configured.

### Security and production status

Wrong current-password responses use `403 PASSWORD_MISMATCH`, not session
expiry. Password, deletion and export actions are rate-limited and recheck the
current password. Avatar uploads are rate-limited, capped at 5 MiB, restricted
to structurally valid, bounded RGB/RGBA PNGs, written with private filesystem
permissions, and never served as static files. Production avatar uploads remain
unavailable until private object storage is integrated.

Account deletion immediately suspends sign-in, revokes sessions and records a
requested processing date. **This deployment has no automated erasure worker.**
The configured retention period is not evidence that final erasure ran; the
organization must approve a data-retention/exception policy and implement or
operate the actual purge process before advertising completion of deletion.

SMTP, published legal documents, production retention approval, private
S3-compatible storage, FCM, OAuth/wallet verification and production data
handling are not asserted as configured by these endpoints.
