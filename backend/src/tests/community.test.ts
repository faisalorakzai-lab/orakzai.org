import { randomUUID } from "node:crypto";
import { unlink } from "node:fs/promises";
import { resolve } from "node:path";

import request from "supertest";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { config } from "../config.js";
import { createApp } from "../app.js";
import { pool } from "../db/pool.js";
import { runMigrations } from "../db/migrate.js";

const app = createApp();
type TestMember = { id: string; token: string; email: string };
const createdUserIds: string[] = [];
const uploadedMediaIds: string[] = [];
let owner: TestMember;
let member: TestMember;
let groupId = "";
let conversationId = "";
let directConversationId = "";

async function createVerifiedMember(name: string): Promise<TestMember> {
  const suffix = randomUUID().replaceAll("-", "").slice(0, 12);
  const email = `community-${suffix}@example.invalid`;
  const phone = `+1${Array.from(suffix, (character) => parseInt(character, 16) % 10)
    .join("")
    .slice(0, 10)}`;
  const password = "OrakzaiCommunityTest123";
  const registered = await request(app).post("/api/auth/register").send({
    fullName: name,
    email,
    phone,
    password,
    country: 'Pakistan',
    acceptedTerms: true,
  });
  expect(registered.status).toBe(201);

  const resend = await request(app)
    .post("/api/auth/resend-verification")
    .send({ email });
  expect(resend.status).toBe(202);
  const verified = await request(app)
    .post("/api/auth/verify-email")
    .send({ email, code: resend.body.devVerificationCode });
  expect(verified.status).toBe(200);

  const login = await request(app)
    .post("/api/auth/login")
    .send({ identifier: email, password });
  expect(login.status).toBe(200);
  const token = login.body.accessToken as string;
  const profile = await request(app)
    .get("/api/users/me")
    .set("Authorization", `Bearer ${token}`);
  expect(profile.status).toBe(200);
  const id = profile.body.user.id as string;
  createdUserIds.push(id);
  return { id, token, email };
}

beforeAll(async () => {
  await runMigrations();
  owner = await createVerifiedMember("Community Group Owner");
  member = await createVerifiedMember("Community Group Member");
});

afterAll(async () => {
  for (const mediaId of uploadedMediaIds) {
    await unlink(resolve(config.communityMediaStorageDir, `${mediaId}.png`)).catch(
      () => undefined,
    );
  }
  if (createdUserIds.length > 0) {
    await pool.query(
      `DELETE FROM conversations
       WHERE group_id IS NULL
         AND id IN (
           SELECT conversation_id FROM conversation_members
           WHERE user_id = ANY($1::uuid[])
         )`,
      [createdUserIds],
    );
    await pool.query(
      "DELETE FROM community_groups WHERE owner_id = ANY($1::uuid[])",
      [createdUserIds],
    );
    await pool.query("DELETE FROM users WHERE id = ANY($1::uuid[])", [createdUserIds]);
  }
  await pool.end();
});

