import { randomUUID } from "node:crypto";
import { mkdir,readFile,unlink,writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { inflateSync } from "node:zlib";
import { config } from "../config.js";
import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";

const crcTable = Array.from({length:256},(_,i)=>{
  let n=i; for(let bit=0;bit<8;bit++) n=(n&1)?0xedb88320^(n>>>1):n>>>1;
  return n>>>0;
});
function crc32(bytes:Buffer) {
  let crc=0xffffffff;
  for(const byte of bytes) crc=(crc>>>8)^crcTable[(crc^byte)&255]!;
  return (crc^0xffffffff)>>>0;
}

/** Native cropper produces a bounded, non-interlaced 8-bit RGB/RGBA PNG. */
export function validateAvatar(buffer:Buffer) {
  const invalid=()=>new HttpError(400,"INVALID_AVATAR","Choose a valid cropped PNG image.");
  if(buffer.length<45||buffer.length>5*1024*1024||
    !buffer.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw invalid();
  let offset=8,width=0,height=0,channels=0,ended=false;
  const data:Buffer[]=[];
  while(offset+12<=buffer.length) {
    const length=buffer.readUInt32BE(offset);
    if(length>buffer.length-offset-12) throw invalid();
    const type=buffer.toString("ascii",offset+4,offset+8);
    const chunk=buffer.subarray(offset+8,offset+8+length);
    if(crc32(buffer.subarray(offset+4,offset+8+length))!==buffer.readUInt32BE(offset+8+length)) throw invalid();
    if(offset===8&&type!=="IHDR") throw invalid();
    if(type==="IHDR") {
      if(width||length!==13) throw invalid();
      width=chunk.readUInt32BE(0);height=chunk.readUInt32BE(4);
      channels=chunk[9]===6?4:chunk[9]===2?3:0;
      if(!width||!height||width>2048||height>2048||chunk[8]!==8||!channels||
        chunk[10]!==0||chunk[11]!==0||chunk[12]!==0) throw invalid();
    } else if(type==="IDAT") data.push(chunk);
    else if(type==="IEND") {
      if(length!==0||offset+12!==buffer.length) throw invalid();
      ended=true;break;
    } else if(type==="acTL"||type==="fcTL"||type==="fdAT") throw invalid();
    offset+=12+length;
  }
  if(!ended||!data.length) throw invalid();
  let decoded:Buffer;
  try { decoded=inflateSync(Buffer.concat(data),{maxOutputLength:17*1024*1024}); }
  catch { throw invalid(); }
  const stride=width*channels+1;
  if(decoded.length!==stride*height) throw invalid();
  for(let row=0;row<height;row++) if(decoded[row*stride]!>4) throw invalid();
  return {width,height};
}

function storageAvailable() {
  if(config.nodeEnv==="production"||config.communityMediaProvider!=="local-development") {
    throw new HttpError(503,"MEDIA_STORAGE_NOT_CONFIGURED","Private profile storage is not configured.");
  }
}
function filePath(key:string) {
  if(!/^[a-f0-9-]{36}\.png$/.test(key)) throw new HttpError(404,"PHOTO_NOT_FOUND","Photo not found.");
  return resolve(config.communityMediaStorageDir,"avatars",key);
}

export async function storeAvatar(userId:string,bytes:Buffer) {
  storageAvailable();validateAvatar(bytes);
  const directory=resolve(config.communityMediaStorageDir,"avatars");
  await mkdir(directory,{recursive:true,mode:0o700});
  const key=`${randomUUID()}.png`;
  await writeFile(filePath(key),bytes,{mode:0o600,flag:"wx"});
  const client=await pool.connect();
  let old:string|null=null;
  try {
    await client.query("BEGIN");
    const current=await client.query(
      "SELECT avatar_storage_key FROM user_profiles WHERE user_id=$1 FOR UPDATE",[userId]);
    old=current.rows[0]?.avatar_storage_key??null;
    await client.query(`UPDATE user_profiles SET avatar_storage_key=$2,
      profile_photo_url=NULL,updated_at=now() WHERE user_id=$1`,[userId,key]);
    await client.query(`INSERT INTO audit_logs(actor_id,action,entity_type,entity_id)
      VALUES($1,'profile.photo_updated','user',$1)`,[userId]);
    await client.query("COMMIT");
  } catch(error) {
    await client.query("ROLLBACK");
    await unlink(filePath(key)).catch(()=>{});
    throw error;
  } finally { client.release(); }
  if(old) await unlink(filePath(old)).catch(()=>{});
}

export async function readAvatar(userId:string) {
  storageAvailable();
  const result=await pool.query(
    "SELECT avatar_storage_key FROM user_profiles WHERE user_id=$1",[userId]);
  const key=result.rows[0]?.avatar_storage_key as string|null;
  if(!key) throw new HttpError(404,"PHOTO_NOT_FOUND","Photo not found.");
  try { return await readFile(filePath(key)); }
  catch { throw new HttpError(404,"PHOTO_NOT_FOUND","Photo not found."); }
}

export async function removeAvatar(userId:string) {
  const result=await pool.query(`UPDATE user_profiles SET avatar_storage_key=NULL,
    profile_photo_url=NULL,updated_at=now() WHERE user_id=$1
    RETURNING user_id`,[userId]);
  return {removed:result.rowCount===1};
}
