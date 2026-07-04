"""
Validate the trained YOLO26n-pose hand model with a live webcam feed.

Usage:
    python tools/validate_hand_model.py [--model path/to/best.pt] [--camera 0]

Press 'q' to quit, 's' to save a screenshot.

Tests to perform:
    - Single hand at various distances
    - Two hands (same person)
    - Two people, 4 hands
    - Hands crossing/overlapping
    - Fast slash motions
    - Various lighting conditions
"""

import argparse
import time
from pathlib import Path

import cv2
from ultralytics import YOLO


def main():
    parser = argparse.ArgumentParser(description="Validate hand tracking model with webcam")
    parser.add_argument(
        "--model",
        type=str,
        default="runs/pose/hand-yolo26n/weights/best.pt",
        help="Path to trained model weights",
    )
    parser.add_argument("--camera", type=int, default=0, help="Camera index")
    parser.add_argument("--conf", type=float, default=0.5, help="Confidence threshold")
    parser.add_argument("--imgsz", type=int, default=640, help="Inference image size")
    args = parser.parse_args()

    model_path = Path(args.model)
    if not model_path.exists():
        print(f"Model not found at {model_path}")
        print("Run tools/train_hand_model.py first, or specify --model path/to/weights.pt")
        return

    print(f"Loading model: {model_path}")
    model = YOLO(str(model_path))

    print(f"Opening camera {args.camera}...")
    cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        print(f"Failed to open camera {args.camera}")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    print("Webcam validation running. Press 'q' to quit, 's' to save screenshot.")
    print("Test: single hand, two hands, crossing, fast slashes, multiple people")

    frame_count = 0
    fps_start = time.time()
    fps = 0.0

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        # Run inference
        results = model(frame, conf=args.conf, imgsz=args.imgsz, verbose=False)

        # Draw results
        annotated = results[0].plot()

        # Count hands detected
        num_hands = len(results[0].boxes) if results[0].boxes is not None else 0

        # FPS counter
        frame_count += 1
        elapsed = time.time() - fps_start
        if elapsed >= 1.0:
            fps = frame_count / elapsed
            frame_count = 0
            fps_start = time.time()

        # Overlay info
        cv2.putText(
            annotated,
            f"Hands: {num_hands} | FPS: {fps:.1f} | Conf: {args.conf}",
            (10, 30),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (0, 255, 0),
            2,
        )

        cv2.imshow("YOLO26 Hand Tracking Validation", annotated)

        key = cv2.waitKey(1) & 0xFF
        if key == ord("q"):
            break
        elif key == ord("s"):
            screenshot_path = f"screenshot_{int(time.time())}.png"
            cv2.imwrite(screenshot_path, annotated)
            print(f"Screenshot saved: {screenshot_path}")

    cap.release()
    cv2.destroyAllWindows()
    print("Done.")


if __name__ == "__main__":
    main()
