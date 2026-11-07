CREATE TABLE IF NOT EXISTS regions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    code text UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS districts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    region_id uuid NOT NULL REFERENCES regions(id) ON DELETE RESTRICT,
    name text NOT NULL,
    code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (region_id, name),
    UNIQUE (region_id, code)
);

CREATE TABLE IF NOT EXISTS qoums (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    district_id uuid NOT NULL REFERENCES districts(id) ON DELETE RESTRICT,
    name text NOT NULL,
    code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (district_id, name),
    UNIQUE (district_id, code)
);

CREATE TABLE IF NOT EXISTS villages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    qoum_id uuid NOT NULL REFERENCES qoums(id) ON DELETE RESTRICT,
    name text NOT NULL,
    code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (qoum_id, name),
    UNIQUE (qoum_id, code)
);

CREATE TABLE IF NOT EXISTS users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text NOT NULL,
    phone text NOT NULL,
    password_hash text NOT NULL,
    email_verified_at timestamptz,
    account_status text NOT NULL DEFAULT 'pending'
        CHECK (account_status IN ('pending', 'active', 'suspended')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT users_email_unique UNIQUE (email),
    CONSTRAINT users_phone_unique UNIQUE (phone)
);

CREATE TABLE IF NOT EXISTS user_profiles (
    user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    full_name text NOT NULL,
    username text UNIQUE,
    member_id text UNIQUE,
    profile_photo_url text,
    city text,
    country text,
    profession text,
    skills text[] NOT NULL DEFAULT '{}',
    education text,
    biography text,
    show_city_publicly boolean NOT NULL DEFAULT false,
    show_profession_publicly boolean NOT NULL DEFAULT false,
    show_skills_publicly boolean NOT NULL DEFAULT false,
    show_education_publicly boolean NOT NULL DEFAULT false,
    allow_profile_search boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash text NOT NULL UNIQUE,
    expires_at timestamptz NOT NULL,
    last_used_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE,
    slug text NOT NULL UNIQUE,
    description text NOT NULL DEFAULT '',
    is_system boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    key text NOT NULL UNIQUE,
    description text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_roles (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
    granted_by uuid REFERENCES users(id) ON DELETE SET NULL,
    granted_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id),
    CONSTRAINT user_roles_no_self_grant CHECK (granted_by IS NULL OR granted_by <> user_id)
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS user_region_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    region_id uuid REFERENCES regions(id) ON DELETE RESTRICT,
    district_id uuid REFERENCES districts(id) ON DELETE RESTRICT,
    qoum_id uuid REFERENCES qoums(id) ON DELETE RESTRICT,
    village_id uuid REFERENCES villages(id) ON DELETE RESTRICT,
    assigned_by uuid REFERENCES users(id) ON DELETE SET NULL,
    is_primary boolean NOT NULL DEFAULT false,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_region_assignment_has_location CHECK (
        region_id IS NOT NULL OR district_id IS NOT NULL OR qoum_id IS NOT NULL OR village_id IS NOT NULL
    )
);

CREATE TABLE IF NOT EXISTS verification_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    request_type text NOT NULL
        CHECK (request_type IN ('email_verification', 'password_reset', 'membership_review')),
    token_hash text NOT NULL,
    expires_at timestamptz NOT NULL,
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    consumed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id uuid REFERENCES users(id) ON DELETE SET NULL,
    action text NOT NULL,
    entity_type text,
    entity_id uuid,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_sessions_user_expiry_idx
    ON user_sessions (user_id, expires_at);
CREATE INDEX IF NOT EXISTS user_sessions_active_idx
    ON user_sessions (id, revoked_at, expires_at);
CREATE INDEX IF NOT EXISTS user_roles_role_idx ON user_roles (role_id);
CREATE INDEX IF NOT EXISTS role_permissions_permission_idx ON role_permissions (permission_id);
CREATE INDEX IF NOT EXISTS verification_user_type_idx
    ON verification_requests (user_id, request_type, created_at DESC);
CREATE INDEX IF NOT EXISTS verification_expiry_idx
    ON verification_requests (expires_at)
    WHERE consumed_at IS NULL;
CREATE INDEX IF NOT EXISTS audit_actor_created_idx
    ON audit_logs (actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS user_region_user_idx
    ON user_region_assignments (user_id, is_primary);

INSERT INTO roles (name, slug, description) VALUES
    ('Super Admin', 'super_admin', 'Full administrative control; assigned only by a trusted operator.'),
    ('Executive Admin', 'executive_admin', 'Executive-level organization administration.'),
    ('Department Director', 'department_director', 'Department-level administration.'),
    ('Regional Coordinator', 'regional_coordinator', 'Assigned regional coordination.'),
    ('Support Officer', 'support_officer', 'Review of assigned support and verification requests.'),
    ('Moderator', 'moderator', 'Community moderation tools.'),
    ('Verified Member', 'verified_member', 'Member status verified by an authorized organization administrator.'),
    ('Standard Member', 'standard_member', 'Default role for a newly registered account.')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO permissions (key, description) VALUES
    ('profile:read:own', 'Read the signed-in user profile.'),
    ('profile:update:own', 'Update permitted fields on the signed-in user profile.'),
    ('users:read:any', 'Read member profiles for an approved organization purpose.'),
    ('users:update:any', 'Update a member profile through an authorized workflow.'),
    ('roles:assign', 'Assign or revoke application roles.'),
    ('members:assign_id', 'Assign an organization-issued member ID.'),
    ('verification:review', 'Review organization membership verification requests.'),
    ('regions:assign', 'Assign members to geographic regions.'),
    ('content:moderate', 'Moderate community content.'),
    ('audit:read', 'Read security and administrative audit records.')
ON CONFLICT (key) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.slug = 'super_admin'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN permissions p ON p.key IN (
    'profile:read:own', 'profile:update:own', 'users:read:any',
    'users:update:any', 'members:assign_id', 'verification:review',
    'regions:assign', 'content:moderate', 'audit:read'
)
WHERE r.slug = 'executive_admin'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN permissions p ON p.key IN (
    'profile:read:own', 'profile:update:own', 'users:read:any',
    'users:update:any', 'members:assign_id', 'verification:review',
    'regions:assign'
)
WHERE r.slug = 'department_director'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN permissions p ON p.key IN (
    'profile:read:own', 'profile:update:own', 'users:read:any',
    'verification:review', 'regions:assign'
)
WHERE r.slug = 'regional_coordinator'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN permissions p ON p.key IN (
    'profile:read:own', 'profile:update:own', 'verification:review'
)
WHERE r.slug = 'support_officer'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN permissions p ON p.key IN ('profile:read:own', 'profile:update:own', 'content:moderate')
WHERE r.slug = 'moderator'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN permissions p ON p.key IN ('profile:read:own', 'profile:update:own')
WHERE r.slug IN ('verified_member', 'standard_member')
ON CONFLICT DO NOTHING;
