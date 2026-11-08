import type { PoolClient } from "pg";

import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";

function readCursor(cursor?: string) {
  if (!cursor) return null;
  try {
    const value = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as {
      createdAt?: unknown;
      id?: unknown;
    };
    if (
      typeof value.createdAt === "string" &&
      !Number.isNaN(Date.parse(value.createdAt)) &&
      typeof value.id === "string" &&
      /^[0-9a-f-]{36}$/i.test(value.id)
    ) {
      return { createdAt: value.createdAt, id: value.id };
    }
  } catch {
    // Invalid cursor strings are rejected below and never enter SQL.
  }
  throw new HttpError(400, "INVALID_CURSOR", "The page cursor is invalid.");
}

function makeCursor(createdAt: Date | string, id: string) {
  return Buffer.from(JSON.stringify({ createdAt, id })).toString("base64url");
}

function escapeLike(value: string) {
  return value.replaceAll("\\", "\\\\").replaceAll("%", "\\%").replaceAll("_", "\\_");
}

async function withTransaction<T>(work: (client: PoolClient) => Promise<T>) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const value = await work(client);
    await client.query("COMMIT");
    return value;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function requireConversationMember(
  userId: string,
  conversationId: string,
) {
  const result = await pool.query(
    `SELECT c.id, c.conversation_type AS "conversationType",
            c.group_id AS "groupId", cm.last_read_at AS "lastReadAt"
     FROM conversations c
     JOIN conversation_members cm
       ON cm.conversation_id = c.id AND cm.user_id = $1 AND cm.left_at IS NULL
     WHERE c.id = $2
       AND (
         c.conversation_type = 'direct'
         OR EXISTS (
           SELECT 1 FROM group_members gm
           WHERE gm.group_id = c.group_id AND gm.user_id = $1 AND gm.status = 'active'
         )
       )
       AND (
         c.conversation_type <> 'direct'
         OR NOT EXISTS (
           SELECT 1 FROM conversation_members other_member
           JOIN user_blocks b
             ON (b.blocker_id = $1 AND b.blocked_id = other_member.user_id)
             OR (b.blocker_id = other_member.user_id AND b.blocked_id = $1)
           WHERE other_member.conversation_id = c.id
             AND other_member.user_id <> $1
         )
       )
     LIMIT 1`,
    [userId, conversationId],
  );
  if (!result.rowCount) {
    throw new HttpError(404, "CONVERSATION_NOT_FOUND", "The conversation was not found.");
  }
  return result.rows[0] as {
    id: string;
    conversationType: "direct" | "group";
    groupId: string | null;
    lastReadAt: string | null;
  };
}

