"""
Train YOLO26n-pose on the Ultralytics Hand Keypoints dataset.

Usage:
    python tools/train_hand_model.py

The hand-keypoints dataset (369MB) auto-downloads on first run.
Model weights save to runs/pose/hand-yolo26n/weights/best.pt

Hardware: NVIDIA GeForce RTX 3070 Ti Laptop GPU (8GB VRAM)
Expected time: ~2-3 hours for 100 epochs
"""

from ultralytics import YOLO


def main():
    # Load YOLO26n-pose pretrained on COCO body keypoints.
    # Transfer learning: the backbone and neck are pretrained,
    # only the head needs to adapt from 17 body keypoints to 21 hand keypoints.
    model = YOLO("yolo26n-pose.pt")

    # Train on hand keypoints dataset.
    # Dataset YAML auto-downloads from:
    #   https://github.com/ultralytics/assets/releases/download/v0.0.0/hand-keypoints.zip
    #
    # Dataset stats:
    #   - 26,768 images total (18,776 train / 7,992 val)
    #   - 21 keypoints per hand (same topology as MediaPipe)
    #   - 1 class: "hand"
    results = model.train(
        data="hand-keypoints.yaml",
        epochs=100,
        imgsz=640,
        batch=16,            # Fits in 8GB VRAM for nano model
        device=0,            # RTX 3070 Ti
        name="hand-yolo26n",
        patience=20,         # Early stopping if no improvement for 20 epochs
        save_period=10,      # Save checkpoint every 10 epochs
        plots=True,          # Generate training plots
        verbose=True,
    )

    # Validate on the val set
    print("\n" + "=" * 60)
    print("VALIDATION RESULTS")
    print("=" * 60)
    metrics = model.val()
    print(f"  mAP50-95 (pose): {metrics.pose.map:.4f}")
    print(f"  mAP50 (pose):    {metrics.pose.map50:.4f}")
    print(f"  mAP75 (pose):    {metrics.pose.map75:.4f}")
    print(f"  mAP50-95 (box):  {metrics.box.map:.4f}")

    # Export to ONNX
    print("\n" + "=" * 60)
    print("EXPORTING TO ONNX")
    print("=" * 60)
    onnx_path = model.export(format="onnx", imgsz=640, simplify=True)
    print(f"  ONNX model saved to: {onnx_path}")

    print("\nDone! Next steps:")
    print("  1. Run tools/validate_hand_model.py to test with webcam")
    print("  2. Copy the .onnx file to models/ for Godot integration")


if __name__ == "__main__":
    main()
