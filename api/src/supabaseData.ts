import { HttpError } from "./httpError.js";

export async function fetchSupabaseAuthUser(
  authorization: string | undefined
): Promise<{ id: string; email: string | null }> {
  if (!authorization?.startsWith("Bearer ")) {
    throw new HttpError(401, "Missing or invalid Authorization header");
  }
  const token = authorization.slice(7).trim();
  if (!token) throw new HttpError(401, "Empty bearer token");

  const supabaseUrl = requireEnvAny("SUPABASE_URL", "supabase_url").replace(/\/$/, "");
  const anon = requireEnvAny("SUPABASE_ANON_KEY", "supabase_anon_key");

  const r = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      apikey: anon,
      Authorization: `Bearer ${token}`,
    },
  });

  if (!r.ok) {
    throw new HttpError(401, "Invalid or expired session");
  }
  const j = (await r.json()) as { id?: string; email?: string };
  if (!j.id || typeof j.id !== "string") {
    throw new HttpError(401, "Invalid user payload");
  }
  const email =
    typeof j.email === "string" && j.email.trim().length > 0
      ? j.email.trim().toLowerCase()
      : null;
  return { id: j.id, email };
}

function requireEnvAny(...names: string[]): string {
  for (const name of names) {
    const v = process.env[name]?.trim();
    if (v) return v;
  }
  throw new Error(`Missing required env: ${names.join(" or ")}`);
}

export function supabaseRestBase(): string {
  return `${requireEnvAny("SUPABASE_URL", "supabase_url").replace(/\/$/, "")}/rest/v1`;
}

export function supabaseAnonKey(): string {
  return requireEnvAny("SUPABASE_ANON_KEY", "supabase_anon_key");
}

/** Service role JWT: bypasses RLS; use only on trusted server routes. */
export function supabaseServiceRoleKey(): string {
  return requireEnvAny("SUPABASE_SERVICE_ROLE_KEY", "supabase_service_role_key");
}

export async function restFetchServiceRole(
  table: string,
  init: RequestInit & { search?: string }
): Promise<Response> {
  const key = supabaseServiceRoleKey();
  const url = new URL(`${supabaseRestBase()}/${table}`);
  if (init.search) {
    url.search = init.search;
  }
  const { search: _s, ...rest } = init;
  const baseHeaders: Record<string, string> = {
    apikey: key,
    Authorization: `Bearer ${key}`,
    Accept: "application/json",
  };
  if (rest.body !== undefined && !(rest.headers as Record<string, string> | undefined)?.["Content-Type"]) {
    baseHeaders["Content-Type"] = "application/json";
  }
  return fetch(url, {
    ...rest,
    headers: {
      ...baseHeaders,
      ...((rest.headers as Record<string, string>) ?? {}),
    },
  });
}

export async function restJsonServiceRole<T>(
  table: string,
  method: "GET" | "PATCH" | "POST" | "DELETE",
  body?: unknown,
  search?: string,
  extraHeaders?: Record<string, string>
): Promise<T> {
  const headers: Record<string, string> = { ...extraHeaders };
  const init: RequestInit & { search?: string } = {
    method,
    search,
    headers,
  };
  if (body !== undefined) {
    init.body = JSON.stringify(body);
  }
  const r = await restFetchServiceRole(table, init);
  if (!r.ok) {
    const text = await r.text();
    throw new HttpError(502, `PostgREST ${table} failed: ${r.status} ${text.slice(0, 240)}`);
  }
  if (r.status === 204 || r.headers.get("content-length") === "0") {
    return undefined as T;
  }
  const ct = r.headers.get("content-type") ?? "";
  if (!ct.includes("application/json")) {
    return undefined as T;
  }
  return r.json() as Promise<T>;
}

/** PostgREST request; `jwt` is user access token or anon JWT for public reads. */
export async function restFetch(
  table: string,
  jwt: string,
  init: RequestInit & { search?: string }
): Promise<Response> {
  const anon = supabaseAnonKey();
  const url = new URL(`${supabaseRestBase()}/${table}`);
  if (init.search) {
    url.search = init.search;
  }
  const { search: _s, ...rest } = init;
  return fetch(url, {
    ...rest,
    headers: {
      apikey: anon,
      Authorization: `Bearer ${jwt}`,
      Accept: "application/json",
      ...((rest.headers as Record<string, string>) ?? {}),
    },
  });
}

export async function restJson<T>(table: string, jwt: string, search?: string): Promise<T> {
  const r = await restFetch(table, jwt, { method: "GET", search });
  if (!r.ok) {
    const text = await r.text();
    throw new HttpError(502, `PostgREST ${table} failed: ${r.status} ${text.slice(0, 240)}`);
  }
  return r.json() as Promise<T>;
}