export async function listConversations(userId: string, search?: string) {
  const result = await pool.query(
    `SELECT c.id, c.conversation_type AS "conversationType",
            c.group_id AS "groupId", g.name AS "groupName",
            c.last_message_at AS "lastMessageAt",
            cm.last_read_at AS "lastReadAt",
            cm.muted_until AS "mutedUntil",
            (
              SELECT count(*)::int FROM messages m
              WHERE m.conversation_id = c.id
                AND m.sender_id <> $1
                AND m.deleted_at IS NULL
                AND m.moderation_status = 'visible'
                AND m.created_at > COALESCE(cm.last_read_at, cm.joined_at)
                AND NOT EXISTS (
                  SELECT 1 FROM user_blocks b
                  WHERE (b.blocker_id = $1 AND b.blocked_id = m.sender_id)
                     OR (b.blocker_id = m.sender_id AND b.blocked_id = $1)
                )
            ) AS "unreadCount",
            (
              SELECT m.body FROM messages m
              WHERE m.conversation_id = c.id AND m.deleted_at IS NULL
                AND m.moderation_status = 'visible'
                AND NOT EXISTS (
                  SELECT 1 FROM user_blocks b
                  WHERE (b.blocker_id = $1 AND b.blocked_id = m.sender_id)
                     OR (b.blocker_id = m.sender_id AND b.blocked_id = $1)
                )
              ORDER BY m.created_at DESC, m.id DESC LIMIT 1
            ) AS "lastMessage",
            (
              SELECT json_build_object(
                'id', u.id, 'fullName', p.full_name,
                'username', p.username, 'profilePhotoUrl', p.profile_photo_url
              )
              FROM conversation_members other_member
              JOIN users u ON u.id = other_member.user_id AND u.account_status = 'active'
              JOIN user_profiles p ON p.user_id = u.id
              WHERE other_member.conversation_id = c.id
                AND other_member.user_id <> $1
                AND other_member.left_at IS NULL
              ORDER BY other_member.joined_at LIMIT 1
            ) AS "otherMember"
     FROM conversations c
     JOIN conversation_members cm
       ON cm.conversation_id = c.id AND cm.user_id = $1 AND cm.left_at IS NULL
     LEFT JOIN community_groups g ON g.id = c.group_id
     WHERE (
       c.conversation_type = 'direct'
       OR EXISTS (
         SELECT 1 FROM group_members gm
         WHERE gm.group_id = c.group_id AND gm.user_id = $1 AND gm.status = 'active'
       )
     )
       AND (
         c.conversation_type <> 'direct'
         OR NOT EXISTS (
           SELECT 1 FROM conversation_members other_member
           JOIN user_blocks b
             ON (b.blocker_id = $1 AND b.blocked_id = other_member.user_id)
             OR (b.blocker_id = other_member.user_id AND b.blocked_id = $1)
           WHERE other_member.conversation_id = c.id AND other_member.user_id <> $1
         )
       )
       AND (
         $2::text IS NULL
         OR COALESCE(g.name, '') ILIKE '%' || $2 || '%'
         OR EXISTS (
           SELECT 1
           FROM conversation_members search_member
           JOIN user_profiles search_profile ON search_profile.user_id = search_member.user_id
           WHERE search_member.conversation_id = c.id
             AND search_member.user_id <> $1
             AND search_member.left_at IS NULL
             AND search_profile.full_name ILIKE '%' || $2 || '%'
         )
         OR EXISTS (
           SELECT 1 FROM messages search_message
           WHERE search_message.conversation_id = c.id
             AND search_message.deleted_at IS NULL
             AND search_message.moderation_status = 'visible'
             AND search_message.body ILIKE '%' || $2 || '%'
             AND NOT EXISTS (
               SELECT 1 FROM user_blocks b
               WHERE (b.blocker_id = $1 AND b.blocked_id = search_message.sender_id)
                  OR (b.blocker_id = search_message.sender_id AND b.blocked_id = $1)
             )
         )
       )
     ORDER BY c.last_message_at DESC NULLS LAST, c.created_at DESC
     LIMIT 200`,
    [userId, search?.trim() || null],
  );
  return result.rows;
}

