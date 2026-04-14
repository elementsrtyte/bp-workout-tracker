import express, { type NextFunction, type Request, type Response } from "express";
import multer from "multer";

export const programImportUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2 * 1024 * 1024 },
});

/** Routes JSON (global parser), multipart `file`, or raw text to a usable `req.body` / `req.file`. */
export function programImportBodyParser(req: Request, res: Response, next: NextFunction): void {
  const ct = (req.headers["content-type"] ?? "").toLowerCase();
  if (ct.includes("multipart/form-data")) {
    programImportUpload.single("file")(req, res, next);
    return;
  }
  if (!ct.includes("application/json")) {
    express.text({ limit: "2mb", type: () => true })(req, res, next);
    return;
  }
  next();
}
