-- Manual development rollback only. Back up first; never run against production
-- through the development runner. Refuse to discard real support records.
BEGIN;
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM helpdesk_requests)
    OR EXISTS(SELECT 1 FROM helpdesk_announcements)
    OR EXISTS(SELECT 1 FROM helpdesk_faqs WHERE created_by IS NOT NULL)
    OR EXISTS(SELECT 1 FROM helpdesk_departments WHERE name <> 'General Support')
    OR EXISTS(SELECT 1 FROM community_notifications WHERE kind LIKE 'helpdesk_%')
    OR EXISTS(SELECT 1 FROM user_roles ur JOIN roles r ON r.id=ur.role_id
      WHERE r.slug IN ('helpdesk_admin','support_manager','support_agent')) THEN
    RAISE EXCEPTION 'Help Desk contains records or assigned roles. Export/backup and review a forward migration instead.';
  END IF;
END $$;
DROP TABLE helpdesk_request_mutes,helpdesk_message_reads,helpdesk_request_attachments,
  helpdesk_request_messages,helpdesk_internal_notes,helpdesk_status_history,
  helpdesk_request_assignments,helpdesk_requests,helpdesk_departments,
  helpdesk_faqs,helpdesk_announcements;
DROP SEQUENCE helpdesk_reference_seq;
ALTER TABLE notification_preferences DROP COLUMN helpdesk_updates;
ALTER TABLE community_notifications DROP CONSTRAINT community_notifications_kind_check;
ALTER TABLE community_notifications ADD CONSTRAINT community_notifications_kind_check CHECK(kind IN (
 'private_message','group_message','group_invitation','comment','reply','post_reaction','announcement','moderation_action'));
DELETE FROM permissions WHERE key IN ('helpdesk:manage','helpdesk:agent');
DELETE FROM roles WHERE slug IN ('helpdesk_admin','support_manager','support_agent');
DELETE FROM app_schema_migrations WHERE name IN ('0006_helpdesk','0007_helpdesk_guards');
COMMIT;
