import { useEffect, useMemo, useRef, useState } from "react";
import {
  CartesianGrid,
  ResponsiveContainer,
  Scatter,
  ScatterChart,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import {
  type ProgressDataBundle,
  parseDateMs,
  removeEntriesFromExercise,
} from "../lib/progressBundle";

type ChartPoint = {
  x: number;
  y: number;
  entryIndex: number;
  date: string;
  reps: number;
  program: string;
  dayTitle: string;
};

type Props = {
  bundle: ProgressDataBundle;
  exerciseIndex: number;
  onBundleChange: (b: ProgressDataBundle) => void;
};

export function ProgressExerciseEditor({ bundle, exerciseIndex, onBundleChange }: Props) {
  const ex = bundle.exerciseProgressData[exerciseIndex];
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const lastAnchorRef = useRef<number | null>(null);
  const [rangeStart, setRangeStart] = useState("");
  const [rangeEnd, setRangeEnd] = useState("");

  useEffect(() => {
    setSelected(new Set());
    lastAnchorRef.current = null;
  }, [exerciseIndex]);

  const points: ChartPoint[] = useMemo(() => {
    if (!ex) return [];
    const sorted = ex.entries.map((e, entryIndex) => ({ e, entryIndex }));
    sorted.sort((a, b) => parseDateMs(a.e.date) - parseDateMs(b.e.date));
    return sorted.map(({ e, entryIndex }) => ({
      x: parseDateMs(e.date),
      y: e.weight,
      entryIndex,
      date: e.date,
      reps: e.reps,
      program: e.program,
      dayTitle: e.dayTitle,
    }));
  }, [ex]);

  if (!ex) {
    return <p className="muted">No exercise data. Add exercises in JSON or load from server.</p>;
  }

  function toggleIndex(idx: number, event?: { shiftKey?: boolean }) {
    if (event?.shiftKey && lastAnchorRef.current !== null) {
      const [a, b] = [lastAnchorRef.current, idx].sort((x, y) => x - y);
      const next = new Set(selected);
      for (let i = a; i <= b; i++) next.add(i);
      setSelected(next);
      return;
    }
    const next = new Set(selected);
    if (next.has(idx)) next.delete(idx);
    else next.add(idx);
    setSelected(next);
    lastAnchorRef.current = idx;
  }

  function selectByDateRange() {
    if (!rangeStart || !rangeEnd) return;
    const t0 = Date.parse(rangeStart);
    const t1 = Date.parse(rangeEnd);
    if (Number.isNaN(t0) || Number.isNaN(t1)) return;
    const lo = Math.min(t0, t1);
    const hi = Math.max(t0, t1);
    const next = new Set(selected);
    ex.entries.forEach((e, i) => {
      const t = parseDateMs(e.date);
      if (t >= lo && t <= hi) next.add(i);
    });
    setSelected(next);
  }

  function deleteSelected() {
    if (selected.size === 0) return;
    if (
      !window.confirm(
        `Remove ${selected.size} point(s) from “${ex.name}”? Aggregates will be recomputed; empty exercises are dropped.`
      )
    ) {
      return;
    }
    const next = removeEntriesFromExercise(bundle, exerciseIndex, selected);
    onBundleChange(next);
    setSelected(new Set());
    lastAnchorRef.current = null;
  }

  return (
    <div className="stack loose">
      <div className="card">
        <h3>Chart — {ex.name}</h3>
        <p className="muted small">
          Click a point to select. Shift+click another to select the range between. Selected points
          are orange.
        </p>
        <div className="chart-box">
          <ResponsiveContainer width="100%" height={360}>
            <ScatterChart margin={{ top: 16, right: 16, bottom: 8, left: 8 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#444" />
              <XAxis
                type="number"
                dataKey="x"
                domain={["dataMin - 86400000", "dataMax + 86400000"]}
                tickFormatter={(v) => (typeof v === "number" ? new Date(v).toLocaleDateString() : "")}
                stroke="#888"
              />
              <YAxis type="number" dataKey="y" name="Weight" stroke="#888" />
              <Tooltip
                cursor={{ strokeDasharray: "3 3" }}
                contentStyle={{ background: "#2a2a2a", border: "1px solid #555" }}
                labelFormatter={(_, payload) => {
                  const p = payload?.[0]?.payload as ChartPoint | undefined;
                  if (!p) return "";
                  return `${p.date} · ${p.reps} reps · ${p.program} / ${p.dayTitle}`;
                }}
              />
              <Scatter
                data={points}
                isAnimationActive={false}
                shape={(props: {
                  cx?: number;
                  cy?: number;
                  payload?: ChartPoint;
                }) => {
                  const { cx, cy, payload } = props;
                  if (cx == null || cy == null || !payload) return null;
                  const idx = payload.entryIndex;
                  const sel = selected.has(idx);
                  return (
                    <circle
                      cx={cx}
                      cy={cy}
                      r={sel ? 9 : 6}
                      fill={sel ? "#e67e22" : "#7c6fd1"}
                      stroke="#e8e4dc"
                      strokeWidth={1}
                      style={{ cursor: "pointer" }}
                      onClick={(e) => {
                        e.stopPropagation();
                        toggleIndex(idx, e);
                      }}
                    />
                  );
                }}
              />
            </ScatterChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="card">
        <h3>Select by date range</h3>
        <div className="row-wrap">
          <label>
            From
            <input type="date" value={rangeStart} onChange={(e) => setRangeStart(e.target.value)} />
          </label>
          <label>
            To
            <input type="date" value={rangeEnd} onChange={(e) => setRangeEnd(e.target.value)} />
          </label>
          <button type="button" onClick={selectByDateRange}>
            Add points in range to selection
          </button>
        </div>
      </div>

      <div className="card">
        <div className="row-wrap spread">
          <h3>Entries ({ex.entries.length})</h3>
          <div className="row-wrap">
            <span className="muted">{selected.size} selected</span>
            <button type="button" onClick={() => setSelected(new Set())}>
              Clear selection
            </button>
            <button type="button" className="danger" disabled={selected.size === 0} onClick={deleteSelected}>
              Delete selected
            </button>
          </div>
        </div>
        <div className="table-wrap">
          <table className="table compact">
            <thead>
              <tr>
                <th />
                <th>Date</th>
                <th>Weight</th>
                <th>Reps</th>
                <th>Program</th>
                <th>Day</th>
              </tr>
            </thead>
            <tbody>
              {[...ex.entries.map((e, i) => ({ e, i }))]
                .sort((a, b) => parseDateMs(a.e.date) - parseDateMs(b.e.date))
                .map(({ e: row, i: entryIndex }) => (
                  <tr
                    key={`${entryIndex}-${row.date}-${row.weight}-${row.reps}`}
                    className={selected.has(entryIndex) ? "row-selected" : undefined}
                    onClick={(e) => toggleIndex(entryIndex, e)}
                    style={{ cursor: "pointer" }}
                  >
                    <td>
                      <input
                        type="checkbox"
                        checked={selected.has(entryIndex)}
                        onChange={() => toggleIndex(entryIndex)}
                        onClick={(ev) => ev.stopPropagation()}
                      />
                    </td>
                    <td>{row.date}</td>
                    <td>{row.weight}</td>
                    <td>{row.reps}</td>
                    <td>{row.program}</td>
                    <td>{row.dayTitle}</td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
        <p className="muted small">
          Table rows mirror the chart: click a row or its checkbox. Shift+click uses the last
          clicked row as the other end of a range.
        </p>
      </div>
    </div>
  );
}