export async function createDirectConversation(userId: string, otherUserId: string) {
  if (userId === otherUserId) {
    throw new HttpError(400, "INVALID_RECIPIENT", "You cannot start a private chat with yourself.");
  }
  return withTransaction(async (client) => {
    const sortedIds = [userId, otherUserId].sort();
    await client.query(
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      [`direct:${sortedIds[0]}:${sortedIds[1]}`],
    );
    const target = await client.query(
      `SELECT u.id FROM users u
       WHERE u.id = $1 AND u.account_status = 'active'
         AND u.email_verified_at IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $2 AND b.blocked_id = u.id)
              OR (b.blocker_id = u.id AND b.blocked_id = $2)
         )`,
      [otherUserId, userId],
    );
    if (!target.rowCount) {
      throw new HttpError(404, "MEMBER_UNAVAILABLE", "This member is unavailable for private messaging.");
    }
    const existing = await client.query(
      `SELECT c.id
       FROM conversations c
       JOIN conversation_members a
         ON a.conversation_id = c.id AND a.user_id = $1 AND a.left_at IS NULL
       JOIN conversation_members b
         ON b.conversation_id = c.id AND b.user_id = $2 AND b.left_at IS NULL
       WHERE c.conversation_type = 'direct'
         AND (SELECT count(*) FROM conversation_members cm
              WHERE cm.conversation_id = c.id AND cm.left_at IS NULL) = 2
       LIMIT 1`,
      [userId, otherUserId],
    );
    if (existing.rowCount) return { id: existing.rows[0].id, conversationType: "direct" };
    const conversation = await client.query(
      `INSERT INTO conversations (conversation_type, created_by)
       VALUES ('direct', $1) RETURNING id`,
      [userId],
    );
    await client.query(
      `INSERT INTO conversation_members (conversation_id, user_id)
       VALUES ($1, $2), ($1, $3)`,
      [conversation.rows[0].id, userId, otherUserId],
    );
    await client.query(
      `INSERT INTO notification_preferences (user_id)
       VALUES ($1), ($2) ON CONFLICT (user_id) DO NOTHING`,
      [userId, otherUserId],
    );
    return { id: conversation.rows[0].id, conversationType: "direct" };
  });
}

export async function getConversation(userId: string, conversationId: string) {
  await requireConversationMember(userId, conversationId);
  const result = await pool.query(
    `SELECT c.id, c.conversation_type AS "conversationType",
            c.group_id AS "groupId", g.name AS "groupName",
            g.visibility AS "groupVisibility",
            cm.last_read_at AS "lastReadAt",
            cm.muted_until AS "mutedUntil",
            COALESCE((
              SELECT json_agg(json_build_object(
                'id', u.id, 'fullName', p.full_name, 'username', p.username,
                'profilePhotoUrl', p.profile_photo_url, 'role', gm.role
              ) ORDER BY gm.joined_at)
              FROM conversation_members member
              JOIN users u ON u.id = member.user_id AND u.account_status = 'active'
              JOIN user_profiles p ON p.user_id = u.id
              LEFT JOIN group_members gm
                ON gm.group_id = c.group_id AND gm.user_id = u.id
              WHERE member.conversation_id = c.id
                AND member.left_at IS NULL
                AND NOT EXISTS (
                  SELECT 1 FROM user_blocks b
                  WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
                     OR (b.blocker_id = u.id AND b.blocked_id = $1)
                )
            ), '[]'::json) AS members
     FROM conversations c
     JOIN conversation_members cm
       ON cm.conversation_id = c.id AND cm.user_id = $1 AND cm.left_at IS NULL
     LEFT JOIN community_groups g ON g.id = c.group_id
     WHERE c.id = $2`,
    [userId, conversationId],
  );
  if (!result.rowCount) {
    throw new HttpError(404, "CONVERSATION_NOT_FOUND", "The conversation was not found.");
  }
  return result.rows[0];
}

