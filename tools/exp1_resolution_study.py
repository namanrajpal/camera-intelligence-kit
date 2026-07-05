"""
GamePose Experiment 1: Resolution operating-point study.

Runs pretrained yolo26n-pose over the corpus at multiple input sizes and
measures, per size:
  - inference latency P50/P95
  - slash dropout at 1/2/3 m (fewer persons than protocol => drop)
  - wrist deviation vs the 640 reference (px @720p, matched frames)

Wrist deviation is computed only between the largest-`expected` persons per
frame (ghost/background detections excluded) and reported as MEDIAN px.

Output: benchmark_results/exp1_resolution_<device>/<imgsz>/<clip>.json + summary.

Usage:
    python tools/exp1_resolution_study.py               # GPU (cuda)
    python tools/exp1_resolution_study.py --device cpu  # CPU (mobile-relevant scaling)
"""

import argparse
import json
import statistics
import time
from pathlib import Path

import cv2

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "corpus"

SIZES = [640, 480, 384, 320]
CLIPS = {
    "idle_2m": 1,
    "slash_1m": 1, "slash_2m": 1, "slash_3m": 1,
    "two_slash_2m": 2,
}


def run_size(model, imgsz: int, clip: str, people: int, device: str, out: Path) -> dict:
    cap = cv2.VideoCapture(str(CORPUS / f"{clip}.mp4"))
    ok, f0 = cap.read()
    if not ok:
        raise RuntimeError(clip)
    for _ in range(10):  # warmup at this size
        model(f0, imgsz=imgsz, conf=0.4, device=device, verbose=False)
    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)

    frames = []
    i = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        h, w = frame.shape[:2]
        t0 = time.perf_counter()
        res = model(frame, imgsz=imgsz, conf=0.4, device=device, verbose=False)[0]
        lat = (time.perf_counter() - t0) * 1000
        ents = []
        if res.keypoints is not None and res.boxes is not None:
            kps = res.keypoints.xy.cpu().numpy()
            boxes = res.boxes.xywh.cpu().numpy()
            for j in range(len(boxes)):
                wrists = []
                for k in (9, 10):
                    x, y = kps[j][k]
                    if x > 0 or y > 0:
                        wrists.append([float(x / w), float(y / h)])
                ents.append({"cx": float(boxes[j][0] / w), "cy": float(boxes[j][1] / h),
                             "area": float(boxes[j][2] * boxes[j][3] / (w * h)),
                             "wrists": wrists})
        frames.append({"i": i, "latency_ms": round(lat, 3), "entities": ents})
        i += 1
    cap.release()

    out_dir = out / str(imgsz)
    out_dir.mkdir(parents=True, exist_ok=True)
    payload = {"imgsz": imgsz, "clip": clip, "expected_entities": people, "frames": frames}
    (out_dir / f"{clip}.json").write_text(json.dumps(payload))
    return payload


def _main_wrists(frame_entities, n):
    """Wrists of the n largest-area persons (game-relevant; excludes ghosts)."""
    ents = sorted(frame_entities, key=lambda e: -e.get("area", 0))[:n]
    return [p for e in ents for p in e["wrists"]]


def wrist_deviation(ref: dict, test: dict, w=1280, h=720):
    """MEDIAN px distance between matched wrists of the largest-`expected`
    persons per frame (robust to ghost-detection flicker)."""
    n = ref["expected_entities"]
    dists = []
    for fr, ft in zip(ref["frames"], test["frames"]):
        wr = _main_wrists(fr["entities"], n)
        wt = _main_wrists(ft["entities"], n)
        if not wr or not wt:
            continue
        for p in wr:
            best = min(((p[0]-q[0])*w)**2 + ((p[1]-q[1])*h)**2 for q in wt) ** 0.5
            dists.append(best)
    return statistics.median(dists) if dists else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default="0", help="'0' = cuda, 'cpu' = mobile-relevant")
    args = ap.parse_args()
    dev_tag = "cpu" if args.device == "cpu" else "gpu"
    out = ROOT / "benchmark_results" / f"exp1_resolution_{dev_tag}"

    from ultralytics import YOLO
    model = YOLO("yolo26n-pose.pt")

    results = {}  # (imgsz, clip) -> payload
    for imgsz in SIZES:
        print(f"== imgsz {imgsz} ({dev_tag}) ==")
        for clip, people in CLIPS.items():
            if not (CORPUS / f"{clip}.mp4").exists():
                continue
            p = run_size(model, imgsz, clip, people, args.device, out)
            lats = sorted(f["latency_ms"] for f in p["frames"])
            drops = sum(1 for f in p["frames"] if len(f["entities"]) < people)
            print(f"  {clip}: p50={lats[len(lats)//2]:.1f}ms "
                  f"p95={lats[int(len(lats)*0.95)]:.1f}ms "
                  f"drop={100*drops/len(p['frames']):.1f}%")
            results[(imgsz, clip)] = p

    # Summary table
    print("\n" + "=" * 100)
    print(f"{'imgsz':>6} {'clip':<14} {'p50ms':>7} {'p95ms':>7} {'drop%':>7} {'wrist_dev_px_vs640':>20}")
    print("-" * 100)
    summary = []
    for imgsz in SIZES:
        for clip, people in CLIPS.items():
            p = results.get((imgsz, clip))
            if not p:
                continue
            lats = sorted(f["latency_ms"] for f in p["frames"])
            drops = 100 * sum(1 for f in p["frames"] if len(f["entities"]) < people) / len(p["frames"])
            dev = None
            if imgsz != 640 and (640, clip) in results:
                dev = wrist_deviation(results[(640, clip)], p)
            row = {"imgsz": imgsz, "clip": clip, "device": dev_tag,
                   "p50": lats[len(lats)//2], "p95": lats[int(len(lats)*0.95)],
                   "drop_pct": round(drops, 2),
                   "wrist_dev_px": round(dev, 1) if dev is not None else None}
            summary.append(row)
            print(f"{imgsz:>6} {clip:<14} {row['p50']:>7.1f} {row['p95']:>7.1f} "
                  f"{row['drop_pct']:>7.2f} {str(row['wrist_dev_px'] if row['wrist_dev_px'] is not None else 'ref'):>20}")

    (out / "summary.json").write_text(json.dumps(summary, indent=2))
    print(f"\nSaved {out / 'summary.json'}")


if __name__ == "__main__":
    main()
