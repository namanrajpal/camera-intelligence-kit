"""
GamePose Experiment 2: Velocity-predictive wrist tracking (offline).

The game renders frame t using the detection from t-1 (or older). We measure
how well simple predictors estimate the wrist at t+k from history up to t,
against the actual detection at t+k — entirely offline on the existing
benchmark JSON (yolo26_body runs). No new inference.

Predictors:
  P0 hold:      pred(t+k) = pos(t)                      [today's behavior]
  P1 velocity:  pred(t+k) = pos(t) + k * v(t)           v = pos(t) - pos(t-1)
  P2 damped:    like P1 with EMA-smoothed velocity (alpha=0.5)

Error = px distance @720p between prediction and actual future wrist,
matched per track & wrist slot. Reported per slash clip, horizons k=1,2,3.

Usage:
    python tools/exp2_predictive_tracking.py
"""

import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "benchmark_results" / "yolo26_body"
OUT = ROOT / "benchmark_results" / "exp2_prediction"
CLIPS = ["slash_1m", "slash_2m", "slash_3m", "two_slash_2m"]
W, H = 1280, 720
HORIZONS = [1, 2, 3]


def greedy_tracks(payload, max_dist=0.15):
    tracks, history, next_id = {}, {}, 0
    for f in payload["frames"]:
        unmatched = list(range(len(f["entities"])))
        new_tracks = {}
        for tid, (px, py) in list(tracks.items()):
            best, bd = None, max_dist
            for j in unmatched:
                e = f["entities"][j]
                d = math.hypot(e["cx"] - px, e["cy"] - py)
                if d < bd:
                    best, bd = j, d
            if best is not None:
                e = f["entities"][best]
                new_tracks[tid] = (e["cx"], e["cy"])
                history.setdefault(tid, []).append((f["i"], e))
                unmatched.remove(best)
        for j in unmatched:
            e = f["entities"][j]
            new_tracks[next_id] = (e["cx"], e["cy"])
            history.setdefault(next_id, []).append((f["i"], e))
            next_id += 1
        tracks = new_tracks
    return history


def wrist_series(history):
    """Per (track, wrist-slot): {frame_index: (x_px, y_px)} with consecutive frames only."""
    series = []
    for tid, seq in history.items():
        n_slots = max(len(e["wrists"]) for _, e in seq)
        for k in range(n_slots):
            s = {i: (e["wrists"][k][0] * W, e["wrists"][k][1] * H)
                 for i, e in seq if len(e["wrists"]) > k}
            if len(s) >= 10:
                series.append(s)
    return series


def evaluate(series, horizon):
    errs = {"P0_hold": [], "P1_velocity": [], "P2_damped": []}
    for s in series:
        ema_v = (0.0, 0.0)
        for i in sorted(s):
            if i - 1 not in s or i + horizon not in s:
                # still update EMA when velocity is computable
                if i - 1 in s:
                    vx, vy = s[i][0] - s[i-1][0], s[i][1] - s[i-1][1]
                    ema_v = (0.5 * vx + 0.5 * ema_v[0], 0.5 * vy + 0.5 * ema_v[1])
                continue
            actual = s[i + horizon]
            vx, vy = s[i][0] - s[i-1][0], s[i][1] - s[i-1][1]
            ema_v = (0.5 * vx + 0.5 * ema_v[0], 0.5 * vy + 0.5 * ema_v[1])
            preds = {
                "P0_hold": s[i],
                "P1_velocity": (s[i][0] + horizon * vx, s[i][1] + horizon * vy),
                "P2_damped": (s[i][0] + horizon * ema_v[0], s[i][1] + horizon * ema_v[1]),
            }
            for name, p in preds.items():
                errs[name].append(math.hypot(p[0] - actual[0], p[1] - actual[1]))
    return {name: {"mean": statistics.mean(v), "p95": sorted(v)[int(len(v) * 0.95)], "n": len(v)}
            for name, v in errs.items() if v}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    all_rows = []
    print(f"{'clip':<14} {'k':>2} {'ms':>4}  {'P0 hold':>12} {'P1 velocity':>12} {'P2 damped':>12}  best")
    print("-" * 78)
    for clip in CLIPS:
        p = RESULTS / f"{clip}.json"
        if not p.exists():
            continue
        payload = json.loads(p.read_text())
        series = wrist_series(greedy_tracks(payload))
        for k in HORIZONS:
            r = evaluate(series, k)
            if not r:
                continue
            best = min(r, key=lambda n: r[n]["mean"])
            print(f"{clip:<14} {k:>2} {k*33:>4}  "
                  f"{r['P0_hold']['mean']:>9.1f}px {r['P1_velocity']['mean']:>9.1f}px "
                  f"{r['P2_damped']['mean']:>9.1f}px  {best}")
            all_rows.append({"clip": clip, "horizon": k, **{n: v["mean"] for n, v in r.items()},
                             "best": best})

    # Aggregate improvement
    p0 = [r["P0_hold"] for r in all_rows]
    p1 = [r["P1_velocity"] for r in all_rows]
    p2 = [r["P2_damped"] for r in all_rows]
    print("-" * 78)
    print(f"Mean error across slash clips/horizons: "
          f"P0 {statistics.mean(p0):.1f}px | P1 {statistics.mean(p1):.1f}px | P2 {statistics.mean(p2):.1f}px")
    imp1 = 100 * (1 - statistics.mean(p1) / statistics.mean(p0))
    imp2 = 100 * (1 - statistics.mean(p2) / statistics.mean(p0))
    print(f"Improvement vs hold-last: P1 {imp1:+.1f}%  P2 {imp2:+.1f}%")

    (OUT / "summary.json").write_text(json.dumps(all_rows, indent=2))
    print(f"Saved {OUT / 'summary.json'}")


if __name__ == "__main__":
    main()