export async function listMessages(
  userId: string,
  conversationId: string,
  limit: number,
  cursor?: string,
) {
  await requireConversationMember(userId, conversationId);
  const page = readCursor(cursor);
  const result = await pool.query(
    `SELECT m.id, m.conversation_id AS "conversationId",
            m.sender_id AS "senderId", p.full_name AS "senderName",
            p.profile_photo_url AS "senderPhotoUrl",
            CASE WHEN m.deleted_at IS NOT NULL THEN '' ELSE m.body END AS body,
            m.reply_to_id AS "replyToId",
            m.forwarded_from_message_id AS "forwardedFromMessageId",
            (SELECT CASE WHEN reply.deleted_at IS NOT NULL THEN '[Message deleted]' ELSE reply.body END
             FROM messages reply WHERE reply.id = m.reply_to_id) AS "replyToPreview",
            m.edited_at AS "editedAt", m.deleted_at AS "deletedAt",
            m.created_at AS "createdAt",
            CASE WHEN m.sender_id = $1 THEN
              CASE
                WHEN EXISTS (
                  SELECT 1 FROM message_read_receipts rr
                  WHERE rr.message_id = m.id AND rr.user_id <> $1 AND rr.read_at IS NOT NULL
                ) THEN 'read'
                WHEN EXISTS (
                  SELECT 1 FROM message_read_receipts rr
                  WHERE rr.message_id = m.id AND rr.user_id <> $1 AND rr.delivered_at IS NOT NULL
                ) THEN 'delivered'
                ELSE 'sent'
              END
            ELSE NULL END AS status,
            COALESCE((
              SELECT json_agg(json_build_object(
                'id', media.id, 'name', media.original_name,
                'contentType', media.content_type, 'byteSize', media.byte_size
              ) ORDER BY mm.position)
              FROM message_media mm
              JOIN media_objects media ON media.id = mm.media_id
              WHERE mm.message_id = m.id
            ), '[]'::json) AS media,
            COALESCE((
              SELECT json_agg(json_build_object(
                'reaction', r.reaction, 'count', r.reaction_count,
                'mine', r.mine
              ) ORDER BY r.reaction)
              FROM (
                SELECT mr.reaction, count(*)::int AS reaction_count,
                       bool_or(mr.user_id = $1) AS mine
                FROM message_reactions mr
                WHERE mr.message_id = m.id GROUP BY mr.reaction
              ) r
            ), '[]'::json) AS reactions,
            EXISTS (
              SELECT 1 FROM message_read_receipts rr
              WHERE rr.message_id = m.id AND rr.user_id = $1
                AND rr.delivered_at IS NOT NULL
            ) AS "deliveredToMe",
            EXISTS (
              SELECT 1 FROM message_read_receipts rr
              WHERE rr.message_id = m.id AND rr.user_id = $1
                AND rr.read_at IS NOT NULL
            ) AS "readByMe"
     FROM messages m
     JOIN user_profiles p ON p.user_id = m.sender_id
     WHERE m.conversation_id = $2
       AND (
         m.moderation_status = 'visible'
         OR EXISTS (
           SELECT 1 FROM user_roles ur
           JOIN role_permissions rp ON rp.role_id = ur.role_id
           JOIN permissions permission ON permission.id = rp.permission_id
           WHERE ur.user_id = $1 AND permission.key = 'content:moderate'
         )
       )
       AND ($3::timestamptz IS NULL OR (m.created_at, m.id) < ($3, $4::uuid))
       AND (
         m.deleted_at IS NULL
         OR m.sender_id = $1
         OR EXISTS (
           SELECT 1 FROM user_roles ur
           JOIN role_permissions rp ON rp.role_id = ur.role_id
           JOIN permissions permission ON permission.id = rp.permission_id
           WHERE ur.user_id = $1 AND permission.key = 'content:moderate'
         )
       )
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $1 AND b.blocked_id = m.sender_id)
            OR (b.blocker_id = m.sender_id AND b.blocked_id = $1)
       )
     ORDER BY m.created_at DESC, m.id DESC
     LIMIT $5`,
    [userId, conversationId, page?.createdAt ?? null, page?.id ?? null, limit + 1],
  );
  const hasMore = result.rows.length > limit;
  const messages = hasMore ? result.rows.slice(0, limit) : result.rows;
  return {
    messages: messages.reverse(),
    nextCursor:
      hasMore && messages.length
        ? makeCursor(messages[0].createdAt, messages[0].id)
        : null,
  };
}

