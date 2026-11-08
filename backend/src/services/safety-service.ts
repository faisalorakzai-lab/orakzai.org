import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";
import { canReadPost } from "./feed-service.js";
import { requireConversationMember } from "./message-service.js";

export type MuteTargetType = "user" | "group" | "conversation";

export async function blockUser(userId: string, blockedId: string) {
  if (userId === blockedId) {
    throw new HttpError(400, "INVALID_BLOCK", "You cannot block your own account.");
  }
  const active = await pool.query(
    `SELECT 1 FROM users WHERE id = $1 AND account_status = 'active'`,
    [blockedId],
  );
  if (!active.rowCount) throw new HttpError(404, "MEMBER_NOT_FOUND", "The member was not found.");
  await pool.query(
    `INSERT INTO user_blocks (blocker_id, blocked_id)
     VALUES ($1, $2) ON CONFLICT DO NOTHING`,
    [userId, blockedId],
  );
  return { blockedId, blocked: true };
}

export async function unblockUser(userId: string, blockedId: string) {
  await pool.query(
    `DELETE FROM user_blocks WHERE blocker_id = $1 AND blocked_id = $2`,
    [userId, blockedId],
  );
  return { blockedId, blocked: false };
}

export async function listBlockedUsers(userId: string) {
  const result = await pool.query(
    `SELECT u.id, p.full_name AS "fullName", p.username,
            b.created_at AS "blockedAt"
     FROM user_blocks b
     JOIN users u ON u.id = b.blocked_id AND u.account_status = 'active'
     JOIN user_profiles p ON p.user_id = u.id
     WHERE b.blocker_id = $1 ORDER BY b.created_at DESC LIMIT 200`,
    [userId],
  );
  return result.rows;
}

export async function searchMembers(userId: string, query: string, limit: number) {
  const escaped = query.trim().replaceAll("\\", "\\\\").replaceAll("%", "\\%").replaceAll("_", "\\_");
  if (escaped.length < 2) {
    throw new HttpError(400, "SEARCH_TOO_SHORT", "Search for at least 2 characters.");
  }
  const result = await pool.query(
    `SELECT u.id, p.full_name AS "fullName", p.username,
            p.profile_photo_url AS "profilePhotoUrl",
            CASE WHEN p.show_city_publicly THEN p.city ELSE NULL END AS city
     FROM users u
     JOIN user_profiles p ON p.user_id = u.id
     WHERE u.account_status = 'active' AND u.email_verified_at IS NOT NULL
       AND u.id <> $1 AND p.allow_profile_search = true
       AND (p.full_name ILIKE '%' || $2 || '%' OR p.username ILIKE '%' || $2 || '%')
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
            OR (b.blocker_id = u.id AND b.blocked_id = $1)
       )
     ORDER BY p.full_name LIMIT $3`,
    [userId, escaped, limit],
  );
  return result.rows;
}

export async function getMemberProfile(viewerId: string, targetId: string) {
  const result = await pool.query(
    `SELECT u.id, p.full_name AS "fullName", p.username,
            p.profile_photo_url AS "profilePhotoUrl",
            p.show_city_publicly, p.show_profession_publicly,
            p.show_skills_publicly, p.show_education_publicly,
            p.allow_profile_search, p.city, p.country, p.profession,
            p.skills, p.education, p.biography
     FROM users u
     JOIN user_profiles p ON p.user_id = u.id
     WHERE u.id = $2 AND u.account_status = 'active'
       AND u.email_verified_at IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
            OR (b.blocker_id = u.id AND b.blocked_id = $1)
       )
       AND (
         u.id = $1
         OR p.allow_profile_search = true
         OR EXISTS (
           SELECT 1 FROM group_members a
           JOIN group_members b ON b.group_id = a.group_id
           WHERE a.user_id = $1 AND a.status = 'active'
             AND b.user_id = u.id AND b.status = 'active'
         )
         OR EXISTS (
           SELECT 1 FROM conversation_members a
           JOIN conversation_members b ON b.conversation_id = a.conversation_id
           JOIN conversations c ON c.id = a.conversation_id
           WHERE a.user_id = $1 AND a.left_at IS NULL
             AND b.user_id = u.id AND b.left_at IS NULL
             AND (c.conversation_type <> 'group' OR EXISTS (
               SELECT 1 FROM group_members gm
               WHERE gm.group_id = c.group_id AND gm.user_id = $1 AND gm.status = 'active'
             ))
         )
       )`,
    [viewerId, targetId],
  );
  const member = result.rows[0];
  if (!member) throw new HttpError(404, "MEMBER_NOT_FOUND", "The member profile was not found.");
  return {
    id: member.id,
    fullName: member.fullName,
    username: member.username,
    profilePhotoUrl: member.profilePhotoUrl,
    city: member.show_city_publicly ? member.city : null,
    country: member.show_city_publicly ? member.country : null,
    profession: member.show_profession_publicly ? member.profession : null,
    skills: member.show_skills_publicly ? member.skills : [],
    education: member.show_education_publicly ? member.education : null,
    biography: member.allow_profile_search || viewerId === targetId
      ? member.biography
      : null,
  };
}

