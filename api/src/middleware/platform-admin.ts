import type { NextFunction, Request, Response } from "express";
import { fetchSupabaseAuthUser } from "../integrations/supabase.js";
import { assertPlatformAdmin } from "../services/platform-admin.js";

export type AdminRequest = Request & {
  adminEmail: string | null;
  adminUserId: string;
};

export async function requirePlatformAdmin(
  req: Request,
  _res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const user = await fetchSupabaseAuthUser(
      req.header("authorization") ?? req.header("Authorization")
    );
    assertPlatformAdmin(user.email);
    (req as AdminRequest).adminEmail = user.email;
    (req as AdminRequest).adminUserId = user.id;
    next();
  } catch (e) {
    next(e);
  }
}
