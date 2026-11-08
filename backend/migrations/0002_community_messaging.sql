CREATE TABLE IF NOT EXISTS community_groups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL CHECK (char_length(name) BETWEEN 3 AND 80),
    description text NOT NULL DEFAULT '' CHECK (char_length(description) <= 2000),
    category text NOT NULL CHECK (category IN (
        'general', 'regional', 'youth', 'education', 'healthcare',
        'business', 'employment', 'overseas', 'welfare', 'culture'
    )),
    visibility text NOT NULL DEFAULT 'public'
        CHECK (visibility IN ('public', 'private')),
    status text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'suspended', 'archived')),
    owner_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    region_id uuid REFERENCES regions(id) ON DELETE RESTRICT,
    district_id uuid REFERENCES districts(id) ON DELETE RESTRICT,
    qoum_id uuid REFERENCES qoums(id) ON DELETE RESTRICT,
    village_id uuid REFERENCES villages(id) ON DELETE RESTRICT,
    profile_image_url text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS group_members (
    group_id uuid NOT NULL REFERENCES community_groups(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role text NOT NULL DEFAULT 'member'
        CHECK (role IN ('owner', 'admin', 'moderator', 'member')),
    status text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'pending', 'left', 'removed', 'banned')),
    joined_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (group_id, user_id)
);

CREATE TABLE IF NOT EXISTS group_invitations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id uuid NOT NULL REFERENCES community_groups(id) ON DELETE CASCADE,
    invitee_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invited_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'declined', 'revoked', 'expired')),
    created_at timestamptz NOT NULL DEFAULT now(),
    responded_at timestamptz
);

CREATE TABLE IF NOT EXISTS group_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id uuid NOT NULL REFERENCES community_groups(id) ON DELETE CASCADE,
    title text NOT NULL CHECK (char_length(title) BETWEEN 2 AND 120),
    body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
    position integer NOT NULL DEFAULT 0,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS media_objects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    storage_key text NOT NULL UNIQUE,
    original_name text NOT NULL CHECK (char_length(original_name) <= 255),
    content_type text NOT NULL,
    byte_size bigint NOT NULL CHECK (byte_size BETWEEN 1 AND 26214400),
    sha256 text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS community_posts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    group_id uuid REFERENCES community_groups(id) ON DELETE CASCADE,
    visibility text NOT NULL CHECK (visibility IN ('public', 'regional', 'group', 'private')),
    region_id uuid REFERENCES regions(id) ON DELETE RESTRICT,
    body text NOT NULL DEFAULT '' CHECK (char_length(body) <= 10000),
    is_announcement boolean NOT NULL DEFAULT false,
    pinned_at timestamptz,
    status text NOT NULL DEFAULT 'published'
        CHECK (status IN ('published', 'hidden', 'removed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
      (visibility = 'regional' AND region_id IS NOT NULL)
      OR (visibility <> 'regional' AND region_id IS NULL)
    ),
    CHECK (
      (visibility = 'group' AND group_id IS NOT NULL)
      OR (visibility <> 'group' AND group_id IS NULL)
    )
);

CREATE TABLE IF NOT EXISTS post_media (
    post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    media_id uuid NOT NULL REFERENCES media_objects(id) ON DELETE RESTRICT,
    position smallint NOT NULL DEFAULT 0,
    PRIMARY KEY (post_id, media_id),
    UNIQUE (post_id, position)
);

CREATE TABLE IF NOT EXISTS post_comments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    author_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_comment_id uuid REFERENCES post_comments(id) ON DELETE CASCADE,
    body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 4000),
    status text NOT NULL DEFAULT 'published'
        CHECK (status IN ('published', 'hidden', 'removed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS post_reactions (
    post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reaction text NOT NULL CHECK (reaction IN ('like', 'support', 'celebrate', 'care')),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS post_bookmarks (
    post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_type text NOT NULL CHECK (conversation_type IN ('direct', 'group')),
    group_id uuid UNIQUE REFERENCES community_groups(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    last_message_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
      (conversation_type = 'group' AND group_id IS NOT NULL)
      OR (conversation_type = 'direct' AND group_id IS NULL)
    )
);

CREATE TABLE IF NOT EXISTS conversation_members (
    conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at timestamptz NOT NULL DEFAULT now(),
    left_at timestamptz,
    last_read_at timestamptz,
    muted_until timestamptz,
    PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_nonce uuid,
    body text NOT NULL DEFAULT '' CHECK (char_length(body) <= 10000),
    reply_to_id uuid REFERENCES messages(id) ON DELETE SET NULL,
    edited_at timestamptz,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (sender_id, client_nonce)
);

CREATE TABLE IF NOT EXISTS message_media (
    message_id uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    media_id uuid NOT NULL REFERENCES media_objects(id) ON DELETE RESTRICT,
    position smallint NOT NULL DEFAULT 0,
    PRIMARY KEY (message_id, media_id),
    UNIQUE (message_id, position)
);

CREATE TABLE IF NOT EXISTS message_reactions (
    message_id uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reaction text NOT NULL CHECK (reaction IN ('like', 'love', 'laugh', 'support', 'celebrate')),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (message_id, user_id)
);

CREATE TABLE IF NOT EXISTS message_read_receipts (
    message_id uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    delivered_at timestamptz,
    read_at timestamptz,
    PRIMARY KEY (message_id, user_id),
    CHECK (read_at IS NULL OR delivered_at IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS user_blocks (
    blocker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);

CREATE TABLE IF NOT EXISTS user_mutes (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_type text NOT NULL CHECK (target_type IN ('user', 'group', 'conversation')),
    target_id uuid NOT NULL,
    muted_until timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, target_type, target_id)
);

CREATE TABLE IF NOT EXISTS content_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_type text NOT NULL CHECK (target_type IN ('post', 'comment', 'message', 'group', 'user')),
    target_id uuid NOT NULL,
    category text NOT NULL CHECK (category IN (
        'spam', 'harassment', 'threats', 'hate_abuse', 'fraud_scams',
        'impersonation', 'inappropriate', 'other'
    )),
    details text NOT NULL DEFAULT '' CHECK (char_length(details) <= 2000),
    status text NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'reviewing', 'actioned', 'dismissed')),
    assigned_to uuid REFERENCES users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    UNIQUE (reporter_id, target_type, target_id)
);

