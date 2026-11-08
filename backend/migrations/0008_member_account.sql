-- Additive only: self-reported location never changes regional role grants.
ALTER TABLE users ADD COLUMN IF NOT EXISTS terms_accepted_at timestamptz;
ALTER TABLE users ADD COLUMN IF NOT EXISTS terms_version text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deletion_requested_at timestamptz;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deletion_scheduled_for timestamptz;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS region_label text CHECK (char_length(region_label)<=100);
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS district_label text CHECK (char_length(district_label)<=100);
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS qoum_label text CHECK (char_length(qoum_label)<=100);
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS village_label text CHECK (char_length(village_label)<=100);
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS avatar_storage_key text;
CREATE INDEX IF NOT EXISTS users_deletion_schedule_idx ON users(deletion_scheduled_for)
  WHERE deletion_requested_at IS NOT NULL;
COMMENT ON COLUMN user_profiles.region_label IS 'Self-reported location, not a regional authorization grant.';
