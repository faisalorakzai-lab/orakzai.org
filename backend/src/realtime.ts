import type { Server as HttpServer } from "node:http";
import { Server, type Socket } from "socket.io";

import { config } from "./config.js";
import { pool } from "./db/pool.js";
import { verifyAccessToken } from "./security.js";
import { HttpError } from "./http/errors.js";
import {
  markConversationRead,
  markMessagesDelivered,
  requireConversationMember,
} from "./services/message-service.js";

type Principal = { userId: string; sessionId: string };
type Ack = (result: { ok: boolean; error?: string }) => void;

let io: Server | null = null;
const socketsByUser = new Map<string, Set<string>>();
const typingAtBySocket = new Map<string, number>();

function presenceRoom(userId: string) {
  return `presence:${userId}`;
}

function conversationRoom(conversationId: string) {
  return `conversation:${conversationId}`;
}

async function validSession(principal: Principal) {
  const result = await pool.query(
    `SELECT 1
     FROM user_sessions s
     JOIN users u ON u.id = s.user_id
     WHERE s.id = $1 AND s.user_id = $2
       AND s.revoked_at IS NULL AND s.expires_at > now()
       AND u.account_status = 'active' AND u.email_verified_at IS NOT NULL`,
    [principal.sessionId, principal.userId],
  );
  return result.rowCount === 1;
}

async function notifyPresence(userId: string, online: boolean) {
  if (!io) return;
  const preference = await pool.query(
    `SELECT show_online_status, share_last_seen, last_seen_at
     FROM user_presence WHERE user_id = $1`,
    [userId],
  );
  const settings = preference.rows[0];
  if (!settings?.show_online_status) return;
  io.to(presenceRoom(userId)).emit("presence:update", {
    userId,
    online,
    ...(settings.share_last_seen && settings.last_seen_at
      ? { lastSeenAt: settings.last_seen_at }
      : {}),
  });
}

async function canWatchPresence(viewerId: string, targetId: string) {
  if (viewerId === targetId) return false;
  const result = await pool.query(
    `SELECT 1
     FROM user_presence presence
     WHERE presence.user_id = $2 AND presence.show_online_status = true
       AND (
         EXISTS (
           SELECT 1 FROM conversation_members a
           JOIN conversation_members b ON b.conversation_id = a.conversation_id
           JOIN conversations c ON c.id = a.conversation_id
           WHERE a.user_id = $1 AND a.left_at IS NULL
             AND b.user_id = $2 AND b.left_at IS NULL
             AND (c.conversation_type <> 'group' OR EXISTS (
               SELECT 1 FROM group_members gm
               WHERE gm.group_id = c.group_id AND gm.user_id = $1 AND gm.status = 'active'
             ))
         )
         OR EXISTS (
           SELECT 1 FROM group_members a
           JOIN group_members b ON b.group_id = a.group_id
           JOIN community_groups g ON g.id = a.group_id AND g.status = 'active'
           WHERE a.user_id = $1 AND a.status = 'active'
             AND b.user_id = $2 AND b.status = 'active'
         )
       )
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks block
         WHERE (block.blocker_id = $1 AND block.blocked_id = $2)
            OR (block.blocker_id = $2 AND block.blocked_id = $1)
       )`,
    [viewerId, targetId],
  );
  return result.rowCount === 1;
}

function sessionPrincipal(socket: Socket): Principal {
  const principal = socket.data.principal as Principal | undefined;
  if (!principal) throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
  return principal;
}

