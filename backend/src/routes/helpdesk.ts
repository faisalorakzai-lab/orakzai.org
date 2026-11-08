import { Router,type Request } from "express";
import rateLimit from "express-rate-limit";
import multer from "multer";
import { z } from "zod";
import { pool } from "../db/pool.js";
import { requireAuth } from "../middleware/authenticate.js";
import { HttpError } from "../http/errors.js";
import { access,audit,categories,requireManager,statuses,transaction } from "../services/helpdesk-core.js";
import * as service from "../services/helpdesk-service.js";
import * as conversation from "../services/helpdesk-conversation.js";
import * as storage from "../services/helpdesk-storage.js";

const router=Router();
router.use(requireAuth);
const rateResponse={error:{code:"RATE_LIMITED",message:"Too many Help Desk requests. Please try again later."}};
router.use(rateLimit({windowMs:60_000,limit:process.env.NODE_ENV==="test"?2000:180,
  standardHeaders:true,legacyHeaders:false,message:rateResponse}));
const limiter=rateLimit({windowMs:60_000,limit:process.env.NODE_ENV==="test"?500:30,
  standardHeaders:true,legacyHeaders:false,message:rateResponse});
router.use((req,res,next)=> { if(["POST","PATCH"].includes(req.method)) limiter(req,res,next); else next(); });
const upload=multer({storage:multer.memoryStorage(),limits:{fileSize:25*1024*1024,files:1,fields:0}});
const uuid=z.string().uuid();
function parse<T>(schema:z.ZodType<T>,value:unknown):T {
  const parsed=schema.safeParse(value);
  if(!parsed.success) throw new HttpError(400,"VALIDATION_ERROR",parsed.error.issues[0]?.message??"Invalid request.");
  return parsed.data;
}
const user=(req:Request)=>req.auth!.userId;
const id=(req:Request)=>parse(uuid,req.params.id);
const pageSchema=z.object({limit:z.coerce.number().int().min(1).max(100).default(20),offset:z.coerce.number().int().min(0).max(100000).default(0)});
const filtersSchema=pageSchema.extend({category:z.enum(categories).optional(),priority:z.enum(["low","normal","high","urgent"]).optional(),
  status:z.enum(statuses).optional(),search:z.string().trim().max(160).optional()});
const text=(min:number,max:number)=>z.string().trim().min(min).max(max);
const requestSchema=z.object({title:text(5,160),category:z.enum(categories),description:text(20,10000),
  priority:z.enum(["low","normal","high","urgent"]).default("normal"),region:text(2,100),
  district:text(0,100).default(""),qoum:text(0,100).default(""),village:text(0,100).default(""),
  contactPreference:z.enum(["in_app","email","phone"]).default("in_app")}).strict();
const messageSchema=z.object({body:text(1,10000),attachmentIds:z.array(uuid).max(10).default([]),
  requestDocuments:z.boolean().default(false)}).strict().refine(v=>new Set(v.attachmentIds).size===v.attachmentIds.length,"Duplicate attachment IDs.");

router.get("/home",async(req,res)=>res.json(await service.dashboard(user(req))));
router.get("/notifications",async(req,res)=>{
  const p=parse(pageSchema,req.query);res.json(await service.notifications(user(req),p.limit,p.offset));
});
router.post("/notifications/:notificationId/read",async(req,res)=>
  res.json(await service.readNotification(user(req),parse(uuid,req.params.notificationId))));
