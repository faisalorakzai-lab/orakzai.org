ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS forwarded_from_message_id uuid
    REFERENCES messages(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS messages_forwarded_from_idx
    ON messages (forwarded_from_message_id)
    WHERE forwarded_from_message_id IS NOT NULL;
