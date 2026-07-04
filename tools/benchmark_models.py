"""
Benchmark hand tracking models: YOLO26 vs MediaPipe vs RTMPose.

Measures per-frame inference latency, FPS, and detection count on live webcam.
Runs each model for N seconds, reports percentile latencies.

Usage:
    python tools/benchmark_models.py [--camera 0] [--duration 30] [--imgsz 640]

Requires:
    pip install ultralytics opencv-python mediapipe onnxruntime
"""

import argparse
import time
import statistics
from pathlib import Path

import cv2
import numpy as np


def benchmark_yolo26(cap, duration, imgsz, model_path):
    """Benchmark YOLO26n-pose hand model."""
    from ultralytics import YOLO

    if not Path(model_path).exists():
        print(f"  SKIP: model not found at {model_path}")
        return None

    model = YOLO(model_path)

    # Warm up
    ret, frame = cap.read()
    for _ in range(5):
        model(frame, imgsz=imgsz, verbose=False)

    latencies = []
    total_hands = 0
    frames = 0
    start = time.time()

    while time.time() - start < duration:
        ret, frame = cap.read()
        if not ret:
            break

        t0 = time.perf_counter()
        results = model(frame, imgsz=imgsz, verbose=False, conf=0.4)
        t1 = time.perf_counter()

        latency_ms = (t1 - t0) * 1000
        latencies.append(latency_ms)
        num_hands = len(results[0].boxes) if results[0].boxes is not None else 0
        total_hands += num_hands
        frames += 1

    return {
        "frames": frames,
        "fps": frames / duration,
        "avg_latency_ms": statistics.mean(latencies) if latencies else 0,
        "p50_latency_ms": statistics.median(latencies) if latencies else 0,
        "p95_latency_ms": sorted(latencies)[int(len(latencies) * 0.95)] if latencies else 0,
        "p99_latency_ms": sorted(latencies)[int(len(latencies) * 0.99)] if latencies else 0,
        "min_latency_ms": min(latencies) if latencies else 0,
        "max_latency_ms": max(latencies) if latencies else 0,
        "avg_hands": total_hands / frames if frames else 0,
    }


def benchmark_mediapipe(cap, duration):
    """Benchmark MediaPipe HandLandmarker."""
    try:
        import mediapipe as mp
    except ImportError:
        print("  SKIP: mediapipe not installed (pip install mediapipe)")
        return None

    mp_hands = mp.solutions.hands
    hands = mp_hands.Hands(
        static_image_mode=False,
        max_num_hands=2,
        min_detection_confidence=0.4,
        min_tracking_confidence=0.3,
    )

    # Warm up
    ret, frame = cap.read()
    for _ in range(5):
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        hands.process(rgb)

    latencies = []
    total_hands = 0
    frames = 0
    start = time.time()

    while time.time() - start < duration:
        ret, frame = cap.read()
        if not ret:
            break

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        t0 = time.perf_counter()
        results = hands.process(rgb)
        t1 = time.perf_counter()

        latency_ms = (t1 - t0) * 1000
        latencies.append(latency_ms)
        num_hands = len(results.multi_hand_landmarks) if results.multi_hand_landmarks else 0
        total_hands += num_hands
        frames += 1

    hands.close()

    return {
        "frames": frames,
        "fps": frames / duration,
        "avg_latency_ms": statistics.mean(latencies) if latencies else 0,
        "p50_latency_ms": statistics.median(latencies) if latencies else 0,
        "p95_latency_ms": sorted(latencies)[int(len(latencies) * 0.95)] if latencies else 0,
        "p99_latency_ms": sorted(latencies)[int(len(latencies) * 0.99)] if latencies else 0,
        "min_latency_ms": min(latencies) if latencies else 0,
        "max_latency_ms": max(latencies) if latencies else 0,
        "avg_hands": total_hands / frames if frames else 0,
    }


def benchmark_yolo26_onnx(cap, duration, onnx_path, imgsz=640):
    """Benchmark YOLO26 ONNX model via onnxruntime (simulates what Godot GDExtension would do)."""
    try:
        import onnxruntime as ort
    except ImportError:
        print("  SKIP: onnxruntime not installed")
        return None

    if not Path(onnx_path).exists():
        print(f"  SKIP: ONNX model not found at {onnx_path}")
        return None

    providers = ort.get_available_providers()
    print(f"  ONNX Runtime providers: {providers}")
    session = ort.InferenceSession(str(onnx_path), providers=providers)
    input_name = session.get_inputs()[0].name
    input_shape = session.get_inputs()[0].shape  # e.g. [1, 3, 640, 640]

    h, w = input_shape[2], input_shape[3]

    # Warm up
    ret, frame = cap.read()
    dummy = cv2.resize(frame, (w, h))
    dummy = dummy.astype(np.float32) / 255.0
    dummy = np.transpose(dummy, (2, 0, 1))[np.newaxis]
    for _ in range(5):
        session.run(None, {input_name: dummy})

    latencies = []
    frames = 0
    start = time.time()

    while time.time() - start < duration:
        ret, frame = cap.read()
        if not ret:
            break

        # Preprocess (same as YOLO pipeline)
        t0 = time.perf_counter()
        resized = cv2.resize(frame, (w, h))
        blob = resized.astype(np.float32) / 255.0
        blob = np.transpose(blob, (2, 0, 1))[np.newaxis]
        outputs = session.run(None, {input_name: blob})
        t1 = time.perf_counter()

        latency_ms = (t1 - t0) * 1000
        latencies.append(latency_ms)
        frames += 1

    return {
        "frames": frames,
        "fps": frames / duration,
        "avg_latency_ms": statistics.mean(latencies) if latencies else 0,
        "p50_latency_ms": statistics.median(latencies) if latencies else 0,
        "p95_latency_ms": sorted(latencies)[int(len(latencies) * 0.95)] if latencies else 0,
        "p99_latency_ms": sorted(latencies)[int(len(latencies) * 0.99)] if latencies else 0,
        "min_latency_ms": min(latencies) if latencies else 0,
        "max_latency_ms": max(latencies) if latencies else 0,
        "avg_hands": -1,  # ONNX raw output needs post-processing
    }


