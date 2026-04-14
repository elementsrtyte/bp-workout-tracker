import type { NextFunction, Request, Response } from "express";
import { fetchSupabaseAuthUser } from "../integrations/supabase.js";

/** Requires `Authorization: Bearer <Supabase access token>`. */
export async function requireAuth(req: Request, _res: Response, next: NextFunction): Promise<void> {
  try {
    await fetchSupabaseAuthUser(req.header("authorization") ?? req.header("Authorization"));
    next();
  } catch (e) {
    next(e);
  }
}