export function attachRealtime(server: HttpServer) {
  if (io) return io;
  io = new Server(server, {
    cors: {
      origin: (origin, callback) => {
        if (!origin || config.corsOrigins.includes(origin)) callback(null, true);
        else callback(new Error("Origin is not allowed."));
      },
    },
    maxHttpBufferSize: 64 * 1024,
    transports: ["websocket", "polling"],
  });

  io.use(async (socket, next) => {
    try {
      const token =
        typeof socket.handshake.auth?.token === "string"
          ? socket.handshake.auth.token
          : socket.handshake.headers.authorization?.replace(/^Bearer\s+/i, "");
      if (!token) return next(new Error("Authentication required."));
      const principal = verifyAccessToken(token);
      if (!(await validSession(principal))) return next(new Error("Session expired."));
      socket.data.principal = principal;
      next();
    } catch {
      next(new Error("Authentication required."));
    }
  });

  io.on("connection", (socket) => {
    const principal = sessionPrincipal(socket);
    const { userId } = principal;
    const userSockets = socketsByUser.get(userId) ?? new Set<string>();
    const wasOffline = userSockets.size === 0;
    userSockets.add(socket.id);
    socketsByUser.set(userId, userSockets);
    socket.join(`user:${userId}`);
    if (wasOffline) void notifyPresence(userId, true);

    const sessionCheck = setInterval(() => {
      void validSession(principal).then((valid) => {
        if (!valid) socket.disconnect(true);
      }).catch(() => socket.disconnect(true));
    }, 15_000);

    socket.on("conversation:join", (payload: unknown, ack?: Ack) => {
      void (async () => {
        try {
          const conversationId = parseIdPayload(payload);
          await requireConversationMember(userId, conversationId);
          await socket.join(conversationRoom(conversationId));
          ack?.({ ok: true });
        } catch {
          ack?.({ ok: false, error: "Conversation unavailable." });
        }
      })();
    });

    socket.on("conversation:leave", (payload: unknown, ack?: Ack) => {
      try {
        const conversationId = parseIdPayload(payload);
        void socket.leave(conversationRoom(conversationId));
        ack?.({ ok: true });
      } catch {
        ack?.({ ok: false, error: "Invalid conversation." });
      }
    });

    const relayTyping = (event: "typing:start" | "typing:stop", payload: unknown) => {
      try {
        const conversationId = parseIdPayload(payload);
        const room = conversationRoom(conversationId);
        if (!socket.rooms.has(room)) return;
        const now = Date.now();
        const previous = typingAtBySocket.get(socket.id) ?? 0;
        if (now - previous < 250) return;
        typingAtBySocket.set(socket.id, now);
        socket.to(room).emit("typing:update", {
          conversationId,
          userId,
          isTyping: event === "typing:start",
        });
      } catch {
        // Invalid transient typing events are ignored without exposing a socket error.
      }
    };
    socket.on("typing:start", (payload: unknown) => relayTyping("typing:start", payload));
    socket.on("typing:stop", (payload: unknown) => relayTyping("typing:stop", payload));

    socket.on("message:delivered", (payload: unknown, ack?: Ack) => {
      void (async () => {
        try {
          const { conversationId, messageIds } = parseReceiptPayload(payload);
          const result = await markMessagesDelivered(userId, conversationId, messageIds);
          socket.to(conversationRoom(conversationId)).emit("message:receipt", {
            conversationId,
            userId,
            deliveredIds: result.deliveredIds,
          });
          ack?.({ ok: true });
        } catch {
          ack?.({ ok: false, error: "Receipt was not accepted." });
        }
      })();
    });

    socket.on("message:read", (payload: unknown, ack?: Ack) => {
      void (async () => {
        try {
          const conversationId = parseIdPayload(payload);
          const result = await markConversationRead(userId, conversationId);
          socket.to(conversationRoom(conversationId)).emit("message:receipt", {
            conversationId,
            userId,
            readAt: result.readAt,
          });
          ack?.({ ok: true });
        } catch {
          ack?.({ ok: false, error: "Receipt was not accepted." });
        }
      })();
    });

    socket.on("presence:watch", (payload: unknown, ack?: Ack) => {
      void (async () => {
        try {
          const userIds = parsePresencePayload(payload);
          for (const targetId of userIds) {
            if (!(await canWatchPresence(userId, targetId))) continue;
            await socket.join(presenceRoom(targetId));
            socket.emit("presence:update", {
              userId: targetId,
              online: (socketsByUser.get(targetId)?.size ?? 0) > 0,
            });
          }
          ack?.({ ok: true });
        } catch {
          ack?.({ ok: false, error: "Presence subscriptions were not accepted." });
        }
      })();
    });

    socket.on("presence:unwatch", (payload: unknown, ack?: Ack) => {
      try {
        const userIds = parsePresencePayload(payload);
        for (const targetId of userIds) void socket.leave(presenceRoom(targetId));
        ack?.({ ok: true });
      } catch {
        ack?.({ ok: false, error: "Invalid presence request." });
      }
    });

    socket.on("disconnect", () => {
      clearInterval(sessionCheck);
      typingAtBySocket.delete(socket.id);
      const active = socketsByUser.get(userId);
      active?.delete(socket.id);
      if (!active?.size) {
        socketsByUser.delete(userId);
        void pool.query(
          `INSERT INTO user_presence (user_id, last_seen_at)
           VALUES ($1, now())
           ON CONFLICT (user_id) DO UPDATE SET last_seen_at = now(), updated_at = now()`,
          [userId],
        ).then(() => notifyPresence(userId, false)).catch(() => undefined);
      }
    });
  });

  return io;
}

function parseIdPayload(payload: unknown) {
  const value =
    payload && typeof payload === "object" && "conversationId" in payload
      ? (payload as { conversationId: unknown }).conversationId
      : payload;
  if (typeof value !== "string" || !/^[0-9a-f-]{36}$/i.test(value)) {
    throw new Error("Invalid ID.");
  }
  return value;
}

