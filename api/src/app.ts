import cors from "cors";
import express from "express";
import { errorHandler } from "./middleware/error-handler.js";
import { createV1Router } from "./routes/v1/index.js";

export function createApp(): express.Express {
  const app = express();

  app.use(cors({ origin: "*" }));
  app.use(express.json({ limit: "2mb" }));

  app.get("/health", (_req, res) => {
    res.json({ ok: true, service: "bp-workout-api" });
  });

  app.use("/v1", createV1Router());

  app.use(errorHandler);

  return app;
}
