const apiBase = (import.meta.env.VITE_BLUEPRINT_API_URL ?? "").replace(/\/$/, "");

export type AuthSession = {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  user?: { id: string; email: string | null };
};

const SESSION_KEY = "bp.admin.session";

export const authConfigured = apiBase.length > 0;

export function loadStoredSession(): AuthSession | null {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as AuthSession;
  } catch {
    return null;
  }
}

export function saveSession(session: AuthSession | null): void {
  if (!session) {
    localStorage.removeItem(SESSION_KEY);
    return;
  }
  localStorage.setItem(SESSION_KEY, JSON.stringify(session));
}

function parseError(data: unknown, status: number): string {
  if (data && typeof data === "object") {
    const o = data as Record<string, unknown>;
    if (typeof o.message === "string") return o.message;
    if (typeof o.error === "string") return o.error;
  }
  return `Auth failed (${status})`;
}

export async function signInWithPassword(email: string, password: string): Promise<AuthSession> {
  const url = `${apiBase}/v1/auth/token?grant_type=password`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(parseError(data, res.status));
  return data as AuthSession;
}

export async function refreshStoredSession(refreshToken: string): Promise<AuthSession> {
  const url = `${apiBase}/v1/auth/token?grant_type=refresh_token`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(parseError(data, res.status));
  return data as AuthSession;
}
