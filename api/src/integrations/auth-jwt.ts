import crypto from "node:crypto";
import jwt from "jsonwebtoken";
import { HttpError } from "../lib/http-error.js";

export type AccessTokenPayload = {
  sub: string;
  email: string | null;
};

const ACCESS_TTL_SEC = 60 * 60; // 1 hour
const REFRESH_TTL_SEC = 60 * 60 * 24 * 30; // 30 days

function jwtSecret(): string {
  const s = process.env.JWT_SECRET?.trim();
  if (!s || s.length < 32) {
    throw new Error("JWT_SECRET must be set (min 32 chars)");
  }
  return s;
}

export function signAccessToken(userId: string, email: string | null): { token: string; expiresIn: number } {
  const expiresIn = ACCESS_TTL_SEC;
  const token = jwt.sign({ sub: userId, email }, jwtSecret(), { expiresIn });
  return { token, expiresIn };
}

export function verifyAccessToken(token: string): AccessTokenPayload {
  try {
    const decoded = jwt.verify(token, jwtSecret()) as jwt.JwtPayload;
    const sub = decoded.sub;
    if (typeof sub !== "string" || !sub) {
      throw new HttpError(401, "Invalid token subject");
    }
    const email =
      typeof decoded.email === "string" && decoded.email.trim().length > 0
        ? decoded.email.trim().toLowerCase()
        : null;
    return { sub, email };
  } catch (e) {
    if (e instanceof HttpError) throw e;
    throw new HttpError(401, "Invalid or expired session");
  }
}

export function newRefreshToken(): string {
  return crypto.randomBytes(32).toString("base64url");
}

export function hashRefreshToken(token: string): string {
  return crypto.createHash("sha256").update(token).digest("hex");
}

export function refreshExpiresAt(): Date {
  return new Date(Date.now() + REFRESH_TTL_SEC * 1000);
}

export function sessionResponse(userId: string, email: string | null, refreshToken: string) {
  const { token, expiresIn } = signAccessToken(userId, email);
  return {
    access_token: token,
    refresh_token: refreshToken,
    expires_in: expiresIn,
    user: { id: userId, email },
  };
}
