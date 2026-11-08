import { randomUUID } from "node:crypto";
import { readFile,readdir,unlink } from "node:fs/promises";
import { resolve } from "node:path";
import request from "supertest";
import { afterAll,beforeAll,describe,expect,it } from "vitest";
import { createApp } from "../app.js";
import { config } from "../config.js";
import { pool } from "../db/pool.js";
import { runMigrations } from "../db/migrate.js";
import { createAccessToken,hashOpaqueToken } from "../security.js";
import { canReopen } from "../services/helpdesk-core.js";

const app=createApp();
type Actor={id:string;token:string};
const actors:Actor[]=[];
const files:string[]=[];
const departments:string[]=[];
let member:Actor,other:Actor,manager:Actor,agent:Actor,second:Actor;
let caseId:string,reference:string,departmentId:string,attachmentId:string;
function as(actor:Actor) { return {Authorization:`Bearer ${actor.token}`}; }
const valid={title:"Help Desk integration fixture",category:"technical_support",
  description:"This is a temporary automated integration test, not a real support application.",
  priority:"normal",region:"Test region",district:"",qoum:"",village:"",contactPreference:"in_app"};
function validPdf():Buffer {
  const objects=[
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>",
    "<< /Length 0 >>\nstream\n\nendstream",
  ];
  let text="%PDF-1.4\n";const offsets=[0];
  for(const [i,obj] of objects.entries()){offsets.push(Buffer.byteLength(text));text+=`${i+1} 0 obj\n${obj}\nendobj\n`;}
  const xref=Buffer.byteLength(text);
  text+=`xref\n0 5\n0000000000 65535 f \n${offsets.slice(1).map(n=>`${String(n).padStart(10,"0")} 00000 n \n`).join("")}`;
  return Buffer.from(`${text}trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`);
}
async function actor(role?:string):Promise<Actor> {
  const id=randomUUID(),sid=randomUUID(),suffix=randomUUID().replaceAll("-","");
  await pool.query(`INSERT INTO users(id,email,phone,password_hash,email_verified_at,account_status)
    VALUES($1,$2,$3,'!test-account-no-password-login',now(),'active')`,
    [id,`helpdesk-${suffix}@example.invalid`,`+99${suffix}`]);
  await pool.query(`INSERT INTO user_profiles(user_id,full_name) VALUES($1,'Help Desk automated test')`,[id]);
  await pool.query(`INSERT INTO user_sessions(id,user_id,refresh_token_hash,expires_at)
    VALUES($1,$2,$3,now()+interval '1 hour')`,[sid,id,hashOpaqueToken(randomUUID())]);
  if(role) await pool.query(`INSERT INTO user_roles(user_id,role_id)
    SELECT $1,id FROM roles WHERE slug=$2`,[id,role]);
  const a={id,token:createAccessToken(id,sid)};actors.push(a);return a;
}
beforeAll(async()=>{
  await runMigrations();
  member=await actor("standard_member");other=await actor("standard_member");
  manager=await actor("helpdesk_admin");agent=await actor("support_agent");second=await actor("support_agent");
  departmentId=(await pool.query(`SELECT id FROM helpdesk_departments WHERE active LIMIT 1`)).rows[0].id;
});
afterAll(async()=>{
  for(const f of files) await unlink(f).catch(()=>undefined);
  if(actors.length) {
    const ids=actors.map(a=>a.id);
    await pool.query(`DELETE FROM helpdesk_requests WHERE owner_id=ANY($1::uuid[])`,[ids]);
    await pool.query(`DELETE FROM helpdesk_faqs WHERE created_by=ANY($1::uuid[])`,[ids]);
    await pool.query(`DELETE FROM helpdesk_announcements WHERE created_by=ANY($1::uuid[])`,[ids]);
    if(departments.length) await pool.query(`DELETE FROM helpdesk_departments WHERE id=ANY($1::uuid[])`,[departments]);
    await pool.query(`DELETE FROM audit_logs WHERE actor_id=ANY($1::uuid[])`,[ids]);
    await pool.query(`DELETE FROM users WHERE id=ANY($1::uuid[])`,[ids]);
  }
  await pool.end();
});
describe("Help Desk real PostgreSQL/API authorization",()=>{
  it("requires authenticated verified sessions",async()=>{
    expect((await request(app).get("/api/helpdesk/requests")).status).toBe(401);
    const revoked=await actor();
    await pool.query(`UPDATE user_sessions SET revoked_at=now() WHERE user_id=$1`,[revoked.id]);
    expect((await request(app).get("/api/helpdesk/home").set(as(revoked))).status).toBe(401);
  });
  it("validates request fields and disallows injected ownership/status",async()=>{
    expect((await request(app).post("/api/helpdesk/requests").set(as(member)).send({...valid,title:"x"})).status).toBe(400);
    expect((await request(app).post("/api/helpdesk/requests").set(as(member)).send({...valid,ownerId:other.id})).status).toBe(400);
    expect((await request(app).post("/api/helpdesk/requests").set(as(member)).send({...valid,priority:"critical"})).status).toBe(400);
  });
  it("submits persisted requests with unique database references and truthful statistics",async()=>{
    const created=await request(app).post("/api/helpdesk/requests").set(as(member)).send(valid);
    expect(created.status).toBe(201);caseId=created.body.request.id;reference=created.body.request.reference;
    expect(reference).toMatch(/^ORK-\d{4}-\d+$/);
    const concurrent=await Promise.all(Array.from({length:4},()=>request(app).post("/api/helpdesk/requests").set(as(member)).send(valid)));
    expect(concurrent.every(r=>r.status===201)).toBe(true);
    expect(new Set([reference,...concurrent.map(r=>r.body.request.reference)]).size).toBe(5);
    const home=await request(app).get("/api/helpdesk/home").set(as(member));
    expect(home.body.stats).toEqual({total:5,pending:5,inProgress:0,resolved:0});
    expect((await request(app).get("/api/helpdesk/home").set(as(other))).body.stats.total).toBe(0);
  });
  it("tracks only authorized requests and hides record existence from other members/agents",async()=>{
    expect((await request(app).get(`/api/helpdesk/track/${reference}`).set(as(member))).status).toBe(200);
    for(const who of [other,agent]) {
      expect((await request(app).get(`/api/helpdesk/track/${reference}`).set(as(who))).status).toBe(404);
      expect((await request(app).get(`/api/helpdesk/requests/${caseId}`).set(as(who))).status).toBe(404);
    }
  });
  it("paginates lists and denies member access to staff queue",async()=>{
    const p=await request(app).get("/api/helpdesk/requests?limit=2&offset=2&category=technical_support").set(as(member));
    expect(p.status).toBe(200);expect(p.body.items).toHaveLength(2);expect(p.body.total).toBe(5);
    expect((await request(app).get("/api/helpdesk/requests?limit=0").set(as(member))).status).toBe(400);
    expect((await request(app).get("/api/helpdesk/admin/requests").set(as(member))).status).toBe(403);
    expect((await request(app).get("/api/helpdesk/admin/requests").set(as(manager))).body.total).toBeGreaterThanOrEqual(5);
    expect((await request(app).get("/api/helpdesk/admin/requests").set(as(agent))).body.total).toBe(0);
  });
  it("allows manager assignment, refuses member/agent escalation and invalid candidates",async()=>{
    const route=`/api/helpdesk/admin/requests/${caseId}/assign`;
    for(const who of [member,agent]) expect((await request(app).post(route).set(as(who)).send({staffId:agent.id,departmentId})).status).toBe(403);
    expect((await request(app).post(route).set(as(manager)).send({staffId:other.id,departmentId})).status).toBe(400);
    const assigned=await request(app).post(route).set(as(manager)).send({staffId:agent.id,departmentId});
    expect(assigned.status).toBe(200);expect(assigned.body.request.status).toBe("assigned");
    expect((await request(app).get(`/api/helpdesk/requests/${caseId}`).set(as(agent))).status).toBe(200);
    expect((await request(app).get("/api/helpdesk/admin/requests").set(as(agent))).body.total).toBe(1);
  });
  it("enforces status graph and denies member updates",async()=>{
    const route=`/api/helpdesk/admin/requests/${caseId}/status`;
    expect((await request(app).patch(route).set(as(member)).send({status:"resolved"})).status).toBe(403);
    expect((await request(app).patch(route).set(as(agent)).send({status:"closed"})).status).toBe(409);
    expect((await request(app).patch(route).set(as(agent)).send({status:"in_progress",reason:"Test review started."})).status).toBe(200);
  });
  it("keeps internal notes private in all member surfaces",async()=>{
    const route=`/api/helpdesk/admin/requests/${caseId}/notes`;
    const secret="Private staff-only test note";
    expect((await request(app).post(route).set(as(agent)).send({body:secret})).status).toBe(201);
    for(const who of [member,other,second]) {
      expect((await request(app).get(route).set(as(who))).status).not.toBe(200);
      expect((await request(app).post(route).set(as(who)).send({body:"Unauthorized test note"})).status).not.toBe(201);
    }
    for(const path of [`/requests/${caseId}`,`/requests/${caseId}/messages`,`/requests/${caseId}/history`]) {
      const result=await request(app).get(`/api/helpdesk${path}`).set(as(member));
      expect(result.status).toBe(200);expect(JSON.stringify(result.body)).not.toContain(secret);
    }
  });
  it("supports private replies, requested documents, read receipts and conversation pagination",async()=>{
    const reply=await request(app).post(`/api/helpdesk/admin/requests/${caseId}/reply`).set(as(agent))
      .send({body:"Please provide a supporting document.",requestDocuments:true});
    expect(reply.status).toBe(201);
    expect((await request(app).get(`/api/helpdesk/requests/${caseId}`).set(as(member))).body.request.status).toBe("waiting_for_member");
    const m=await request(app).post(`/api/helpdesk/requests/${caseId}/messages`).set(as(member)).send({body:"My additional information is ready."});
    expect(m.status).toBe(201);
    expect((await request(app).get(`/api/helpdesk/requests/${caseId}`).set(as(member))).body.request.status).toBe("in_progress");
    expect((await request(app).post(`/api/helpdesk/requests/${caseId}/messages/read`).set(as(agent)).send({messageIds:[m.body.message.id]})).status).toBe(200);
    const list=await request(app).get(`/api/helpdesk/requests/${caseId}/messages?limit=1&offset=0`).set(as(member));
    expect(list.body.items).toHaveLength(1);expect(list.body.total).toBe(2);expect(list.body.items[0].read).toBe(true);
    expect((await request(app).get(`/api/helpdesk/requests/${caseId}/messages`).set(as(other))).status).toBe(404);
    expect((await request(app).post(`/api/helpdesk/requests/${caseId}/messages`).set(as(member)).send({body:"Escalate",requestDocuments:true})).status).toBe(403);
  });
  it("validates private attachments and denies unauthorized downloads/cross-request linking",async()=>{
    const route=`/api/helpdesk/requests/${caseId}/attachments`;
    expect((await request(app).post(route).set(as(member)).attach("file",Buffer.from("MZ invalid executable"),{filename:"bad.exe",contentType:"application/octet-stream"})).status).toBe(415);
    expect((await request(app).post(route).set(as(other)).attach("file",Buffer.from("%PDF-1.4\nfixture\n%%EOF"),{filename:"test.pdf",contentType:"application/pdf"})).status).toBe(404);
    const pdf=validPdf();
    const uploaded=await request(app).post(route).set(as(member)).attach("file",pdf,{filename:"support.pdf",contentType:"application/pdf"});
    expect(uploaded.status).toBe(201);attachmentId=uploaded.body.attachment.id;
    files.push(resolve(config.communityMediaStorageDir,"helpdesk",`${attachmentId}.pdf`));
    const content=`${route}/${attachmentId}/content`;
    expect((await request(app).get(content).set(as(other))).status).toBe(404);
    const read=await request(app).get(content).set(as(agent));
    expect(read.status).toBe(200);expect(Buffer.compare(read.body,pdf)).toBe(0);
    expect(read.headers["cache-control"]).toBe("private, no-store");
    const another=await request(app).post("/api/helpdesk/requests").set(as(member)).send(valid);
    expect((await request(app).post(`/api/helpdesk/requests/${another.body.request.id}/messages`).set(as(member))
      .send({body:"Invalid cross-case link",attachmentIds:[attachmentId]})).status).toBe(400);
    const linked=await request(app).post(`/api/helpdesk/requests/${caseId}/messages`).set(as(member)).send({body:"Supporting file attached.",attachmentIds:[attachmentId]});
    expect(linked.status).toBe(201);
  });
  it("honors global notification preferences and request mutes",async()=>{
    await request(app).patch("/api/helpdesk/preferences").set(as(member)).send({enabled:false});
    const count=async()=>Number((await pool.query(`SELECT count(*) FROM community_notifications WHERE user_id=$1 AND entity_id=$2`,[member.id,caseId])).rows[0].count);
    const before=await count();
    await request(app).post(`/api/helpdesk/admin/requests/${caseId}/reply`).set(as(agent)).send({body:"Preference disabled test."});
    expect(await count()).toBe(before);
    await request(app).patch("/api/helpdesk/preferences").set(as(member)).send({enabled:true});
    await request(app).patch(`/api/helpdesk/requests/${caseId}/preferences`).set(as(member)).send({muted:true});
    await request(app).post(`/api/helpdesk/admin/requests/${caseId}/reply`).set(as(agent)).send({body:"Muted case test."});
    expect(await count()).toBe(before);
    await request(app).patch(`/api/helpdesk/requests/${caseId}/preferences`).set(as(member)).send({muted:false});
    await request(app).post(`/api/helpdesk/admin/requests/${caseId}/reply`).set(as(agent)).send({body:"Notifications enabled test."});
    expect(await count()).toBe(before+1);
  });
  it("revokes old agent access immediately after reassignment",async()=>{
    expect((await request(app).post(`/api/helpdesk/admin/requests/${caseId}/assign`).set(as(manager))
      .send({staffId:second.id,departmentId})).status).toBe(200);
    for(const suffix of ["","/messages","/attachments","/history"]) {
      expect((await request(app).get(`/api/helpdesk/requests/${caseId}${suffix}`).set(as(agent))).status).toBe(404);
    }
    expect((await request(app).get(`/api/helpdesk/admin/requests/${caseId}/notes`).set(as(agent))).status).toBe(404);
    expect((await request(app).get(`/api/helpdesk/requests/${caseId}`).set(as(second))).status).toBe(200);
  });
  it("resolves, applies seven-day reopen policy, closes and rejects further replies",async()=>{
    const route=`/api/helpdesk/admin/requests/${caseId}/status`;
    expect((await request(app).patch(route).set(as(second)).send({status:"resolved"})).status).toBe(200);
    expect((await request(app).patch(`/api/helpdesk/requests/${caseId}`).set(as(member)).send({action:"reopen"})).status).toBe(200);
    expect((await request(app).patch(route).set(as(second)).send({status:"resolved"})).status).toBe(200);
    await pool.query(`UPDATE helpdesk_requests SET resolved_at=now()-interval '8 days' WHERE id=$1`,[caseId]);
    expect((await request(app).patch(`/api/helpdesk/requests/${caseId}`).set(as(member)).send({action:"reopen"})).status).toBe(409);
    expect((await request(app).patch(route).set(as(second)).send({status:"closed"})).status).toBe(200);
    expect((await request(app).post(`/api/helpdesk/requests/${caseId}/messages`).set(as(member)).send({body:"Cannot reply to a closed case."})).status).toBe(409);
    expect(canReopen({status:"resolved",resolved_at:null})).toBe(false);
  });
  it("records status/assignment/audit history with responsible actors and indexes/constraints",async()=>{
    const h=await request(app).get(`/api/helpdesk/requests/${caseId}/history?limit=100`).set(as(member));
    expect(h.body.items.some((r:any)=>r.toStatus==="closed" && r.actorId===second.id)).toBe(true);
    expect(h.body.assignments).toHaveLength(2);
    const audit=await pool.query(`SELECT action FROM audit_logs WHERE entity_id=$1`,[caseId]);
    expect(audit.rows.map(r=>r.action)).toContain("helpdesk.attachment.downloaded");
    expect(audit.rows.map(r=>r.action)).toContain("helpdesk.note.created");
    const constraints=await pool.query(`SELECT contype FROM pg_constraint WHERE conrelid='helpdesk_requests'::regclass`);
    expect(constraints.rows.some(r=>r.contype==="u")).toBe(true);
    expect(constraints.rows.some(r=>r.contype==="f")).toBe(true);
    expect((await pool.query(`SELECT 1 FROM pg_indexes WHERE indexname='helpdesk_owner_created_idx'`)).rowCount).toBe(1);
  });
  it("rejects malformed and oversized JSON with consistent errors",async()=>{
    const bad=await request(app).post("/api/helpdesk/requests").set(as(member)).set("Content-Type","application/json").send("{");
    expect(bad.status).toBe(400);expect(bad.body.error.code).toBe("INVALID_JSON");
    const huge=await request(app).post("/api/helpdesk/requests").set(as(member)).send({...valid,description:"a".repeat(70000)});
    expect(huge.status).toBe(413);expect(huge.body.error.code).toBe("REQUEST_TOO_LARGE");
  });
  it("accepts validated image bytes, rejects empty and oversized attachments",async()=>{
    const created=await request(app).post("/api/helpdesk/requests").set(as(member)).send(valid);
    const route=`/api/helpdesk/requests/${created.body.request.id}/attachments`;
    const png=Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZSz8AAAAASUVORK5CYII=","base64");
    const image=await request(app).post(route).set(as(member)).attach("file",png,{filename:"pixel.png",contentType:"image/png"});
    expect(image.status).toBe(201);files.push(resolve(config.communityMediaStorageDir,"helpdesk",`${image.body.attachment.id}.png`));
    expect(image.body.attachment.contentType).toBe("image/png");
    expect((await request(app).post(route).set(as(member)).attach("file",Buffer.alloc(0),{filename:"empty.pdf",contentType:"application/pdf"})).status).toBe(413);
    expect((await request(app).post(route).set(as(member)).attach("file",Buffer.alloc(25*1024*1024+1),{filename:"oversized.pdf",contentType:"application/pdf"})).status).toBe(413);
  });
  it("gates content management and directory access; returns real seeded policy FAQs",async()=>{
    expect((await request(app).get("/api/helpdesk/faqs").set(as(member))).body.items.length).toBeGreaterThanOrEqual(4);
    expect((await request(app).get("/api/helpdesk/admin/staff").set(as(member))).status).toBe(403);
    expect((await request(app).get("/api/helpdesk/admin/staff").set(as(manager))).body.items.some((s:any)=>s.id===agent.id)).toBe(true);
    for(const resource of ["faqs","announcements"]) {
      expect((await request(app).post(`/api/helpdesk/admin/${resource}`).set(as(member))
        .send({title:"Unauthorized content fixture",body:"This should not be published."})).status).toBe(403);
      expect((await request(app).get(`/api/helpdesk/${resource}?limit=1&offset=0`).set(as(member))).status).toBe(200);
    }
  });
  it("does not count a closed rejected case as a successful resolution",async()=>{
    const created=await request(app).post("/api/helpdesk/requests").set(as(other)).send(valid);
    const route=`/api/helpdesk/admin/requests/${created.body.request.id}/status`;
    expect((await request(app).patch(route).set(as(manager)).send({status:"assigned"})).status).toBe(409);
    expect((await request(app).patch(route).set(as(manager)).send({status:"rejected"})).status).toBe(200);
    expect((await request(app).patch(route).set(as(manager)).send({status:"closed"})).status).toBe(200);
    expect((await request(app).get("/api/helpdesk/home").set(as(other))).body.stats.resolved).toBe(0);
  });
  it("lets managers publish real knowledge/routing records without seeded fake announcements",async()=>{
    for(const kind of ["faqs","announcements"]) {
      const created=await request(app).post(`/api/helpdesk/admin/${kind}`).set(as(manager))
        .send({title:"Temporary automated content verification",body:"Temporary integration test content, removed during test cleanup."});
      expect(created.status).toBe(201);
      const listed=await request(app).get(`/api/helpdesk/${kind}?limit=100`).set(as(member));
      expect(listed.body.items.some((i:any)=>i.id===created.body.item.id)).toBe(true);
    }
    const d=await request(app).post("/api/helpdesk/admin/departments").set(as(manager))
      .send({name:`Help Desk test dept ${randomUUID()}`});
    if(d.body.department?.id) departments.push(d.body.department.id);
    expect(d.status).toBe(201);
    expect((await request(app).get("/api/helpdesk/departments").set(as(member))).body.items.some((i:any)=>i.id===d.body.department.id)).toBe(true);
  });
  it("shows private in-app updates only to current authorized recipients and records reads",async()=>{
    const updates=await request(app).get("/api/helpdesk/notifications?limit=1&offset=0").set(as(member));
    expect(updates.status).toBe(200);expect(updates.body.items).toHaveLength(1);
    const n=updates.body.items[0];
    expect(n.kind).toMatch(/^helpdesk_/);
    expect((await request(app).post(`/api/helpdesk/notifications/${n.id}/read`).set(as(other))).status).toBe(404);
    expect((await request(app).post(`/api/helpdesk/notifications/${n.id}/read`).set(as(member))).status).toBe(200);
    expect((await pool.query(`SELECT read_at FROM community_notifications WHERE id=$1`,[n.id])).rows[0].read_at).not.toBeNull();
    const formerAgent=await request(app).get("/api/helpdesk/notifications?limit=100").set(as(agent));
    expect(formerAgent.body.items.every((i:any)=>i.requestId!==caseId)).toBe(true);
  });
  it("refuses destructive rollback when actual support records exist",async()=>{
    const sql=await readFile(resolve(import.meta.dirname,"../../migrations/rollback/0006_helpdesk.sql"),"utf8");
    const guard=sql.match(/DO \$\$[\s\S]*?END \$\$;/)?.[0];
    expect(guard).toBeDefined();
    await expect(pool.query(guard!)).rejects.toThrow("Help Desk contains records");
    expect((await pool.query(`SELECT 1 FROM helpdesk_requests WHERE id=$1`,[caseId])).rowCount).toBe(1);
  });
  it("replays migrations and rollback scripts in an isolated schema without deleting live cases",async()=>{
    const schema=`hd_test_${randomUUID().replaceAll("-","")}`;
    const db=await pool.connect();
    try {
      await db.query(`CREATE SCHEMA "${schema}"`);
      await db.query(`SET search_path TO "${schema}",public`);
      await db.query(`CREATE TABLE app_schema_migrations(name text PRIMARY KEY,applied_at timestamptz DEFAULT now())`);
      const dir=resolve(import.meta.dirname,"../../migrations");
      // Use the actual migration files; no mocked database or migration parser.
      const migrationFiles=(await readdir(dir)).filter(f=>/^\d{4}_[a-z0-9_]+\.sql$/.test(f)).sort();
      expect(migrationFiles.length).toBeGreaterThanOrEqual(7);
      for(const file of migrationFiles) await db.query(await readFile(resolve(dir,file),"utf8"));
      expect((await db.query(`SELECT to_regclass($1) AS table`,[`${schema}.helpdesk_requests`])).rows[0].table).not.toBeNull();
      await db.query(await readFile(resolve(dir,"rollback/0007_helpdesk_guards.sql"),"utf8"));
      await db.query(await readFile(resolve(dir,"0007_helpdesk_guards.sql"),"utf8"));
      await db.query(await readFile(resolve(dir,"rollback/0006_helpdesk.sql"),"utf8"));
      expect((await db.query(`SELECT to_regclass($1) AS table`,[`${schema}.helpdesk_requests`])).rows[0].table).toBeNull();
      expect((await db.query(`SELECT to_regclass('public.helpdesk_requests') AS table`)).rows[0].table).not.toBeNull();
    } finally {
      await db.query("ROLLBACK");
      await db.query("RESET search_path");
      await db.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      db.release();
    }
  });
});
