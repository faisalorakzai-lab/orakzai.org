import type { PoolClient } from "pg";

import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";

export const groupCategories = [
  "general",
  "regional",
  "youth",
  "education",
  "healthcare",
  "business",
  "employment",
  "overseas",
  "welfare",
  "culture",
] as const;

type GroupCategory = (typeof groupCategories)[number];
type GroupVisibility = "public" | "private";

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

function makeCursor(createdAt: Date | string, id: string): string {
  return Buffer.from(JSON.stringify({ createdAt, id })).toString("base64url");
}

function readCursor(cursor?: string): { createdAt: string; id: string } | null {
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
    // The caller receives a validation error below; cursor text is never interpolated into SQL.
  }
  throw new HttpError(400, "INVALID_CURSOR", "The page cursor is invalid.");
}

async function assertLocationIsConsistent(
  client: PoolClient,
  location: {
    regionId?: string;
    districtId?: string;
    qoumId?: string;
    villageId?: string;
  },
) {
  const { regionId, districtId, qoumId, villageId } = location;
  if (districtId) {
    const result = await client.query(
      `SELECT 1 FROM districts WHERE id = $1 AND ($2::uuid IS NULL OR region_id = $2)`,
      [districtId, regionId ?? null],
    );
    if (result.rowCount !== 1) throw new HttpError(400, "INVALID_REGION", "District does not belong to the selected region.");
  } else if (regionId) {
    const result = await client.query("SELECT 1 FROM regions WHERE id = $1", [regionId]);
    if (result.rowCount !== 1) throw new HttpError(400, "INVALID_REGION", "The selected region was not found.");
  }
  if (qoumId) {
    const result = await client.query(
      `SELECT 1 FROM qoums WHERE id = $1 AND ($2::uuid IS NULL OR district_id = $2)`,
      [qoumId, districtId ?? null],
    );
    if (result.rowCount !== 1) throw new HttpError(400, "INVALID_QOUM", "Qoum does not belong to the selected district.");
  }
  if (villageId) {
    const result = await client.query(
      `SELECT 1 FROM villages WHERE id = $1 AND ($2::uuid IS NULL OR qoum_id = $2)`,
      [villageId, qoumId ?? null],
    );
    if (result.rowCount !== 1) throw new HttpError(400, "INVALID_VILLAGE", "Village does not belong to the selected qoum.");
  }
}

export async function listGroups(input: {
  userId: string;
  search?: string;
  category?: GroupCategory;
  mine?: boolean;
  limit: number;
  cursor?: string;
}) {
  const cursor = readCursor(input.cursor);
  const search = input.search?.trim() || null;
  const result = await pool.query(
    `SELECT g.id, g.name, g.description, g.category, g.visibility, g.status,
            g.owner_id AS "ownerId", g.region_id AS "regionId",
            g.district_id AS "districtId", g.qoum_id AS "qoumId",
            g.village_id AS "villageId", g.created_at AS "createdAt",
            count(DISTINCT gm.user_id)::int AS "memberCount",
            mine.role AS "myRole", mine.status AS "myStatus",
            (SELECT p.id FROM community_posts p
             WHERE p.group_id = g.id AND p.is_announcement
               AND p.status = 'published'
             ORDER BY p.pinned_at DESC NULLS LAST, p.created_at DESC
             LIMIT 1) AS "pinnedPostId"
     FROM community_groups g
     LEFT JOIN group_members gm
       ON gm.group_id = g.id AND gm.status = 'active'
     LEFT JOIN group_members mine
       ON mine.group_id = g.id AND mine.user_id = $1
     WHERE g.status = 'active'
       AND (g.visibility = 'public'
         OR mine.status = 'active'
         OR EXISTS (
           SELECT 1 FROM group_invitations gi
           WHERE gi.group_id = g.id AND gi.invitee_id = $1
             AND gi.status = 'pending'
         ))
       AND ($2::boolean = false OR mine.status = 'active')
       AND ($3::text IS NULL OR g.category = $3)
       AND ($4::text IS NULL OR g.name ILIKE '%' || replace(replace(replace($4, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%')
       AND ($5::timestamptz IS NULL OR (g.created_at, g.id) < ($5, $6::uuid))
     GROUP BY g.id, mine.role, mine.status
     ORDER BY g.created_at DESC, g.id DESC
     LIMIT $7`,
    [
      input.userId,
      input.mine === true,
      input.category ?? null,
      search,
      cursor?.createdAt ?? null,
      cursor?.id ?? null,
      input.limit + 1,
    ],
  );
  const hasMore = result.rows.length > input.limit;
  const rows = hasMore ? result.rows.slice(0, input.limit) : result.rows;
  return {
    groups: rows,
    nextCursor:
      hasMore && rows.length > 0
        ? makeCursor(rows[rows.length - 1].createdAt, rows[rows.length - 1].id)
        : null,
  };
}

