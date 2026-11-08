ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'visible'
    CHECK (moderation_status IN ('visible', 'hidden', 'removed'));

CREATE INDEX IF NOT EXISTS messages_moderation_idx
    ON messages (conversation_id, moderation_status, created_at DESC);
