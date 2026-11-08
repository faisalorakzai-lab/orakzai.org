import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";
import { access,audit,changeStatus,notify,requireStaff,transaction } from "./helpdesk-core.js";

export async function messages(userId:string,id:string,limit:number,offset:number) {
  await access(pool,userId,id);
  const result = await pool.query(`SELECT m.id,m.body,m.is_staff AS "isStaff",m.author_id AS "authorId",
    p.full_name AS "authorName",m.requests_documents AS "requestsDocuments",m.created_at AS "createdAt",
    EXISTS(SELECT 1 FROM helpdesk_message_reads rr WHERE rr.message_id=m.id AND rr.user_id<>m.author_id) AS read,
    COALESCE((SELECT json_agg(json_build_object('id',a.id,'name',a.original_name,'contentType',a.content_type,'byteSize',a.byte_size))
      FROM helpdesk_request_attachments a WHERE a.message_id=m.id),'[]'::json) AS attachments
    FROM helpdesk_request_messages m LEFT JOIN user_profiles p ON p.user_id=m.author_id
    WHERE m.request_id=$1 ORDER BY m.created_at DESC,m.id DESC LIMIT $2 OFFSET $3`,[id,limit,offset]);
  const count = await pool.query(`SELECT count(*)::int AS total FROM helpdesk_request_messages WHERE request_id=$1`,[id]);
  return {items:result.rows,total:count.rows[0].total,limit,offset};
}
export async function reply(userId:string,id:string,body:string,isStaff:boolean,attachmentIds:string[],requestDocuments:boolean) {
  return transaction(async (db,pending) => {
    const a = await access(db,userId,id,true);
    if (isStaff) requireStaff(a);
    else if (a.request.owner_id !== userId) throw new HttpError(403,"HELPDESK_FORBIDDEN","Only the owner may send a member reply.");
    if (["resolved","closed","rejected"].includes(a.request.status))
      throw new HttpError(409,"REQUEST_FINAL","This request does not currently accept replies.");
    const message = await db.query(`INSERT INTO helpdesk_request_messages
      (request_id,author_id,is_staff,body,requests_documents) VALUES($1,$2,$3,$4,$5)
      RETURNING id,created_at AS "createdAt"`,[id,userId,isStaff,body,requestDocuments]);
    const messageId = message.rows[0].id;
    if (attachmentIds.length) {
      const attached = await db.query(`UPDATE helpdesk_request_attachments SET message_id=$1
        WHERE id=ANY($2::uuid[]) AND request_id=$3 AND uploaded_by=$4 AND message_id IS NULL RETURNING id`,
        [messageId,attachmentIds,id,userId]);
      if (attached.rowCount !== attachmentIds.length) throw new HttpError(400,"INVALID_ATTACHMENTS","Choose unattached files uploaded by you to this request.");
    }
    if (requestDocuments && a.request.status !== "waiting_for_member")
      await changeStatus(db,pending,userId,a.request,"waiting_for_member","Additional documents requested.");
    else if (!isStaff && a.request.status === "waiting_for_member")
      await changeStatus(db,pending,userId,a.request,"in_progress","Member replied.");
    await db.query(`UPDATE helpdesk_requests SET updated_at=now() WHERE id=$1`,[id]);
    await audit(db,userId,id,isStaff ? "staff.replied" : "member.replied",{messageId,requestDocuments});
    await notify(db,pending,userId,a.request,requestDocuments ? "helpdesk_documents" : "helpdesk_reply");
    return message.rows[0];
  });
}
export async function markRead(userId:string,id:string,messageIds:string[]) {
  await transaction(async db => {
    await access(db,userId,id,true);
    const allowed = await db.query(`SELECT id FROM helpdesk_request_messages
      WHERE request_id=$1 AND id=ANY($2::uuid[])`,[id,messageIds]);
    if (allowed.rowCount !== messageIds.length) throw new HttpError(400,"INVALID_MESSAGES","Choose messages from this request.");
    await db.query(`INSERT INTO helpdesk_message_reads(message_id,user_id)
      SELECT id,$1 FROM helpdesk_request_messages WHERE request_id=$2 AND id=ANY($3::uuid[])
      ON CONFLICT DO NOTHING`,[userId,id,messageIds]);
  });
  return {read:true};
}
export async function history(userId:string,id:string,limit:number,offset:number) {
  await access(pool,userId,id);
  const events = await pool.query(`SELECT h.id,h.from_status AS "fromStatus",h.to_status AS "toStatus",
    h.reason,h.actor_id AS "actorId",p.full_name AS "actorName",h.created_at AS "createdAt"
    FROM helpdesk_status_history h LEFT JOIN user_profiles p ON p.user_id=h.actor_id
    WHERE h.request_id=$1 ORDER BY h.created_at DESC,h.id DESC LIMIT $2 OFFSET $3`,[id,limit,offset]);
  const count = await pool.query(`SELECT count(*)::int AS total FROM helpdesk_status_history WHERE request_id=$1`,[id]);
  const assignments = await pool.query(`SELECT a.id,a.staff_id AS "staffId",p.full_name AS "staffName",
    d.name AS "departmentName",a.assigned_by AS "assignedBy",a.created_at AS "createdAt"
    FROM helpdesk_request_assignments a LEFT JOIN user_profiles p ON p.user_id=a.staff_id
    JOIN helpdesk_departments d ON d.id=a.department_id WHERE a.request_id=$1
    ORDER BY a.created_at DESC,a.id DESC LIMIT $2 OFFSET $3`,[id,limit,offset]);
  return {items:events.rows,total:count.rows[0].total,assignments:assignments.rows,limit,offset};
}
export async function notes(userId:string,id:string,limit:number,offset:number) {
  requireStaff(await access(pool,userId,id));
  const result = await pool.query(`SELECT n.id,n.body,n.author_id AS "authorId",p.full_name AS "authorName",
    n.created_at AS "createdAt" FROM helpdesk_internal_notes n LEFT JOIN user_profiles p ON p.user_id=n.author_id
    WHERE n.request_id=$1 ORDER BY n.created_at DESC,n.id DESC LIMIT $2 OFFSET $3`,[id,limit,offset]);
  const count = await pool.query(`SELECT count(*)::int AS total FROM helpdesk_internal_notes WHERE request_id=$1`,[id]);
  return {items:result.rows,total:count.rows[0].total,limit,offset};
}
export async function addNote(userId:string,id:string,body:string) {
  return transaction(async db => {
    const a = await access(db,userId,id,true); requireStaff(a);
    const result = await db.query(`INSERT INTO helpdesk_internal_notes(request_id,author_id,body)
      VALUES($1,$2,$3) RETURNING id,created_at AS "createdAt"`,[id,userId,body]);
    await audit(db,userId,id,"note.created",{noteId:result.rows[0].id});
    return result.rows[0];
  });
}
