import { pool } from "../db/pool.js";
import { config } from "../config.js";
import { HttpError } from "../http/errors.js";
import { hashPassword, verifyPassword } from "../security.js";
import { canReadPost } from "./feed-service.js";
import { getUserProfile } from "./user-service.js";

function publicHttps(value?: string) {
  if (!value) return null;
  try { const url = new URL(value); return url.protocol === "https:" ? url.href : null; }
  catch { return null; }
}

export function accountCapabilities() {
  const mail = config.authDevMode || Boolean(config.smtpUrl && config.smtpFrom);
  const termsUrl = publicHttps(config.termsUrl);
  const privacyUrl = publicHttps(config.privacyUrl);
  const days = config.accountDeletionRetentionDays;
  const retention = Number.isInteger(days) && days >= 1 && days <= 3650;
  return {
    registrationAvailable: mail && (config.authDevMode ||
      Boolean(termsUrl && privacyUrl && config.legalVersion)),
    emailVerificationAvailable: mail,
    passwordResetAvailable: mail,
    phoneVerificationAvailable: false,
    developmentMode: config.authDevMode,
    // A provider must have an actual backend verifier and native adapter.
    // None are configured by this deployment; never advertise simulated login.
    providers: { google: false, apple: false, wallet: false },
    legal: { termsUrl, privacyUrl,
      version: config.legalVersion ?? (config.authDevMode ? "development-notice-v1" : null) },
    deletionAvailable: retention,
    deletionRetentionDays: retention ? days : null,
    avatarAvailable: config.nodeEnv !== "production" &&
      config.communityMediaProvider === "local-development",
    membershipAvailable: false,
    applicationsAvailable: false,
  };
}

export async function auditAccount(userId: string, action: string) {
  await pool.query(
    `INSERT INTO audit_logs(actor_id,action,entity_type,entity_id)
     VALUES($1,$2,'user',$1)`, [userId, action]);
}

export async function activeSessions(userId: string, currentSessionId: string) {
  const result = await pool.query(
    `SELECT id,created_at AS "createdAt",last_used_at AS "lastUsedAt",
       expires_at AS "expiresAt",(id=$2::uuid) AS "isCurrent"
     FROM user_sessions WHERE user_id=$1 AND revoked_at IS NULL
       AND expires_at>now() ORDER BY created_at DESC`, [userId, currentSessionId]);
  return result.rows;
}

export async function revokeSession(userId: string, sessionId: string) {
  const result = await pool.query(
    `UPDATE user_sessions SET revoked_at=now() WHERE id=$1 AND user_id=$2
     AND revoked_at IS NULL RETURNING id`, [sessionId, userId]);
  if (!result.rowCount) throw new HttpError(404,"SESSION_NOT_FOUND","Session not found.");
  await auditAccount(userId,"account.session_revoked");
}

async function sensitiveAccount<T>(
  userId: string, password: string,
  run: (client: import("pg").PoolClient) => Promise<T>,
) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await client.query(
      `SELECT password_hash FROM users WHERE id=$1 AND account_status='active'
       FOR UPDATE`, [userId]);
    if (!result.rowCount || !await verifyPassword(password,result.rows[0].password_hash)) {
      throw new HttpError(403,"PASSWORD_MISMATCH","The current password is incorrect.");
    }
    const value = await run(client);
    await client.query("COMMIT");
    return value;
  } catch (error) { await client.query("ROLLBACK"); throw error; }
  finally { client.release(); }
}

export async function changeAccountPassword(
  userId: string, currentSessionId: string, currentPassword: string, newPassword: string,
) {
  const passwordHash = await hashPassword(newPassword);
  const revoked = await sensitiveAccount(userId,currentPassword,async client => {
    await client.query(
      "UPDATE users SET password_hash=$2,updated_at=now() WHERE id=$1",
      [userId,passwordHash]);
    const sessions = await client.query(
      `UPDATE user_sessions SET revoked_at=now() WHERE user_id=$1 AND id<>$2
       AND revoked_at IS NULL RETURNING id`,[userId,currentSessionId]);
    await client.query(
      `UPDATE verification_requests SET consumed_at=now()
       WHERE user_id=$1 AND request_type='password_reset' AND consumed_at IS NULL`,
      [userId]);
    await client.query(
      `INSERT INTO audit_logs(actor_id,action,entity_type,entity_id)
       VALUES($1,'account.password_changed','user',$1)`,[userId]);
    return sessions.rows.map(row=>row.id as string);
  });
  return revoked;
}

export async function requestAccountDeletion(userId: string,currentPassword: string) {
  const caps = accountCapabilities();
  if (!caps.deletionAvailable || caps.deletionRetentionDays === null) {
    throw new HttpError(503,"RETENTION_POLICY_NOT_CONFIGURED",
      "The organization must configure the retention policy first.");
  }
  return sensitiveAccount(userId,currentPassword,async client => {
    const result = await client.query(
      `UPDATE users SET account_status='suspended',deletion_requested_at=now(),
       deletion_scheduled_for=now()+($2::int * interval '1 day'),updated_at=now()
       WHERE id=$1 RETURNING deletion_requested_at AS "requestedAt",
       deletion_scheduled_for AS "scheduledFor"`,
      [userId,caps.deletionRetentionDays]);
    const sessions = await client.query(
      `UPDATE user_sessions SET revoked_at=now() WHERE user_id=$1
       AND revoked_at IS NULL RETURNING id`,[userId]);
    await client.query(
      `INSERT INTO audit_logs(actor_id,action,entity_type,entity_id)
       VALUES($1,'account.deletion_requested','user',$1)`,[userId]);
    return { ...result.rows[0], sessions: sessions.rows.map(row=>row.id as string) };
  });
}

