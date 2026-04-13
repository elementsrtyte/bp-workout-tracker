import type { NextFunction, Request, Response } from "express";
import { HttpError } from "./httpError.js";
import { fetchSupabaseAuthUser, restJsonServiceRole } from "./supabaseData.js";
import { parseProgram, replaceCatalogProgramGraph } from "./catalogPublish.js";

function assertUserAuthoredProgramId(id: string): void {
  const t = id.trim();
  if (!t.startsWith("user-")) {
    throw new HttpError(400, "Shared programs must use an id starting with \"user-\"");
  }
}

/**
 * Authenticated users can insert or update their own public catalog program (`created_by` = JWT sub).
 * Official rows (`created_by` null) cannot be overwritten here.
 */
export async function postPublishUserProgram(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const auth = req.header("authorization") ?? req.header("Authorization");
    const user = await fetchSupabaseAuthUser(auth);
    const parsed = parseProgram(req.body);
    const program = { ...parsed, isUserCreated: true };

    const rows = await restJsonServiceRole<{ id: string; created_by: string | null }[]>(
      "catalog_programs",
      "GET",
      undefined,
      `select=id,created_by&id=eq.${encodeURIComponent(program.id)}`
    );
    const existing = rows[0];

    if (!existing) {
      assertUserAuthoredProgramId(program.id);
      const catalogVersion = await replaceCatalogProgramGraph(program, {
        kind: "insert",
        createdBy: user.id,
      });
      res.json({ ok: true, programId: program.id, catalogVersion });
      return;
    }

    if (existing.created_by === null) {
      throw new HttpError(403, "Cannot publish over an official catalog program");
    }
    if (existing.created_by !== user.id) {
      throw new HttpError(403, "This program is owned by another account");
    }

    const catalogVersion = await replaceCatalogProgramGraph(program, { kind: "patch" });
    res.json({ ok: true, programId: program.id, catalogVersion });
  } catch (e) {
    next(e);
  }
}

/** Remove a user-owned program from the shared catalog (local copy unaffected). */
export async function postUnpublishUserProgram(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const auth = req.header("authorization") ?? req.header("Authorization");
    const user = await fetchSupabaseAuthUser(auth);
    const rawId = (req.body as { id?: unknown })?.id;
    const id = typeof rawId === "string" ? rawId.trim() : "";
    if (!id) throw new HttpError(400, "id required");
    assertUserAuthoredProgramId(id);

    const rows = await restJsonServiceRole<{ id: string; created_by: string | null }[]>(
      "catalog_programs",
      "GET",
      undefined,
      `select=id,created_by&id=eq.${encodeURIComponent(id)}`
    );
    const existing = rows[0];
    if (!existing) {
      res.json({ ok: true, removed: false });
      return;
    }
    if (existing.created_by === null) {
      throw new HttpError(403, "Cannot unpublish an official catalog program");
    }
    if (existing.created_by !== user.id) {
      throw new HttpError(403, "Not authorized to unpublish this program");
    }

    await restJsonServiceRole("catalog_programs", "DELETE", undefined, `id=eq.${encodeURIComponent(id)}`);

    const rel = await restJsonServiceRole<{ version: number }[]>(
      "catalog_release",
      "GET",
      undefined,
      "select=version&id=eq.1"
    );
    const prev = rel[0]?.version;
    const nextVersion = typeof prev === "number" && Number.isFinite(prev) ? prev + 1 : 1;

    await restJsonServiceRole(
      "catalog_release",
      "PATCH",
      {
        version: nextVersion,
        notes: `unpublish:${id}`,
        published_at: new Date().toISOString(),
      },
      "id=eq.1"
    );

    res.json({ ok: true, removed: true, catalogVersion: nextVersion });
  } catch (e) {
    next(e);
  }
}
