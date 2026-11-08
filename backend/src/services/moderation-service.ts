import type { PoolClient } from "pg";

import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";

type ModerationAction =
  | "hide_content"
  | "restore_content"
  | "remove_content"
  | "suspend_group"
  | "restore_group"
  | "restrict_member"
  | "dismiss_report";

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

async function hasPermission(userId: string, permission: string, client?: PoolClient) {
  const sql = `SELECT 1
     FROM user_roles ur
     JOIN role_permissions rp ON rp.role_id = ur.role_id
     JOIN permissions p ON p.id = rp.permission_id
     WHERE ur.user_id = $1 AND p.key = $2 LIMIT 1`;
  const values = [userId, permission];
  const result = client
    ? await client.query(sql, values)
    : await pool.query(sql, values);
  return result.rowCount === 1;
}

async function requirePermission(userId: string, permission: string, client?: PoolClient) {
  if (!(await hasPermission(userId, permission, client))) {
    throw new HttpError(403, "FORBIDDEN", "You do not have permission for this moderation action.");
  }
}

export async function listReports(input: {
  userId: string;
  status?: "open" | "reviewing" | "actioned" | "dismissed";
  limit: number;
  cursor?: string;
}) {
  await requirePermission(input.userId, "content:moderate");
  const cursor = input.cursor ? decodeReportCursor(input.cursor) : null;
  const result = await pool.query(
    `SELECT r.id, r.reporter_id AS "reporterId",
            reporter.full_name AS "reporterName",
            r.target_type AS "targetType", r.target_id AS "targetId",
            r.category, r.details, r.status, r.assigned_to AS "assignedTo",
            r.created_at AS "createdAt", r.resolved_at AS "resolvedAt"
     FROM content_reports r
     JOIN user_profiles reporter ON reporter.user_id = r.reporter_id
     WHERE ($1::text IS NULL OR r.status = $1)
       AND ($2::timestamptz IS NULL OR (r.created_at, r.id) > ($2, $3::uuid))
     ORDER BY r.created_at ASC, r.id ASC
     LIMIT $4`,
    [input.status ?? null, cursor?.createdAt ?? null, cursor?.id ?? null, input.limit + 1],
  );
  const hasMore = result.rows.length > input.limit;
  const reports = hasMore ? result.rows.slice(0, input.limit) : result.rows;
  return {
    reports,
    nextCursor:
      hasMore && reports.length
        ? encodeReportCursor(reports[reports.length - 1].createdAt, reports[reports.length - 1].id)
        : null,
  };
}

export async function getReport(userId: string, reportId: string) {
  await requirePermission(userId, "content:moderate");
  const result = await pool.query(
    `SELECT r.id, r.reporter_id AS "reporterId",
            reporter.full_name AS "reporterName",
            r.target_type AS "targetType", r.target_id AS "targetId",
            r.category, r.details, r.status, r.assigned_to AS "assignedTo",
            r.created_at AS "createdAt", r.resolved_at AS "resolvedAt"
     FROM content_reports r
     JOIN user_profiles reporter ON reporter.user_id = r.reporter_id
     WHERE r.id = $1`,
    [reportId],
  );
  const report = result.rows[0];
  if (!report) throw new HttpError(404, "REPORT_NOT_FOUND", "The report was not found.");
  let target: unknown = null;
  if (report.targetType === "post") {
    const item = await pool.query(
      `SELECT p.id, p.author_id AS "authorId", up.full_name AS "authorName",
              p.body, p.status, p.created_at AS "createdAt"
       FROM community_posts p JOIN user_profiles up ON up.user_id = p.author_id
       WHERE p.id = $1`,
      [report.targetId],
    );
    target = item.rows[0] ?? null;
  } else if (report.targetType === "comment") {
    const item = await pool.query(
      `SELECT c.id, c.post_id AS "postId", c.author_id AS "authorId",
              up.full_name AS "authorName", c.body, c.status,
              c.created_at AS "createdAt"
       FROM post_comments c JOIN user_profiles up ON up.user_id = c.author_id
       WHERE c.id = $1`,
      [report.targetId],
    );
    target = item.rows[0] ?? null;
  } else if (report.targetType === "message") {
    const item = await pool.query(
      `SELECT m.id, m.conversation_id AS "conversationId",
              m.sender_id AS "authorId", up.full_name AS "authorName",
              m.body, m.moderation_status AS status,
              m.created_at AS "createdAt"
       FROM messages m JOIN user_profiles up ON up.user_id = m.sender_id
       WHERE m.id = $1`,
      [report.targetId],
    );
    target = item.rows[0] ?? null;
  } else if (report.targetType === "group") {
    const item = await pool.query(
      `SELECT id, name, description, visibility, status, created_at AS "createdAt"
       FROM community_groups WHERE id = $1`,
      [report.targetId],
    );
    target = item.rows[0] ?? null;
  } else {
    const item = await pool.query(
      `SELECT u.id, p.full_name AS "fullName", p.username,
              u.account_status AS "accountStatus", u.created_at AS "createdAt"
       FROM users u JOIN user_profiles p ON p.user_id = u.id
       WHERE u.id = $1`,
      [report.targetId],
    );
    target = item.rows[0] ?? null;
  }
  return { ...report, target };
}

