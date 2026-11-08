import { Router } from "express";
import { z } from "zod";

import { requireAuth } from "../middleware/authenticate.js";
import { HttpError } from "../http/errors.js";
import {
  getUserPermissions,
  getUserProfile,
  updateUserProfile,
} from "../services/user-service.js";

const usersRouter = Router();

const profileSchema = z
  .object({
    fullName: z.string().trim().min(2).max(100).optional(),
    username: z.string().trim().min(3).max(30).regex(/^[A-Za-z0-9_]+$/).nullable().optional(),
    profilePhotoUrl: z.string().url().max(2048).nullable().optional(),
    city: z.string().trim().max(100).nullable().optional(),
    country: z.string().trim().max(100).nullable().optional(),
    region: z.string().trim().max(100).nullable().optional(),
    district: z.string().trim().max(100).nullable().optional(),
    qoum: z.string().trim().max(100).nullable().optional(),
    village: z.string().trim().max(100).nullable().optional(),
    profession: z.string().trim().max(120).nullable().optional(),
    skills: z.array(z.string().trim().min(1).max(60)).max(30).optional(),
    education: z.string().trim().max(200).nullable().optional(),
    biography: z.string().trim().max(500).nullable().optional(),
    showCityPublicly: z.boolean().optional(),
    showProfessionPublicly: z.boolean().optional(),
    showSkillsPublicly: z.boolean().optional(),
    showEducationPublicly: z.boolean().optional(),
    allowProfileSearch: z.boolean().optional(),
  })
  .strict();

usersRouter.get("/me", requireAuth, async (request, response) => {
  if (!request.auth) throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
  response.json({ user: await getUserProfile(request.auth.userId) });
});

usersRouter.patch("/me", requireAuth, async (request, response) => {
  if (!request.auth) throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
  const parsed = profileSchema.safeParse(request.body);
  if (!parsed.success) {
    throw new HttpError(400, "VALIDATION_ERROR", parsed.error.issues[0]?.message ?? "Invalid profile.");
  }
  response.json({
    user: await updateUserProfile(request.auth.userId, parsed.data),
  });
});

usersRouter.get("/me/permissions", requireAuth, async (request, response) => {
  if (!request.auth) throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
  response.json(await getUserPermissions(request.auth.userId));
});

export default usersRouter;
