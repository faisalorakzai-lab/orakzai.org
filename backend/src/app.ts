import cors from "cors";
import express, { type ErrorRequestHandler } from "express";
import helmet from "helmet";

import { config } from "./config.js";
import { HttpError } from "./http/errors.js";
import authRouter from "./routes/auth.js";
import adminRouter from "./routes/admin.js";
import usersRouter from "./routes/users.js";

export function createApp() {
  const app = express();
  app.disable("x-powered-by");
  app.set("trust proxy", 1);
  app.use(helmet());
  app.use(
    cors({
      origin(origin, callback) {
        if (!origin || config.corsOrigins.includes(origin)) {
          callback(null, true);
          return;
        }
        callback(new HttpError(403, "ORIGIN_NOT_ALLOWED", "This app origin is not allowed."));
      },
    }),
  );
  app.use(express.json({ limit: "32kb" }));

  app.get("/api/health", (_request, response) => {
    response.json({ status: "ok", service: "orakzai-auth-api" });
  });
  app.use("/api/auth", authRouter);
  app.use("/api/users", usersRouter);
  app.use("/api/admin", adminRouter);
  app.use((_request, response) => {
    response.status(404).json({
      error: { code: "NOT_FOUND", message: "The requested endpoint was not found." },
    });
  });

  const errorHandler: ErrorRequestHandler = (error, _request, response, _next) => {
    if (error instanceof HttpError) {
      response.status(error.status).json({
        error: { code: error.code, message: error.message },
      });
      return;
    }
    response.status(500).json({
      error: {
        code: "INTERNAL_ERROR",
        message: "The request could not be completed.",
      },
    });
  };
  app.use(errorHandler);
  return app;
}
