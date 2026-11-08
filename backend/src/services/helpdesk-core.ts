import type { Pool, PoolClient } from "pg";
import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";
import { publishNotification } from "../realtime.js";

export type Db = Pool | PoolClient;
export const categories = ["general_inquiry","technical_support","education_assistance",
  "healthcare_assistance","employment_assistance","business_support","social_welfare",
  "membership_support","complaints","emergency_assistance","other"] as const;
export const statuses = ["submitted","under_review","assigned","in_progress",
  "waiting_for_member","resolved","closed","rejected"] as const;
export type Status = typeof statuses[number];
export const transitions: Record<Status, Status[]> = {
  submitted: ["under_review","assigned","rejected"],
  under_review: ["assigned","in_progress","waiting_for_member","resolved","rejected"],
  assigned: ["under_review","in_progress","waiting_for_member","resolved","rejected"],
  in_progress: ["waiting_for_member","resolved","rejected"],
  waiting_for_member: ["in_progress","resolved","rejected"],
  resolved: ["in_progress","closed"], closed: [], rejected: ["closed"],
};
export async function capabilities(db: Db, userId: string) {
  const result = await db.query(
    `SELECT p.key FROM user_roles ur JOIN role_permissions rp ON rp.role_id=ur.role_id
     JOIN permissions p ON p.id=rp.permission_id WHERE ur.user_id=$1
     AND p.key IN ('helpdesk:manage','helpdesk:agent')`, [userId]);
  const keys = result.rows.map(r => r.key);
  return { manage: keys.includes("helpdesk:manage"), agent: keys.includes("helpdesk:agent") };
}
export async function access(db: Db, userId: string, id: string, lock = false) {
  const found = await db.query(`SELECT * FROM helpdesk_requests WHERE id=$1 ${lock ? "FOR UPDATE" : ""}`, [id]);
  const r = found.rows[0];
  const c = await capabilities(db, userId);
  if (!r || !(r.owner_id === userId || c.manage || (c.agent && r.assigned_to === userId))) {
    throw new HttpError(404, "REQUEST_NOT_FOUND", "The request was not found.");
  }
  return { request: r, ...c, staff: c.manage || (c.agent && r.assigned_to === userId && r.owner_id !== userId) };
}
export function requireStaff(a: { staff: boolean }) {
  if (!a.staff) throw new HttpError(403, "HELPDESK_FORBIDDEN", "Authorized assigned support staff are required.");
}
export async function requireManager(db: Db, userId: string) {
  if (!(await capabilities(db,userId)).manage) throw new HttpError(403,"HELPDESK_FORBIDDEN","A Help Desk manager is required.");
}
export async function audit(db: Db, userId: string, id: string, action: string, metadata = {}) {
  await db.query(`INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,metadata)
    VALUES($1,$2,'helpdesk_request',$3,$4)`,[userId,`helpdesk.${action}`,id,JSON.stringify(metadata)]);
}
export type PendingNotification = { userId: string; notification: unknown };
export async function notify(db: Db, pending: PendingNotification[], actor: string, r: Record<string,any>, kind: string) {
  const recipients = [...new Set([r.owner_id,r.assigned_to].filter(Boolean))];
  for (const recipient of recipients) {
    const result = await db.query(
      `INSERT INTO community_notifications(user_id,actor_id,kind,entity_type,entity_id)
       SELECT $1,$2,$3,'helpdesk_request',$4
       WHERE COALESCE((SELECT helpdesk_updates FROM notification_preferences WHERE user_id=$1),true)
       AND NOT EXISTS(SELECT 1 FROM helpdesk_request_mutes WHERE user_id=$1 AND request_id=$4)
       RETURNING id,kind,entity_type AS "entityType",entity_id AS "entityId",created_at AS "createdAt"`,
      [recipient,actor,kind,r.id]);
    if (result.rows[0]) pending.push({userId:recipient,notification:result.rows[0]});
  }
}
export async function transaction<T>(work: (db: PoolClient, pending: PendingNotification[]) => Promise<T>): Promise<T> {
  const db = await pool.connect();
  const pending: PendingNotification[] = [];
  let value: T;
  try {
    await db.query("BEGIN");
    value = await work(db,pending);
    await db.query("COMMIT");
  } catch (error) { await db.query("ROLLBACK"); throw error; }
  finally { db.release(); }
  for (const event of pending) publishNotification(event.userId,event.notification);
  return value;
}
export function canReopen(r: Record<string,any>): boolean {
  return r.status === "resolved" && r.resolved_at != null
    && Date.now() - new Date(r.resolved_at).getTime() <= 7*24*60*60*1000;
}
export async function changeStatus(db: PoolClient, pending: PendingNotification[], userId: string,
  r: Record<string,any>, status: Status, reason: string) {
  if (status === "assigned" && !r.assigned_to)
    throw new HttpError(409,"ASSIGNMENT_REQUIRED","Assign a support agent before using Assigned status.");
  if (!(transitions[r.status as Status] ?? []).includes(status) ||
      (r.status === "resolved" && status === "in_progress" && !canReopen(r))) {
    throw new HttpError(409,"INVALID_TRANSITION","This status change is not allowed by the request policy.");
  }
  await db.query(`UPDATE helpdesk_requests SET status=$2,updated_at=now(),
    resolved_at=CASE WHEN $2='resolved' THEN now() WHEN $2='in_progress' THEN NULL ELSE resolved_at END
    WHERE id=$1`, [r.id,status]);
  await db.query(`INSERT INTO helpdesk_status_history(request_id,from_status,to_status,actor_id,reason)
    VALUES($1,$2,$3,$4,$5)`,[r.id,r.status,status,userId,reason]);
  await audit(db,userId,r.id,"status.changed",{from:r.status,to:status});
  r.status = status;
  await notify(db,pending,userId,r,status === "resolved" ? "helpdesk_resolved" : status === "closed" ? "helpdesk_closed" : "helpdesk_status");
}
export const requestColumns = `r.id,r.reference,r.title,r.category,r.priority,r.status,
  r.owner_id AS "ownerId",r.department_id AS "departmentId",d.name AS "departmentName",
  r.assigned_to AS "assignedTo",p.full_name AS "assignedName",
  r.created_at AS "createdAt",r.updated_at AS "updatedAt",r.resolved_at AS "resolvedAt"`;
export const requestJoins = `LEFT JOIN helpdesk_departments d ON d.id=r.department_id
  LEFT JOIN user_profiles p ON p.user_id=r.assigned_to`;
