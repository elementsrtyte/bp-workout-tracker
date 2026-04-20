import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { ApiError, apiJson } from "../lib/api";
import { useAuth } from "../context/AuthContext";

type WorkoutRow = {
  id: string;
  user_id: string;
  logged_at: string;
  program_id: string | null;
  program_name: string | null;
  day_label: string | null;
};

type ListResponse = {
  workouts: WorkoutRow[];
  total: number;
  profilesByUserId: Record<string, { email: string | null; display_name: string | null }>;
};

export function WorkoutsPage() {
  const { session } = useAuth();
  const [emailInput, setEmailInput] = useState("");
  const [anomalyInput, setAnomalyInput] = useState(false);
  const [unlinkedInput, setUnlinkedInput] = useState(false);
  const [email, setEmail] = useState("");
  const [anomaly, setAnomaly] = useState(false);
  const [unlinked, setUnlinked] = useState(false);
  const [offset, setOffset] = useState(0);
  const limit = 25;
  const [data, setData] = useState<ListResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!session?.access_token) return;
    let cancelled = false;
    void (async () => {
      try {
        const q = new URLSearchParams();
        q.set("limit", String(limit));
        q.set("offset", String(offset));
        if (email.trim()) q.set("email", email.trim().toLowerCase());
        if (anomaly) q.set("anomaly", "1");
        if (unlinked) q.set("unlinked", "1");
        const list = await apiJson<ListResponse>(
          `/v1/admin/workouts?${q.toString()}`,
          session.access_token
        );
        if (!cancelled) {
          setData(list);
          setError(null);
        }
      } catch (e) {
        if (!cancelled) {
          setData(null);
          setError(e instanceof ApiError ? `${e.message}: ${e.body ?? ""}` : String(e));
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session?.access_token, email, anomaly, unlinked, offset]);

  function applyFilters() {
    setEmail(emailInput);
    setAnomaly(anomalyInput);
    setUnlinked(unlinkedInput);
    setOffset(0);
  }

  return (
    <div className="stack loose">
      <h1>Workouts</h1>
      <p className="muted">
        Cross-user list (service role on API). Use filters to narrow; anomaly/unlinked modes cap at
        250 ids server-side.
      </p>
      <div className="card row-wrap">
        <label>
          User email
          <input
            type="email"
            value={emailInput}
            onChange={(e) => setEmailInput(e.target.value)}
            placeholder="filter by profile email"
          />
        </label>
        <label className="checkbox">
          <input
            type="checkbox"
            checked={anomalyInput}
            onChange={(e) => setAnomalyInput(e.target.checked)}
          />
          Anomaly only
        </label>
        <label className="checkbox">
          <input
            type="checkbox"
            checked={unlinkedInput}
            onChange={(e) => setUnlinkedInput(e.target.checked)}
          />
          Has unlinked exercise
        </label>
        <button type="button" onClick={applyFilters}>
          Apply filters
        </button>
      </div>
      {error ? <p className="error">{error}</p> : null}
      {!data && !error ? <p className="muted">Loading…</p> : null}
      {data ? (
        <>
          <p className="muted">
            Showing {data.workouts.length} of {data.total} (offset {offset})
          </p>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>When</th>
                  <th>User</th>
                  <th>Program</th>
                  <th>Day</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {data.workouts.map((w) => {
                  const prof = data.profilesByUserId[w.user_id];
                  return (
                    <tr key={w.id}>
                      <td>{new Date(w.logged_at).toLocaleString()}</td>
                      <td>
                        {prof?.email ?? w.user_id.slice(0, 8)}
                        {prof?.display_name ? ` (${prof.display_name})` : ""}
                      </td>
                      <td>{w.program_name ?? w.program_id ?? "—"}</td>
                      <td>{w.day_label ?? "—"}</td>
                      <td>
                        <Link to={`/workouts/${w.id}`}>Open</Link>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <div className="row">
            <button
              type="button"
              disabled={offset === 0}
              onClick={() => setOffset((o) => Math.max(0, o - limit))}
            >
              Previous
            </button>
            <button
              type="button"
              disabled={!data || offset + data.workouts.length >= data.total}
              onClick={() => setOffset((o) => o + limit)}
            >
              Next
            </button>
          </div>
        </>
      ) : null}
    </div>
  );
}
