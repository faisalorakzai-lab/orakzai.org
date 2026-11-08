# ORAKZAI.ORG Community Privacy Notice — Draft

**This is a product draft for organization review, not legal advice or an
approved public policy. Complete the organization contact, jurisdiction,
retention, and user-rights sections with the organization before publishing.**

## Information the Community feature handles

The service stores account/profile information already collected by the app,
community posts and comments, group memberships and invitations, direct and
group messages, message delivery/read receipts, uploaded attachment metadata,
moderation reports/actions, notification preferences, blocks/mutes, and
presence/last-seen settings.

## How information is used and shared

Information is used to operate accounts, deliver posts and messages, maintain
group access, show unread/read state, provide in-app notifications, protect
members, and investigate reports. Post visibility and group membership control
who can see community content. Private conversations are available only to
their active participants and authorized moderation workflows.

Profile search, city, profession, skills, education, online presence, and
last-seen visibility are controlled by the corresponding account settings.
Members can block or mute other members and can report content.

## Storage and security

API access requires an active account. Private media downloads require both
authentication and content/conversation access checks. Media URLs are
short-lived. Production private object storage is not connected yet; media
upload/download is disabled in production until that is configured.

Messages are stored in readable form by the service and are **not
end-to-end encrypted**. Production transport must use HTTPS. Database backup
encryption and hosting-region details depend on the production infrastructure
and must be confirmed by the organization.

## Retention

The current retention job is disabled by default. When explicitly configured
and manually run, it removes only aged hidden/removed community content,
responded invitations, read notifications, and unattached files. Active
messages/posts, unread notifications, open reports, and moderation history are
not purged by that job. The organization must approve a retention period and
backup policy before scheduling cleanup.

## Push notifications and third parties

The current implementation stores in-app notifications. FCM/APNs push
notifications are not configured. Add the approved provider and update this
notice before enabling push delivery.

## Organization review required before publication

Add an organization privacy contact, applicable legal entity/jurisdiction,
member access/deletion request process, approved retention schedule, production
storage provider, hosting region, backup policy, and any push/email providers.
