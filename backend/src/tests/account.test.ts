import {randomUUID} from "node:crypto";
import request from "supertest";
import {afterAll,beforeAll,describe,expect,it} from "vitest";
import {createApp} from "../app.js";
import {pool} from "../db/pool.js";
import {runMigrations} from "../db/migrate.js";

const app=createApp();
const suffix=randomUUID().replaceAll("-","").slice(0,12);
const email=`account-${suffix}@example.invalid`;
const phone=`+1${Array.from(suffix,c=>parseInt(c,16)%10).join("").slice(0,10)}`;
const password="AccountAuditPass2026";
let userId="",token="";

beforeAll(async()=>{
  await runMigrations();
  const registered=await request(app).post("/api/auth/register").send({
    fullName:"Account Endpoint Test",email,phone,password,country:"Pakistan",
    region:"Test Region",district:"Test District",acceptedTerms:true,
  });
  expect(registered.status).toBe(201);
  const resend=await request(app).post("/api/auth/resend-verification").send({email});
  expect(resend.status).toBe(202);
  expect(resend.body.devVerificationCode).toMatch(/^\d{6}$/);
  const verified=await request(app).post("/api/auth/verify-email").send({
    email,code:resend.body.devVerificationCode,
  });
  expect(verified.status).toBe(200);
  const login=await request(app).post("/api/auth/login")
    .send({identifier:email,password});
  expect(login.status).toBe(200);
  token=login.body.accessToken;
  const profile=await request(app).get("/api/users/me")
    .set("Authorization",`Bearer ${token}`);
  userId=profile.body.user.id;
},60_000);

afterAll(async()=>{
  if(email)await pool.query("DELETE FROM users WHERE email=$1",[email]);
  await pool.end();
});

const auth=()=>({Authorization:`Bearer ${token}`});

describe("authenticated account dashboard and privacy",()=>{
  it("reports only integrations actually available",async()=>{
    const response=await request(app).get("/api/auth/capabilities");
    expect(response.status).toBe(200);
    expect(response.body.developmentMode).toBe(true);
    expect(response.body.providers).toEqual({
      google:false,apple:false,wallet:false,
    });
    expect(response.body.membershipAvailable).toBe(false);
    expect(response.body.applicationsAvailable).toBe(false);
  });

  it("returns private session metadata but never session credentials",async()=>{
    const response=await request(app).get("/api/users/me/sessions").set(auth());
    expect(response.status).toBe(200);
    expect(response.body.items).toHaveLength(1);
    expect(response.body.items[0].isCurrent).toBe(true);
    const serialized=JSON.stringify(response.body);
    expect(serialized).not.toMatch(/refresh.?token|access.?token|password.?hash/i);
  });

  it("persists self-reported locations without creating regional grants",async()=>{
    const result=await request(app).patch("/api/users/me").set(auth()).send({
      qoum:"Test Qoum",village:"Test Village",
    });
    expect(result.status).toBe(200);
    expect(result.body.user.profile.qoum).toBe("Test Qoum");
    expect(result.body.user.profile.village).toBe("Test Village");
    const grants=await pool.query(
      "SELECT id FROM user_region_assignments WHERE user_id=$1",[userId]);
    expect(grants.rows).toEqual([]);
  });

  it("serves owner-only pages with explicit pagination and no fake records",async()=>{
    for(const kind of ["groups","posts","comments","saved","contributions","requests"]){
      const response=await request(app).get(`/api/users/me/community/${kind}?page=1`).set(auth());
      expect(response.status).toBe(200);
      expect(response.body.items).toEqual([]);
      expect(response.body.nextPage).toBeNull();
    }
    const activity=await request(app).get("/api/users/me/activity?page=1").set(auth());
    expect(activity.status).toBe(200);
    expect(activity.body.items).toBeInstanceOf(Array);
  });

  it("refuses invalid photos instead of storing unverified bytes",async()=>{
    const response=await request(app).post("/api/users/me/photo")
      .set(auth()).set("Content-Type","image/png").send(Buffer.from("not a png"));
    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("INVALID_AVATAR");
  });

  it("does not invalidate an account session for a wrong password",async()=>{
    const rejected=await request(app).post("/api/users/me/change-password")
      .set(auth()).send({currentPassword:"IncorrectCurrent2026",newPassword:"NewAccountSecure2026"});
    expect(rejected.status).toBe(403);
    expect(rejected.body.error.code).toBe("PASSWORD_MISMATCH");
    const sessions=await request(app).get("/api/users/me/sessions").set(auth());
    expect(sessions.status).toBe(200);
  });

  it("requires confirmation and correct credentials before deletion",async()=>{
    const wrongPassword=await request(app).post("/api/users/me/delete-account")
      .set(auth()).send({currentPassword:"IncorrectCurrent2026",confirmation:true});
    expect(wrongPassword.status).toBe(403);
    const missingConfirmation=await request(app).post("/api/users/me/delete-account")
      .set(auth()).send({currentPassword:password});
    expect(missingConfirmation.status).toBe(400);
    const sessions=await request(app).get("/api/users/me/sessions").set(auth());
    expect(sessions.status).toBe(200);
    expect(sessions.body.items[0].isCurrent).toBe(true);
  });

  it("does not accept profile edits that could claim organization membership",async()=>{
    const response=await request(app).patch("/api/users/me")
      .set(auth()).send({memberId:"ORZ-000001",membershipStatus:"approved"});
    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("VALIDATION_ERROR");
    expect(userId).toMatch(/^[0-9a-f-]{36}$/);
  });
});