export async function accountActivity(userId: string,page: number) {
  const result = await pool.query(
    `SELECT id,action,created_at AS "createdAt" FROM audit_logs
     WHERE actor_id=$1 ORDER BY created_at DESC,id DESC LIMIT 21 OFFSET $2`,
    [userId,(page-1)*20]);
  return {items:result.rows.slice(0,20),nextPage:result.rows.length>20?page+1:null};
}

export async function accountItems(userId: string,kind: string,page: number) {
  const offset = (page-1)*20;
  let query: string;
  switch(kind) {
    case "groups":
      query=`SELECT g.id,g.name AS title,g.description AS body,
        gm.joined_at AS "createdAt" FROM community_groups g
        JOIN group_members gm ON gm.group_id=g.id
        WHERE gm.user_id=$1 AND gm.status='active' AND g.status='active'
        ORDER BY gm.joined_at DESC,g.id DESC LIMIT 21 OFFSET $2`; break;
    case "posts": case "contributions":
      query=`SELECT id,body AS title,body,created_at AS "createdAt",id AS "postId"
        FROM community_posts WHERE author_id=$1 AND status='published'
        ORDER BY created_at DESC,id DESC LIMIT 21 OFFSET $2`; break;
    case "comments":
      query=`SELECT id,body AS title,body,created_at AS "createdAt",post_id AS "postId"
        FROM post_comments WHERE author_id=$1 AND status='published'
        ORDER BY created_at DESC,id DESC LIMIT 21 OFFSET $2`; break;
    case "saved":
      query=`SELECT p.id,p.body AS title,p.body,b.created_at AS "createdAt",p.id AS "postId"
        FROM post_bookmarks b JOIN community_posts p ON p.id=b.post_id
        WHERE b.user_id=$1 AND p.status='published'
        ORDER BY b.created_at DESC,p.id DESC LIMIT 21 OFFSET $2`; break;
    case "notifications":
      query=`SELECT id,kind AS title,kind,status,created_at AS "createdAt" FROM
        (SELECT id,kind,CASE WHEN read_at IS NULL THEN 'unread' ELSE 'read' END AS status,
         created_at FROM community_notifications WHERE user_id=$1) n
        ORDER BY created_at DESC,id DESC LIMIT 21 OFFSET $2`; break;
    case "requests":
      query=`SELECT id,title,reference,status,created_at AS "createdAt"
        FROM helpdesk_requests WHERE owner_id=$1
        ORDER BY created_at DESC,id DESC LIMIT 21 OFFSET $2`; break;
    default: throw new HttpError(404,"NOT_FOUND","Account section not found.");
  }
  const result = await pool.query(query,[userId,offset]);
  const items = [];
  for (const row of result.rows.slice(0,20)) {
    if (row.postId && !await canReadPost(userId,row.postId)) continue;
    items.push(row);
  }
  return {items,nextPage:result.rows.length>20?page+1:null};
}

export async function exportAccountData(userId: string,password: string) {
  await sensitiveAccount(userId,password,async()=>true);
  const [profile,sessions,posts,comments,groups,bookmarks,requests,preferences] =
    await Promise.all([
      getUserProfile(userId),
      pool.query(`SELECT id,created_at,last_used_at,expires_at,revoked_at
        FROM user_sessions WHERE user_id=$1`,[userId]),
      pool.query(`SELECT id,body,visibility,status,created_at,updated_at
        FROM community_posts WHERE author_id=$1`,[userId]),
      pool.query(`SELECT id,post_id,body,status,created_at,updated_at
        FROM post_comments WHERE author_id=$1`,[userId]),
      pool.query(`SELECT group_id,role,status,joined_at FROM group_members WHERE user_id=$1`,[userId]),
      pool.query(`SELECT post_id,created_at FROM post_bookmarks WHERE user_id=$1`,[userId]),
      pool.query(`SELECT id,reference,title,description,category,priority,status,created_at
        FROM helpdesk_requests WHERE owner_id=$1`,[userId]),
      pool.query(`SELECT * FROM notification_preferences WHERE user_id=$1`,[userId]),
    ]);
  await auditAccount(userId,"account.data_exported");
  return {
    exportedAt:new Date().toISOString(),profile,sessions:sessions.rows,
    authoredPosts:posts.rows,authoredComments:comments.rows,groups:groups.rows,
    savedPosts:bookmarks.rows,helpDeskRequests:requests.rows,
    notificationPreferences:preferences.rows[0]??{},
    scope:"Account metadata and authored content; excludes other members, internal notes, credentials and binary attachments.",
  };
}
