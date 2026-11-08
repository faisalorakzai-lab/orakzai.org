import { Router } from "express";
import multer from "multer";

import { HttpError } from "../http/errors.js";
import { requireAuth } from "../middleware/authenticate.js";
import { createMediaAccessUrl, readMedia, uploadMedia } from "../services/media-service.js";

const mediaRouter = Router();
const uploadFile = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 25 * 1024 * 1024, files: 1 },
});

function userId(request: { auth?: { userId: string } }) {
  if (!request.auth) throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
  return request.auth.userId;
}

mediaRouter.use(requireAuth);

mediaRouter.post("/upload", (request, response, next) => {
  uploadFile.single("file")(request, response, (error) => {
    if (error instanceof multer.MulterError) {
      if (error.code === "LIMIT_FILE_SIZE") {
        next(new HttpError(413, "MEDIA_SIZE_INVALID", "Files must be smaller than 25 MB."));
        return;
      }
      next(new HttpError(400, "UPLOAD_INVALID", "The file upload could not be read."));
      return;
    }
    if (error) {
      next(error);
      return;
    }
    void (async () => {
      if (!request.file) throw new HttpError(400, "FILE_REQUIRED", "Choose a file to upload.");
      const media = await uploadMedia(userId(request), request.file);
      response.status(201).json({ media });
    })().catch(next);
  });
});

mediaRouter.get("/:mediaId/access", async (request, response) => {
  const result = await createMediaAccessUrl(
    userId(request),
    request.params.mediaId,
  );
  response.json(result);
});

mediaRouter.get("/:mediaId/content", async (request, response) => {
  const expires = request.query.expires;
  const signature = request.query.signature;
  if (typeof expires !== "string" || typeof signature !== "string") {
    throw new HttpError(403, "MEDIA_URL_INVALID", "The file access link is invalid.");
  }
  const { media, buffer } = await readMedia(
    userId(request),
    request.params.mediaId,
    expires,
    signature,
  );
  const asciiName = media.name.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_");
  response
    .setHeader("Content-Type", media.contentType)
    .setHeader("Content-Length", buffer.length)
    .setHeader("Content-Disposition", `attachment; filename="${asciiName}"; filename*=UTF-8''${encodeURIComponent(media.name)}`)
    .setHeader("Cache-Control", "private, no-store")
    .setHeader("X-Content-Type-Options", "nosniff")
    .send(buffer);
});

export default mediaRouter;
