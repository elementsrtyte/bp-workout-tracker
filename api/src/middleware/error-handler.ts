import type { NextFunction, Request, Response } from "express";
import type { MulterError } from "multer";
import { HttpError } from "../lib/http-error.js";

function isMulterError(e: unknown): e is MulterError {
  return typeof e === "object" && e !== null && "code" in e;
}

export function errorHandler(
  err: unknown,
  _req: Request,
  res: Response,
  _next: NextFunction
): void {
  if (err instanceof HttpError) {
    res.status(err.status).json({ error: err.message });
    return;
  }
  if (isMulterError(err)) {
    const msg =
      err.code === "LIMIT_FILE_SIZE" ? "File too large (max 2MB)" : err.message;
    res.status(400).json({ error: msg });
    return;
  }
  console.error(err);
  res.status(500).json({ error: "Internal server error" });
}
