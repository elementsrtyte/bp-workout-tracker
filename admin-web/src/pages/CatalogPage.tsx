import { useCallback, useEffect, useState } from "react";
import { ApiError, apiFetch, apiJson } from "../lib/api";
import { useAuth } from "../context/AuthContext";

type Snapshot = {
  catalog_release: { version: number; notes: string | null } | null;
  exerciseCount: number;
  programs: { id: string; name: string }[];
};

export function CatalogPage() {
  const { session } = useAuth();
  const [data, setData] = useState<Snapshot | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!session?.access_token) return;
    const snap = await apiJson<Snapshot>("/v1/admin/catalog/snapshot", session.access_token);
    setData(snap);
  }, [session?.access_token]);

  useEffect(() => {
    if (!session?.access_token) return;
    let cancelled = false;
    void (async () => {
      try {
        await load();
        if (!cancelled) setError(null);
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof ApiError ? `${e.message}: ${e.body ?? ""}` : String(e));
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session?.access_token, load]);

  async function deleteProgram(programId: string, programName: string) {
    if (!session?.access_token) return;
    if (
      !window.confirm(
        `Delete catalog program “${programName}” (${programId})? This removes all its days and exercise lines from the catalog. Workouts that reference this program_id are unchanged.`
      )
    ) {
      return;
    }
    setMessage(null);
    setError(null);
    setDeletingId(programId);
    try {
      const res = await apiFetch(
        `/v1/admin/catalog/programs/${encodeURIComponent(programId)}`,
        session.access_token,
        { method: "DELETE" }
      );
      const text = await res.text();
      if (!res.ok) {
        throw new ApiError(`Delete failed ${res.status}`, res.status, text);
      }
      const body = text ? (JSON.parse(text) as { catalogVersion?: number }) : {};
      setMessage(
        `Deleted. Catalog version is now ${body.catalogVersion ?? "—"}. Clients should refetch the catalog.`
      );
      await load();
    } catch (e) {
      setError(e instanceof ApiError ? `${e.message}: ${e.body ?? ""}` : String(e));
    } finally {
      setDeletingId(null);
    }
  }

  if (error && !data) {
    return <p className="error">{error}</p>;
  }
  if (!data) {
    return <p className="muted">Loading catalog snapshot…</p>;
  }

  return (
    <div className="stack loose">
      <h1>Catalog snapshot</h1>
      <p className="muted">
        Publish program changes via <code>POST /v1/admin/catalog/programs</code>. You can remove a
        catalog program below (cascades days and day-exercise rows; canonical exercises are not
        deleted).
      </p>
      {error ? <p className="error">{error}</p> : null}
      {message ? <p className="ok">{message}</p> : null}
      <section className="card">
        <h2>Release</h2>
        {data.catalog_release ? (
          <p>
            Version <strong>{data.catalog_release.version}</strong>
            {data.catalog_release.notes ? ` — ${data.catalog_release.notes}` : ""}
          </p>
        ) : (
          <p className="muted">No catalog_release row.</p>
        )}
        <p>
          Canonical exercises: <strong>{data.exerciseCount}</strong>
        </p>
      </section>
      <section className="card">
        <h2>Programs ({data.programs.length})</h2>
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>ID</th>
                <th>Name</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {data.programs.map((p) => (
                <tr key={p.id}>
                  <td>
                    <code>{p.id}</code>
                  </td>
                  <td>{p.name}</td>
                  <td>
                    <button
                      type="button"
                      className="danger"
                      disabled={deletingId !== null}
                      onClick={() => void deleteProgram(p.id, p.name)}
                    >
                      {deletingId === p.id ? "Deleting…" : "Delete"}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
