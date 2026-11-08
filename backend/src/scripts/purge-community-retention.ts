import { unlink } from "node:fs/promises";
import { resolve, sep } from "node:path";

import { config } from "../config.js";
import { pool } from "../db/pool.js";

async function purgeCommunityRetention() {
  const days = config.communityDeletedContentRetentionDays;
  if (!Number.isInteger(days) || days < 1 || days > 3650) {
    throw new Error(
      "Set COMMUNITY_DELETED_CONTENT_RETENTION_DAYS to a whole number from 1 to 3650 before running this purge.",
    );
  }
  if (
    config.nodeEnv === "production" &&
    process.env.COMMUNITY_RETENTION_PURGE_CONFIRM !== "true"
  ) {
    throw new Error(
      "Production purge requires COMMUNITY_RETENTION_PURGE_CONFIRM=true for this run.",
    );
  }
  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

  const messages = await pool.query(
    `DELETE FROM messages
     WHERE (deleted_at IS NOT NULL AND deleted_at < $1)
        OR (moderation_status IN ('hidden', 'removed') AND created_at < $1)`,
    [cutoff],
  );
  const comments = await pool.query(
    `DELETE FROM post_comments
     WHERE status IN ('hidden', 'removed') AND created_at < $1`,
    [cutoff],
  );
  const posts = await pool.query(
    `DELETE FROM community_posts
     WHERE status IN ('hidden', 'removed') AND updated_at < $1`,
    [cutoff],
  );
  const invitations = await pool.query(
    `DELETE FROM group_invitations
     WHERE status IN ('accepted', 'declined', 'revoked', 'expired')
       AND COALESCE(responded_at, created_at) < $1`,
    [cutoff],
  );
  const notifications = await pool.query(
    `DELETE FROM community_notifications
     WHERE read_at IS NOT NULL AND read_at < $1`,
    [cutoff],
  );
  const media = await pool.query(
    `DELETE FROM media_objects media
     WHERE media.created_at < $1
       AND NOT EXISTS (SELECT 1 FROM post_media pm WHERE pm.media_id = media.id)
       AND NOT EXISTS (SELECT 1 FROM message_media mm WHERE mm.media_id = media.id)
     RETURNING storage_key`,
    [cutoff],
  );

  const mediaRoot = resolve(config.communityMediaStorageDir);
  let filesRemoved = 0;
  for (const row of media.rows as Array<{ storage_key: string }>) {
    const filePath = resolve(mediaRoot, row.storage_key);
    if (!filePath.startsWith(`${mediaRoot}${sep}`)) continue;
    try {
      await unlink(filePath);
      filesRemoved += 1;
    } catch {
      // Metadata is already deleted; an absent file requires no additional action.
    }
  }

  console.info(
    JSON.stringify({
      cutoff: cutoff.toISOString(),
      deletedMessages: messages.rowCount ?? 0,
      deletedComments: comments.rowCount ?? 0,
      deletedPosts: posts.rowCount ?? 0,
      deletedInvitations: invitations.rowCount ?? 0,
      deletedReadNotifications: notifications.rowCount ?? 0,
      deletedOrphanMedia: media.rowCount ?? 0,
      removedMediaFiles: filesRemoved,
    }),
  );
}

purgeCommunityRetention()
  .catch((error: unknown) => {
    console.error(
      error instanceof Error ? error.message : "Community retention purge failed.",
    );
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
