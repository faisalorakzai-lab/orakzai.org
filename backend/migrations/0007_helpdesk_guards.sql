ALTER TABLE helpdesk_status_history ADD CONSTRAINT helpdesk_history_from_status_check
  CHECK(from_status IS NULL OR from_status IN ('submitted','under_review','assigned',
    'in_progress','waiting_for_member','resolved','closed','rejected'));
ALTER TABLE helpdesk_requests ADD CONSTRAINT helpdesk_resolved_timestamp_check
  CHECK(status <> 'resolved' OR resolved_at IS NOT NULL);
CREATE INDEX helpdesk_history_actor_idx ON helpdesk_status_history(actor_id);
CREATE INDEX helpdesk_assignment_staff_idx ON helpdesk_request_assignments(staff_id);
CREATE INDEX helpdesk_assignment_actor_idx ON helpdesk_request_assignments(assigned_by);
CREATE INDEX helpdesk_notes_author_idx ON helpdesk_internal_notes(author_id);
CREATE INDEX helpdesk_messages_author_idx ON helpdesk_request_messages(author_id);
CREATE INDEX helpdesk_attachment_author_idx ON helpdesk_request_attachments(uploaded_by);
CREATE INDEX helpdesk_read_user_idx ON helpdesk_message_reads(user_id);
CREATE INDEX helpdesk_mute_user_idx ON helpdesk_request_mutes(user_id);