CREATE TABLE IF NOT EXISTS moderation_actions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id uuid REFERENCES content_reports(id) ON DELETE SET NULL,
    actor_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    target_type text NOT NULL CHECK (target_type IN ('post', 'comment', 'message', 'group', 'user')),
    target_id uuid NOT NULL,
    action text NOT NULL CHECK (action IN (
        'hide_content', 'restore_content', 'remove_content', 'suspend_group',
        'restore_group', 'restrict_member', 'remove_member', 'dismiss_report'
    )),
    reason text NOT NULL CHECK (char_length(reason) BETWEEN 3 AND 1000),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    private_messages boolean NOT NULL DEFAULT true,
    group_messages boolean NOT NULL DEFAULT true,
    group_invitations boolean NOT NULL DEFAULT true,
    comments_and_replies boolean NOT NULL DEFAULT true,
    post_reactions boolean NOT NULL DEFAULT true,
    announcements boolean NOT NULL DEFAULT true,
    moderator_actions boolean NOT NULL DEFAULT true,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS community_notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    actor_id uuid REFERENCES users(id) ON DELETE SET NULL,
    kind text NOT NULL CHECK (kind IN (
        'private_message', 'group_message', 'group_invitation', 'comment',
        'reply', 'post_reaction', 'announcement', 'moderation_action'
    )),
    entity_type text,
    entity_id uuid,
    read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_presence (
    user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    show_online_status boolean NOT NULL DEFAULT false,
    share_last_seen boolean NOT NULL DEFAULT false,
    last_seen_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS group_visibility_created_idx
    ON community_groups (visibility, status, created_at DESC);
CREATE INDEX IF NOT EXISTS group_region_idx
    ON community_groups (region_id, district_id, qoum_id, village_id);
CREATE INDEX IF NOT EXISTS group_members_user_status_idx
    ON group_members (user_id, status, joined_at DESC);
CREATE INDEX IF NOT EXISTS group_invitations_user_status_idx
    ON group_invitations (invitee_id, status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS group_invitations_pending_unique_idx
    ON group_invitations (group_id, invitee_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS community_posts_feed_idx
    ON community_posts (created_at DESC, id DESC) WHERE status = 'published';
CREATE INDEX IF NOT EXISTS community_posts_group_feed_idx
    ON community_posts (group_id, created_at DESC, id DESC)
    WHERE status = 'published';
CREATE INDEX IF NOT EXISTS community_posts_announcements_idx
    ON community_posts (created_at DESC, id DESC)
    WHERE is_announcement = true AND status = 'published';
CREATE INDEX IF NOT EXISTS post_comments_post_created_idx
    ON post_comments (post_id, created_at DESC, id DESC)
    WHERE status = 'published';
CREATE INDEX IF NOT EXISTS conversations_last_message_idx
    ON conversations (last_message_at DESC NULLS LAST, created_at DESC);
CREATE INDEX IF NOT EXISTS conversation_members_user_active_idx
    ON conversation_members (user_id, left_at, conversation_id);
CREATE INDEX IF NOT EXISTS messages_conversation_page_idx
    ON messages (conversation_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS messages_sender_idx ON messages (sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS message_receipts_user_read_idx
    ON message_read_receipts (user_id, read_at, delivered_at);
CREATE INDEX IF NOT EXISTS content_reports_queue_idx
    ON content_reports (status, created_at ASC);
CREATE INDEX IF NOT EXISTS moderation_target_idx
    ON moderation_actions (target_type, target_id, created_at DESC);
CREATE INDEX IF NOT EXISTS notifications_user_unread_idx
    ON community_notifications (user_id, created_at DESC) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS media_owner_created_idx
    ON media_objects (owner_id, created_at DESC);

INSERT INTO notification_preferences (user_id)
SELECT id FROM users
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO user_presence (user_id)
SELECT id FROM users
ON CONFLICT (user_id) DO NOTHING;
