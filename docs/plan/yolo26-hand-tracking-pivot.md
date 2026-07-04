# Strategic Pivot: YOLO26 Hand Keypoint Tracking

**Date:** 2026-07-04
**Status:** Planning
**Worktree:** To be set up as a parallel OpenCode session

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

## Success Criteria

- [ ] YOLO26n-pose trained on hand-keypoints, mAP50 > 80%
- [ ] Detects 4+ hands in a single frame reliably
- [ ] No ID swaps when hands cross (handled by Hungarian matching in AIInput)
- [ ] Exported to ONNX, runs at >25fps on CPU
- [ ] Integrated into Godot via one of the options above

---

## Files This Will Produce

```
tools/
  train_hand_model.py       # Training script
  validate_hand_model.py    # Webcam validation script
  convert_annotations.py    # MediaPipe -> YOLO format converter
models/
  hand-yolo26n.onnx         # Exported model (gitignored)
  hand-yolo26n.pt           # PyTorch weights (gitignored)
docs/plan/
  yolo26-hand-tracking-pivot.md  # This file
```
