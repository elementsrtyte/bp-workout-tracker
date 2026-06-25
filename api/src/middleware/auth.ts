import type { NextFunction, Request, Response } from "express";
import { verifyAuthUser } from "../services/auth-service.js";

export type AuthedRequest = Request & {
  user?: { id: string; email: string | null };
};

/** Requires `Authorization: Bearer <access token>`. */
export async function requireAuth(req: Request, _res: Response, next: NextFunction): Promise<void> {
  try {
    const user = await verifyAuthUser(req.header("authorization") ?? req.header("Authorization"));
    (req as AuthedRequest).user = user;
    next();
  } catch (e) {
    next(e);
  }
}
