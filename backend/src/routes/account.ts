import { Router } from "express";
import express from "express";
import rateLimit from "express-rate-limit";
import { z } from "zod";
import { requireAuth } from "../middleware/authenticate.js";
import { HttpError } from "../http/errors.js";
import { pool } from "../db/pool.js";
import { getNotificationPreferences,updateNotificationPreferences,listNotifications,
  notificationPreferenceKeys,unblockUser,listBlockedUsers } from "../services/safety-service.js";
import { accountActivity,accountItems,activeSessions,auditAccount,
  changeAccountPassword,exportAccountData,requestAccountDeletion,
 } from "../services/account-service.js";
import { readAvatar,removeAvatar,storeAvatar } from "../services/avatar-service.js";
import { disconnectSessionSockets } from "../realtime.js";

const router=Router();
router.use(requireAuth);
const credentialRateLimit=rateLimit({
  windowMs:15*60_000,
  limit:process.env.NODE_ENV==="test"?100:8,
  standardHeaders:true,
  legacyHeaders:false,
});
const avatarRateLimit=rateLimit({
  windowMs:60*60_000,
  limit:process.env.NODE_ENV==="test"?100:8,
  standardHeaders:true,
  legacyHeaders:false,
});
function actor(req:{auth?:{userId:string;sessionId:string}}) {
  if(!req.auth) throw new HttpError(401,"UNAUTHENTICATED","Please sign in.");
  return req.auth;
}
const currentPassword=z.string().min(1).max(128);
const positivePage=z.coerce.number().int().min(1).max(50_000).default(1);

router.get("/sessions",async(req,res)=>{
  const auth=actor(req);
  res.set("Cache-Control","private, no-store")
    .json({items:await activeSessions(auth.userId,auth.sessionId)});
});
router.delete("/sessions/:id",async(req,res)=>{
  const auth=actor(req);
  const result=await pool.query(
    "SELECT user_id FROM user_sessions WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL",
    [req.params.id,auth.userId]);
  if(!result.rowCount) throw new HttpError(404,"SESSION_NOT_FOUND","Session not found.");
  await pool.query("UPDATE user_sessions SET revoked_at=now() WHERE id=$1 AND user_id=$2",
    [req.params.id,auth.userId]);
  await disconnectSessionSockets(req.params.id);
  await auditAccount(auth.userId,"account.session_revoked");
  res.json({current:req.params.id===auth.sessionId});
});

router.post("/change-password",credentialRateLimit,async(req,res)=>{
  const body=z.object({
    currentPassword,newPassword:z.string().min(12).max(128)
      .regex(/[A-Za-z]/).regex(/\d/),
  }).strict().safeParse(req.body);
  if(!body.success) throw new HttpError(400,"VALIDATION_ERROR","Use at least 12 characters with a letter and a number.");
  const auth=actor(req);
  const revoked=await changeAccountPassword(auth.userId,auth.sessionId,
    body.data.currentPassword,body.data.newPassword);
  for(const sessionId of revoked) await disconnectSessionSockets(sessionId);
  res.json({changed:true,otherSessionsRevoked:revoked.length});
});
router.post("/delete-account",credentialRateLimit,async(req,res)=>{
  const body=z.object({currentPassword,confirmation:z.literal(true)}).strict().safeParse(req.body);
  if(!body.success) throw new HttpError(400,"VALIDATION_ERROR","Confirm deletion and enter your current password.");
  const auth=actor(req);
  const {sessions,...result}=await requestAccountDeletion(auth.userId,body.data.currentPassword);
  for(const sessionId of sessions) await disconnectSessionSockets(sessionId);
  res.set("Cache-Control","no-store").json(result);
});
router.post("/data-export",credentialRateLimit,async(req,res)=>{
  const body=z.object({currentPassword}).strict().safeParse(req.body);
  if(!body.success) throw new HttpError(400,"VALIDATION_ERROR","Enter your current password.");
  res.set("Cache-Control","private, no-store")
    .json(await exportAccountData(actor(req).userId,body.data.currentPassword));
});
router.get("/activity",async(req,res)=>{
  const page=positivePage.safeParse(req.query.page);
  if(!page.success) throw new HttpError(400,"INVALID_PAGE","Page number is invalid.");
  res.set("Cache-Control","private, no-store")
    .json(await accountActivity(actor(req).userId,page.data));
});
router.get("/community/:kind",async(req,res)=>{
  if(!["groups","posts","comments","saved","contributions","notifications","requests"].includes(req.params.kind))
    throw new HttpError(404,"NOT_FOUND","Account section not found.");
  const page=positivePage.safeParse(req.query.page);
  if(!page.success) throw new HttpError(400,"INVALID_PAGE","Page number is invalid.");
  const userId=actor(req).userId,kind=req.params.kind;
  if(kind==="notifications") {
    const rows=await listNotifications(userId,Math.min(100,page.data*20+20));
    const start=(page.data-1)*20,items=rows.slice(start,start+20);
    res.set("Cache-Control","private, no-store").json({
      items,nextPage:rows.length>start+20?page.data+1:null});
    return;
  }
  res.set("Cache-Control","private, no-store")
    .json(await accountItems(userId,kind,page.data));
});
router.get("/notification-preferences",async(req,res)=>{
  res.set("Cache-Control","private, no-store")
    .json({preferences:await getNotificationPreferences(actor(req).userId)});
});
router.patch("/notification-preferences",async(req,res)=>{
  const schema=z.object(Object.fromEntries(
    notificationPreferenceKeys().map(key=>[key,z.boolean().optional()]),
  )).strict().refine(value=>Object.values(value).some(v=>v!==undefined));
  const body=schema.safeParse(req.body);
  if(!body.success) throw new HttpError(400,"VALIDATION_ERROR","Notification choices are invalid.");
  res.json({preferences:await updateNotificationPreferences(actor(req).userId,body.data)});
});
router.get("/blocked-users",async(req,res)=>{
  res.set("Cache-Control","private, no-store")
    .json({items:await listBlockedUsers(actor(req).userId)});
});
router.delete("/blocked-users/:id",async(req,res)=>{
  const userId=actor(req).userId;
  await unblockUser(userId,req.params.id);
  await auditAccount(userId,"account.user_unblocked");
  res.json({unblocked:true});
});
router.post("/photo",avatarRateLimit,expressRawPng(),async(req,res)=>{
  const auth=actor(req);
  if(!Buffer.isBuffer(req.body)) throw new HttpError(400,"INVALID_AVATAR","Upload a cropped PNG.");
  await storeAvatar(auth.userId,req.body);
  res.status(201).json({uploaded:true});
});
router.delete("/photo",async(req,res)=>{
  const result=await removeAvatar(actor(req).userId);
  await auditAccount(actor(req).userId,"profile.photo_removed");
  res.json(result);
});
router.get("/photo",async(req,res)=>{
  const image=await readAvatar(actor(req).userId);
  res.set({"Content-Type":"image/png","Cache-Control":"private, no-store",
    "X-Content-Type-Options":"nosniff"}).send(image);
});

function expressRawPng(){return express.raw({type:"image/png",limit:"5mb"});}
export default router;