export async function assignReport(
  userId: string,
  reportId: string,
  assigneeId: string | null,
) {
  await requirePermission(userId, "content:moderate");
  const activeAssignee = assigneeId
    ? await pool.query(
        `SELECT 1 FROM users u
         JOIN user_roles ur ON ur.user_id = u.id
         JOIN role_permissions rp ON rp.role_id = ur.role_id
         JOIN permissions p ON p.id = rp.permission_id AND p.key = 'content:moderate'
         WHERE u.id = $1 AND u.account_status = 'active'`,
        [assigneeId],
      )
    : null;
  if (assigneeId && !activeAssignee?.rowCount) {
    throw new HttpError(404, "MODERATOR_NOT_FOUND", "The moderator was not found.");
  }
  const result = await pool.query(
    `UPDATE content_reports
     SET assigned_to = $1,
         status = CASE WHEN $1::uuid IS NULL THEN status ELSE 'reviewing' END
     WHERE id = $2
     RETURNING id, assigned_to AS "assignedTo", status`,
    [assigneeId, reportId],
  );
  if (!result.rowCount) throw new HttpError(404, "REPORT_NOT_FOUND", "The report was not found.");
  return result.rows[0];
}

export async function applyModerationAction(input: {
  actorId: string;
  reportId: string;
  action: ModerationAction;
  reason: string;
}) {
  return withTransaction(async (client) => {
    const reportResult = await client.query(
      `SELECT id, target_type AS "targetType", target_id AS "targetId",
              status
       FROM content_reports WHERE id = $1 FOR UPDATE`,
      [input.reportId],
    );
    const report = reportResult.rows[0];
    if (!report || report.status === "dismissed" || report.status === "actioned") {
      throw new HttpError(404, "REPORT_NOT_AVAILABLE", "The report is not available for action.");
    }
    if (input.action === "suspend_group" || input.action === "restore_group") {
      await requirePermission(input.actorId, "groups:suspend", client);
      if (report.targetType !== "group") {
        throw new HttpError(400, "ACTION_TARGET_MISMATCH", "This action requires a group report.");
      }
      await client.query(
        `UPDATE community_groups SET status = $1, updated_at = now() WHERE id = $2`,
        [input.action === "suspend_group" ? "suspended" : "active", report.targetId],
      );
    } else if (input.action === "restrict_member") {
      await requirePermission(input.actorId, "members:restrict", client);
      if (report.targetType !== "user") {
        throw new HttpError(400, "ACTION_TARGET_MISMATCH", "Member restriction requires a member report.");
      }
      await client.query(
        `UPDATE users SET account_status = 'suspended', updated_at = now() WHERE id = $1`,
        [report.targetId],
      );
      await client.query(
        `UPDATE user_sessions SET revoked_at = COALESCE(revoked_at, now())
         WHERE user_id = $1`,
        [report.targetId],
      );
    } else if (input.action === "dismiss_report") {
      await requirePermission(input.actorId, "content:moderate", client);
    } else {
      await requirePermission(input.actorId, "content:moderate", client);
      const targetTable: Record<string, string> = {
        post: "community_posts",
        comment: "post_comments",
        message: "messages",
      };
      const table = targetTable[report.targetType];
      if (!table) {
        throw new HttpError(400, "ACTION_TARGET_MISMATCH", "This action cannot be applied to the reported target.");
      }
      if (report.targetType === "message") {
        const status = input.action === "hide_content"
          ? "hidden"
          : input.action === "restore_content"
            ? "visible"
            : "removed";
        await client.query(
          `UPDATE messages SET moderation_status = $1 WHERE id = $2`,
          [status, report.targetId],
        );
      } else {
        const status = input.action === "hide_content"
          ? "hidden"
          : input.action === "restore_content"
            ? "published"
            : "removed";
        await client.query(
          `UPDATE ${table} SET status = $1, updated_at = now() WHERE id = $2`,
          [status, report.targetId],
        );
      }
    }

    const resolvedStatus =
      input.action === "dismiss_report" ? "dismissed" : "actioned";
    await client.query(
      `UPDATE content_reports SET status = $1, resolved_at = now() WHERE id = $2`,
      [resolvedStatus, input.reportId],
    );
    const action = await client.query(
      `INSERT INTO moderation_actions
         (report_id, actor_id, target_type, target_id, action, reason)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, report_id AS "reportId", target_type AS "targetType",
                 target_id AS "targetId", action, reason,
                 created_at AS "createdAt"`,
      [
        input.reportId,
        input.actorId,
        report.targetType,
        report.targetId,
        input.action,
        input.reason.trim(),
      ],
    );
    await client.query(
      `INSERT INTO community_notifications (user_id, actor_id, kind, entity_type, entity_id)
       SELECT reporter_id, $1, 'moderation_action', 'report', id
       FROM content_reports WHERE id = $2 AND reporter_id <> $1
         AND COALESCE((SELECT moderator_actions FROM notification_preferences
                       WHERE user_id = content_reports.reporter_id), true)`,
      [input.actorId, input.reportId],
    );
    return { action: action.rows[0], reportStatus: resolvedStatus };
  });
}