export async function muteTarget(
  userId: string,
  targetType: MuteTargetType,
  targetId: string,
  mutedUntil?: string | null,
) {
  if (targetType === "user") {
    if (targetId === userId) throw new HttpError(400, "INVALID_MUTE", "You cannot mute yourself.");
    const target = await pool.query(
      `SELECT 1 FROM users WHERE id = $1 AND account_status = 'active'`,
      [targetId],
    );
    if (!target.rowCount) throw new HttpError(404, "MEMBER_NOT_FOUND", "The member was not found.");
  } else if (targetType === "group") {
    const target = await pool.query(
      `SELECT 1 FROM group_members
       WHERE group_id = $1 AND user_id = $2 AND status = 'active'`,
      [targetId, userId],
    );
    if (!target.rowCount) throw new HttpError(404, "GROUP_NOT_FOUND", "The group was not found.");
  } else {
    await requireConversationMember(userId, targetId);
  }

  const result = await pool.query(
    `INSERT INTO user_mutes (user_id, target_type, target_id, muted_until)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (user_id, target_type, target_id)
     DO UPDATE SET muted_until = EXCLUDED.muted_until
     RETURNING target_type AS "targetType", target_id AS "targetId",
               muted_until AS "mutedUntil"`,
    [userId, targetType, targetId, mutedUntil ?? null],
  );
  if (targetType === "conversation") {
    await pool.query(
      `UPDATE conversation_members SET muted_until = $1
       WHERE user_id = $2 AND conversation_id = $3 AND left_at IS NULL`,
      [mutedUntil ?? null, userId, targetId],
    );
  }
  return { ...result.rows[0], muted: true };
}

export async function unmuteTarget(
  userId: string,
  targetType: MuteTargetType,
  targetId: string,
) {
  await pool.query(
    `DELETE FROM user_mutes
     WHERE user_id = $1 AND target_type = $2 AND target_id = $3`,
    [userId, targetType, targetId],
  );
  if (targetType === "conversation") {
    await pool.query(
      `UPDATE conversation_members SET muted_until = NULL
       WHERE user_id = $1 AND conversation_id = $2 AND left_at IS NULL`,
      [userId, targetId],
    );
  }
  return { targetType, targetId, muted: false };
}

const preferenceKeys = [
  "privateMessages",
  "groupMessages",
  "groupInvitations",
  "commentsAndReplies",
  "postReactions",
  "announcements",
  "moderatorActions",
] as const;

type NotificationPreferences = Record<(typeof preferenceKeys)[number], boolean>;

export async function getNotificationPreferences(userId: string) {
  await pool.query(
    `INSERT INTO notification_preferences (user_id) VALUES ($1)
     ON CONFLICT (user_id) DO NOTHING`,
    [userId],
  );
  const result = await pool.query(
    `SELECT private_messages AS "privateMessages",
            group_messages AS "groupMessages",
            group_invitations AS "groupInvitations",
            comments_and_replies AS "commentsAndReplies",
            post_reactions AS "postReactions",
            announcements, moderator_actions AS "moderatorActions"
     FROM notification_preferences WHERE user_id = $1`,
    [userId],
  );
  return result.rows[0];
}

export async function updateNotificationPreferences(
  userId: string,
  input: Partial<NotificationPreferences>,
) {
  const fields: Record<keyof NotificationPreferences, string> = {
    privateMessages: "private_messages",
    groupMessages: "group_messages",
    groupInvitations: "group_invitations",
    commentsAndReplies: "comments_and_replies",
    postReactions: "post_reactions",
    announcements: "announcements",
    moderatorActions: "moderator_actions",
  };
  const keys = preferenceKeys.filter((key) => input[key] !== undefined);
  if (!keys.length) throw new HttpError(400, "EMPTY_PREFERENCES", "Change at least one notification setting.");
  const columns = keys.map((key) => fields[key]);
  const values = keys.map((key) => input[key]);
  const assignments = columns.map((column, index) => `${column} = $${index + 2}`).join(", ");
  await pool.query(
    `INSERT INTO notification_preferences (user_id)
     VALUES ($1) ON CONFLICT (user_id) DO NOTHING`,
    [userId],
  );
  await pool.query(
    `UPDATE notification_preferences
     SET ${assignments}, updated_at = now()
     WHERE user_id = $1`,
    [userId, ...values],
  );
  return getNotificationPreferences(userId);
}

export async function updatePresenceSettings(
  userId: string,
  input: { showOnlineStatus?: boolean; shareLastSeen?: boolean },
) {
  await pool.query(
    `INSERT INTO user_presence (user_id) VALUES ($1)
     ON CONFLICT (user_id) DO NOTHING`,
    [userId],
  );
  if (input.showOnlineStatus === undefined && input.shareLastSeen === undefined) {
    throw new HttpError(400, "EMPTY_PRESENCE_SETTINGS", "Change at least one presence setting.");
  }
  const showOnlineStatus = input.showOnlineStatus ?? null;
  const shareLastSeen = input.shareLastSeen ?? null;
  const result = await pool.query(
    `UPDATE user_presence
     SET show_online_status = COALESCE($2, show_online_status),
         share_last_seen = COALESCE($3, share_last_seen),
         updated_at = now()
     WHERE user_id = $1
     RETURNING show_online_status AS "showOnlineStatus",
               share_last_seen AS "shareLastSeen",
               last_seen_at AS "lastSeenAt"`,
    [userId, showOnlineStatus, shareLastSeen],
  );
  return result.rows[0];
}

