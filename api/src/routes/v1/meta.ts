import type { Request, Response } from "express";

/** `GET /v1` — lightweight discovery document. */
export function getApiRoot(_req: Request, res: Response): void {
  res.json({
    name: "bp-workout-api",
    version: 1,
    resources: {
      health: { method: "GET", path: "/health" },
      catalogPrograms: { method: "GET", path: "/v1/catalog/programs" },
      workouts: {
        method: "POST",
        path: "/v1/workouts",
        description: "Upsert a logged workout (Bearer auth)",
      },
      exerciseSubstitutionSuggestions: {
        method: "POST",
        path: "/v1/exercises/substitution-suggestions",
        description: "AI swap ideas (Bearer auth)",
      },
      relatedExercises: {
        method: "POST",
        path: "/v1/exercises/related",
        description: "AI picks from allowed catalog names (Bearer auth)",
      },
      programImport: {
        method: "POST",
        path: "/v1/imports/programs",
        description:
          "AI import: application/json {text}, text/plain body, or multipart file field \"file\"",
      },
      publishCatalogProgram: {
        method: "POST",
        path: "/v1/admin/catalog/programs",
        description: "Replace one catalog program graph (admin Bearer auth)",
      },
    },
  });
}