export async function getGroup(userId: string, groupId: string) {
  const result = await pool.query(
    `SELECT g.id, g.name, g.description, g.category, g.visibility, g.status,
            g.owner_id AS "ownerId", g.region_id AS "regionId",
            g.district_id AS "districtId", g.qoum_id AS "qoumId",
            g.village_id AS "villageId", g.profile_image_url AS "profileImageUrl",
            g.created_at AS "createdAt",
            count(DISTINCT active_members.user_id)::int AS "memberCount",
            mine.role AS "myRole", mine.status AS "myStatus",
            c.id AS "conversationId"
     FROM community_groups g
     LEFT JOIN group_members active_members
       ON active_members.group_id = g.id AND active_members.status = 'active'
     LEFT JOIN group_members mine
       ON mine.group_id = g.id AND mine.user_id = $1
     LEFT JOIN conversations c ON c.group_id = g.id
     WHERE g.id = $2 AND g.status = 'active'
       AND (g.visibility = 'public' OR mine.status = 'active'
         OR EXISTS (
           SELECT 1 FROM group_invitations gi
           WHERE gi.group_id = g.id AND gi.invitee_id = $1
             AND gi.status = 'pending'
         ))
     GROUP BY g.id, mine.role, mine.status, c.id`,
    [userId, groupId],
  );
  const group = result.rows[0];
  if (!group) throw new HttpError(404, "GROUP_NOT_FOUND", "The group was not found.");
  const [rules, announcements] = await Promise.all([
    pool.query(
      `SELECT id, title, body, position FROM group_rules
       WHERE group_id = $1 ORDER BY position, created_at`,
      [groupId],
    ),
    pool.query(
      `SELECT id, author_id AS "authorId", body, created_at AS "createdAt"
       FROM community_posts
       WHERE group_id = $1 AND is_announcement = true AND status = 'published'
       ORDER BY pinned_at DESC NULLS LAST, created_at DESC LIMIT 10`,
      [groupId],
    ),
  ]);
  return { ...group, rules: rules.rows, announcements: announcements.rows };
}

export async function createGroup(
  userId: string,
  input: {
    name: string;
    description: string;
    category: GroupCategory;
    visibility: GroupVisibility;
    regionId?: string;
    districtId?: string;
    qoumId?: string;
    villageId?: string;
  },
) {
  return withTransaction(async (client) => {
    await assertLocationIsConsistent(client, input);
    const group = await client.query(
      `INSERT INTO community_groups
         (name, description, category, visibility, owner_id,
          region_id, district_id, qoum_id, village_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING id, name, description, category, visibility, status,
                 owner_id AS "ownerId", region_id AS "regionId",
                 district_id AS "districtId", qoum_id AS "qoumId",
                 village_id AS "villageId", created_at AS "createdAt"`,
      [
        input.name,
        input.description,
        input.category,
        input.visibility,
        userId,
        input.regionId ?? null,
        input.districtId ?? null,
        input.qoumId ?? null,
        input.villageId ?? null,
      ],
    );
    const created = group.rows[0];
    await client.query(
      "INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'owner')",
      [created.id, userId],
    );
    const conversation = await client.query(
      `INSERT INTO conversations (conversation_type, group_id, created_by)
       VALUES ('group', $1, $2) RETURNING id`,
      [created.id, userId],
    );
    await client.query(
      "INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2)",
      [conversation.rows[0].id, userId],
    );
    await client.query(
      `INSERT INTO group_rules (group_id, title, body, position, created_by)
       VALUES ($1, 'Be respectful', 'Treat members with respect. Do not post private information or harmful content.', 0, $2)`,
      [created.id, userId],
    );
    return { ...created, memberCount: 1, myRole: "owner", conversationId: conversation.rows[0].id };
  });
}

