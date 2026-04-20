import { HttpError } from "../lib/http-error.js";

/** Comma-separated emails allowed for catalog publish, seed edits, and workout cleanup. */
export function platformAdminEmails(): string[] {
  const fromList =
    process.env.ADMIN_EMAILS?.split(",").map((s) => s.trim().toLowerCase()).filter(Boolean) ?? [];
  const fromCatalog =
    process.env.CATALOG_ADMIN_EMAILS?.split(",").map((s) => s.trim().toLowerCase()).filter(Boolean) ??
    [];
  const oneAdmin = process.env.ADMIN_EMAIL?.trim().toLowerCase();
  const oneCatalog = process.env.CATALOG_ADMIN_EMAIL?.trim().toLowerCase();
  const set = new Set<string>([...fromList, ...fromCatalog]);
  if (oneAdmin) set.add(oneAdmin);
  if (oneCatalog) set.add(oneCatalog);
  return [...set];
}

export function assertPlatformAdmin(email: string | null): void {
  const allow = platformAdminEmails();
  if (allow.length === 0) {
    throw new HttpError(
      503,
      "Platform admin is not configured (set ADMIN_EMAILS and/or CATALOG_ADMIN_EMAILS)"
    );
  }
  if (!email || !allow.includes(email.trim().toLowerCase())) {
    throw new HttpError(403, "Not authorized for admin operations");
  }
}

export function logAdminAction(
  email: string | null,
  action: string,
  detail: Record<string, unknown>
): void {
  const payload = { admin_email: email ?? "unknown", action, ...detail };
  console.info(`[admin] ${JSON.stringify(payload)}`);
}
