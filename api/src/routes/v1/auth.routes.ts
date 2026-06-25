import type { NextFunction, Request, Response } from "express";
import { Router } from "express";
import { HttpError } from "../../lib/http-error.js";
import { requireAuth, type AuthedRequest } from "../../middleware/auth.js";
import {
  changePassword,
  refreshSession,
  signIn,
  signUp,
} from "../../services/auth-service.js";

export const authRouter = Router();

authRouter.post("/signup", async (req, res, next) => {
  try {
    const email = typeof req.body?.email === "string" ? req.body.email : "";
    const password = typeof req.body?.password === "string" ? req.body.password : "";
    const session = await signUp(email, password);
    res.json(session);
  } catch (e) {
    next(e);
  }
});

/** POST /v1/auth/token — Supabase-compatible (grant_type in query or body). */
authRouter.post("/token", async (req, res, next) => {
  try {
    const grant =
      (typeof req.query.grant_type === "string" ? req.query.grant_type : "") ||
      (typeof req.body?.grant_type === "string" ? req.body.grant_type : "");
    if (grant === "password") {
      const email = typeof req.body?.email === "string" ? req.body.email : "";
      const password = typeof req.body?.password === "string" ? req.body.password : "";
      res.json(await signIn(email, password));
      return;
    }
    if (grant === "refresh_token") {
      const refresh =
        typeof req.body?.refresh_token === "string" ? req.body.refresh_token : "";
      if (!refresh) throw new HttpError(400, "refresh_token required");
      res.json(await refreshSession(refresh));
      return;
    }
    throw new HttpError(400, "Unsupported grant_type");
  } catch (e) {
    next(e);
  }
});

authRouter.post("/signin", async (req, res, next) => {
  try {
    const email = typeof req.body?.email === "string" ? req.body.email : "";
    const password = typeof req.body?.password === "string" ? req.body.password : "";
    res.json(await signIn(email, password));
  } catch (e) {
    next(e);
  }
});

authRouter.get("/user", requireAuth, async (req, res, next) => {
  try {
    const user = (req as AuthedRequest).user!;
    res.json({ id: user.id, email: user.email });
  } catch (e) {
    next(e);
  }
});

authRouter.patch("/user", requireAuth, async (req, res, next) => {
  try {
    const user = (req as AuthedRequest).user!;
    const password = typeof req.body?.password === "string" ? req.body.password : "";
    await changePassword(user.id, password);
    res.status(204).end();
  } catch (e) {
    next(e);
  }
});

/** Password reset email — stub until SMTP is configured. */
authRouter.post("/recover", async (_req, res) => {
  res.status(204).end();
});