export async function listModerationActions(userId: string, targetId?: string, limit = 50) {
  await requirePermission(userId, "content:moderate");
  const result = await pool.query(
    `SELECT a.id, a.report_id AS "reportId", a.actor_id AS "actorId",
            actor.full_name AS "actorName", a.target_type AS "targetType",
            a.target_id AS "targetId", a.action, a.reason,
            a.created_at AS "createdAt"
     FROM moderation_actions a
     JOIN user_profiles actor ON actor.user_id = a.actor_id
     WHERE ($1::uuid IS NULL OR a.target_id = $1)
     ORDER BY a.created_at DESC LIMIT $2`,
    [targetId ?? null, limit],
  );
  return result.rows;
}

function encodeReportCursor(createdAt: Date | string, id: string) {
  return Buffer.from(JSON.stringify({ createdAt, id })).toString("base64url");
}

function decodeReportCursor(cursor: string) {
  try {
    const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as {
      createdAt?: unknown;
      id?: unknown;
    };
    if (
      typeof parsed.createdAt === "string" &&
      !Number.isNaN(Date.parse(parsed.createdAt)) &&
      typeof parsed.id === "string" &&
      /^[0-9a-f-]{36}$/i.test(parsed.id)
    ) {
      return { createdAt: parsed.createdAt, id: parsed.id };
    }
  } catch {
    // Invalid cursor is rejected below.
  }
  throw new HttpError(400, "INVALID_CURSOR", "The page cursor is invalid.");
}
