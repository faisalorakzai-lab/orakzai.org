import type { PoolClient } from "pg";

import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";

export type PostVisibility = "public" | "regional" | "group" | "private";
export type PostReaction = "like" | "support" | "celebrate" | "care";

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
    // An invalid cursor is rejected below; its value is never interpolated into SQL.
  }
  throw new HttpError(400, "INVALID_CURSOR", "The page cursor is invalid.");
}

function makeCursor(createdAt: Date | string, id: string) {
  return Buffer.from(JSON.stringify({ createdAt, id })).toString("base64url");
}

const postAccess = `
  p.status = 'published'
  AND NOT EXISTS (
    SELECT 1 FROM user_blocks b
    WHERE (b.blocker_id = $1 AND b.blocked_id = p.author_id)
       OR (b.blocker_id = p.author_id AND b.blocked_id = $1)
  )
  AND (
    p.author_id = $1
    OR p.visibility = 'public'
    OR (
      p.visibility = 'regional'
      AND EXISTS (
        SELECT 1
        FROM user_region_assignments ur
        LEFT JOIN districts rd ON rd.id = ur.district_id
        LEFT JOIN qoums rq ON rq.id = ur.qoum_id
        LEFT JOIN districts qd ON qd.id = rq.district_id
        LEFT JOIN villages rv ON rv.id = ur.village_id
        LEFT JOIN qoums vq ON vq.id = rv.qoum_id
        LEFT JOIN districts vd ON vd.id = vq.district_id
        WHERE ur.user_id = $1
          AND COALESCE(ur.region_id, rd.region_id, qd.region_id, vd.region_id) = p.region_id
      )
    )
    OR (
      p.visibility = 'group'
      AND EXISTS (
        SELECT 1 FROM group_members gm
        JOIN community_groups g ON g.id = gm.group_id AND g.status = 'active'
        WHERE gm.group_id = p.group_id AND gm.user_id = $1 AND gm.status = 'active'
      )
    )
  )
`;

const postFields = `
  p.id, p.author_id AS "authorId", author.full_name AS "authorName",
  author.username AS "authorUsername",
  author.profile_photo_url AS "authorPhotoUrl",
  p.group_id AS "groupId", g.name AS "groupName",
  p.visibility, p.region_id AS "regionId", p.body,
  p.is_announcement AS "isAnnouncement", p.pinned_at AS "pinnedAt",
  p.created_at AS "createdAt", p.updated_at AS "updatedAt",
  (SELECT count(*)::int FROM post_comments c
   WHERE c.post_id = p.id AND c.status = 'published') AS "commentCount",
  (SELECT count(*)::int FROM post_reactions r WHERE r.post_id = p.id) AS "reactionCount",
  (SELECT count(*)::int FROM post_shares s WHERE s.post_id = p.id) AS "shareCount",
  (SELECT r.reaction FROM post_reactions r
   WHERE r.post_id = p.id AND r.user_id = $1) AS "myReaction",
  EXISTS (SELECT 1 FROM post_bookmarks b
          WHERE b.post_id = p.id AND b.user_id = $1) AS "isBookmarked",
  COALESCE((
    SELECT json_agg(json_build_object(
      'id', m.id, 'name', m.original_name,
      'contentType', m.content_type, 'byteSize', m.byte_size
    ) ORDER BY pm.position)
    FROM post_media pm
    JOIN media_objects m ON m.id = pm.media_id
    WHERE pm.post_id = p.id
  ), '[]'::json) AS media
`;

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

export async function canReadPost(userId: string, postId: string) {
  const result = await pool.query(
    `SELECT 1 FROM community_posts p
     WHERE p.id = $2 AND ${postAccess}
     LIMIT 1`,
    [userId, postId],
  );
  return result.rowCount === 1;
}

async function requireReadablePost(userId: string, postId: string) {
  if (!(await canReadPost(userId, postId))) {
    throw new HttpError(404, "POST_NOT_FOUND", "The post was not found.");
  }
}

async function userHasPermission(userId: string, permission: string) {
  const result = await pool.query(
    `SELECT 1 FROM user_roles ur
     JOIN role_permissions rp ON rp.role_id = ur.role_id
     JOIN permissions p ON p.id = rp.permission_id
     WHERE ur.user_id = $1 AND p.key = $2 LIMIT 1`,
    [userId, permission],
  );
  return result.rowCount === 1;
}