export async function sendMessage(
  userId: string,
  conversationId: string,
  input: { body: string; replyToId?: string; mediaIds?: string[]; clientNonce?: string },
) {
  const body = input.body.trim();
  const mediaIds = [...new Set(input.mediaIds ?? [])];
  if (!body && !mediaIds.length) {
    throw new HttpError(400, "EMPTY_MESSAGE", "Write a message or attach a file.");
  }
  if (mediaIds.length > 10) {
    throw new HttpError(400, "TOO_MANY_MEDIA", "A message can include up to 10 files.");
  }
  return withTransaction(async (client) => {
    const access = await client.query(
      `SELECT c.conversation_type AS "conversationType"
       FROM conversations c
       JOIN conversation_members cm
         ON cm.conversation_id = c.id AND cm.user_id = $1 AND cm.left_at IS NULL
       WHERE c.id = $2
         AND (
           c.conversation_type = 'direct'
           OR EXISTS (
             SELECT 1 FROM group_members gm
             WHERE gm.group_id = c.group_id AND gm.user_id = $1 AND gm.status = 'active'
           )
         )
         AND (
           c.conversation_type <> 'direct'
           OR NOT EXISTS (
             SELECT 1 FROM conversation_members other_member
             JOIN user_blocks b
               ON (b.blocker_id = $1 AND b.blocked_id = other_member.user_id)
               OR (b.blocker_id = other_member.user_id AND b.blocked_id = $1)
             WHERE other_member.conversation_id = c.id
               AND other_member.user_id <> $1
           )
         )
       FOR UPDATE OF c`,
      [userId, conversationId],
    );
    if (!access.rowCount) {
      throw new HttpError(404, "CONVERSATION_NOT_FOUND", "The conversation was not found.");
    }
    if (access.rows[0].conversationType === "direct") {
      const blocked = await client.query(
        `SELECT 1
         FROM conversation_members other_member
         WHERE other_member.conversation_id = $1 AND other_member.user_id <> $2
           AND EXISTS (
             SELECT 1 FROM user_blocks b
             WHERE (b.blocker_id = $2 AND b.blocked_id = other_member.user_id)
                OR (b.blocker_id = other_member.user_id AND b.blocked_id = $2)
           )`,
        [conversationId, userId],
      );
      if (blocked.rowCount) throw new HttpError(403, "DIRECT_MESSAGE_BLOCKED", "This conversation is unavailable.");
    }
    if (input.replyToId) {
      const parent = await client.query(
        `SELECT 1 FROM messages WHERE id = $1 AND conversation_id = $2`,
        [input.replyToId, conversationId],
      );
      if (!parent.rowCount) throw new HttpError(404, "REPLY_NOT_FOUND", "The message being replied to was not found.");
    }
    if (mediaIds.length) {
      const owned = await client.query(
        `SELECT id FROM media_objects WHERE owner_id = $1 AND id = ANY($2::uuid[])`,
        [userId, mediaIds],
      );
      if (owned.rowCount !== mediaIds.length) {
        throw new HttpError(403, "MEDIA_ACCESS_DENIED", "One or more files are unavailable.");
      }
    }
    const inserted = await client.query(
      `INSERT INTO messages (conversation_id, sender_id, body, reply_to_id, client_nonce)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (conversation_id, sender_id, client_nonce) DO NOTHING
       RETURNING id, created_at AS "createdAt"`,
      [
        conversationId,
        userId,
        body,
        input.replyToId ?? null,
        input.clientNonce ?? null,
      ],
    );
    let message = inserted.rows[0];
    if (!message && input.clientNonce) {
      const existing = await client.query(
        `SELECT id, created_at AS "createdAt"
         FROM messages
         WHERE conversation_id = $1 AND sender_id = $2 AND client_nonce = $3`,
        [conversationId, userId, input.clientNonce],
      );
      message = existing.rows[0];
    }
    if (!message) throw new HttpError(409, "MESSAGE_NOT_SAVED", "The message could not be saved.");
    if (inserted.rowCount) {
      for (const [position, mediaId] of mediaIds.entries()) {
        await client.query(
          `INSERT INTO message_media (message_id, media_id, position) VALUES ($1, $2, $3)`,
          [message.id, mediaId, position],
        );
      }
      await client.query(
        `UPDATE conversations SET last_message_at = now() WHERE id = $1`,
        [conversationId],
      );
      await createMessageNotifications(client, userId, conversationId, access.rows[0].conversationType);
    }
    const response = await client.query(
      `SELECT m.id, m.conversation_id AS "conversationId",
              m.sender_id AS "senderId", p.full_name AS "senderName",
              p.profile_photo_url AS "senderPhotoUrl", m.body,
              m.reply_to_id AS "replyToId", m.created_at AS "createdAt",
              COALESCE((
                SELECT json_agg(json_build_object(
                  'id', media.id, 'name', media.original_name,
                  'contentType', media.content_type, 'byteSize', media.byte_size
                ) ORDER BY mm.position)
                FROM message_media mm
                JOIN media_objects media ON media.id = mm.media_id
                WHERE mm.message_id = m.id
              ), '[]'::json) AS media
       FROM messages m
       JOIN user_profiles p ON p.user_id = m.sender_id
       WHERE m.id = $1`,
      [message.id],
    );
    return response.rows[0];
  });
}

