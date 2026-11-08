CREATE SEQUENCE IF NOT EXISTS helpdesk_reference_seq;

CREATE TABLE helpdesk_departments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE CHECK (length(trim(name)) BETWEEN 2 AND 100),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE helpdesk_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text NOT NULL UNIQUE DEFAULT
    ('ORK-' || extract(year FROM now())::text || '-' || nextval('helpdesk_reference_seq')::text),
  owner_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 5 AND 160),
  category text NOT NULL CHECK (category IN ('general_inquiry','technical_support',
    'education_assistance','healthcare_assistance','employment_assistance','business_support',
    'social_welfare','membership_support','complaints','emergency_assistance','other')),
  description text NOT NULL CHECK (length(trim(description)) BETWEEN 20 AND 10000),
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  region text NOT NULL CHECK (length(trim(region)) BETWEEN 2 AND 100),
  district text NOT NULL DEFAULT '' CHECK (length(district) <= 100),
  qoum text NOT NULL DEFAULT '' CHECK (length(qoum) <= 100),
  village text NOT NULL DEFAULT '' CHECK (length(village) <= 100),
  contact_preference text NOT NULL DEFAULT 'in_app' CHECK (contact_preference IN ('in_app','email','phone')),
  status text NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted','under_review','assigned',
    'in_progress','waiting_for_member','resolved','closed','rejected')),
  department_id uuid REFERENCES helpdesk_departments(id) ON DELETE RESTRICT,
  assigned_to uuid REFERENCES users(id) ON DELETE SET NULL,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (assigned_to IS NULL OR assigned_to <> owner_id)
);
CREATE INDEX helpdesk_owner_created_idx ON helpdesk_requests(owner_id, created_at DESC, id DESC);
CREATE INDEX helpdesk_assigned_created_idx ON helpdesk_requests(assigned_to, created_at DESC, id DESC);
CREATE INDEX helpdesk_queue_idx ON helpdesk_requests(status, priority, category, created_at DESC);
CREATE INDEX helpdesk_department_idx ON helpdesk_requests(department_id);

CREATE TABLE helpdesk_request_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES helpdesk_requests(id) ON DELETE CASCADE,
  author_id uuid REFERENCES users(id) ON DELETE SET NULL,
  is_staff boolean NOT NULL,
  body text NOT NULL CHECK (length(trim(body)) BETWEEN 1 AND 10000),
  requests_documents boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(id, request_id)
);
CREATE INDEX helpdesk_messages_page_idx ON helpdesk_request_messages(request_id, created_at DESC, id DESC);
CREATE TABLE helpdesk_message_reads (
  message_id uuid NOT NULL REFERENCES helpdesk_request_messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(message_id, user_id)
);

CREATE TABLE helpdesk_request_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES helpdesk_requests(id) ON DELETE CASCADE,
  message_id uuid,
  uploaded_by uuid REFERENCES users(id) ON DELETE SET NULL,
  original_name text NOT NULL CHECK (length(original_name) BETWEEN 1 AND 255),
  storage_key text NOT NULL UNIQUE,
  content_type text NOT NULL,
  byte_size bigint NOT NULL CHECK (byte_size BETWEEN 1 AND 26214400),
  sha256 text NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (message_id, request_id) REFERENCES helpdesk_request_messages(id, request_id) ON DELETE CASCADE
);
CREATE INDEX helpdesk_attachments_request_idx ON helpdesk_request_attachments(request_id, created_at DESC, id DESC);
CREATE INDEX helpdesk_attachments_message_idx ON helpdesk_request_attachments(message_id);

CREATE TABLE helpdesk_request_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES helpdesk_requests(id) ON DELETE CASCADE,
  staff_id uuid REFERENCES users(id) ON DELETE SET NULL,
  department_id uuid NOT NULL REFERENCES helpdesk_departments(id) ON DELETE RESTRICT,
  assigned_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX helpdesk_assignments_request_idx ON helpdesk_request_assignments(request_id, created_at DESC);
CREATE TABLE helpdesk_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES helpdesk_requests(id) ON DELETE CASCADE,
  from_status text,
  to_status text NOT NULL CHECK (to_status IN ('submitted','under_review','assigned',
    'in_progress','waiting_for_member','resolved','closed','rejected')),
  actor_id uuid REFERENCES users(id) ON DELETE SET NULL,
  reason text NOT NULL DEFAULT '' CHECK (length(reason) <= 2000),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX helpdesk_history_request_idx ON helpdesk_status_history(request_id, created_at DESC, id DESC);
