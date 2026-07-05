"""
Record the benchmark test corpus.

Records the standard clip set used by notebooks/hand_tracking_benchmark.ipynb.
Every model is later evaluated on these IDENTICAL frames — fair and reproducible.

Usage:
    python tools/record_corpus.py                 # interactive, records all clips
    python tools/record_corpus.py --clip slash_2m # record/re-record one clip
    python tools/record_corpus.py --list          # show clip plan + status

Clips are saved to corpus/<name>.mp4 at 1280x720, ~30fps, with a JSON sidecar
recording actual fps/frame count/duration.

Protocol notes (IMPORTANT for valid results):
- Keep hands/people in frame for the WHOLE clip. Any 0-detection frame is
  counted as a model dropout, so presence must be guaranteed by protocol.
- Distances are from camera to person. Mark 1m/2m/3m spots on the floor first.
- 'slash' = fast, aggressive, erratic hand slashing — like playing Fruit Ninja.
"""

import argparse
import json
import time
from pathlib import Path

import cv2

CORPUS_DIR = Path(__file__).resolve().parent.parent / "corpus"

# name -> (duration_s, people, instructions)
# IMPORTANT: "people" = how many people must be IN FRAME. For 1-person clips,
# everyone else must step completely OUT of camera view (dropout metric counts
# expected people — an extra person in the background breaks the math).
CLIP_PLAN = {
    "idle_1m":      (15, 1, "ONLY 1 person in frame (others step OUT of view). Stand 1m away. BOTH hands up at chest height, KEEP STILL."),
    "idle_2m":      (15, 1, "ONLY 1 person in frame. Stand 2m away. BOTH hands up at chest height, KEEP STILL."),
    "idle_3m":      (15, 1, "ONLY 1 person in frame. Stand 3m away. BOTH hands up at chest height, KEEP STILL."),
    "slash_1m":     (20, 1, "ONLY 1 person in frame. Stand 1m away. SLASH aggressively with both hands — fast, erratic, like Fruit Ninja."),
    "slash_2m":     (20, 1, "ONLY 1 person in frame. Stand 2m away. SLASH aggressively with both hands — fast, erratic."),
    "slash_3m":     (20, 1, "ONLY 1 person in frame. Stand 3m away. SLASH aggressively with both hands — fast, erratic."),
    "two_idle_2m":  (15, 2, "BOTH people in frame at 2m, side by side. Hands up at chest height, KEEP STILL."),
    "two_slash_2m": (20, 2, "BOTH people in frame at 2m. Both SLASH aggressively at the same time."),
    "two_cross_2m": (30, 2, "BOTH people in frame at 2m. Cross arms into each other's space and SWAP POSITIONS ~5 times."),
    "walkon_2m":    (15, 1, "Start with NOBODY in frame. ONE person walks in at 2m, slashes 5s, walks out. Repeat once."),
}


def record_clip(name: str, camera: int) -> None:
    duration, people, instructions = CLIP_PLAN[name]
    CORPUS_DIR.mkdir(exist_ok=True)
    out_path = CORPUS_DIR / f"{name}.mp4"

    cap = cv2.VideoCapture(camera)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    if not cap.isOpened():
        print(f"ERROR: cannot open camera {camera}")
        return

    print(f"\n=== {name} ({duration}s, {people} person(s)) ===")
    print(f">>> {instructions}")
    print("Position yourself using the preview. Press SPACE to start recording, ESC to skip.")

    # Preview until SPACE
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        preview = frame.copy()
        cv2.putText(preview, f"{name}: {instructions[:60]}", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
        cv2.putText(preview, "SPACE = record   ESC = skip", (10, 65),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
        cv2.imshow("Corpus Recorder", preview)
        key = cv2.waitKey(1) & 0xFF
        if key == 27:  # ESC
            cap.release()
            cv2.destroyAllWindows()
            print("skipped.")
            return
        if key == 32:  # SPACE
            break

    # Countdown so the operator can get into position
    for i in range(3, 0, -1):
        t_end = time.time() + 1.0
        while time.time() < t_end:
            ret, frame = cap.read()
            preview = frame.copy()
            cv2.putText(preview, str(i), (600, 380), cv2.FONT_HERSHEY_SIMPLEX, 6, (0, 0, 255), 12)
            cv2.imshow("Corpus Recorder", preview)
            cv2.waitKey(1)

    # Record
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(out_path), fourcc, 30.0, (1280, 720))
    frames = 0
    start = time.time()
    while time.time() - start < duration:
        ret, frame = cap.read()
        if not ret:
            break
        writer.write(frame)
        frames += 1
        remaining = duration - (time.time() - start)
        preview = frame.copy()
        cv2.putText(preview, f"REC {remaining:.0f}s", (10, 40),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)
        cv2.imshow("Corpus Recorder", preview)
        cv2.waitKey(1)

    elapsed = time.time() - start
    writer.release()
    cap.release()
    cv2.destroyAllWindows()

    meta = {
        "name": name, "people": people, "instructions": instructions,
        "requested_duration_s": duration, "actual_duration_s": round(elapsed, 2),
        "frames": frames, "actual_fps": round(frames / elapsed, 2),
        "resolution": [1280, 720],
    }
    (CORPUS_DIR / f"{name}.json").write_text(json.dumps(meta, indent=2))
    print(f"saved {out_path.name}: {frames} frames, {meta['actual_fps']} fps")


def status() -> None:
    print(f"{'clip':<15} {'dur':>4} {'ppl':>3}  status")
    print("-" * 60)
    for name, (dur, ppl, _) in CLIP_PLAN.items():
        f = CORPUS_DIR / f"{name}.mp4"
        s = f"RECORDED ({f.stat().st_size // 1024} KB)" if f.exists() else "missing"
        print(f"{name:<15} {dur:>3}s {ppl:>3}  {s}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--camera", type=int, default=0)
    ap.add_argument("--clip", type=str, help="record a single clip by name")
    ap.add_argument("--list", action="store_true", help="show clip plan + status")
    ap.add_argument("--resume", action="store_true", help="skip clips already recorded")
    args = ap.parse_args()

    if args.list:
        status()
        return
    if args.clip:
        if args.clip not in CLIP_PLAN:
            print(f"unknown clip '{args.clip}'. options: {', '.join(CLIP_PLAN)}")
            return
        record_clip(args.clip, args.camera)
        return
    for name in CLIP_PLAN:
        if args.resume and (CORPUS_DIR / f"{name}.mp4").exists():
            print(f"skipping {name} (already recorded)")
            continue
        record_clip(name, args.camera)
    status()


if __name__ == "__main__":
    main()