export async function listFeed(input: {
  userId: string;
  limit: number;
  cursor?: string;
  groupId?: string;
  announcementsOnly?: boolean;
  regionId?: string;
  search?: string;
}) {
  const cursor = readCursor(input.cursor);
  const search = input.search?.trim() ? escapeLike(input.search.trim()) : null;
  const result = await pool.query(
    `SELECT ${postFields}
     FROM community_posts p
     JOIN user_profiles author ON author.user_id = p.author_id
     LEFT JOIN community_groups g ON g.id = p.group_id
     WHERE ${postAccess}
       AND ($2::uuid IS NULL OR p.group_id = $2)
       AND ($3::boolean = false OR p.is_announcement = true)
       AND ($4::uuid IS NULL OR p.region_id = $4)
       AND ($5::text IS NULL OR p.body ILIKE '%' || $5 || '%')
       AND ($6::timestamptz IS NULL OR (p.created_at, p.id) < ($6, $7::uuid))
     ORDER BY p.created_at DESC, p.id DESC
     LIMIT $8`,
    [
      input.userId,
      input.groupId ?? null,
      input.announcementsOnly === true,
      input.regionId ?? null,
      search,
      cursor?.createdAt ?? null,
      cursor?.id ?? null,
      input.limit + 1,
    ],
  );
  const hasMore = result.rows.length > input.limit;
  const posts = hasMore ? result.rows.slice(0, input.limit) : result.rows;
  return {
    posts,
    nextCursor:
      hasMore && posts.length
        ? makeCursor(posts[posts.length - 1].createdAt, posts[posts.length - 1].id)
        : null,
  };
}

/** Home totals share the exact post visibility/blocking predicate used by feed. */
export async function getCommunitySummary(userId: string) {
  const result = await pool.query(
    `SELECT count(*)::int AS "accessiblePosts",
            count(*) FILTER (WHERE p.is_announcement)::int AS "accessibleAnnouncements",
            (SELECT count(*)::int FROM group_members gm
             JOIN community_groups g ON g.id = gm.group_id
             WHERE gm.user_id = $1 AND gm.status = 'active' AND g.status = 'active') AS "joinedGroups"
     FROM community_posts p WHERE ${postAccess}`,
    [userId],
  );
  return { ...result.rows[0], scope: "authorized_user" };
}

export async function getPost(userId: string, postId: string) {
  const result = await pool.query(
    `SELECT ${postFields}
     FROM community_posts p
     JOIN user_profiles author ON author.user_id = p.author_id
     LEFT JOIN community_groups g ON g.id = p.group_id
     WHERE p.id = $2 AND ${postAccess}
     LIMIT 1`,
    [userId, postId],
  );
  if (!result.rowCount) throw new HttpError(404, "POST_NOT_FOUND", "The post was not found.");
  return result.rows[0];
}

async function assertPostLocation(userId: string, regionId: string) {
  const result = await pool.query(
    `SELECT 1
     FROM regions r
     WHERE r.id = $2
       AND EXISTS (
         SELECT 1
         FROM user_region_assignments ur
         LEFT JOIN districts rd ON rd.id = ur.district_id
         LEFT JOIN qoums rq ON rq.id = ur.qoum_id
         LEFT JOIN districts qd ON qd.id = rq.district_id
         LEFT JOIN villages rv ON rv.id = ur.village_id
         LEFT JOIN qoums vq ON vq.id = rv.qoum_id
         LEFT JOIN districts vd ON vd.id = vq.district_id
         WHERE ur.user_id = $1
           AND COALESCE(ur.region_id, rd.region_id, qd.region_id, vd.region_id) = r.id
       )`,
    [userId, regionId],
  );
  if (!result.rowCount) {
    throw new HttpError(403, "REGIONAL_POST_DENIED", "You can post only in an assigned region.");
  }
}