export async function forwardMessage(
  userId: string,
  sourceConversationId: string,
  messageId: string,
  targetConversationId: string,
  clientNonce: string,
) {
  await requireConversationMember(userId, sourceConversationId);
  const targetAccess = await requireConversationMember(userId, targetConversationId);
  const source = await pool.query(
    `SELECT id, body, sender_id AS "senderId"
     FROM messages
     WHERE id = $1 AND conversation_id = $2
       AND deleted_at IS NULL AND moderation_status = 'visible'
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $3 AND b.blocked_id = messages.sender_id)
            OR (b.blocker_id = messages.sender_id AND b.blocked_id = $3)
       )`,
    [messageId, sourceConversationId, userId],
  );
  if (!source.rowCount) {
    throw new HttpError(404, "MESSAGE_NOT_FOUND", "The message was not found.");
  }

  const savedId = await withTransaction(async (client) => {
    const inserted = await client.query(
      `INSERT INTO messages
         (conversation_id, sender_id, body, client_nonce, forwarded_from_message_id)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (conversation_id, sender_id, client_nonce) DO NOTHING
       RETURNING id`,
      [targetConversationId, userId, source.rows[0].body, clientNonce, messageId],
    );
    let id = inserted.rows[0]?.id as string | undefined;
    if (!id) {
      const existing = await client.query(
        `SELECT id FROM messages
         WHERE conversation_id = $1 AND sender_id = $2 AND client_nonce = $3`,
        [targetConversationId, userId, clientNonce],
      );
      id = existing.rows[0]?.id as string | undefined;
    }
    if (!id) throw new HttpError(409, "MESSAGE_NOT_SAVED", "The forwarded message could not be saved.");

    if (inserted.rowCount) {
      const media = await client.query(
        `SELECT media_id, position FROM message_media
         WHERE message_id = $1 ORDER BY position`,
        [messageId],
      );
      for (const attachment of media.rows as Array<{ media_id: string; position: number }>) {
        await client.query(
          `INSERT INTO message_media (message_id, media_id, position)
           VALUES ($1, $2, $3)`,
          [id, attachment.media_id, attachment.position],
        );
      }
      await client.query(
        "UPDATE conversations SET last_message_at = now() WHERE id = $1",
        [targetConversationId],
      );
      await createMessageNotifications(
        client,
        userId,
        targetConversationId,
        targetAccess.conversationType,
      );
    }
    return id;
  });

  const response = await pool.query(
    `SELECT m.id, m.conversation_id AS "conversationId",
            m.sender_id AS "senderId", p.full_name AS "senderName",
            p.profile_photo_url AS "senderPhotoUrl", m.body,
            m.reply_to_id AS "replyToId",
            m.forwarded_from_message_id AS "forwardedFromMessageId",
            m.created_at AS "createdAt",
            COALESCE((
              SELECT json_agg(json_build_object(
                'id', media.id, 'name', media.original_name,
                'contentType', media.content_type, 'byteSize', media.byte_size
              ) ORDER BY mm.position)
              FROM message_media mm
              JOIN media_objects media ON media.id = mm.media_id
              WHERE mm.message_id = m.id
            ), '[]'::json) AS media
     FROM messages m
     JOIN user_profiles p ON p.user_id = m.sender_id
     WHERE m.id = $1`,
    [savedId],
  );
  return response.rows[0];
}

