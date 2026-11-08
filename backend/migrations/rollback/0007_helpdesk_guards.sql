-- Non-destructive rollback of guards only. Do not remove the tables or cases.
BEGIN;
ALTER TABLE helpdesk_status_history DROP CONSTRAINT helpdesk_history_from_status_check;
ALTER TABLE helpdesk_requests DROP CONSTRAINT helpdesk_resolved_timestamp_check;
DROP INDEX helpdesk_history_actor_idx,helpdesk_assignment_staff_idx,helpdesk_assignment_actor_idx,
  helpdesk_notes_author_idx,helpdesk_messages_author_idx,helpdesk_attachment_author_idx,
  helpdesk_read_user_idx,helpdesk_mute_user_idx;
DELETE FROM app_schema_migrations WHERE name='0007_helpdesk_guards';
COMMIT;
