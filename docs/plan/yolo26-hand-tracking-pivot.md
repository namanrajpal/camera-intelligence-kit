# Strategic Pivot: YOLO26 Hand Keypoint Tracking

**Date:** 2026-07-04
**Status:** Training in progress (epoch 57/100, mAP50 pose 89.0%, mAP50 box 99.1%)
**Parallel track:** RTMPose pretrained models being evaluated simultaneously (see [ecosystem-scan-round2.md](../research/ecosystem-scan-round2.md))

---

## Objective

Train and integrate a YOLO26n-pose model on the Ultralytics Hand Keypoints dataset as an alternative/replacement for MediaPipe hand tracking. This gives us:

1. **Single-shot multi-hand detection** (no two-stage palm-detector bottleneck)
2. **No ID-swap problem** (each hand is an independent detection)
3. **Export to every mobile target** (ONNX, CoreML, TensorRT, ExecuTorch, NCNN, LiteRT, QNN)
4. **Smaller model** (2.9M params vs MediaPipe's combined pipeline)

---

## Phase 1: Train the Model (Python, off-Godot)

### Setup
```bash
pip install ultralytics
```

### Train
```python
from ultralytics import YOLO

# Load pretrained pose model
model = YOLO("yolo26n-pose.pt")

# Train on hand keypoints (auto-downloads 369MB dataset)
results = model.train(
    data="hand-keypoints.yaml",
    epochs=100,
    imgsz=640,
    device=0,          # RTX 3070 Ti
    batch=16,
    name="hand-yolo26n"
)
```

### Evaluate
```python
metrics = model.val()
print(f"mAP50-95: {metrics.pose.map}")
print(f"mAP50: {metrics.pose.map50}")
```

### Export
```python
# ONNX (for desktop/cross-platform)
model.export(format="onnx", imgsz=640, simplify=True)

# CoreML (for iOS)
model.export(format="coreml", imgsz=640)

# TFLite/LiteRT (for Android)
model.export(format="litert", imgsz=640, quantize=True)

# ExecuTorch (for mobile, future)
model.export(format="executorch", imgsz=640)
```

### Expected Output
- `hand-yolo26n.onnx` (~10MB FP32, ~3MB INT8)
- 21 keypoints per hand (same topology as MediaPipe)
- Inference: ~40ms CPU, ~2ms GPU

---

## Phase 2: Desktop Validation (Python script)

Before touching Godot, validate with a Python script:
```python
from ultralytics import YOLO
import cv2

model = YOLO("runs/pose/hand-yolo26n/weights/best.pt")
cap = cv2.VideoCapture(0)

while cap.isOpened():
    ret, frame = cap.read()
    results = model(frame, stream=True)
    for r in results:
        annotated = r.plot()
        cv2.imshow("YOLO26 Hands", annotated)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break
```

Test specifically:
- [ ] 2 people, 4 hands simultaneously
- [ ] Hands crossing/overlapping
- [ ] Fast slash motions
- [ ] Various lighting conditions
- [ ] Hand detection at distance (1m, 2m, 3m)

---

## Phase 3: Godot Integration Path

### Option A: ONNX Runtime GDExtension (recommended)
Build or find a Godot GDExtension wrapping ONNX Runtime:
```
SubViewport Image -> ONNX Runtime session -> YOLO26 post-processing -> AIInput
```
- Use DirectML EP on Windows, NNAPI on Android, CoreML on iOS
- Model file: `res://models/hand-yolo26n.onnx`

### Option B: Python bridge (quick prototype)
Run YOLO26 in a Python subprocess, communicate via UDP:
```
Python process: webcam -> YOLO26 -> landmarks -> UDP localhost:9999
Godot: UDP listener -> parse landmarks -> AIInput.process_hand_result()
```
- Quick to prototype, not shippable
- Good for validating the model before committing to C++ work

### Option C: Add YOLO26 to GDMP
Fork GDMP, add YOLO26 ONNX inference alongside MediaPipe.
- Reuses existing GDExtension infrastructure
- But GDMP is tightly coupled to MediaPipe's C++ API

---

## Phase 4: Custom Dataset (Post-Demo)

After validating YOLO26 on the stock dataset, create a custom dataset:

1. **Record:** Film 2-player slash gameplay sessions (diverse lighting, skin tones)
2. **Annotate:** Use MediaPipe VIDEO mode for auto-annotation, convert to YOLO format
3. **Augment:** Motion blur, hand overlap, various distances
4. **Fine-tune:** Continue training from Phase 1 weights on combined dataset
5. **Optional:** Add gesture labels (idle, slash, pinch, fist) for end-to-end detection

---

## Training Progress (live)

| Epoch | Box mAP50 | Box mAP50-95 | Pose mAP50 | Pose mAP50-95 | Status |
|-------|-----------|--------------|------------|---------------|--------|
| 25 | 98.9% | 85.6% | 84.1% | 69.3% | Checkpoint saved |
| 52 | 99.1% | 88.0% | 88.8% | 74.6% | Checkpoint saved |
| 57 | 99.1% | 88.2% | 89.0% | 74.9% | Currently training... |

Training runs at ~2.5 it/s on RTX 3070 Ti, ~8 min/epoch. ETA for epoch 100: ~5-6 hours from start.

---

## Parallel Evaluation: RTMPose

Discovered during [ecosystem scan round 2](../research/ecosystem-scan-round2.md) that RTMPose (mmpose, 7.7k stars) provides **pretrained hand keypoint ONNX models** that may outperform YOLO26 on inference speed:

- RTMPose-t hand: 3ms CPU, 9ms Snapdragon 865
- RTMPose-s hand: 4.5ms CPU, 14ms Snapdragon 865

These are top-down models (need a hand detector first), but the total pipeline may still be faster than YOLO26's single-shot 40ms. Benchmark script at `tools/benchmark_models.py` will compare all three approaches.

---

## Success Criteria

- [ ] YOLO26n-pose trained on hand-keypoints, mAP50 > 80% -- DONE (89.0% at epoch 57)
- [ ] Detects 4+ hands in a single frame reliably
- [ ] No ID swaps when hands cross (handled by Hungarian matching in AIInput)
- [ ] Exported to ONNX, runs at >25fps on CPU
- [ ] Benchmarked against RTMPose and MediaPipe
- [ ] Integrated into Godot via one of the options above

---

## Files This Will Produce

```
tools/
  train_hand_model.py       # Training script (DONE)
  validate_hand_model.py    # Webcam validation script (DONE)
  benchmark_models.py       # Compare YOLO26 vs RTMPose vs MediaPipe
  convert_annotations.py    # MediaPipe -> YOLO format converter
models/
  hand-yolo26n.onnx         # Exported model (gitignored)
  hand-yolo26n.pt           # PyTorch weights (gitignored)
docs/plan/
  yolo26-hand-tracking-pivot.md  # This file
```

## Cross-References

- [Initial SOTA Survey](../research/edge-hand-tracking-sota-2026.md) -- why YOLO26 over MediaPipe
- [Ecosystem Scan Round 2](../research/ecosystem-scan-round2.md) -- RTMPose discovery, gesture classifier pattern
- [Gesture Classifier Plan](./gesture-classifier.md) -- ML gesture classification (deferred)
