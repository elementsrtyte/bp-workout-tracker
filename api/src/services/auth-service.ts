import bcrypt from "bcryptjs";
import { query, withTransaction } from "../db/pool.js";
import { HttpError } from "../lib/http-error.js";
import {
  hashRefreshToken,
  newRefreshToken,
  refreshExpiresAt,
  sessionResponse,
  verifyAccessToken,
} from "../integrations/auth-jwt.js";

type UserRow = { id: string; email: string | null; password_hash: string };

async function findUserByEmail(email: string): Promise<UserRow | null> {
  const normalized = email.trim().toLowerCase();
  const r = await query<UserRow>(
    `SELECT id, email, password_hash FROM users WHERE lower(email) = $1 LIMIT 1`,
    [normalized]
  );
  return r.rows[0] ?? null;
}

async function findUserById(id: string): Promise<{ id: string; email: string | null } | null> {
  const r = await query<{ id: string; email: string | null }>(
    `SELECT id, email FROM users WHERE id = $1 LIMIT 1`,
    [id]
  );
  return r.rows[0] ?? null;
}

async function storeRefreshToken(userId: string, rawToken: string): Promise<void> {
  await query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)`,
    [userId, hashRefreshToken(rawToken), refreshExpiresAt()]
  );
}

async function issueSession(userId: string, email: string | null) {
  const refresh = newRefreshToken();
  await storeRefreshToken(userId, refresh);
  return sessionResponse(userId, email, refresh);
}

export async function signUp(email: string, password: string) {
  const normalized = email.trim().toLowerCase();
  if (!normalized || !password || password.length < 8) {
    throw new HttpError(400, "Valid email and password (min 8 chars) required");
  }
  const existing = await findUserByEmail(normalized);
  if (existing) throw new HttpError(409, "An account with this email already exists");

  const hash = await bcrypt.hash(password, 12);
  return withTransaction(async (client) => {
    const ins = await client.query<{ id: string }>(
      `INSERT INTO users (id, email, password_hash) VALUES (gen_random_uuid(), $1, $2) RETURNING id`,
      [normalized, hash]
    );
    const userId = ins.rows[0]?.id;
    if (!userId) throw new HttpError(500, "Failed to create user");
    await client.query(
      `INSERT INTO profiles (id, email) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING`,
      [userId, normalized]
    );
    const refresh = newRefreshToken();
    await client.query(
      `INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)`,
      [userId, hashRefreshToken(refresh), refreshExpiresAt()]
    );
    return sessionResponse(userId, normalized, refresh);
  });
}

export async function signIn(email: string, password: string) {
  const user = await findUserByEmail(email);
  if (!user) throw new HttpError(401, "Invalid email or password");
  const ok = await bcrypt.compare(password, user.password_hash);
  if (!ok) throw new HttpError(401, "Invalid email or password");
  return issueSession(user.id, user.email);
}

export async function refreshSession(rawRefreshToken: string) {
  const hash = hashRefreshToken(rawRefreshToken);
  const r = await query<{ user_id: string; id: string }>(
    `SELECT id, user_id FROM refresh_tokens
     WHERE token_hash = $1 AND expires_at > now()
     LIMIT 1`,
    [hash]
  );
  const row = r.rows[0];
  if (!row) throw new HttpError(401, "Invalid or expired refresh token");

  const user = await findUserById(row.user_id);
  if (!user) throw new HttpError(401, "User not found");

  await query(`DELETE FROM refresh_tokens WHERE id = $1`, [row.id]);
  return issueSession(user.id, user.email);
}

export async function changePassword(userId: string, newPassword: string) {
  if (!newPassword || newPassword.length < 8) {
    throw new HttpError(400, "Password must be at least 8 characters");
  }
  const hash = await bcrypt.hash(newPassword, 12);
  await query(`UPDATE users SET password_hash = $1 WHERE id = $2`, [hash, userId]);
}

export async function verifyAuthUser(authorization: string | undefined): Promise<{ id: string; email: string | null }> {
  if (!authorization?.startsWith("Bearer ")) {
    throw new HttpError(401, "Missing or invalid Authorization header");
  }
  const token = authorization.slice(7).trim();
  if (!token) throw new HttpError(401, "Empty bearer token");

  const payload = verifyAccessToken(token);
  return { id: payload.sub, email: payload.email };
}
