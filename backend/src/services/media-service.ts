import { createHash, createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { extname, resolve } from "node:path";

import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";
import { config } from "../config.js";
import { canReadPost } from "./feed-service.js";
import { requireConversationMember } from "./message-service.js";

const maxBytes = config.communityMaxUploadBytes;
const signedUrlTtl = config.communityMediaUrlTtlSeconds;

function assertStorageAvailable() {
  if (config.nodeEnv === "production" || config.communityMediaProvider !== "local-development") {
    throw new HttpError(503, "MEDIA_STORAGE_NOT_CONFIGURED", "Production private media storage is not configured.");
  }
}

type DetectedFile = { contentType: string; extension: string };

export function detectFile(buffer: Buffer, originalName: string, declaredType: string): DetectedFile {
  const ext = extname(originalName).toLowerCase();
  const starts = (...bytes: number[]) => bytes.every((byte, index) => buffer[index] === byte);
  if (starts(0xff, 0xd8, 0xff)) return { contentType: "image/jpeg", extension: ".jpg" };
  if (starts(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)) {
    return { contentType: "image/png", extension: ".png" };
  }
  if (buffer.toString("ascii", 0, 4) === "RIFF" && buffer.toString("ascii", 8, 12) === "WEBP") {
    return { contentType: "image/webp", extension: ".webp" };
  }
  if (["GIF87a", "GIF89a"].includes(buffer.toString("ascii", 0, 6))) {
    return { contentType: "image/gif", extension: ".gif" };
  }
  if (buffer.toString("ascii", 0, 5) === "%PDF-") return { contentType: "application/pdf", extension: ".pdf" };
  if (buffer.toString("ascii", 4, 8) === "ftyp") {
    if (ext === ".m4a") return { contentType: "audio/mp4", extension: ".m4a" };
    if (ext === ".mov") return { contentType: "video/quicktime", extension: ".mov" };
    return { contentType: "video/mp4", extension: ".mp4" };
  }
  if (starts(0x1a, 0x45, 0xdf, 0xa3)) return { contentType: "video/webm", extension: ".webm" };
  if (buffer.toString("ascii", 0, 4) === "OggS") return { contentType: "audio/ogg", extension: ".ogg" };
  if (buffer.toString("ascii", 0, 3) === "ID3") return { contentType: "audio/mpeg", extension: ".mp3" };
  if (buffer.toString("ascii", 0, 4) === "RIFF" && buffer.toString("ascii", 8, 12) === "WAVE") {
    return { contentType: "audio/wav", extension: ".wav" };
  }
  if (buffer.toString("ascii", 0, 4) === "PK\u0003\u0004" && ext === ".docx") {
    const directoryText = buffer.toString("latin1");
    if (
      directoryText.includes("[Content_Types].xml") &&
      directoryText.includes("word/document.xml") &&
      !directoryText.includes("word/vbaProject.bin")
    ) {
      return {
        contentType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        extension: ".docx",
      };
    }
  }
  if (declaredType === "text/plain" && !buffer.subarray(0, 4096).includes(0)) {
    return { contentType: "text/plain", extension: ".txt" };
  }
  throw new HttpError(415, "UNSUPPORTED_MEDIA_TYPE", "Upload a supported image, video, audio, PDF, DOCX, or text file.");
}

function safeOriginalName(name: string) {
  const base = name.split(/[\\/]/).pop() ?? "upload";
  const cleaned = base.replace(/[\u0000-\u001f\u007f]/g, "").trim();
  return cleaned.slice(0, 255) || "upload";
}

function storagePath(storageKey: string) {
  return resolve(config.communityMediaStorageDir, storageKey);
}

export async function uploadMedia(
  userId: string,
  file: { buffer: Buffer; originalname: string; mimetype: string },
) {
  assertStorageAvailable();
  if (!file.buffer.length || file.buffer.length > maxBytes) {
    throw new HttpError(413, "MEDIA_SIZE_INVALID", "Files must be smaller than 25 MB.");
  }
  const detected = detectFile(file.buffer, file.originalname, file.mimetype);
  const id = randomUUID();
  const storageKey = `${id}${detected.extension}`;
  const directory = config.communityMediaStorageDir;
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await writeFile(storagePath(storageKey), file.buffer, { flag: "wx", mode: 0o600 });
  try {
    const result = await pool.query(
      `INSERT INTO media_objects
         (id, owner_id, storage_key, original_name, content_type, byte_size, sha256)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, original_name AS "name", content_type AS "contentType",
                 byte_size AS "byteSize", created_at AS "createdAt"`,
      [
        id,
        userId,
        storageKey,
        safeOriginalName(file.originalname),
        detected.contentType,
        file.buffer.length,
        createHash("sha256").update(file.buffer).digest("hex"),
      ],
    );
    return result.rows[0];
  } catch (error) {
    await unlink(storagePath(storageKey)).catch(() => undefined);
    throw error;
  }
}

async function canAccessMedia(userId: string, mediaId: string) {
  const media = await pool.query(
    `SELECT id, owner_id AS "ownerId", storage_key AS "storageKey",
            original_name AS "name", content_type AS "contentType",
            byte_size AS "byteSize"
     FROM media_objects WHERE id = $1`,
    [mediaId],
  );
  const row = media.rows[0];
  if (!row) throw new HttpError(404, "MEDIA_NOT_FOUND", "The file was not found.");
  if (row.ownerId === userId) return row;

  const posts = await pool.query(
    `SELECT post_id FROM post_media WHERE media_id = $1`,
    [mediaId],
  );
  for (const { post_id: postId } of posts.rows as Array<{ post_id: string }>) {
    if (await canReadPost(userId, postId)) return row;
  }

  const messages = await pool.query(
    `SELECT mm.message_id, m.conversation_id AS "conversationId",
            m.deleted_at, m.moderation_status AS "moderationStatus"
     FROM message_media mm
     JOIN messages m ON m.id = mm.message_id
     WHERE mm.media_id = $1`,
    [mediaId],
  );
  for (const message of messages.rows) {
    if (message.deleted_at || message.moderationStatus !== "visible") continue;
    try {
      await requireConversationMember(userId, message.conversationId);
      return row;
    } catch {
      // Continue through other attachments; unauthorized files are never enumerated.
    }
  }
  throw new HttpError(404, "MEDIA_NOT_FOUND", "The file was not found.");
}

function signature(userId: string, mediaId: string, expires: number) {
  return createHmac("sha256", config.accessTokenSecret)
    .update(`${userId}:${mediaId}:${expires}`)
    .digest("base64url");
}

export async function createMediaAccessUrl(userId: string, mediaId: string) {
  assertStorageAvailable();
  await canAccessMedia(userId, mediaId);
  const expires = Math.floor(Date.now() / 1000) + signedUrlTtl;
  return {
    path: `/media/${mediaId}/content`,
    expiresAt: new Date(expires * 1000).toISOString(),
    expires,
    signature: signature(userId, mediaId, expires),
  };
}

export async function readMedia(
  userId: string,
  mediaId: string,
  expiresValue: string,
  suppliedSignature: string,
) {
  assertStorageAvailable();
  const expires = Number(expiresValue);
  if (!Number.isInteger(expires) || expires <= Math.floor(Date.now() / 1000)) {
    throw new HttpError(403, "MEDIA_URL_EXPIRED", "The file access link has expired.");
  }
  const expected = Buffer.from(signature(userId, mediaId, expires));
  const supplied = Buffer.from(suppliedSignature);
  if (expected.length !== supplied.length || !timingSafeEqual(expected, supplied)) {
    throw new HttpError(403, "MEDIA_URL_INVALID", "The file access link is invalid.");
  }
  const media = await canAccessMedia(userId, mediaId);
  const path = storagePath(media.storageKey);
  const buffer = await readFile(path).catch(() => {
    throw new HttpError(404, "MEDIA_NOT_FOUND", "The file is not available.");
  });
  return { media, buffer };
}
