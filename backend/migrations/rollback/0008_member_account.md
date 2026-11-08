# Migration 0008 rollback (operator runbook)

Migration 0008 adds account-consent timestamps, scheduled-deletion timestamps,
self-reported profile locations, and private-avatar storage keys. It does not
change old roles, identity records, community records, or regional grants.

Rollback is intentionally not an automatic production command. First deploy
application code that no longer reads/writes these columns; stop account API
traffic; verify and securely preserve any locations, deletion requests and
private avatar files required by the organization's approved retention policy.
Do not remove a pending deletion request simply to make a migration succeed.

Only after authorization and the data review, an operator can drop the new
schema in a transaction:

```sql
BEGIN;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM users WHERE deletion_requested_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Review pending account-deletion requests before rollback';
  END IF;
END $$;
DROP INDEX IF EXISTS users_deletion_schedule_idx;
ALTER TABLE user_profiles DROP COLUMN IF EXISTS avatar_storage_key;
ALTER TABLE user_profiles DROP COLUMN IF EXISTS village_label;
ALTER TABLE user_profiles DROP COLUMN IF EXISTS qoum_label;
ALTER TABLE user_profiles DROP COLUMN IF EXISTS district_label;
ALTER TABLE user_profiles DROP COLUMN IF EXISTS region_label;
ALTER TABLE users DROP COLUMN IF EXISTS deletion_scheduled_for;
ALTER TABLE users DROP COLUMN IF EXISTS deletion_requested_at;
ALTER TABLE users DROP COLUMN IF EXISTS terms_version;
ALTER TABLE users DROP COLUMN IF EXISTS terms_accepted_at;
COMMIT;
```

This discards the new profile-location and consent/deletion metadata. Private
avatar files must be securely removed separately only after the retention
review authorizes their removal. Never run this downgrade automatically or
against production without a verified recovery plan.