export async function joinGroup(userId: string, groupId: string) {
  return withTransaction(async (client) => {
    const groupResult = await client.query(
      "SELECT id, visibility, status FROM community_groups WHERE id = $1 FOR UPDATE",
      [groupId],
    );
    const group = groupResult.rows[0];
    if (!group || group.status !== "active") {
      throw new HttpError(404, "GROUP_NOT_FOUND", "The group was not found.");
    }
    const membershipResult = await client.query(
      "SELECT role, status FROM group_members WHERE group_id = $1 AND user_id = $2 FOR UPDATE",
      [groupId, userId],
    );
    const membership = membershipResult.rows[0];
    if (membership?.status === "banned" || membership?.status === "removed") {
      throw new HttpError(403, "GROUP_ACCESS_DENIED", "You cannot join this group.");
    }
    if (membership?.status === "active") {
      return { groupId, status: "active", role: membership.role };
    }
    if (group.visibility === "private") {
      throw new HttpError(403, "INVITATION_REQUIRED", "A group invitation is required.");
    }
    await client.query(
      `INSERT INTO group_members (group_id, user_id, role, status)
       VALUES ($1, $2, 'member', 'active')
       ON CONFLICT (group_id, user_id)
       DO UPDATE SET role = 'member', status = 'active',
                     joined_at = now(), updated_at = now()`,
      [groupId, userId],
    );
    const conversation = await client.query(
      "SELECT id FROM conversations WHERE group_id = $1",
      [groupId],
    );
    if (conversation.rowCount === 1) {
      await client.query(
        `INSERT INTO conversation_members (conversation_id, user_id)
         VALUES ($1, $2) ON CONFLICT (conversation_id, user_id)
         DO UPDATE SET joined_at = now(), left_at = NULL`,
        [conversation.rows[0].id, userId],
      );
    }
    return { groupId, status: "active", role: "member" };
  });
}

export async function respondToInvitation(
  userId: string,
  invitationId: string,
  accept: boolean,
) {
  return withTransaction(async (client) => {
    const inviteResult = await client.query(
      `SELECT gi.id, gi.group_id AS "groupId", g.status AS "groupStatus",
              g.visibility, gi.status AS "inviteStatus", c.id AS "conversationId"
       FROM group_invitations gi
       JOIN community_groups g ON g.id = gi.group_id
       LEFT JOIN conversations c ON c.group_id = g.id
       WHERE gi.id = $1 AND gi.invitee_id = $2
       FOR UPDATE OF gi`,
      [invitationId, userId],
    );
    const invite = inviteResult.rows[0];
    if (!invite || invite.inviteStatus !== "pending" || invite.groupStatus !== "active") {
      throw new HttpError(404, "INVITATION_NOT_FOUND", "The invitation is no longer available.");
    }
    await client.query(
      `UPDATE group_invitations SET status = $1, responded_at = now() WHERE id = $2`,
      [accept ? "accepted" : "declined", invitationId],
    );
    if (!accept) return { invitationId, status: "declined" };
    await client.query(
      `INSERT INTO group_members (group_id, user_id, role, status)
       VALUES ($1, $2, 'member', 'active')
       ON CONFLICT (group_id, user_id)
       DO UPDATE SET role = 'member', status = 'active',
                     joined_at = now(), updated_at = now()`,
      [invite.groupId, userId],
    );
    if (invite.conversationId) {
      await client.query(
        `INSERT INTO conversation_members (conversation_id, user_id)
         VALUES ($1, $2) ON CONFLICT (conversation_id, user_id)
         DO UPDATE SET joined_at = now(), left_at = NULL`,
        [invite.conversationId, userId],
      );
    }
    return { invitationId, groupId: invite.groupId, status: "accepted" };
  });
}

async function requireGroupAdmin(
  client: PoolClient,
  actorId: string,
  groupId: string,
): Promise<"owner" | "admin" | "moderator" | "member"> {
  const result = await client.query(
    `SELECT gm.role FROM group_members gm
     JOIN community_groups g ON g.id = gm.group_id AND g.status = 'active'
     WHERE gm.group_id = $1 AND gm.user_id = $2 AND gm.status = 'active'`,
    [groupId, actorId],
  );
  const role = result.rows[0]?.role;
  if (!["owner", "admin"].includes(role)) {
    throw new HttpError(403, "GROUP_ADMIN_REQUIRED", "Only group owners and admins can perform this action.");
  }
  return role;
}