async function createMessageNotifications(
  client: PoolClient,
  actorId: string,
  conversationId: string,
  type: "direct" | "group",
) {
  const preferenceColumn = type === "direct" ? "private_messages" : "group_messages";
  const kind = type === "direct" ? "private_message" : "group_message";
  const members = await client.query(
    `SELECT cm.user_id
     FROM conversation_members cm
     WHERE cm.conversation_id = $1 AND cm.user_id <> $2 AND cm.left_at IS NULL
       AND (cm.muted_until IS NULL OR cm.muted_until <= now())
       AND NOT EXISTS (
         SELECT 1 FROM user_mutes mute
         WHERE mute.user_id = cm.user_id
           AND mute.target_type = 'conversation' AND mute.target_id = $1
           AND (mute.muted_until IS NULL OR mute.muted_until > now())
       )`,
    [conversationId, actorId],
  );
  for (const { user_id: recipientId } of members.rows as Array<{ user_id: string }>) {
    const preference = await client.query(
      `SELECT ${preferenceColumn} AS enabled
       FROM notification_preferences WHERE user_id = $1`,
      [recipientId],
    );
    if (preference.rows[0]?.enabled === false) continue;
    await client.query(
      `INSERT INTO community_notifications (user_id, actor_id, kind, entity_type, entity_id)
       VALUES ($1, $2, $3, 'conversation', $4)`,
      [recipientId, actorId, kind, conversationId],
    );
  }
}

export async function markConversationRead(userId: string, conversationId: string) {
  await requireConversationMember(userId, conversationId);
  const previousRead = await pool.query(
    `SELECT last_read_at FROM conversation_members
     WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL`,
    [conversationId, userId],
  );
  const result = await pool.query(
    `INSERT INTO message_read_receipts (message_id, user_id, delivered_at, read_at)
     SELECT m.id, $2, now(), now()
     FROM messages m
     WHERE m.conversation_id = $1 AND m.sender_id <> $2
       AND m.created_at > COALESCE($3::timestamptz, '-infinity'::timestamptz)
     ON CONFLICT (message_id, user_id)
     DO UPDATE SET delivered_at = COALESCE(message_read_receipts.delivered_at, now()),
                   read_at = now()
     RETURNING message_id`,
    [conversationId, userId, previousRead.rows[0]?.last_read_at ?? null],
  );
  await pool.query(
    `UPDATE conversation_members SET last_read_at = now()
     WHERE conversation_id = $1 AND user_id = $2`,
    [conversationId, userId],
  );
  return { conversationId, readCount: result.rowCount ?? 0, readAt: new Date().toISOString() };
}

export async function markMessagesDelivered(
  userId: string,
  conversationId: string,
  messageIds: string[],
) {
  await requireConversationMember(userId, conversationId);
  if (messageIds.length < 1 || messageIds.length > 100) {
    throw new HttpError(400, "INVALID_RECEIPTS", "A delivery receipt must include 1 to 100 messages.");
  }
  const result = await pool.query(
    `INSERT INTO message_read_receipts (message_id, user_id, delivered_at)
     SELECT m.id, $2, now()
     FROM messages m
     WHERE m.conversation_id = $1 AND m.id = ANY($3::uuid[])
       AND m.sender_id <> $2 AND m.deleted_at IS NULL
     ON CONFLICT (message_id, user_id)
     DO UPDATE SET delivered_at = COALESCE(message_read_receipts.delivered_at, now())
     RETURNING message_id`,
    [conversationId, userId, messageIds],
  );
  return { conversationId, deliveredIds: result.rows.map((row) => row.message_id) };
}

