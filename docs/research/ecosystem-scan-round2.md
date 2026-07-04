# Ecosystem Scan Round 2: Hand Tracking Approaches in the Wild

**Date:** 2026-07-04
**Context:** Second research pass after initial SOTA survey ([edge-hand-tracking-sota-2026.md](./edge-hand-tracking-sota-2026.md))
**High-level goal:** Best on-device edge AI hand tracking for multi-person hack-and-slash gameplay in Godot, targeting both laptop and mobile.

---

## Key Discoveries

### 1. RTMPose Hand Models (open-mmlab/mmpose, 7.7k stars)

**[github.com/open-mmlab/mmpose/tree/main/projects/rtmpose](https://github.com/open-mmlab/mmpose/tree/main/projects/rtmpose)**

RTMPose is a production-grade real-time pose estimation framework. Unlike our YOLO26 approach (training from scratch), they provide **pretrained hand keypoint models** that are already optimized and ONNX-exported.

**Why this matters for us:**

| Metric | RTMPose-t | RTMPose-s | RTMPose-m | Our YOLO26n-pose |
|--------|-----------|-----------|-----------|------------------|
| Params | 3.3M | 5.5M | 13.6M | 2.9M (4.1M actual) |
| FLOPs | 0.36G | 0.68G | 1.93G | 7.5G (12.1G actual) |
| CPU FPS (ORT) | 300+ | 200+ | 90+ | ~25 (est.) |
| GPU FPS | 940+ | 710+ | 430+ | TBD |
| Mobile (Snap 865) | 9ms | 14ms | 26ms | TBD |

RTMPose is significantly faster per-inference than YOLO26 because it's a **top-down** model (runs on a pre-cropped hand region, not full image). The trade-off: needs a separate hand/person detector first.

**Pre-exported deployment artifacts available:**
- ONNX models (downloadable directly from OpenMMLab)
- TensorRT engines
- ncnn models (for Android ARM)
- Pure Python inference examples (no MMDeploy dependency)
- **C++ examples with ONNX Runtime** -- direct reference for our Godot GDExtension plan
- **Android examples with ncnn** -- exactly what we need for mobile

**Hand-specific models:** RTMPose provides 21-keypoint hand models trained on combined datasets (COCO-WholeBody hands, InterHand, etc.). Pretrained weights are available.

**Action item:** Download and benchmark RTMPose hand ONNX against our MediaPipe pipeline and YOLO26 model.

### 2. Kazuhito00's Gesture Classification Pattern (750 stars)

**[github.com/Kazuhito00/hand-gesture-recognition-using-mediapipe](https://github.com/Kazuhito00/hand-gesture-recognition-using-mediapipe)**

This is the architecture we should adopt for gesture classification. It uses two lightweight classifiers on top of MediaPipe landmarks:

**A. Keypoint Classifier (static hand pose):**
- Input: 21 landmark positions (flattened, normalized relative to wrist)
- Model: simple 3-layer MLP (Dense 20 -> Dense 10 -> Dense N_classes)
- Output: gesture class (fist, open_palm, peace, point, etc.)
- Model size: <50KB TFLite
- Inference: microseconds

**B. Point History Classifier (dynamic finger gesture):**
- Input: last 16 frames of index fingertip (x,y) position deltas
- Model: LSTM or 1D CNN on the 32-dim sequence
- Output: motion class (idle, clockwise, counterclockwise, move/swipe)
- Model size: <50KB TFLite
- Inference: microseconds

**Built-in training data collection:**
- Press 'k' to enter keypoint logging mode
- Press '0'-'9' to label the current hand pose
- Automatically saves to CSV with landmark coordinates
- Same for point history ('h' mode)

**Why this matters:** Our current rule-based swipe detection (speed threshold + distance) works for Fruit Chop but can't distinguish slash directions, differentiate jabs from swings, or learn custom game gestures. This pattern lets us train game-specific gestures with minimal effort.

**Action item:** Document the architecture for later implementation. Plan data collection during gameplay sessions. See [gesture-classifier.md](../plan/gesture-classifier.md).

### 3. NVIDIA trt_pose_hand (233 stars)

**[github.com/NVIDIA-AI-IOT/trt_pose_hand](https://github.com/NVIDIA-AI-IOT/trt_pose_hand)**

NVIDIA's approach to hand pose on edge devices (Jetson Nano/Xavier):

- **Model:** ResNet18 backbone trained on NVIDIA's own hand dataset
- **21 keypoints** (same topology as MediaPipe)
- **TensorRT accelerated** for real-time on Jetson
- **Gesture classification:** SVM on landmark features (6 classes: fist, pan, stop, fine, peace, no_hand)
- **Applications included:** cursor control, mini-paint, gesture classification demo

**Insight for us:** Their gesture classification uses SVM on raw landmark positions (not temporal sequences). This is even simpler than Kazuhito00's MLP but limited to static poses. For dynamic gestures (slashes), the point history approach is better.

### 4. Sputnikboi/HandLocator (YOLOv8 + ONNX Runtime CUDA, C++)

**[github.com/Sputnikboi/HandLocator](https://github.com/Sputnikboi/HandLocator)**

The closest reference implementation to what we need for Godot integration:

- **Hybrid pipeline:** YOLOv8 for hand detection + MediaPipe for landmarks
- **C++ with ONNX Runtime CUDA** execution provider
- **CMake build system** with setup scripts for ONNX Runtime and CUDA
- **3D GLFW viewer** for hand landmark visualization

**Relevance:** Their C++ ONNX Runtime integration code is a direct reference for building our Godot GDExtension. The CMake structure, session management, and inference loop can be adapted.

### 5. omana1/Motion-controlled-3D-game (Fruit Slicer)

**[github.com/omana1/Motion-controlled-3D-game](https://github.com/omana1/Motion-controlled-3D-game)**

Existing 3D Fruit Slicer game using hand tracking:

- **PoseNet** (body pose, not hand-specific) for hand tracking via wrist keypoints
- **Three.js** for 3D rendering in browser
- **TensorFlow.js** for inference

**Insight:** Uses body wrist keypoints (indices 9, 10 from COCO body pose) rather than hand-specific models. Coarser (no finger detail) but simpler and faster. For our Fruit Chop game, we could use body wrist positions from YOLO26-pose as a fallback when hand models are too slow on mobile.

---

## Revised Model Comparison

| Approach | Params | CPU (ms) | Mobile (ms) | Multi-hand | ONNX Export | Godot Path |
|----------|--------|----------|-------------|------------|-------------|------------|
| **MediaPipe HandLandmarker** (current) | ~10M combined | 50-80 | 20-30 (GPU) | 4 hands, ID swaps | N/A (C++ native) | GDMP plugin |
| **YOLO26n-pose** (training) | 4.1M | ~40 | TBD | Natural multi-instance | Yes (all formats) | ONNX Runtime GDExtension |
| **RTMPose-t hand** (pretrained) | 3.3M | ~3 | 9ms (ncnn) | Needs detector first | Yes (pre-exported) | ONNX Runtime GDExtension |
| **RTMPose-s hand** (pretrained) | 5.5M | ~4.5 | 14ms (ncnn) | Needs detector first | Yes (pre-exported) | ONNX Runtime GDExtension |
| **Body wrist tracking** (YOLO26n-pose COCO) | 2.9M | ~40 | TBD | Person-associated | Yes | ONNX Runtime GDExtension |

**Key insight:** RTMPose hand models are **10-20x faster** per inference than YOLO26 because they run on pre-cropped hand regions (~256x192) instead of full frames (640x640). The total pipeline cost is detector + pose, but with a lightweight detector (RTMDet-nano at ~1ms GPU) it's still faster overall.

---

## Updated Recommendations

### Immediate (parallel with YOLO26 training)

1. **Download and benchmark RTMPose hand ONNX models** -- could be the fastest path to best tracking
2. **Benchmark against current MediaPipe** on same hardware (RTX 3070 Ti laptop, webcam)
3. **When YOLO26 finishes training**, compare all three side-by-side

### Near-term (pre-demo)

4. **Pick the winner** based on benchmarks: latency, accuracy, multi-hand reliability
5. **Document the gesture classifier architecture** (Kazuhito00 pattern) for post-demo implementation

### Post-demo

6. **Build gesture classifier** using Kazuhito00's point_history pattern
7. **Build ONNX Runtime GDExtension** using HandLocator's C++ code as reference
8. **Mobile deployment** with RTMPose ncnn or YOLO26 LiteRT/ExecuTorch

---

## Cross-References

- [Initial SOTA Survey](./edge-hand-tracking-sota-2026.md) -- MediaPipe limitations, 1-Euro filter, YOLO26, edge runtimes
- [YOLO26 Training Plan](../plan/yolo26-hand-tracking-pivot.md) -- training script, validation, export, Godot integration options
- [Gesture Classifier Plan](../plan/gesture-classifier.md) -- Kazuhito00 pattern architecture, data collection, training
- [PROGRESS.md](../../PROGRESS.md) -- what's actually been built and when
- [ROADMAP.md](../../ROADMAP.md) -- priorities and timeline