export async function getPresenceSettings(userId: string) {
  await pool.query(
    `INSERT INTO user_presence (user_id) VALUES ($1)
     ON CONFLICT (user_id) DO NOTHING`,
    [userId],
  );
  const result = await pool.query(
    `SELECT show_online_status AS "showOnlineStatus",
            share_last_seen AS "shareLastSeen",
            last_seen_at AS "lastSeenAt"
     FROM user_presence WHERE user_id = $1`,
    [userId],
  );
  return result.rows[0];
}

export async function createContentReport(input: {
  reporterId: string;
  targetType: "post" | "comment" | "message" | "group" | "user";
  targetId: string;
  category: string;
  details: string;
}) {
  let targetOwnerId: string | undefined;
  if (input.targetType === "post") {
    if (!(await canReadPost(input.reporterId, input.targetId))) {
      throw new HttpError(404, "CONTENT_NOT_FOUND", "The reported content was not found.");
    }
    const post = await pool.query("SELECT author_id FROM community_posts WHERE id = $1", [input.targetId]);
    targetOwnerId = post.rows[0]?.author_id;
  } else if (input.targetType === "comment") {
    const comment = await pool.query(
      `SELECT c.author_id, c.post_id
       FROM post_comments c WHERE c.id = $1 AND c.status = 'published'`,
      [input.targetId],
    );
    if (!comment.rowCount || !(await canReadPost(input.reporterId, comment.rows[0].post_id))) {
      throw new HttpError(404, "CONTENT_NOT_FOUND", "The reported content was not found.");
    }
    targetOwnerId = comment.rows[0].author_id;
  } else if (input.targetType === "message") {
    const message = await pool.query(
      `SELECT m.sender_id, m.conversation_id
       FROM messages m WHERE m.id = $1 AND m.deleted_at IS NULL`,
      [input.targetId],
    );
    if (!message.rowCount) throw new HttpError(404, "CONTENT_NOT_FOUND", "The reported content was not found.");
    await requireConversationMember(input.reporterId, message.rows[0].conversation_id);
    targetOwnerId = message.rows[0].sender_id;
  } else if (input.targetType === "group") {
    const group = await pool.query(
      `SELECT id FROM community_groups WHERE id = $1 AND status = 'active'
       AND (visibility = 'public' OR EXISTS (
         SELECT 1 FROM group_members gm WHERE gm.group_id = community_groups.id
           AND gm.user_id = $2 AND gm.status = 'active'
       ))`,
      [input.targetId, input.reporterId],
    );
    if (!group.rowCount) throw new HttpError(404, "CONTENT_NOT_FOUND", "The reported content was not found.");
  } else {
    const target = await pool.query(
      `SELECT id FROM users
       WHERE id = $1 AND account_status = 'active' AND id <> $2`,
      [input.targetId, input.reporterId],
    );
    if (!target.rowCount) throw new HttpError(404, "MEMBER_NOT_FOUND", "The reported member was not found.");
    targetOwnerId = input.targetId;
  }
  if (targetOwnerId === input.reporterId) {
    throw new HttpError(400, "SELF_REPORT", "You cannot report your own content.");
  }
  try {
    const result = await pool.query(
      `INSERT INTO content_reports (reporter_id, target_type, target_id, category, details)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, status, created_at AS "createdAt"`,
      [input.reporterId, input.targetType, input.targetId, input.category, input.details.trim()],
    );
    return result.rows[0];
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "23505") {
      throw new HttpError(409, "REPORT_ALREADY_EXISTS", "You have already reported this content.");
    }
    throw error;
  }
}

export async function listNotifications(userId: string, limit: number) {
  const result = await pool.query(
    `SELECT n.id, n.actor_id AS "actorId", p.full_name AS "actorName",
            n.kind, n.entity_type AS "entityType", n.entity_id AS "entityId",
            n.read_at AS "readAt", n.created_at AS "createdAt"
     FROM community_notifications n
     LEFT JOIN user_profiles p ON p.user_id = n.actor_id
     WHERE n.user_id = $1 ORDER BY n.created_at DESC LIMIT $2`,
    [userId, limit],
  );
  return result.rows;
}

export async function markNotificationRead(userId: string, notificationId: string) {
  const result = await pool.query(
    `UPDATE community_notifications
     SET read_at = COALESCE(read_at, now())
     WHERE id = $1 AND user_id = $2
     RETURNING id, read_at AS "readAt"`,
    [notificationId, userId],
  );
  if (!result.rowCount) throw new HttpError(404, "NOTIFICATION_NOT_FOUND", "The notification was not found.");
  return result.rows[0];
}

export function notificationPreferenceKeys() {
  return preferenceKeys;
}
