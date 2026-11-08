import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";

export type UserProfile = {
  createdAt: string;
  id: string;
  email: string;
  phone: string;
  emailVerified: boolean;
  accountStatus: string;
  profile: {
    fullName: string;
    username: string | null;
    memberId: string | null;
    profilePhotoUrl: string | null;
    city: string | null;
    country: string | null;
    region: string | null;
    district: string | null;
    qoum: string | null;
    village: string | null;
    hasProfilePhoto: boolean;
    profession: string | null;
    skills: string[];
    education: string | null;
    biography: string | null;
    privacy: {
      showCityPublicly: boolean;
      showProfessionPublicly: boolean;
      showSkillsPublicly: boolean;
      showEducationPublicly: boolean;
      allowProfileSearch: boolean;
    };
  };
  regionAssignments: Array<{
    region: string | null;
    district: string | null;
    qoum: string | null;
    village: string | null;
    primary: boolean;
  }>;
};

export async function getUserProfile(userId: string): Promise<UserProfile> {
  const userResult = await pool.query<{
    id: string;
    email: string;
    phone: string;
    email_verified_at: Date | null;
    account_status: string;
    created_at: Date;
    region_label: string | null;
    district_label: string | null;
    qoum_label: string | null;
    village_label: string | null;
    avatar_storage_key: string | null;
    full_name: string;
    username: string | null;
    member_id: string | null;
    profile_photo_url: string | null;
    city: string | null;
    country: string | null;
    profession: string | null;
    skills: string[];
    education: string | null;
    biography: string | null;
    show_city_publicly: boolean;
    show_profession_publicly: boolean;
    show_skills_publicly: boolean;
    show_education_publicly: boolean;
    allow_profile_search: boolean;
  }>(
    `SELECT u.id, u.email, u.phone, u.email_verified_at, u.account_status,u.created_at,
            p.region_label,p.district_label,p.qoum_label,p.village_label,p.avatar_storage_key,
            p.full_name, p.username, p.member_id, p.profile_photo_url,
            p.city, p.country, p.profession, p.skills, p.education, p.biography,
            p.show_city_publicly, p.show_profession_publicly,
            p.show_skills_publicly, p.show_education_publicly,
            p.allow_profile_search
     FROM users u
     JOIN user_profiles p ON p.user_id = u.id
     WHERE u.id = $1`,
    [userId],
  );
  const user = userResult.rows[0];
  if (!user) throw new HttpError(404, "USER_NOT_FOUND", "Account not found.");

  const assignments = await pool.query<{
    region: string | null;
    district: string | null;
    qoum: string | null;
    village: string | null;
    is_primary: boolean;
  }>(
    `SELECT r.name AS region, d.name AS district, q.name AS qoum,
            v.name AS village, a.is_primary
     FROM user_region_assignments a
     LEFT JOIN regions r ON r.id = a.region_id
     LEFT JOIN districts d ON d.id = a.district_id
     LEFT JOIN qoums q ON q.id = a.qoum_id
     LEFT JOIN villages v ON v.id = a.village_id
     WHERE a.user_id = $1
     ORDER BY a.is_primary DESC, a.assigned_at DESC`,
    [userId],
  );

  return {
    id: user.id,
    createdAt: user.created_at.toISOString(),
    email: user.email,
    phone: user.phone,
    emailVerified: user.email_verified_at !== null,
    accountStatus: user.account_status,
    profile: {
      fullName: user.full_name,
      username: user.username,
      memberId: user.member_id,
      profilePhotoUrl: user.profile_photo_url,
      city: user.city,
      country: user.country,
      region: user.region_label,
      district: user.district_label,
      qoum: user.qoum_label,
      village: user.village_label,
      hasProfilePhoto: Boolean(user.avatar_storage_key),
      profession: user.profession,
      skills: user.skills,
      education: user.education,
      biography: user.biography,
      privacy: {
        showCityPublicly: user.show_city_publicly,
        showProfessionPublicly: user.show_profession_publicly,
        showSkillsPublicly: user.show_skills_publicly,
        showEducationPublicly: user.show_education_publicly,
        allowProfileSearch: user.allow_profile_search,
      },
    },
    regionAssignments: assignments.rows.map((assignment) => ({
      region: assignment.region,
      district: assignment.district,
      qoum: assignment.qoum,
      village: assignment.village,
      primary: assignment.is_primary,
    })),
  };
}

const profileColumns: Record<string, string> = {
  fullName: "full_name",
  username: "username",
  profilePhotoUrl: "profile_photo_url",
  city: "city",
  country: "country",
  region: "region_label",
  district: "district_label",
  qoum: "qoum_label",
  village: "village_label",
  profession: "profession",
  skills: "skills",
  education: "education",
  biography: "biography",
  showCityPublicly: "show_city_publicly",
  showProfessionPublicly: "show_profession_publicly",
  showSkillsPublicly: "show_skills_publicly",
  showEducationPublicly: "show_education_publicly",
  allowProfileSearch: "allow_profile_search",
};

export async function updateUserProfile(
  userId: string,
  updates: Record<string, unknown>,
): Promise<UserProfile> {
  const fields = Object.entries(updates).filter(([, value]) => value !== undefined);
  if (fields.length === 0) {
    throw new HttpError(400, "EMPTY_PROFILE_UPDATE", "Provide at least one profile field.");
  }

  const values: unknown[] = [userId];
  const assignments = fields.map(([key, value], index) => {
    const column = profileColumns[key];
    if (!column) throw new HttpError(400, "INVALID_PROFILE_FIELD", "A profile field is not allowed.");
    values.push(value);
    return `${column} = $${index + 2}`;
  });
  await pool.query(
    `UPDATE user_profiles
     SET ${assignments.join(", ")}, updated_at = now()
     WHERE user_id = $1`,
    values,
  );
  await pool.query(
    "INSERT INTO audit_logs (actor_id, action, entity_type, entity_id) VALUES ($1, 'profile.updated', 'user', $1)",
    [userId],
  );
  return getUserProfile(userId);
}

export async function getUserPermissions(userId: string): Promise<{
  roles: string[];
  permissions: string[];
}> {
  const result = await pool.query<{ role_slug: string; permission_key: string }>(
    `SELECT DISTINCT r.slug AS role_slug, p.key AS permission_key
     FROM user_roles ur
     JOIN roles r ON r.id = ur.role_id
     LEFT JOIN role_permissions rp ON rp.role_id = r.id
     LEFT JOIN permissions p ON p.id = rp.permission_id
     WHERE ur.user_id = $1
     ORDER BY r.slug, p.key`,
    [userId],
  );
  return {
    roles: [...new Set(result.rows.map((row) => row.role_slug))],
    permissions: [
      ...new Set(
        result.rows
          .map((row) => row.permission_key)
          .filter((permission): permission is string => permission !== null),
      ),
    ],
  };
}