router.get("/metadata",(_req,res)=>res.json({categories,statuses,priorities:["low","normal","high","urgent"],reopenDays:7}));
router.patch("/preferences",async(req,res)=>{
  const b=parse(z.object({enabled:z.boolean()}).strict(),req.body);
  res.json(await service.preferences(user(req),b.enabled));
});
router.get("/departments",async(_req,res)=>res.json({items:(await pool.query(`SELECT id,name FROM helpdesk_departments WHERE active ORDER BY name`)).rows}));
router.get("/requests",async(req,res)=>res.json(await service.listRequests(user(req),false,parse(filtersSchema,req.query))));
router.post("/requests",async(req,res)=>res.status(201).json({request:await service.createRequest(user(req),parse(requestSchema,req.body))}));
router.get("/track/:reference",async(req,res)=>res.json({request:await service.track(user(req),parse(text(1,100),req.params.reference))}));
router.get("/requests/:id",async(req,res)=>res.json({request:await service.getRequest(user(req),id(req))}));
router.patch("/requests/:id",async(req,res)=>{
  parse(z.object({action:z.literal("reopen")}).strict(),req.body);
  res.json({request:await service.reopen(user(req),id(req))});
});
router.patch("/requests/:id/preferences",async(req,res)=>{
  const b=parse(z.object({muted:z.boolean()}).strict(),req.body);
  res.json(await service.mute(user(req),id(req),b.muted));
});
router.get("/requests/:id/history",async(req,res)=>{
  const p=parse(pageSchema,req.query); res.json(await conversation.history(user(req),id(req),p.limit,p.offset));
});
router.get("/requests/:id/messages",async(req,res)=>{
  const p=parse(pageSchema,req.query); res.json(await conversation.messages(user(req),id(req),p.limit,p.offset));
});
router.post("/requests/:id/messages",async(req,res)=>{
  const b=parse(messageSchema,req.body);
  if(b.requestDocuments) throw new HttpError(403,"HELPDESK_FORBIDDEN","Only assigned staff may request documents.");
  res.status(201).json({message:await conversation.reply(user(req),id(req),b.body,false,b.attachmentIds,false)});
});
router.post("/requests/:id/messages/read",async(req,res)=>{
  const b=parse(z.object({messageIds:z.array(uuid).min(1).max(100)}).strict()
    .refine(v=>new Set(v.messageIds).size===v.messageIds.length,"Duplicate message IDs."),req.body);
  res.json(await conversation.markRead(user(req),id(req),b.messageIds));
});
router.get("/requests/:id/attachments",async(req,res)=>{
  const p=parse(pageSchema,req.query); res.json(await storage.attachments(user(req),id(req),p.limit,p.offset));
});
router.post("/requests/:id/attachments",async(req,res,next)=>{
  await access(pool,user(req),id(req));
  upload.single("file")(req,res,(error)=>{
    if(error) { next(new HttpError(error.code==="LIMIT_FILE_SIZE"?413:400,"UPLOAD_INVALID","Choose one supported file up to 25 MB.")); return; }
    if(!req.file) { next(new HttpError(400,"FILE_REQUIRED","Choose a file.")); return; }
    void storage.uploadAttachment(user(req),id(req),req.file)
      .then(attachment=>res.status(201).json({attachment})).catch(next);
  });
});
router.get("/requests/:id/attachments/:attachmentId/content",async(req,res)=>{
  const {file,buffer}=await storage.attachmentContent(user(req),id(req),parse(uuid,req.params.attachmentId));
  res.setHeader("Content-Type",file.contentType);
  res.setHeader("Content-Disposition",`attachment; filename="attachment"; filename*=UTF-8''${encodeURIComponent(file.name)}`);
  res.setHeader("Cache-Control","private, no-store");
  res.setHeader("X-Content-Type-Options","nosniff");
  res.send(buffer);
});
router.get("/admin/requests",async(req,res)=>res.json(await service.listRequests(user(req),true,parse(filtersSchema,req.query))));
router.get("/admin/staff",async(req,res)=>res.json({items:await service.staffDirectory(user(req))}));
router.post("/admin/requests/:id/assign",async(req,res)=>{
  const b=parse(z.object({staffId:uuid,departmentId:uuid}).strict(),req.body);
  res.json({request:await service.assign(user(req),id(req),b.staffId,b.departmentId)});
});
router.patch("/admin/requests/:id/status",async(req,res)=>{
  const b=parse(z.object({status:z.enum(statuses),reason:text(0,2000).default("")}).strict(),req.body);
  res.json({request:await service.setStatus(user(req),id(req),b.status,b.reason)});
});
router.post("/admin/requests/:id/reply",async(req,res)=>{
  const b=parse(messageSchema,req.body);
  res.status(201).json({message:await conversation.reply(user(req),id(req),b.body,true,b.attachmentIds,b.requestDocuments)});
});
router.get("/admin/requests/:id/notes",async(req,res)=>{
  const p=parse(pageSchema,req.query); res.json(await conversation.notes(user(req),id(req),p.limit,p.offset));
});
router.post("/admin/requests/:id/notes",async(req,res)=>{
  const b=parse(z.object({body:text(1,10000)}).strict(),req.body);
  res.status(201).json({note:await conversation.addNote(user(req),id(req),b.body)});
});
router.post("/admin/departments",async(req,res)=>{
  const b=parse(z.object({name:text(2,100)}).strict(),req.body);
  await requireManager(pool,user(req));
  const result=await pool.query(`INSERT INTO helpdesk_departments(name) VALUES($1)
    ON CONFLICT(name) DO UPDATE SET active=true RETURNING id,name`,[b.name]);
  await audit(pool,user(req),result.rows[0].id,"department.saved");
  res.status(201).json({department:result.rows[0]});
});
for(const kind of ["faqs","announcements"] as const) {
  const table=kind==="faqs"?"helpdesk_faqs":"helpdesk_announcements";
  router.get(`/${kind}`,async(req,res)=>{
    const p=parse(pageSchema,req.query);
    const items=await pool.query(`SELECT id,${kind==="faqs"?"question,answer":"title,body"},created_at AS "createdAt"
      FROM ${table} WHERE published ORDER BY created_at DESC,id DESC LIMIT $1 OFFSET $2`,[p.limit,p.offset]);
    const total=await pool.query(`SELECT count(*)::int AS total FROM ${table} WHERE published`);
    res.json({items:items.rows,total:total.rows[0].total,...p});
  });
  router.post(`/admin/${kind}`,async(req,res)=>{
    const b=parse(z.object({title:text(5,kind==="faqs"?200:160),body:text(10,10000)}).strict(),req.body);
    const item=await transaction(async db=>{
      await requireManager(db,user(req));
      const result=await db.query(`INSERT INTO ${table}(${kind==="faqs"?"question,answer":"title,body"},created_by)
        VALUES($1,$2,$3) RETURNING id`,[b.title,b.body,user(req)]);
      await audit(db,user(req),result.rows[0].id,`${kind}.published`);
      return result.rows[0];
    });
    res.status(201).json({item});
  });
}
export default router;
