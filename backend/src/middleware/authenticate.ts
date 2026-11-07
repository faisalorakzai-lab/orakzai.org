import type { NextFunction, Request, Response } from "express";

import { pool } from "../db/pool.js";
import { HttpError } from "../http/errors.js";
import { verifyAccessToken } from "../security.js";

export async function requireAuth(
  request: Request,
  _response: Response,
  next: NextFunction,
): Promise<void> {
  try {
    const [scheme, token] = (request.get("authorization") ?? "").split(" ");
    if (scheme !== "Bearer" || !token) {
      throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
    }

    const principal = verifyAccessToken(token);
    const result = await pool.query(
      `SELECT s.id
       FROM user_sessions s
       JOIN users u ON u.id = s.user_id
       WHERE s.id = $1
         AND s.user_id = $2
         AND s.revoked_at IS NULL
         AND s.expires_at > now()
         AND u.account_status = 'active'
         AND u.email_verified_at IS NOT NULL`,
      [principal.sessionId, principal.userId],
    );
    if (result.rowCount !== 1) {
      throw new HttpError(401, "UNAUTHENTICATED", "Please sign in again.");
    }
    request.auth = principal;
    next();
  } catch (error) {
    next(error);
  }
}

export function requirePermission(permission: string) {
  return async (
    request: Request,
    _response: Response,
    next: NextFunction,
  ): Promise<void> => {
    try {
      if (!request.auth) {
        throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
      }
      const result = await pool.query(
        `SELECT 1
         FROM user_roles ur
         JOIN role_permissions rp ON rp.role_id = ur.role_id
         JOIN permissions p ON p.id = rp.permission_id
         WHERE ur.user_id = $1 AND p.key = $2
         LIMIT 1`,
        [request.auth.userId, permission],
      );
      if (result.rowCount !== 1) {
        throw new HttpError(403, "FORBIDDEN", "You do not have permission for this action.");
      }
      next();
    } catch (error) {
      next(error);
    }
  };
}