export async function createPost(
  userId: string,
  input: {
    body: string;
    visibility: PostVisibility;
    groupId?: string;
    regionId?: string;
    mediaIds?: string[];
    isAnnouncement?: boolean;
  },
) {
  if (!input.body.trim() && !input.mediaIds?.length) {
    throw new HttpError(400, "EMPTY_POST", "Write a post or attach at least one file.");
  }
  if (input.visibility === "group") {
    if (!input.groupId) throw new HttpError(400, "GROUP_REQUIRED", "Choose a group for this post.");
    const member = await pool.query(
      `SELECT 1 FROM group_members gm
       JOIN community_groups g ON g.id = gm.group_id AND g.status = 'active'
       WHERE gm.group_id = $1 AND gm.user_id = $2 AND gm.status = 'active'`,
      [input.groupId, userId],
    );
    if (!member.rowCount) throw new HttpError(403, "GROUP_ACCESS_DENIED", "Join the group before posting.");
  }
  if (input.visibility === "regional") {
    if (!input.regionId) throw new HttpError(400, "REGION_REQUIRED", "Choose an assigned region.");
    await assertPostLocation(userId, input.regionId);
  }
  if (input.isAnnouncement && !(await userHasPermission(userId, "content:moderate"))) {
    throw new HttpError(403, "FORBIDDEN", "Only authorized moderators can publish announcements.");
  }
  const mediaIds = [...new Set(input.mediaIds ?? [])];
  if (mediaIds.length > 10) throw new HttpError(400, "TOO_MANY_MEDIA", "A post can include up to 10 files.");
  const postId = await withTransaction(async (client) => {
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
      `INSERT INTO community_posts
         (author_id, group_id, visibility, region_id, body, is_announcement, pinned_at)
       VALUES ($1, $2, $3, $4, $5, $6, CASE WHEN $6 THEN now() ELSE NULL END)
       RETURNING id`,
      [
        userId,
        input.visibility === "group" ? input.groupId : null,
        input.visibility,
        input.visibility === "regional" ? input.regionId : null,
        input.body.trim(),
        input.isAnnouncement === true,
      ],
    );
    for (const [position, mediaId] of mediaIds.entries()) {
      await client.query(
        `INSERT INTO post_media (post_id, media_id, position) VALUES ($1, $2, $3)`,
        [inserted.rows[0].id, mediaId, position],
      );
    }
    return inserted.rows[0].id as string;
  });
  return getPost(userId, postId);
}

export async function updatePost(
  userId: string,
  postId: string,
  body: string,
) {
  const result = await pool.query(
    `UPDATE community_posts p SET body = $1, updated_at = now()
     WHERE p.id = $2 AND p.author_id = $3 AND p.status = 'published'
     RETURNING p.id`,
    [body.trim(), postId, userId],
  );
  if (!result.rowCount) {
    const visible = await pool.query(
      "SELECT author_id FROM community_posts WHERE id = $1 AND status = 'published'",
      [postId],
    );
    if (!visible.rowCount) throw new HttpError(404, "POST_NOT_FOUND", "The post was not found.");
    if (!(await userHasPermission(userId, "content:moderate"))) {
      throw new HttpError(403, "POST_EDIT_DENIED", "You can edit only your own post.");
    }
    await pool.query(
      `UPDATE community_posts SET body = $1, updated_at = now()
       WHERE id = $2 AND status = 'published'`,
      [body.trim(), postId],
    );
  }
  return getPost(userId, postId);
}

export async function deletePost(userId: string, postId: string) {
  const result = await pool.query(
    `SELECT author_id FROM community_posts WHERE id = $1 AND status = 'published'`,
    [postId],
  );
  if (!result.rowCount) throw new HttpError(404, "POST_NOT_FOUND", "The post was not found.");
  const isAuthor = result.rows[0].author_id === userId;
  const moderator = !isAuthor && (await userHasPermission(userId, "content:moderate"));
  if (!isAuthor && !moderator) {
    throw new HttpError(403, "POST_DELETE_DENIED", "You can delete only your own post.");
  }
  await pool.query(
    `UPDATE community_posts SET status = 'removed', updated_at = now()
     WHERE id = $1`,
    [postId],
  );
  if (moderator) {
    await pool.query(
      `INSERT INTO moderation_actions
         (actor_id, target_type, target_id, action, reason)
       VALUES ($1, 'post', $2, 'remove_content', 'Removed through authorized moderation.')`,
      [userId, postId],
    );
  }
  return { id: postId, status: "removed" };
}

