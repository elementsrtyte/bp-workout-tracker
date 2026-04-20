import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { Link, useParams } from "react-router-dom";
import { ApiError, apiFetch, apiJson } from "../lib/api";
import { useAuth } from "../context/AuthContext";

type ExerciseRow = {
  id: string;
  name: string;
  prescribed_name: string | null;
  sort_order: number;
  canonical_exercise_id: string | null;
  workout_sets: { id: string; weight: number; reps: number; sort_order: number }[];
};

type DetailResponse = {
  workout: {
    id: string;
    user_id: string;
    logged_at: string;
    program_id: string | null;
    program_name: string | null;
    day_label: string | null;
    notes: string | null;
  };
  exercises: ExerciseRow[];
  profile: { email: string | null; display_name: string | null } | null;
};

type CatalogEx = { id: string; name: string; name_key: string };

export function WorkoutDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { session } = useAuth();
  const [detail, setDetail] = useState<DetailResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [q, setQ] = useState("");
  const [searchHits, setSearchHits] = useState<CatalogEx[]>([]);
  const [bulkName, setBulkName] = useState("");
  const [bulkCanon, setBulkCanon] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!session?.access_token || !id) return;
    let cancelled = false;
    void (async () => {
      try {
        const d = await apiJson<DetailResponse>(`/v1/admin/workouts/${id}`, session.access_token);
        if (!cancelled) {
          setDetail(d);
          setError(null);
        }
      } catch (e) {
        if (!cancelled) {
          setDetail(null);
          setError(e instanceof ApiError ? `${e.message}: ${e.body ?? ""}` : String(e));
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session?.access_token, id]);

  useEffect(() => {
    if (!session?.access_token || q.trim().length < 2) {
      setSearchHits([]);
      return;
    }
    const t = setTimeout(() => {
      void (async () => {
        try {
          const res = await apiJson<{ exercises: CatalogEx[] }>(
            `/v1/admin/exercises?q=${encodeURIComponent(q.trim())}&limit=20`,
            session.access_token
          );
          setSearchHits(res.exercises);
        } catch {
          setSearchHits([]);
        }
      })();
    }, 250);
    return () => clearTimeout(t);
  }, [q, session?.access_token]);

  async function setCanonical(exerciseId: string, canonicalExerciseId: string | null) {
    if (!session?.access_token) return;
    setMessage(null);
    try {
      await apiFetch(`/v1/admin/workout-exercises/${exerciseId}`, session.access_token, {
        method: "PATCH",
        body: JSON.stringify({ canonical_exercise_id: canonicalExerciseId }),
      }).then(async (r) => {
        if (!r.ok) throw new ApiError("PATCH failed", r.status, await r.text());
      });
      setMessage(canonicalExerciseId ? "Linked." : "Unlinked.");
      const d = await apiJson<DetailResponse>(`/v1/admin/workouts/${id}`, session.access_token);
      setDetail(d);
    } catch (e) {
      setMessage(e instanceof Error ? e.message : String(e));
    }
  }

  async function onBulk(e: FormEvent) {
    e.preventDefault();
    if (!session?.access_token) return;
    setMessage(null);
    try {
      const dry = await apiJson<{ dryRun: boolean; matchCount: number }>(
        "/v1/admin/workout-exercises/bulk-link",
        session.access_token,
        {
          method: "POST",
          body: JSON.stringify({
            nameKey: bulkName.trim(),
            canonicalExerciseId: bulkCanon.trim(),
            dryRun: true,
          }),
        }
      );
      if (!window.confirm(`Dry run: ${dry.matchCount} rows. Apply link?`)) return;
      const done = await apiJson<{ updated: number }>(
        "/v1/admin/workout-exercises/bulk-link",
        session.access_token,
        {
          method: "POST",
          body: JSON.stringify({
            nameKey: bulkName.trim(),
            canonicalExerciseId: bulkCanon.trim(),
            dryRun: false,
          }),
        }
      );
      setMessage(`Updated ${done.updated} exercise rows.`);
      const d = await apiJson<DetailResponse>(`/v1/admin/workouts/${id}`, session.access_token);
      setDetail(d);
    } catch (err) {
      setMessage(err instanceof Error ? err.message : String(err));
    }
  }

  async function deleteWorkout() {
    if (!session?.access_token || !id) return;
    if (!window.confirm("Hard-delete this workout and all exercises/sets?")) return;
    try {
      await apiFetch(`/v1/admin/workouts/${id}`, session.access_token, { method: "DELETE" }).then(
        async (r) => {
          if (!r.ok) throw new ApiError("Delete failed", r.status, await r.text());
        }
      );
      window.location.href = "/workouts";
    } catch (err) {
      setMessage(err instanceof Error ? err.message : String(err));
    }
  }

  if (error) {
    return (
      <div className="stack">
        <p className="error">{error}</p>
        <Link to="/workouts">Back</Link>
      </div>
    );
  }
  if (!detail) {
    return <p className="muted">Loading…</p>;
  }

  return (
    <div className="stack loose">
      <p>
        <Link to="/workouts">← Workouts</Link>
      </p>
      <h1>Workout</h1>
      <p className="muted">
        {new Date(detail.workout.logged_at).toLocaleString()} ·{" "}
        {detail.profile?.email ?? detail.workout.user_id}
      </p>
      {message ? <p className="ok">{message}</p> : null}

      <section className="card">
        <h2>Bulk link by performed name</h2>
        <p className="muted">
          Matches <code>lower(trim(name))</code> on all <strong>unlinked</strong> rows globally.
        </p>
        <form onSubmit={onBulk} className="row-wrap">
          <label>
            Performed name (any casing)
            <input value={bulkName} onChange={(e) => setBulkName(e.target.value)} required />
          </label>
          <label>
            Canonical exercise id (UUID)
            <input value={bulkCanon} onChange={(e) => setBulkCanon(e.target.value)} required />
          </label>
          <button type="submit">Dry-run + confirm apply</button>
        </form>
      </section>

      <section className="card">
        <h2>Search catalog exercises</h2>
        <input
          type="search"
          placeholder="Type 2+ characters…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
        <ul className="hits">
          {searchHits.map((ex) => (
            <li key={ex.id}>
              <code>{ex.id}</code> — {ex.name}{" "}
              <button type="button" className="linkish" onClick={() => navigator.clipboard.writeText(ex.id)}>
                Copy id
              </button>
            </li>
          ))}
        </ul>
      </section>

      <section className="card">
        <h2>Exercises</h2>
        {detail.exercises.map((ex) => (
          <div key={ex.id} className="ex-block">
            <h3>
              {ex.name}
              {ex.prescribed_name && ex.prescribed_name !== ex.name ? (
                <span className="muted"> (prescribed: {ex.prescribed_name})</span>
              ) : null}
            </h3>
            <p className="muted">
              Canonical: {ex.canonical_exercise_id ?? "—"}{" "}
              <button type="button" className="linkish" onClick={() => void setCanonical(ex.id, null)}>
                Clear link
              </button>
            </p>
            <div className="row-wrap">
              {searchHits.slice(0, 5).map((c) => (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => void setCanonical(ex.id, c.id)}
                  title={c.name}
                >
                  Link: {c.name}
                </button>
              ))}
            </div>
            {ex.workout_sets.length === 0 ? (
              <p className="muted small">
                No sets in the database for this exercise line (workout may never have synced sets, or
                data was created outside the API sync path).
              </p>
            ) : null}
            <table className="table compact">
              <thead>
                <tr>
                  <th>Set</th>
                  <th>Weight</th>
                  <th>Reps</th>
                </tr>
              </thead>
              <tbody>
                {ex.workout_sets.map((s) => (
                  <tr key={s.id}>
                    <td>{s.sort_order + 1}</td>
                    <td>{s.weight}</td>
                    <td>{s.reps}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ))}
      </section>

      <section className="card danger-zone">
        <h2>Danger</h2>
        <button type="button" className="danger" onClick={() => void deleteWorkout()}>
          Delete workout
        </button>
      </section>
    </div>
  );
}