def print_results(name, results):
    if results is None:
        print(f"\n{'=' * 50}")
        print(f"  {name}: SKIPPED")
        print(f"{'=' * 50}")
        return

    print(f"\n{'=' * 50}")
    print(f"  {name}")
    print(f"{'=' * 50}")
    print(f"  Frames:      {results['frames']}")
    print(f"  FPS:         {results['fps']:.1f}")
    print(f"  Avg hands:   {results['avg_hands']:.1f}")
    print(f"  Latency (ms):")
    print(f"    avg:  {results['avg_latency_ms']:.1f}")
    print(f"    p50:  {results['p50_latency_ms']:.1f}")
    print(f"    p95:  {results['p95_latency_ms']:.1f}")
    print(f"    p99:  {results['p99_latency_ms']:.1f}")
    print(f"    min:  {results['min_latency_ms']:.1f}")
    print(f"    max:  {results['max_latency_ms']:.1f}")


def main():
    parser = argparse.ArgumentParser(description="Benchmark hand tracking models")
    parser.add_argument("--camera", type=int, default=0, help="Camera index")
    parser.add_argument("--duration", type=int, default=15, help="Seconds per benchmark")
    parser.add_argument("--imgsz", type=int, default=640, help="YOLO input size")
    parser.add_argument(
        "--yolo-model",
        type=str,
        default="runs/pose/hand-yolo26n/weights/best.pt",
        help="YOLO model path",
    )
    parser.add_argument(
        "--yolo-onnx",
        type=str,
        default="runs/pose/hand-yolo26n/weights/best.onnx",
        help="YOLO ONNX model path",
    )
    parser.add_argument("--skip-mediapipe", action="store_true", help="Skip MediaPipe benchmark")
    parser.add_argument("--skip-yolo", action="store_true", help="Skip YOLO PyTorch benchmark")
    parser.add_argument("--skip-onnx", action="store_true", help="Skip ONNX benchmark")
    args = parser.parse_args()

    print(f"Camera: {args.camera}, Duration: {args.duration}s per model, YOLO imgsz: {args.imgsz}")
    print("Hold your hand(s) in front of the camera during the benchmark.\n")

    all_results = {}

    # --- MediaPipe ---
    if not args.skip_mediapipe:
        print("[1/3] Benchmarking MediaPipe Hands...")
        cap = cv2.VideoCapture(args.camera)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        all_results["MediaPipe Hands (CPU)"] = benchmark_mediapipe(cap, args.duration)
        cap.release()
        time.sleep(1)

    # --- YOLO26 PyTorch ---
    if not args.skip_yolo:
        print("[2/3] Benchmarking YOLO26n-pose (PyTorch + CUDA)...")
        cap = cv2.VideoCapture(args.camera)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        all_results["YOLO26n-pose (PyTorch+CUDA)"] = benchmark_yolo26(
            cap, args.duration, args.imgsz, args.yolo_model
        )
        cap.release()
        time.sleep(1)

    # --- YOLO26 ONNX ---
    if not args.skip_onnx:
        print("[3/3] Benchmarking YOLO26n-pose (ONNX Runtime)...")
        cap = cv2.VideoCapture(args.camera)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        all_results["YOLO26n-pose (ONNX Runtime)"] = benchmark_yolo26_onnx(
            cap, args.duration, args.yolo_onnx, args.imgsz
        )
        cap.release()

    # --- Results ---
    print("\n" + "=" * 60)
    print("  BENCHMARK RESULTS")
    print("=" * 60)

    for name, results in all_results.items():
        print_results(name, results)

    # Summary table
    print(f"\n{'Model':<35} {'FPS':>6} {'P50 ms':>8} {'P95 ms':>8} {'Hands':>6}")
    print("-" * 65)
    for name, results in all_results.items():
        if results:
            print(
                f"{name:<35} {results['fps']:>6.1f} {results['p50_latency_ms']:>8.1f} "
                f"{results['p95_latency_ms']:>8.1f} {results['avg_hands']:>6.1f}"
            )

    print("\nDone. Show your hand(s) to the camera next time for meaningful hand counts.")


if __name__ == "__main__":
    main()
