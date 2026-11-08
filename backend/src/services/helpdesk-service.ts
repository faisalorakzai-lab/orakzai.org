import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";
import { access,audit,canReopen,capabilities,changeStatus,notify,requestColumns,
  requestJoins,requireManager,requireStaff,transaction,type Status } from "./helpdesk-core.js";

export type RequestInput = {
  title:string; category:string; description:string; priority:string; region:string;
  district:string; qoum:string; village:string; contactPreference:string;
};
export async function createRequest(userId: string, input: RequestInput) {
  const id = await transaction(async (db,pending) => {
    const result = await db.query(`INSERT INTO helpdesk_requests
      (owner_id,title,category,description,priority,region,district,qoum,village,contact_preference)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *`,
      [userId,input.title,input.category,input.description,input.priority,input.region,
        input.district,input.qoum,input.village,input.contactPreference]);
    const r = result.rows[0];
    await db.query(`INSERT INTO helpdesk_status_history(request_id,to_status,actor_id)
      VALUES($1,'submitted',$2)`,[r.id,userId]);
    await audit(db,userId,r.id,"submitted");
    await notify(db,pending,userId,r,"helpdesk_submitted");
    return r.id as string;
  });
  return getRequest(userId,id);
}
export async function getRequest(userId:string,id:string) {
  const a = await access(pool,userId,id);
  const result = await pool.query(`SELECT ${requestColumns},r.description,r.region,r.district,
    r.qoum,r.village,r.contact_preference AS "contactPreference",
    EXISTS(SELECT 1 FROM helpdesk_request_mutes m WHERE m.request_id=r.id AND m.user_id=$2) AS muted
    FROM helpdesk_requests r ${requestJoins} WHERE r.id=$1`,[id,userId]);
  let contact: {email?:string;phone?:string} | undefined;
  if (a.staff) {
    const owner = await pool.query(`SELECT email,phone FROM users WHERE id=$1`,[a.request.owner_id]);
    if (owner.rows[0]) contact = a.request.contact_preference === "email" ? {email:owner.rows[0].email}
      : a.request.contact_preference === "phone" ? {phone:owner.rows[0].phone} : {};
  }
  return {...result.rows[0],canReopen:canReopen(a.request),canManage:a.manage,canStaffReply:a.staff,contact};
}
export async function listRequests(userId:string, admin:boolean, filters:Record<string,any>) {
  const c = await capabilities(pool,userId);
  if (admin && !c.manage && !c.agent) throw new HttpError(403,"HELPDESK_FORBIDDEN","Support access is required.");
  const args:unknown[] = [userId];
  const where = [admin ? c.manage ? "$1::uuid IS NOT NULL" : "r.assigned_to=$1" : "r.owner_id=$1"];
  for (const key of ["category","priority","status"] as const) {
    if (filters[key]) { args.push(filters[key]); where.push(`r.${key}=$${args.length}`); }
  }
  if (filters.search) {
    args.push(`%${String(filters.search).replace(/[\\%_]/g,"\\$&")}%`);
    where.push(`(r.reference ILIKE $${args.length} OR r.title ILIKE $${args.length})`);
  }
  const predicate = where.join(" AND ");
  const count = await pool.query(`SELECT count(*)::int AS total FROM helpdesk_requests r WHERE ${predicate}`,args);
  args.push(filters.limit,filters.offset);
  const result = await pool.query(`SELECT ${requestColumns} FROM helpdesk_requests r ${requestJoins}
    WHERE ${predicate} ORDER BY r.created_at DESC,r.id DESC LIMIT $${args.length-1} OFFSET $${args.length}`,args);
  return {items:result.rows,total:count.rows[0].total,limit:filters.limit,offset:filters.offset};
}
export async function dashboard(userId:string) {
  const stats = await pool.query(`SELECT count(*)::int AS total,
    count(*) FILTER(WHERE status IN ('submitted','under_review','assigned','waiting_for_member'))::int AS pending,
    count(*) FILTER(WHERE status='in_progress')::int AS "inProgress",
    count(*) FILTER(WHERE status='resolved' OR (status='closed' AND resolved_at IS NOT NULL))::int AS resolved
    FROM helpdesk_requests WHERE owner_id=$1`,[userId]);
  const preference = await pool.query(`SELECT helpdesk_updates AS enabled FROM notification_preferences WHERE user_id=$1`,[userId]);
  return {stats:stats.rows[0],capabilities:await capabilities(pool,userId),notificationsEnabled:preference.rows[0]?.enabled ?? true};
}
export async function track(userId:string,reference:string) {
  const found = await pool.query(`SELECT id FROM helpdesk_requests WHERE reference=$1`,[reference.toUpperCase()]);
  if (!found.rows[0]) throw new HttpError(404,"REQUEST_NOT_FOUND","The request was not found.");
  return getRequest(userId,found.rows[0].id);
}
export async function reopen(userId:string,id:string) {
  await transaction(async (db,pending) => {
    const a = await access(db,userId,id,true);
    if (a.request.owner_id !== userId) throw new HttpError(403,"HELPDESK_FORBIDDEN","Only the request owner can use member reopen.");
    if (!canReopen(a.request)) throw new HttpError(409,"REOPEN_NOT_ALLOWED","Only a request resolved within the last seven days can be reopened.");
    await changeStatus(db,pending,userId,a.request,"in_progress","Reopened by member.");
  });
  return getRequest(userId,id);
}
export async function setStatus(userId:string,id:string,status:Status,reason:string) {
  await transaction(async (db,pending) => {
    const a = await access(db,userId,id,true); requireStaff(a);
    await changeStatus(db,pending,userId,a.request,status,reason);
  });
  return getRequest(userId,id);
}
export async function assign(userId:string,id:string,staffId:string,departmentId:string) {
  await transaction(async (db,pending) => {
    await requireManager(db,userId);
    const a = await access(db,userId,id,true);
    if (["resolved","closed","rejected"].includes(a.request.status)) throw new HttpError(409,"REQUEST_FINAL","Reopen an eligible request before assignment.");
    const candidate = await db.query(`SELECT 1 FROM users WHERE id=$1 AND account_status='active'
      AND email_verified_at IS NOT NULL`,[staffId]);
    const staff = await capabilities(db,staffId);
    const department = await db.query(`SELECT 1 FROM helpdesk_departments WHERE id=$1 AND active=true`,[departmentId]);
    if (!candidate.rowCount || (!staff.agent && !staff.manage) || !department.rowCount || staffId === a.request.owner_id)
      throw new HttpError(400,"INVALID_ASSIGNMENT","Choose an active support staff member and department; owners cannot be assigned their own case.");
    await db.query(`UPDATE helpdesk_requests SET assigned_to=$2,department_id=$3,updated_at=now() WHERE id=$1`,[id,staffId,departmentId]);
    await db.query(`INSERT INTO helpdesk_request_assignments(request_id,staff_id,department_id,assigned_by)
      VALUES($1,$2,$3,$4)`,[id,staffId,departmentId,userId]);
    a.request.assigned_to=staffId;
    if (["submitted","under_review"].includes(a.request.status))
      await changeStatus(db,pending,userId,a.request,"assigned","Assigned to support staff.");
    await audit(db,userId,id,"assigned",{staffId,departmentId});
    await notify(db,pending,userId,a.request,"helpdesk_assigned");
  });
  return getRequest(userId,id);
}
export async function staffDirectory(userId:string) {
  await requireManager(pool,userId);
  const staff = await pool.query(`SELECT DISTINCT u.id,p.full_name AS name FROM users u
    JOIN user_profiles p ON p.user_id=u.id JOIN user_roles ur ON ur.user_id=u.id
    JOIN role_permissions rp ON rp.role_id=ur.role_id JOIN permissions pm ON pm.id=rp.permission_id
    WHERE pm.key IN ('helpdesk:agent','helpdesk:manage') AND u.account_status='active'
    AND u.email_verified_at IS NOT NULL ORDER BY name,u.id LIMIT 500`);
  return staff.rows;
}
export async function preferences(userId:string,enabled:boolean) {
  await pool.query(`INSERT INTO notification_preferences(user_id,helpdesk_updates) VALUES($1,$2)
    ON CONFLICT(user_id) DO UPDATE SET helpdesk_updates=$2,updated_at=now()`,[userId,enabled]);
  return {enabled};
}
export async function notifications(userId:string,limit:number,offset:number) {
  const c=await capabilities(pool,userId);
  const where=`n.user_id=$1 AND n.entity_type='helpdesk_request' AND n.kind LIKE 'helpdesk_%'
    AND (r.owner_id=$1 OR $2::boolean OR ($3::boolean AND r.assigned_to=$1))`;
  const args=[userId,c.manage,c.agent];
  const result=await pool.query(`SELECT n.id,n.kind,n.entity_id AS "requestId",
    n.read_at AS "readAt",n.created_at AS "createdAt" FROM community_notifications n
    JOIN helpdesk_requests r ON r.id=n.entity_id WHERE ${where}
    ORDER BY n.created_at DESC,n.id DESC LIMIT $4 OFFSET $5`,[...args,limit,offset]);
  const count=await pool.query(`SELECT count(*)::int AS total FROM community_notifications n
    JOIN helpdesk_requests r ON r.id=n.entity_id WHERE ${where}`,args);
  return {items:result.rows,total:count.rows[0].total,limit,offset};
}
export async function readNotification(userId:string,notificationId:string) {
  return transaction(async db=>{
    const n=await db.query(`SELECT entity_id FROM community_notifications
      WHERE id=$1 AND user_id=$2 AND entity_type='helpdesk_request' AND kind LIKE 'helpdesk_%'`,[notificationId,userId]);
    if(!n.rows[0]) throw new HttpError(404,"NOTIFICATION_NOT_FOUND","The update was not found.");
    await access(db,userId,n.rows[0].entity_id,true);
    await db.query(`UPDATE community_notifications SET read_at=COALESCE(read_at,now()) WHERE id=$1 AND user_id=$2`,[notificationId,userId]);
    return {read:true};
  });
}
export async function mute(userId:string,id:string,muted:boolean) {
  await transaction(async db => {
    await access(db,userId,id,true);
    if (muted) await db.query(`INSERT INTO helpdesk_request_mutes(user_id,request_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[userId,id]);
    else await db.query(`DELETE FROM helpdesk_request_mutes WHERE user_id=$1 AND request_id=$2`,[userId,id]);
  });
  return {muted};
}