export async function leaveGroup(userId: string, groupId: string) {
  return withTransaction(async (client) => {
    const memberResult = await client.query(
      `SELECT role FROM group_members
       WHERE group_id = $1 AND user_id = $2 AND status = 'active'
       FOR UPDATE`,
      [groupId, userId],
    );
    const member = memberResult.rows[0];
    if (!member) throw new HttpError(404, "MEMBERSHIP_NOT_FOUND", "You are not an active group member.");
    if (member.role === "owner") {
      throw new HttpError(409, "OWNER_CANNOT_LEAVE", "Transfer group ownership before leaving.");
    }
    await client.query(
      `UPDATE group_members SET status = 'left', updated_at = now()
       WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId],
    );
    await client.query(
      `UPDATE conversation_members cm SET left_at = now()
       FROM conversations c
       WHERE c.group_id = $1 AND cm.conversation_id = c.id AND cm.user_id = $2`,
      [groupId, userId],
    );
    return { groupId, status: "left" };
  });
}

export async function inviteMember(
  actorId: string,
  groupId: string,
  inviteeId: string,
) {
  return withTransaction(async (client) => {
    await requireGroupAdmin(client, actorId, groupId);
    const target = await client.query(
      `SELECT u.id, u.account_status
       FROM users u
       WHERE u.id = $1
         AND NOT EXISTS (
           SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $2 AND b.blocked_id = u.id)
              OR (b.blocker_id = u.id AND b.blocked_id = $2)
         )`,
      [inviteeId, actorId],
    );
    if (target.rows[0]?.account_status !== "active") {
      throw new HttpError(404, "MEMBER_NOT_FOUND", "The member is unavailable.");
    }
    const member = await client.query(
      `SELECT status FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, inviteeId],
    );
    if (member.rows[0]?.status === "active") {
      throw new HttpError(409, "ALREADY_MEMBER", "This person is already a group member.");
    }
    const existing = await client.query(
      `SELECT id FROM group_invitations
       WHERE group_id = $1 AND invitee_id = $2 AND status = 'pending'`,
      [groupId, inviteeId],
    );
    if (existing.rowCount) {
      return { invitationId: existing.rows[0].id, status: "pending" };
    }
    const invitation = await client.query(
      `INSERT INTO group_invitations (group_id, invitee_id, invited_by)
       VALUES ($1, $2, $3)
       RETURNING id, group_id AS "groupId", invitee_id AS "inviteeId",
                 status, created_at AS "createdAt"`,
      [groupId, inviteeId, actorId],
    );
    const preference = await client.query(
      `SELECT group_invitations FROM notification_preferences WHERE user_id = $1`,
      [inviteeId],
    );
    if (preference.rows[0]?.group_invitations !== false) {
      await client.query(
        `INSERT INTO community_notifications (user_id, actor_id, kind, entity_type, entity_id)
         VALUES ($1, $2, 'group_invitation', 'group', $3)`,
        [inviteeId, actorId, groupId],
      );
    }
    return invitation.rows[0];
  });
}

export async function listGroupInvitations(userId: string) {
  const result = await pool.query(
    `SELECT gi.id, gi.group_id AS "groupId", g.name AS "groupName",
            gi.invited_by AS "invitedBy",
            inviter.full_name AS "inviterName",
            gi.created_at AS "createdAt"
     FROM group_invitations gi
     JOIN community_groups g ON g.id = gi.group_id
     JOIN user_profiles inviter ON inviter.user_id = gi.invited_by
     WHERE gi.invitee_id = $1 AND gi.status = 'pending'
       AND g.status = 'active'
     ORDER BY gi.created_at DESC LIMIT 100`,
    [userId],
  );
  return result.rows;
}

export async function listGroupMembers(userId: string, groupId: string) {
  const access = await pool.query(
    `SELECT g.visibility, m.status
     FROM community_groups g
     LEFT JOIN group_members m ON m.group_id = g.id AND m.user_id = $1
     WHERE g.id = $2 AND g.status = 'active'`,
    [userId, groupId],
  );
  const group = access.rows[0];
  if (!group || (group.visibility === "private" && group.status !== "active")) {
    throw new HttpError(404, "GROUP_NOT_FOUND", "The group was not found.");
  }
  const result = await pool.query(
    `SELECT m.user_id AS id, p.full_name AS "fullName",
            p.username, p.profile_photo_url AS "profilePhotoUrl",
            m.role, m.joined_at AS "joinedAt"
     FROM group_members m
     JOIN user_profiles p ON p.user_id = m.user_id
     JOIN users u ON u.id = m.user_id AND u.account_status = 'active'
     WHERE m.group_id = $1 AND m.status = 'active'
     ORDER BY CASE m.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1
                          WHEN 'moderator' THEN 2 ELSE 3 END,
              m.joined_at ASC
     LIMIT 500`,
    [groupId],
  );
  return result.rows;
}