function parseReceiptPayload(payload: unknown) {
  if (!payload || typeof payload !== "object") throw new Error("Invalid receipt.");
  const value = payload as { conversationId?: unknown; messageIds?: unknown };
  if (
    typeof value.conversationId !== "string" ||
    !/^[0-9a-f-]{36}$/i.test(value.conversationId) ||
    !Array.isArray(value.messageIds) ||
    value.messageIds.length < 1 ||
    value.messageIds.length > 100 ||
    value.messageIds.some((id) => typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id))
  ) {
    throw new Error("Invalid receipt.");
  }
  return { conversationId: value.conversationId, messageIds: value.messageIds as string[] };
}

function parsePresencePayload(payload: unknown) {
  const ids = payload && typeof payload === "object" && "userIds" in payload
    ? (payload as { userIds: unknown }).userIds
    : payload;
  if (
    !Array.isArray(ids) ||
    ids.length > 50 ||
    ids.some((id) => typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id))
  ) {
    throw new Error("Invalid presence request.");
  }
  return [...new Set(ids as string[])];
}

export async function publishMessage(conversationId: string, message: unknown) {
  if (!io) return;
  const payload = message as { id: string; senderId: string };
  io.to(conversationRoom(conversationId)).emit("message:new", message);
  io.to(`user:${payload.senderId}`).emit("message:sent", {
    conversationId,
    messageId: payload.id,
  });
  const recipients = await pool.query(
    `SELECT cm.user_id AS "userId",
            (cm.muted_until IS NULL OR cm.muted_until <= now())
            AND NOT EXISTS (
              SELECT 1 FROM user_mutes mute
              WHERE mute.user_id = cm.user_id
                AND mute.target_type = 'conversation'
                AND mute.target_id = $1
                AND (mute.muted_until IS NULL OR mute.muted_until > now())
            ) AS "notMuted"
     FROM conversation_members cm
     WHERE cm.conversation_id = $1 AND cm.user_id <> $2 AND cm.left_at IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = cm.user_id AND b.blocked_id = $2)
            OR (b.blocker_id = $2 AND b.blocked_id = cm.user_id)
       )`,
    [conversationId, payload.senderId],
  );
  for (const recipient of recipients.rows as Array<{ userId: string; notMuted: boolean }>) {
    io.to(`user:${recipient.userId}`).emit("conversation:updated", {
      conversationId,
      messageId: payload.id,
    });
    if (recipient.notMuted) {
      io.to(`user:${recipient.userId}`).emit("notification:new", {
        kind: "message",
        conversationId,
        messageId: payload.id,
      });
    }
  }
}

export function publishReadReceipt(conversationId: string, userId: string, readAt: string) {
  io?.to(conversationRoom(conversationId)).emit("message:receipt", {
    conversationId,
    userId,
    readAt,
  });
}

export function publishDeliveryReceipt(conversationId: string, userId: string, deliveredIds: string[]) {
  io?.to(conversationRoom(conversationId)).emit("message:receipt", {
    conversationId,
    userId,
    deliveredIds,
  });
}

export function publishNotification(userId: string, notification: unknown) {
  io?.to(`user:${userId}`).emit("notification:new", notification);
}

export function disconnectSessionSockets(sessionId: string) {
  if (!io) return;
  for (const socket of io.sockets.sockets.values()) {
    const principal = socket.data.principal as Principal | undefined;
    if (principal?.sessionId === sessionId) socket.disconnect(true);
  }
}

export async function listOnlineMembers(userId: string) {
  const onlineIds = [...socketsByUser.entries()]
    .filter(([, sockets]) => sockets.size > 0)
    .map(([id]) => id);
  if (!onlineIds.length) return [];
  const result = await pool.query(
    `SELECT DISTINCT u.id, p.full_name AS "fullName",
            p.username, p.profile_photo_url AS "profilePhotoUrl",
            CASE WHEN presence.share_last_seen THEN presence.last_seen_at
                 ELSE NULL END AS "lastSeenAt"
     FROM group_members mine
     JOIN group_members other ON other.group_id = mine.group_id
     JOIN community_groups g ON g.id = mine.group_id AND g.status = 'active'
     JOIN users u ON u.id = other.user_id AND u.account_status = 'active'
     JOIN user_profiles p ON p.user_id = u.id
     JOIN user_presence presence
       ON presence.user_id = u.id AND presence.show_online_status = true
     WHERE mine.user_id = $1 AND mine.status = 'active'
       AND other.status = 'active' AND other.user_id <> $1
       AND u.id = ANY($2::uuid[])
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
            OR (b.blocker_id = u.id AND b.blocked_id = $1)
       )
     ORDER BY p.full_name LIMIT 100`,
    [userId, onlineIds],
  );
  return result.rows;
}
