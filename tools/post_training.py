"""
Run this after YOLO26 training completes.

Does three things:
  1. Prints final training metrics
  2. Exports best model to ONNX
  3. Runs the benchmark (MediaPipe vs YOLO26 PyTorch vs YOLO26 ONNX)

Usage:
    python tools/post_training.py [--camera 0] [--duration 15]
"""

import argparse
import os
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--duration", type=int, default=15)
    parser.add_argument("--skip-benchmark", action="store_true")
    args = parser.parse_args()

    best_pt = "runs/pose/hand-yolo26n/weights/best.pt"
    best_onnx = "runs/pose/hand-yolo26n/weights/best.onnx"

    if not os.path.exists(best_pt):
        print(f"ERROR: {best_pt} not found. Is training finished?")
        sys.exit(1)

    # --- Step 1: Print final metrics ---
    print("=" * 60)
    print("  STEP 1: Final Training Metrics")
    print("=" * 60)

    import csv
    rows = list(csv.reader(open("runs/pose/hand-yolo26n/results.csv")))
    print(f"  Total epochs: {len(rows) - 1}")
    header = rows[0]
    for i, h in enumerate(header):
        h = h.strip()
        if "map" in h.lower() or "precision" in h.lower() or "recall" in h.lower():
            print(f"  {h} = {rows[-1][i].strip()}")

    # --- Step 2: Export to ONNX ---
    print(f"\n{'=' * 60}")
    print("  STEP 2: Export to ONNX")
    print("=" * 60)

    from ultralytics import YOLO

    if os.path.exists(best_onnx):
        print(f"  ONNX already exists: {best_onnx}")
        size_mb = os.path.getsize(best_onnx) / 1024 / 1024
        print(f"  Size: {size_mb:.1f} MB")
    else:
        model = YOLO(best_pt)
        onnx_path = model.export(format="onnx", imgsz=640, simplify=True)
        size_mb = os.path.getsize(str(onnx_path)) / 1024 / 1024
        print(f"  Exported: {onnx_path} ({size_mb:.1f} MB)")

    # --- Step 3: Benchmark ---
    if args.skip_benchmark:
        print("\nSkipping benchmark (--skip-benchmark)")
        return

    print(f"\n{'=' * 60}")
    print("  STEP 3: Benchmark (hold your hand in front of camera!)")
    print("=" * 60)
    print(f"  Camera: {args.camera}, Duration: {args.duration}s per model")
    print(f"  Testing: MediaPipe Hands, YOLO26 PyTorch+CUDA, YOLO26 ONNX Runtime")
    print()

    os.system(
        f'"{sys.executable}" tools/benchmark_models.py '
        f"--camera {args.camera} --duration {args.duration} "
        f'--yolo-model "{best_pt}" --yolo-onnx "{best_onnx}"'
    )

    print(f"\n{'=' * 60}")
    print("  DONE!")
    print("=" * 60)
    print(f"  Model weights: {best_pt}")
    print(f"  ONNX model:    {best_onnx}")
    print(f"  Validate live:  python tools/validate_hand_model.py --camera {args.camera}")
    print()
    print("  Next steps:")
    print("    - If YOLO26 wins: build ONNX Runtime GDExtension for Godot")
    print("    - If MediaPipe wins: keep current pipeline, optimize further")
    print("    - Either way: evaluate RTMPose hand models (needs separate mmpose setup)")


if __name__ == "__main__":
    main()