export async function updateGroupMember(
  actorId: string,
  groupId: string,
  memberId: string,
  input: { action: "remove" | "role"; role?: "admin" | "moderator" | "member" },
) {
  return withTransaction(async (client) => {
    const actorRole = await requireGroupAdmin(client, actorId, groupId);
    const target = await client.query(
      `SELECT role, status FROM group_members
       WHERE group_id = $1 AND user_id = $2 FOR UPDATE`,
      [groupId, memberId],
    );
    if (!target.rows[0] || target.rows[0].status !== "active") {
      throw new HttpError(404, "MEMBER_NOT_FOUND", "The group member was not found.");
    }
    if (target.rows[0].role === "owner") {
      throw new HttpError(403, "OWNER_PROTECTED", "The group owner cannot be changed through this action.");
    }
    if (actorRole !== "owner" && target.rows[0].role === "admin") {
      throw new HttpError(403, "OWNER_REQUIRED", "Only the group owner can manage another admin.");
    }
    if (input.action === "remove") {
      await client.query(
        `UPDATE group_members SET status = 'removed', updated_at = now()
         WHERE group_id = $1 AND user_id = $2`,
        [groupId, memberId],
      );
      await client.query(
        `UPDATE conversation_members cm SET left_at = now()
         FROM conversations c
         WHERE c.group_id = $1 AND cm.conversation_id = c.id AND cm.user_id = $2`,
        [groupId, memberId],
      );
      return { groupId, memberId, action: "removed" };
    }
    if (!input.role) throw new HttpError(400, "INVALID_ROLE", "Choose a valid group role.");
    if (actorRole !== "owner" && input.role === "admin") {
      throw new HttpError(403, "OWNER_REQUIRED", "Only the group owner can appoint admins.");
    }
    await client.query(
      `UPDATE group_members SET role = $1, updated_at = now()
       WHERE group_id = $2 AND user_id = $3`,
      [input.role, groupId, memberId],
    );
    return { groupId, memberId, role: input.role };
  });
}

export async function updateGroupDetails(
  actorId: string,
  groupId: string,
  input: {
    name?: string;
    description?: string;
    visibility?: GroupVisibility;
    category?: GroupCategory;
  },
) {
  return withTransaction(async (client) => {
    const actorRole = await requireGroupAdmin(client, actorId, groupId);
    if (input.visibility !== undefined && actorRole !== "owner") {
      throw new HttpError(403, "OWNER_REQUIRED", "Only the owner can change group visibility.");
    }
    const result = await client.query(
      `UPDATE community_groups
       SET name = COALESCE($1, name),
           description = COALESCE($2, description),
           visibility = COALESCE($3, visibility),
           category = COALESCE($4, category),
           updated_at = now()
       WHERE id = $5 AND status = 'active'
       RETURNING id, name, description, category, visibility, status,
                 updated_at AS "updatedAt"`,
      [
        input.name ?? null,
        input.description ?? null,
        input.visibility ?? null,
        input.category ?? null,
        groupId,
      ],
    );
    if (!result.rowCount) throw new HttpError(404, "GROUP_NOT_FOUND", "The group was not found.");
    return result.rows[0];
  });
}

export async function replaceGroupRules(
  actorId: string,
  groupId: string,
  rules: Array<{ title: string; body: string }>,
) {
  return withTransaction(async (client) => {
    await requireGroupAdmin(client, actorId, groupId);
    await client.query("DELETE FROM group_rules WHERE group_id = $1", [groupId]);
    for (const [position, rule] of rules.entries()) {
      await client.query(
        `INSERT INTO group_rules (group_id, title, body, position, created_by)
         VALUES ($1, $2, $3, $4, $5)`,
        [groupId, rule.title, rule.body, position, actorId],
      );
    }
    return { groupId, rules };
  });
}
