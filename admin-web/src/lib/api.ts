function apiBase(): string {
  const u = import.meta.env.VITE_BLUEPRINT_API_URL?.trim() ?? "";
  return u.replace(/\/$/, "");
}

export class ApiError extends Error {
  status: number;
  body?: string;

  constructor(message: string, status: number, body?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.body = body;
  }
}

export async function apiFetch(
  path: string,
  token: string,
  init: RequestInit = {}
): Promise<Response> {
  const base = apiBase();
  if (!base) {
    throw new ApiError("VITE_BLUEPRINT_API_URL is not set", 0);
  }
  const url = `${base}${path.startsWith("/") ? path : `/${path}`}`;
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${token}`);
  if (init.body !== undefined && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  return fetch(url, { ...init, headers });
}

export async function apiJson<T>(path: string, token: string, init: RequestInit = {}): Promise<T> {
  const res = await apiFetch(path, token, init);
  const text = await res.text();
  if (!res.ok) {
    throw new ApiError(`API ${res.status}`, res.status, text);
  }
  if (!text) return undefined as T;
  return JSON.parse(text) as T;
}
