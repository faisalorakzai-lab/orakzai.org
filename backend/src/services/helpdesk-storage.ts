import { createHash,randomUUID } from "node:crypto";
import { mkdir,readFile,unlink,writeFile } from "node:fs/promises";
import { basename,resolve } from "node:path";
import { config } from "../config.js";
import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";
import { access,audit,transaction } from "./helpdesk-core.js";
import { detectFile } from "./media-service.js";

export const attachmentColumns = `id,original_name AS name,content_type AS "contentType",
  byte_size::int AS "byteSize",uploaded_by AS "uploadedBy",message_id AS "messageId",created_at AS "createdAt"`;
function storageReady() {
  if (config.nodeEnv === "production" || config.communityMediaProvider !== "local-development")
    throw new HttpError(503,"PRIVATE_STORAGE_NOT_CONFIGURED","Production Help Desk private storage is not configured.");
}
const directory = () => resolve(config.communityMediaStorageDir,"helpdesk");
export async function uploadAttachment(userId:string,id:string,file:{buffer:Buffer;originalname:string;mimetype:string}) {
  storageReady();
  if (!file.buffer.length || file.buffer.length > Math.min(config.communityMaxUploadBytes,25*1024*1024))
    throw new HttpError(413,"ATTACHMENT_SIZE_INVALID","Choose a nonempty file up to 25 MB.");
  const detected = detectFile(file.buffer,file.originalname,file.mimetype);
  const attachmentId = randomUUID();
  const key = `${attachmentId}${detected.extension}`;
  const name = basename(file.originalname.replaceAll("\\","/")).replace(/[\u0000-\u001f\u007f]/g,"").trim().slice(0,255) || `attachment${detected.extension}`;
  const path = resolve(directory(),key);
  let written = false;
  try {
    return await transaction(async db => {
      const a = await access(db,userId,id,true);
      if (["resolved","closed","rejected"].includes(a.request.status))
        throw new HttpError(409,"REQUEST_FINAL","This request does not currently accept attachments.");
      await mkdir(directory(),{recursive:true,mode:0o700});
      await writeFile(path,file.buffer,{flag:"wx",mode:0o600}); written=true;
      const result = await db.query(`INSERT INTO helpdesk_request_attachments
        (id,request_id,uploaded_by,original_name,storage_key,content_type,byte_size,sha256)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING ${attachmentColumns}`,
        [attachmentId,id,userId,name,key,detected.contentType,file.buffer.length,createHash("sha256").update(file.buffer).digest("hex")]);
      await audit(db,userId,id,"attachment.uploaded",{attachmentId});
      return result.rows[0];
    });
  } catch(error) { if(written) await unlink(path).catch(()=>undefined); throw error; }
}
export async function attachments(userId:string,id:string,limit:number,offset:number) {
  await access(pool,userId,id);
  const result = await pool.query(`SELECT ${attachmentColumns} FROM helpdesk_request_attachments
    WHERE request_id=$1 ORDER BY created_at DESC,id DESC LIMIT $2 OFFSET $3`,[id,limit,offset]);
  const count = await pool.query(`SELECT count(*)::int AS total FROM helpdesk_request_attachments WHERE request_id=$1`,[id]);
  return {items:result.rows,total:count.rows[0].total,limit,offset};
}
export async function attachmentContent(userId:string,id:string,attachmentId:string) {
  storageReady();
  return transaction(async db => {
    await access(db,userId,id,true);
    const result = await db.query(`SELECT ${attachmentColumns},storage_key AS key
      FROM helpdesk_request_attachments WHERE request_id=$1 AND id=$2`,[id,attachmentId]);
    const file = result.rows[0];
    if (!file || !/^[a-f0-9-]{36}\.[a-z0-9]+$/.test(file.key))
      throw new HttpError(404,"ATTACHMENT_NOT_FOUND","The file was not found.");
    let buffer:Buffer;
    try { buffer = await readFile(resolve(directory(),file.key)); }
    catch { throw new HttpError(404,"ATTACHMENT_UNAVAILABLE","The stored file is unavailable; contact support."); }
    await audit(db,userId,id,"attachment.downloaded",{attachmentId});
    return {file,buffer};
  });
}
