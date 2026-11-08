ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS messages_sender_id_client_nonce_key;

ALTER TABLE messages
    ADD CONSTRAINT messages_conversation_sender_nonce_key
    UNIQUE (conversation_id, sender_id, client_nonce);

CREATE TABLE IF NOT EXISTS post_shares (
    post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

INSERT INTO permissions (key, description) VALUES
    ('groups:suspend', 'Suspend or restore community groups.'),
    ('members:restrict', 'Restrict or restore member accounts after moderation review.')
ON CONFLICT (key) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.slug IN ('super_admin', 'executive_admin')
  AND p.key IN ('groups:suspend', 'members:restrict')
ON CONFLICT DO NOTHING;
