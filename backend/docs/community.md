# Community and messaging implementation

This backend supplies the Flutter Community area. All `/api/community`,
`/api/messages`, `/api/media`, and `/api/moderation` routes require a verified,
active account unless a route explicitly says otherwise.

## Local setup

```sh
pnpm --filter @orakzai/backend migrate
pnpm --filter @orakzai/backend dev
flutter pub get
flutter analyze
flutter test
pnpm --filter @orakzai/backend typecheck
pnpm --filter @orakzai/backend test
```

Migrations `0002`–`0005` add community data, security rules, message moderation
status, and forwarding metadata. `src/db/migrate.ts` is development/test-only;
production schema changes must use the configured production migration process.

## REST API

All paths below are beneath `/api`; send `Authorization: Bearer <access token>`.

| Area | Routes |
| --- | --- |
| Feed | `GET /community/feed`, `GET /community/announcements`, `GET /community/regional/:regionId/feed` |
| Posts | `POST /community/posts`, `GET/PATCH/DELETE /community/posts/:postId`, `GET/POST .../:postId/comments`, `POST .../:postId/reactions`, `POST .../:postId/share`, `PUT .../:postId/bookmark`, `PUT .../:postId/announcement` |
| Groups | `GET/POST /community/groups`, `GET/PATCH /community/groups/:groupId`, `POST .../:groupId/join`, `POST .../:groupId/leave`, `GET .../:groupId/members`, `PATCH .../:groupId/members/:memberId`, `PUT .../:groupId/rules` |
| Invitations | `POST /community/groups/:groupId/invite`, `GET /community/groups/invitations`, `POST /community/invitations/:invitationId/respond` |
| Members and safety | `GET /community/members/search?q=...`, `GET /community/members/:memberId`, `GET /community/blocks`, `POST/DELETE /community/blocks/:memberId`, `PUT /community/mutes`, `DELETE /community/mutes/:targetType/:targetId`, `POST /community/reports` |
| Notifications and privacy | `GET /community/notifications`, `POST /community/notifications/:id/read`, `GET/PATCH /community/notifications/preferences`, `GET/PATCH /community/presence/settings`, `GET /community/online-members` |
| Conversations | `GET/POST /messages/conversations`, `GET /messages/conversations/:id`, `GET /messages/conversations/:id/messages`, `GET /messages/conversations/:id/search?q=...` |
| Messages | `POST /messages/conversations/:id/messages`, `POST /messages/conversations/:id/messages/:messageId/forward`, `PATCH/DELETE /messages/conversations/:id/messages/:messageId`, `POST .../:messageId/reactions`, `POST /messages/conversations/:id/read`, `POST /messages/conversations/:id/delivered` |
| Media | `POST /media/upload` (multipart field `file`), `GET /media/:id/access`, `GET /media/:id/content` |
| Moderation | `GET /moderation/reports`, `GET /moderation/reports/:id`, `POST /moderation/reports/:id/actions`, `GET /moderation/actions` |

Create/edit/delete operations enforce author, group membership, visibility,
block, moderation, and permission checks on the server. Private media access
checks the requesting account and the content or conversation that owns the
attachment; a short-lived HMAC signature is not a substitute for authentication.

## Realtime events

Socket.IO is served by the API process. Connect with
`auth: { token: <access token> }`. The server verifies the token and active
session, then authorizes conversation membership before joining a room.

Client events: `conversation:join`, `conversation:leave`, `typing:start`,
`typing:stop`, `message:delivered`, `message:read`, `presence:watch`, and
`presence:unwatch`.

Server events: `message:new`, `message:sent`, `message:receipt`,
`conversation:updated`, `notification:new`, `typing:update`, and
`presence:update`. The Flutter client reconnects and refreshes data after
reconnection. Presence is based on active sockets and each member's privacy
setting.

The current presence/socket registry is process-local. Before running multiple
API replicas, add a Socket.IO Redis adapter and shared presence storage; otherwise
cross-replica room broadcasts and online status will be incomplete.

## Storage, notifications, and release requirements

- The local private media adapter stores files under
  `backend/var/private-media` (ignored by Git). Uploads are limited to 25 MiB
  and inspected by file signature. Files are not exposed by static hosting.
- Production media storage is **not configured**. Production upload and download
  return `503 MEDIA_STORAGE_NOT_CONFIGURED`; do not enable community media in a
  public release until a private object-storage adapter, access policy, and
  malware-scanning decision are in place.
- In-app notifications are stored in PostgreSQL. FCM/APNs push delivery is not
  configured, and the app does not claim to send push notifications.
- Messages are not end-to-end encrypted. The API stores their content to provide
  delivery, search, moderation, and receipts. Do not describe this as
  end-to-end encrypted.
- Email verification requires a configured production mail provider. Do not
  enable `AUTH_DEV_MODE` outside local development/test.

## Retention

No purge runs automatically. The default
`COMMUNITY_DELETED_CONTENT_RETENTION_DAYS=0` disables cleanup. To manually
purge only old hidden/removed posts, comments, and messages, responded
invitations, read notifications, and unattached media, set a retention period
and run:

```sh
COMMUNITY_DELETED_CONTENT_RETENTION_DAYS=365 \
pnpm --filter @orakzai/backend purge-community-retention
```

For production, also set `COMMUNITY_RETENTION_PURGE_CONFIRM=true` for that
invocation. Active posts/messages, unread notifications, open reports, and
moderation history are not removed by this job. Review the organization policy
and backups before scheduling it.