describe("community, groups, messaging and private media", () => {
  it("requires authentication for community endpoints", async () => {
    const response = await request(app).get("/api/community/feed");
    expect(response.status).toBe(401);
    expect((await request(app).get("/api/community/summary")).status).toBe(401);
  });

  it("computes Home totals from authorized posts and active memberships without leaking private records", async () => {
    const summary = async (who: TestMember) => {
      const res = await request(app).get("/api/community/summary")
        .set("Authorization", `Bearer ${who.token}`);
      expect(res.status).toBe(200);
      expect(res.headers["cache-control"]).toBe("private, no-store");
      expect(res.body.scope).toBe("authorized_user");
      return res.body;
    };
    const beforeOwner = await summary(owner);
    const beforeMember = await summary(member);
    const ids: string[] = [];
    let temporaryGroupId: string | undefined;
    try {
      const group = await request(app).post("/api/community/groups")
        .set("Authorization", `Bearer ${owner.token}`).send({
          name: "Temporary Home count verification", description: "Automated test fixture",
          category: "general", visibility: "private",
        });
      expect(group.status).toBe(201);
      temporaryGroupId = group.body.id;
      expect((await summary(owner)).joinedGroups).toBe(beforeOwner.joinedGroups + 1);
      expect((await summary(member)).joinedGroups).toBe(beforeMember.joinedGroups);
      await pool.query(
        "INSERT INTO group_members(group_id,user_id,role,status) VALUES($1,$2,'member','active')",
        [temporaryGroupId,member.id]);
      expect((await summary(member)).joinedGroups).toBe(beforeMember.joinedGroups + 1);
      await pool.query("UPDATE group_members SET status='left' WHERE group_id=$1 AND user_id=$2",
        [temporaryGroupId,member.id]);
      expect((await summary(member)).joinedGroups).toBe(beforeMember.joinedGroups);
      const fixture = await pool.query(
        `INSERT INTO community_posts(author_id,body,visibility,is_announcement)
         VALUES ($1,'Temporary private Home summary verification','private',true) RETURNING id`, [owner.id]);
      ids.push(fixture.rows[0].id);
      expect((await summary(owner)).accessiblePosts).toBe(beforeOwner.accessiblePosts + 1);
      expect((await summary(owner)).accessibleAnnouncements).toBe(beforeOwner.accessibleAnnouncements + 1);
      expect((await summary(member)).accessiblePosts).toBe(beforeMember.accessiblePosts);
      expect((await summary(member)).accessibleAnnouncements).toBe(beforeMember.accessibleAnnouncements);
      const published = await pool.query(
        `INSERT INTO community_posts(author_id,body,visibility,is_announcement)
         VALUES ($1,'Temporary public Home summary verification','public',false) RETURNING id`, [owner.id]);
      ids.push(published.rows[0].id);
      expect((await summary(member)).accessiblePosts).toBe(beforeMember.accessiblePosts + 1);
      await pool.query("INSERT INTO user_blocks(blocker_id,blocked_id) VALUES($1,$2)", [member.id,owner.id]);
      expect((await summary(member)).accessiblePosts).toBe(beforeMember.accessiblePosts);
      await pool.query("DELETE FROM user_blocks WHERE blocker_id=$1 AND blocked_id=$2",[member.id,owner.id]);
      await pool.query("UPDATE community_posts SET status='removed' WHERE id=ANY($1::uuid[])",[ids]);
      expect((await summary(owner)).accessiblePosts).toBe(beforeOwner.accessiblePosts);
      expect((await summary(member)).accessiblePosts).toBe(beforeMember.accessiblePosts);
      const expectedGroups = await pool.query(
        `SELECT count(*)::int AS n FROM group_members gm JOIN community_groups g ON g.id=gm.group_id
         WHERE gm.user_id=$1 AND gm.status='active' AND g.status='active'`,[member.id]);
      expect((await summary(member)).joinedGroups).toBe(expectedGroups.rows[0].n);
    } finally {
      await pool.query("DELETE FROM user_blocks WHERE blocker_id=$1 AND blocked_id=$2",[member.id,owner.id]);
      await pool.query("DELETE FROM community_posts WHERE id=ANY($1::uuid[])",[ids]);
      if (temporaryGroupId) await pool.query("DELETE FROM community_groups WHERE id=$1",[temporaryGroupId]);
    }
  });

  it("keeps private group content hidden until an invitation is accepted", async () => {
    const created = await request(app)
      .post("/api/community/groups")
      .set("Authorization", `Bearer ${owner.token}`)
      .send({
        name: "Community Test Group",
        description: "A private group created by the community API test.",
        category: "general",
        visibility: "private",
      });
    expect(created.status).toBe(201);
    groupId = created.body.id;
    expect(groupId).toBeTruthy();
    conversationId = created.body.conversationId;

    const hiddenGroup = await request(app)
      .get(`/api/community/groups/${groupId}`)
      .set("Authorization", `Bearer ${member.token}`);
    expect(hiddenGroup.status).toBe(404);

    const invite = await request(app)
      .post(`/api/community/groups/${groupId}/invite`)
      .set("Authorization", `Bearer ${owner.token}`)
      .send({ inviteeId: member.id });
    expect(invite.status).toBe(201);

    const invitations = await request(app)
      .get("/api/community/groups/invitations")
      .set("Authorization", `Bearer ${member.token}`);
    expect(invitations.status).toBe(200);
    const invitation = invitations.body.invitations.find(
      (item: { groupId: string }) => item.groupId === groupId,
    );
    expect(invitation).toBeTruthy();

    const accepted = await request(app)
      .post(`/api/community/invitations/${invitation.id}/respond`)
      .set("Authorization", `Bearer ${member.token}`)
      .send({ accept: true });
    expect(accepted.status).toBe(200);

    const visibleGroup = await request(app)
      .get(`/api/community/groups/${groupId}`)
      .set("Authorization", `Bearer ${member.token}`);
    expect(visibleGroup.status).toBe(200);
    expect(visibleGroup.body.myStatus).toBe("active");
    conversationId = visibleGroup.body.conversationId;
    expect(conversationId).toBeTruthy();
  });

  it("sends group messages and records delivered/read receipts", async () => {
    const sent = await request(app)
      .post(`/api/messages/conversations/${conversationId}/messages`)
      .set("Authorization", `Bearer ${owner.token}`)
      .send({ body: "This is a real group-message integration test." });
    expect([200, 201]).toContain(sent.status);
    const message = sent.body.message ?? sent.body;
    expect(message.id).toBeTruthy();
    expect(message.body).toContain("real group-message");

    const memberMessages = await request(app)
      .get(`/api/messages/conversations/${conversationId}/messages`)
      .set("Authorization", `Bearer ${member.token}`);
    expect(memberMessages.status).toBe(200);
    expect(memberMessages.body.messages.some(
      (item: { id: string }) => item.id === message.id,
    )).toBe(true);

    const read = await request(app)
      .post(`/api/messages/conversations/${conversationId}/read`)
      .set("Authorization", `Bearer ${member.token}`)
      .send({});
    expect(read.status).toBe(200);
    const receipt = await pool.query(
      `SELECT delivered_at, read_at
       FROM message_read_receipts WHERE message_id = $1 AND user_id = $2`,
      [message.id, member.id],
    );
    expect(receipt.rows).toHaveLength(1);
    expect(receipt.rows[0].delivered_at).toBeTruthy();
    expect(receipt.rows[0].read_at).toBeTruthy();

    const ownerMessages = await request(app)
      .get(`/api/messages/conversations/${conversationId}/messages`)
      .set("Authorization", `Bearer ${owner.token}`);
    const readMessage = ownerMessages.body.messages.find(
      (item: { id: string }) => item.id === message.id,
    );
    expect(readMessage.status).toBe("read");

    const direct = await request(app)
      .post("/api/messages/conversations")
      .set("Authorization", `Bearer ${owner.token}`)
      .send({ recipientId: member.id });
    expect(direct.status).toBe(201);
    directConversationId = direct.body.id;
    expect(directConversationId).toBeTruthy();

    const forwarded = await request(app)
      .post(`/api/messages/conversations/${conversationId}/messages/${message.id}/forward`)
      .set("Authorization", `Bearer ${owner.token}`)
      .send({
        targetConversationId: directConversationId,
        clientNonce: randomUUID(),
      });
    expect(forwarded.status).toBe(201);
    expect(forwarded.body.message.forwardedFromMessageId).toBe(message.id);

    const directMessages = await request(app)
      .get(`/api/messages/conversations/${directConversationId}/messages`)
      .set("Authorization", `Bearer ${member.token}`);
    expect(directMessages.status).toBe(200);
    expect(directMessages.body.messages.some(
      (item: { forwardedFromMessageId?: string }) =>
        item.forwardedFromMessageId === message.id,
    )).toBe(true);

    const searched = await request(app)
      .get("/api/messages/conversations?search=real%20group-message")
      .set("Authorization", `Bearer ${member.token}`);
    expect(searched.status).toBe(200);
    expect(searched.body.conversations.some(
      (item: { id: string }) => item.id === conversationId,
    )).toBe(true);
  });

  it("enforces post visibility and accepts visible reactions and replies", async () => {
    const privatePost = await request(app)
      .post("/api/community/posts")
      .set("Authorization", `Bearer ${owner.token}`)
      .send({ body: "Only the author can see this post.", visibility: "private" });
    expect(privatePost.status, JSON.stringify(privatePost.body)).toBe(201);
    const privatePostId = privatePost.body.id;
    expect(privatePostId).toBeTruthy();

    const hiddenPost = await request(app)
      .get(`/api/community/posts/${privatePostId}`)
      .set("Authorization", `Bearer ${member.token}`);
    expect(hiddenPost.status).toBe(404);

    const publicPost = await request(app)
      .post("/api/community/posts")
      .set("Authorization", `Bearer ${owner.token}`)
      .send({ body: "A public community post for integration testing.", visibility: "public" });
    expect(publicPost.status, JSON.stringify(publicPost.body)).toBe(201);

    const visible = await request(app)
      .get(`/api/community/posts/${publicPost.body.id}`)
      .set("Authorization", `Bearer ${member.token}`);
    expect(visible.status).toBe(200);

    const comment = await request(app)
      .post(`/api/community/posts/${publicPost.body.id}/comments`)
      .set("Authorization", `Bearer ${member.token}`)
      .send({ body: "A verified member can reply to this visible post." });
    expect(comment.status).toBe(201);

    const reaction = await request(app)
      .post(`/api/community/posts/${publicPost.body.id}/reactions`)
      .set("Authorization", `Bearer ${member.token}`)
      .send({ reaction: "support" });
    expect(reaction.status).toBe(200);

    const unauthorizedModeration = await request(app)
      .get("/api/moderation/reports")
      .set("Authorization", `Bearer ${member.token}`);
    expect(unauthorizedModeration.status).toBe(403);
  });

  it("keeps uploaded files private and requires an expiring, user-bound access URL", async () => {
    const png = Buffer.from("89504e470d0a1a0a0000000049454e44ae426082", "hex");
    const uploaded = await request(app)
      .post("/api/media/upload")
      .set("Authorization", `Bearer ${owner.token}`)
      .attach("file", png, { filename: "private-test.png", contentType: "image/png" });
    expect(uploaded.status).toBe(201);
    const media = uploaded.body.media;
    uploadedMediaIds.push(media.id);
    expect(media.contentType).toBe("image/png");

    const ownerAccess = await request(app)
      .get(`/api/media/${media.id}/access`)
      .set("Authorization", `Bearer ${owner.token}`);
    expect(ownerAccess.status).toBe(200);
    expect(ownerAccess.body.signature).toBeTruthy();

    const content = await request(app)
      .get(`/api${ownerAccess.body.path}?expires=${ownerAccess.body.expires}&signature=${ownerAccess.body.signature}`)
      .set("Authorization", `Bearer ${owner.token}`);
    expect(content.status).toBe(200);
    expect(content.headers["content-type"]).toContain("image/png");

    const otherMemberAccess = await request(app)
      .get(`/api/media/${media.id}/access`)
      .set("Authorization", `Bearer ${member.token}`);
    expect(otherMemberAccess.status).toBe(404);
  });
});
