import { Router } from "express";
import { z } from "zod";

import { pool } from "../db/pool.js";
import { requireAuth, requirePermission } from "../middleware/authenticate.js";
import { HttpError } from "../http/errors.js";

const adminRouter = Router();
const roleSchema = z.object({ roleSlug: z.string().regex(/^[a-z_]+$/) }).strict();
const memberIdSchema = z.object({ memberId: z.string().trim().min(3).max(40) }).strict();

adminRouter.post(
  "/users/:userId/roles",
  requireAuth,
  requirePermission("roles:assign"),
  async (request, response) => {
    if (!request.auth) throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
    if (request.params.userId === request.auth.userId) {
      throw new HttpError(403, "SELF_ROLE_ASSIGNMENT", "You cannot change your own roles.");
    }
    const parsed = roleSchema.safeParse(request.body);
    if (!parsed.success) {
      throw new HttpError(400, "VALIDATION_ERROR", "Select a valid role.");
    }
    const result = await pool.query<{ id: string }>(
      "SELECT id FROM roles WHERE slug = $1",
      [parsed.data.roleSlug],
    );
    const role = result.rows[0];
    if (!role) throw new HttpError(404, "ROLE_NOT_FOUND", "Role not found.");

    await pool.query(
      `INSERT INTO user_roles (user_id, role_id, granted_by)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, role_id) DO NOTHING`,
      [request.params.userId, role.id, request.auth.userId],
    );
    await pool.query(
      `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata)
       VALUES ($1, 'roles.assigned', 'user', $2, jsonb_build_object('role', $3))`,
      [request.auth.userId, request.params.userId, parsed.data.roleSlug],
    );
    response.status(204).end();
  },
);

adminRouter.patch(
  "/users/:userId/member-id",
  requireAuth,
  requirePermission("members:assign_id"),
  async (request, response) => {
    if (!request.auth) throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
    const parsed = memberIdSchema.safeParse(request.body);
    if (!parsed.success) {
      throw new HttpError(400, "VALIDATION_ERROR", "Enter a valid member ID.");
    }
    const updated = await pool.query(
      `UPDATE user_profiles
       SET member_id = $1, updated_at = now()
       WHERE user_id = $2`,
      [parsed.data.memberId, request.params.userId],
    );
    if (updated.rowCount !== 1) {
      throw new HttpError(404, "USER_NOT_FOUND", "Account not found.");
    }
    await pool.query(
      `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id)
       VALUES ($1, 'members.member_id_assigned', 'user', $2)`,
      [request.auth.userId, request.params.userId],
    );
    response.status(204).end();
  },
);

export default adminRouter;