export async function listComments(
  userId: string,
  postId: string,
  limit: number,
  cursor?: string,
) {
  await requireReadablePost(userId, postId);
  const page = readCursor(cursor);
  const result = await pool.query(
    `SELECT c.id, c.post_id AS "postId", c.author_id AS "authorId",
            p.full_name AS "authorName", p.username AS "authorUsername",
            c.parent_comment_id AS "parentCommentId", c.body,
            c.created_at AS "createdAt", c.updated_at AS "updatedAt"
     FROM post_comments c
     JOIN user_profiles p ON p.user_id = c.author_id
     WHERE c.post_id = $1 AND c.status = 'published'
       AND ($2::timestamptz IS NULL OR (c.created_at, c.id) < ($2, $3::uuid))
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $4 AND b.blocked_id = c.author_id)
            OR (b.blocker_id = c.author_id AND b.blocked_id = $4)
       )
     ORDER BY c.created_at DESC, c.id DESC LIMIT $5`,
    [postId, page?.createdAt ?? null, page?.id ?? null, userId, limit + 1],
  );
  const hasMore = result.rows.length > limit;
  const comments = hasMore ? result.rows.slice(0, limit) : result.rows;
  return {
    comments,
    nextCursor:
      hasMore && comments.length
        ? makeCursor(comments[comments.length - 1].createdAt, comments[comments.length - 1].id)
        : null,
  };
}

export async function addComment(
  userId: string,
  postId: string,
  input: { body: string; parentCommentId?: string },
) {
  await requireReadablePost(userId, postId);
  if (input.parentCommentId) {
    const parent = await pool.query(
      `SELECT 1 FROM post_comments
       WHERE id = $1 AND post_id = $2 AND status = 'published'`,
      [input.parentCommentId, postId],
    );
    if (!parent.rowCount) throw new HttpError(404, "COMMENT_NOT_FOUND", "The parent comment was not found.");
  }
  const result = await pool.query(
    `INSERT INTO post_comments (post_id, author_id, parent_comment_id, body)
     VALUES ($1, $2, $3, $4)
     RETURNING id, post_id AS "postId", author_id AS "authorId",
               parent_comment_id AS "parentCommentId", body, created_at AS "createdAt"`,
    [postId, userId, input.parentCommentId ?? null, input.body.trim()],
  );
  return result.rows[0];
}

export async function setPostReaction(
  userId: string,
  postId: string,
  reaction: PostReaction,
) {
  await requireReadablePost(userId, postId);
  const current = await pool.query(
    "SELECT reaction FROM post_reactions WHERE post_id = $1 AND user_id = $2",
    [postId, userId],
  );
  if (current.rows[0]?.reaction === reaction) {
    await pool.query("DELETE FROM post_reactions WHERE post_id = $1 AND user_id = $2", [postId, userId]);
    return { postId, reaction: null };
  }
  await pool.query(
    `INSERT INTO post_reactions (post_id, user_id, reaction)
     VALUES ($1, $2, $3)
     ON CONFLICT (post_id, user_id) DO UPDATE SET reaction = EXCLUDED.reaction`,
    [postId, userId, reaction],
  );
  return { postId, reaction };
}

export async function setPostBookmark(userId: string, postId: string, saved: boolean) {
  await requireReadablePost(userId, postId);
  if (saved) {
    await pool.query(
      `INSERT INTO post_bookmarks (post_id, user_id) VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [postId, userId],
    );
  } else {
    await pool.query("DELETE FROM post_bookmarks WHERE post_id = $1 AND user_id = $2", [postId, userId]);
  }
  return { postId, saved };
}

export async function recordPostShare(userId: string, postId: string) {
  await requireReadablePost(userId, postId);
  await pool.query(
    `INSERT INTO post_shares (post_id, user_id)
     VALUES ($1, $2) ON CONFLICT DO NOTHING`,
    [postId, userId],
  );
  const count = await pool.query(
    `SELECT count(*)::int AS count FROM post_shares WHERE post_id = $1`,
    [postId],
  );
  return { postId, shareCount: count.rows[0].count };
}

export async function setAnnouncementPin(
  actorId: string,
  postId: string,
  pinned: boolean,
) {
  if (!(await userHasPermission(actorId, "content:moderate"))) {
    throw new HttpError(403, "FORBIDDEN", "Only authorized moderators can manage announcements.");
  }
  const result = await pool.query(
    `UPDATE community_posts
     SET is_announcement = $1, pinned_at = CASE WHEN $1 THEN now() ELSE NULL END,
         updated_at = now()
     WHERE id = $2 AND status = 'published'
     RETURNING id`,
    [pinned, postId],
  );
  if (!result.rowCount) throw new HttpError(404, "POST_NOT_FOUND", "The post was not found.");
  return { id: postId, isAnnouncement: pinned };
}
