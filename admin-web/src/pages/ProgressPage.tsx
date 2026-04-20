import { useCallback, useEffect, useState } from "react";
import type { FormEvent } from "react";
import { ProgressExerciseEditor } from "../components/ProgressExerciseEditor";
import { ApiError, apiFetch, apiJson } from "../lib/api";
import {
  type ProgressDataBundle,
  downloadJson,
  parseProgressBundle,
} from "../lib/progressBundle";
import { useAuth } from "../context/AuthContext";

type Tab = "visual" | "raw";

export function ProgressPage() {
  const { session } = useAuth();
  const [tab, setTab] = useState<Tab>("visual");
  const [bundle, setBundle] = useState<ProgressDataBundle | null>(null);
  const [rawText, setRawText] = useState("{}");
  const [exerciseIndex, setExerciseIndex] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const loadFromServer = useCallback(async () => {
    if (!session?.access_token) return;
    const res = await apiJson<{ bundled_progress: { payload: unknown } | null }>(
      "/v1/admin/bundled-progress",
      session.access_token
    );
    const p = res.bundled_progress?.payload;
    if (p === undefined || p === null) {
      const empty: ProgressDataBundle = { exerciseProgressData: [], programColors: {} };
      setBundle(empty);
      setRawText(JSON.stringify(empty, null, 2));
    } else {
      const b = parseProgressBundle(p);
      setBundle(b);
      setRawText(JSON.stringify(b, null, 2));
    }
    setExerciseIndex(0);
    setError(null);
  }, [session?.access_token]);

  useEffect(() => {
    if (!session?.access_token) return;
    let cancelled = false;
    void (async () => {
      try {
        await loadFromServer();
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof ApiError ? `${e.message}: ${e.body ?? ""}` : String(e));
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session?.access_token, loadFromServer]);

  useEffect(() => {
    if (!bundle) return;
    const n = bundle.exerciseProgressData.length;
    setExerciseIndex((i) => (n === 0 ? 0 : Math.min(i, n - 1)));
  }, [bundle]);

  function switchTab(next: Tab) {
    if (next === tab) return;
    if (next === "raw" && bundle) {
      setRawText(JSON.stringify(bundle, null, 2));
      setTab("raw");
      return;
    }
    if (next === "visual") {
      try {
        const parsed = parseProgressBundle(JSON.parse(rawText));
        setBundle(parsed);
        setTab("visual");
        setError(null);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Invalid JSON — fix the raw editor first.");
      }
    }
  }

  async function onSave(e: FormEvent) {
    e.preventDefault();
    if (!session?.access_token) return;
    setError(null);
    setSaved(null);
    setBusy(true);
    try {
      let payload: ProgressDataBundle;
      if (tab === "raw") {
        const raw = JSON.parse(rawText) as unknown;
        if (typeof raw !== "object" || raw === null) {
          throw new Error("Root JSON must be an object");
        }
        payload = parseProgressBundle(raw);
        setBundle(payload);
      } else {
        if (!bundle) throw new Error("Nothing to save");
        payload = bundle;
      }
      await apiFetch("/v1/admin/bundled-progress", session.access_token, {
        method: "PATCH",
        body: JSON.stringify({ payload }),
      }).then(async (r) => {
        if (!r.ok) {
          const t = await r.text();
          throw new ApiError(`Save failed ${r.status}`, r.status, t);
        }
      });
      setSaved("Saved to server.");
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  function onExport() {
    try {
      const data =
        tab === "raw"
          ? parseProgressBundle(JSON.parse(rawText))
          : (bundle ?? { exerciseProgressData: [], programColors: {} });
      const d = new Date().toISOString().slice(0, 10);
      downloadJson(data, `progress-bundle-cleaned-${d}.json`);
      setSaved("Export downloaded.");
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }

  const exCount = bundle?.exerciseProgressData.length ?? 0;
  const safeExIndex =
    exCount === 0 ? 0 : Math.max(0, Math.min(exerciseIndex, exCount - 1));

  return (
    <div className="stack loose">
      <h1>Bundled progress seed</h1>
      <p className="muted">
        Visual editor: chart and table per exercise, multi-select points (click, Shift+range, date
        range), delete, then save or export JSON.
      </p>

      <div className="row-wrap tabs">
        <button
          type="button"
          className={tab === "visual" ? "tab-active" : ""}
          onClick={() => switchTab("visual")}
        >
          Visual
        </button>
        <button
          type="button"
          className={tab === "raw" ? "tab-active" : ""}
          onClick={() => switchTab("raw")}
        >
          Raw JSON
        </button>
      </div>

      {error ? <p className="error">{error}</p> : null}
      {saved ? <p className="ok">{saved}</p> : null}

      <div className="row-wrap">
        <button type="button" onClick={() => void loadFromServer()} disabled={busy}>
          Reload from server
        </button>
        <button type="button" onClick={onExport}>
          Export cleaned JSON
        </button>
      </div>

      {tab === "visual" && bundle ? (
        <>
          {exCount > 0 ? (
            <label className="card inline-field">
              Exercise
              <select
                value={safeExIndex}
                onChange={(e) => setExerciseIndex(parseInt(e.target.value, 10))}
              >
                {bundle.exerciseProgressData.map((x, i) => (
                  <option key={`${x.name}-${i}`} value={i}>
                    {x.name} ({x.entries.length} pts)
                  </option>
                ))}
              </select>
            </label>
          ) : null}
          <ProgressExerciseEditor
            bundle={bundle}
            exerciseIndex={safeExIndex}
            onBundleChange={(b) => {
              setBundle(b);
              setSaved(null);
            }}
          />
        </>
      ) : null}

      {tab === "visual" && !bundle ? <p className="muted">Loading…</p> : null}

      {tab === "raw" ? (
        <textarea
          className="json-editor"
          value={rawText}
          onChange={(e) => setRawText(e.target.value)}
          spellCheck={false}
        />
      ) : null}

      <form onSubmit={onSave} className="row">
        <button type="submit" disabled={busy || !bundle}>
          {busy ? "Saving…" : "Save payload to server"}
        </button>
      </form>
    </div>
  );
}