export async function editMessage(userId: string, conversationId: string, messageId: string, body: string) {
  await requireConversationMember(userId, conversationId);
  const result = await pool.query(
    `UPDATE messages SET body = $1, edited_at = now()
     WHERE id = $2 AND conversation_id = $3 AND sender_id = $4
       AND deleted_at IS NULL AND created_at > now() - interval '15 minutes'
     RETURNING id, body, edited_at AS "editedAt"`,
    [body.trim(), messageId, conversationId, userId],
  );
  if (!result.rowCount) {
    const exists = await pool.query(
      `SELECT 1 FROM messages WHERE id = $1 AND conversation_id = $2`,
      [messageId, conversationId],
    );
    if (!exists.rowCount) throw new HttpError(404, "MESSAGE_NOT_FOUND", "The message was not found.");
    throw new HttpError(403, "MESSAGE_EDIT_DENIED", "Only the sender can edit a message within 15 minutes.");
  }
  return result.rows[0];
}

export async function deleteMessage(
  userId: string,
  conversationId: string,
  messageId: string,
) {
  await requireConversationMember(userId, conversationId);
  const own = await pool.query(
    `UPDATE messages SET body = '', deleted_at = now()
     WHERE id = $1 AND conversation_id = $2 AND sender_id = $3
       AND deleted_at IS NULL
     RETURNING id`,
    [messageId, conversationId, userId],
  );
  if (own.rowCount) return { id: messageId, deleted: true };
  const exists = await pool.query(
    `SELECT 1 FROM messages WHERE id = $1 AND conversation_id = $2`,
    [messageId, conversationId],
  );
  if (!exists.rowCount) throw new HttpError(404, "MESSAGE_NOT_FOUND", "The message was not found.");
  throw new HttpError(403, "MESSAGE_DELETE_DENIED", "Only the message sender can delete this message.");
}

export async function setMessageReaction(
  userId: string,
  conversationId: string,
  messageId: string,
  reaction: "like" | "love" | "laugh" | "support" | "celebrate",
) {
  await requireConversationMember(userId, conversationId);
  const message = await pool.query(
    `SELECT id FROM messages WHERE id = $1 AND conversation_id = $2 AND deleted_at IS NULL`,
    [messageId, conversationId],
  );
  if (!message.rowCount) throw new HttpError(404, "MESSAGE_NOT_FOUND", "The message was not found.");
  const existing = await pool.query(
    `SELECT reaction FROM message_reactions WHERE message_id = $1 AND user_id = $2`,
    [messageId, userId],
  );
  if (existing.rows[0]?.reaction === reaction) {
    await pool.query(
      `DELETE FROM message_reactions WHERE message_id = $1 AND user_id = $2`,
      [messageId, userId],
    );
    return { messageId, reaction: null };
  }
  await pool.query(
    `INSERT INTO message_reactions (message_id, user_id, reaction)
     VALUES ($1, $2, $3)
     ON CONFLICT (message_id, user_id) DO UPDATE SET reaction = EXCLUDED.reaction`,
    [messageId, userId, reaction],
  );
  return { messageId, reaction };
}

export async function searchMessages(
  userId: string,
  conversationId: string,
  query: string,
  limit: number,
) {
  await requireConversationMember(userId, conversationId);
  const pattern = escapeLike(query.trim());
  if (!pattern) return { messages: [] };
  const result = await pool.query(
    `SELECT m.id, m.sender_id AS "senderId", p.full_name AS "senderName",
            m.body, m.created_at AS "createdAt"
     FROM messages m
     JOIN user_profiles p ON p.user_id = m.sender_id
     WHERE m.conversation_id = $1 AND m.deleted_at IS NULL
       AND m.moderation_status = 'visible'
       AND m.body ILIKE '%' || $2 || '%'
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $3 AND b.blocked_id = m.sender_id)
            OR (b.blocker_id = m.sender_id AND b.blocked_id = $3)
       )
     ORDER BY m.created_at DESC LIMIT $4`,
    [conversationId, pattern, userId, limit],
  );
  return { messages: result.rows };
}