CREATE TABLE helpdesk_internal_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES helpdesk_requests(id) ON DELETE CASCADE,
  author_id uuid REFERENCES users(id) ON DELETE SET NULL,
  body text NOT NULL CHECK (length(trim(body)) BETWEEN 1 AND 10000),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX helpdesk_notes_request_idx ON helpdesk_internal_notes(request_id, created_at DESC, id DESC);
CREATE TABLE helpdesk_request_mutes (
  request_id uuid NOT NULL REFERENCES helpdesk_requests(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY(request_id, user_id)
);
CREATE TABLE helpdesk_faqs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question text NOT NULL CHECK (length(trim(question)) BETWEEN 5 AND 200),
  answer text NOT NULL CHECK (length(trim(answer)) BETWEEN 10 AND 10000),
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  published boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE helpdesk_announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 5 AND 160),
  body text NOT NULL CHECK (length(trim(body)) BETWEEN 10 AND 10000),
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  published boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX helpdesk_faq_published_idx ON helpdesk_faqs(published, created_at DESC, id DESC);
CREATE INDEX helpdesk_announcement_published_idx ON helpdesk_announcements(published, created_at DESC, id DESC);

ALTER TABLE notification_preferences ADD COLUMN helpdesk_updates boolean NOT NULL DEFAULT true;
ALTER TABLE community_notifications DROP CONSTRAINT community_notifications_kind_check;
ALTER TABLE community_notifications ADD CONSTRAINT community_notifications_kind_check CHECK(kind IN (
  'private_message','group_message','group_invitation','comment','reply','post_reaction',
  'announcement','moderation_action','helpdesk_submitted','helpdesk_assigned','helpdesk_status',
  'helpdesk_reply','helpdesk_documents','helpdesk_resolved','helpdesk_closed'));

INSERT INTO roles(name,slug,description) VALUES
 ('Help Desk Administrator','helpdesk_admin','Manage Help Desk requests and support content.'),
 ('Support Manager','support_manager','Assign and oversee the Help Desk queue.'),
 ('Support Agent','support_agent','Access only currently assigned Help Desk requests.')
ON CONFLICT(slug) DO NOTHING;
INSERT INTO permissions(key,description) VALUES
 ('helpdesk:manage','Manage the Help Desk queue, assignments and knowledge content.'),
 ('helpdesk:agent','Respond to currently assigned Help Desk requests.')
ON CONFLICT(key) DO NOTHING;
INSERT INTO role_permissions(role_id,permission_id)
 SELECT r.id,p.id FROM roles r CROSS JOIN permissions p
 WHERE r.slug IN ('super_admin','helpdesk_admin','support_manager')
 AND p.key IN ('helpdesk:manage','helpdesk:agent')
ON CONFLICT DO NOTHING;
INSERT INTO role_permissions(role_id,permission_id)
 SELECT r.id,p.id FROM roles r JOIN permissions p ON p.key='helpdesk:agent'
 WHERE r.slug IN ('support_agent','support_officer')
ON CONFLICT DO NOTHING;

-- Routing configuration, not a fabricated department workload or case.
INSERT INTO helpdesk_departments(name) VALUES ('General Support') ON CONFLICT DO NOTHING;
-- These describe implemented system policy, not invented NGO services/outcomes.
INSERT INTO helpdesk_faqs(question,answer) VALUES
 ('Who can access my request?',
  'Only your account and authorized Help Desk staff can access your request. Support agents must be currently assigned to the case. Internal staff notes are not included in member views.'),
 ('Can I reopen a resolved request?',
  'You may reopen your own resolved request within seven days of resolution. Closed or rejected requests cannot be reopened through this policy.'),
 ('Is Emergency Assistance an emergency response service?',
  'No. Submitting an urgent request does not guarantee an immediate response. For immediate danger or a medical emergency, contact the appropriate local emergency services.'),
 ('How do I provide additional documents?',
  'Open your request and use Attachments to upload a supported file. Documents are private and require authorized request access. Production uploads remain unavailable until private storage is configured.');
