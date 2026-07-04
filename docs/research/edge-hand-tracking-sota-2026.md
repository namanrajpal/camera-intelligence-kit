# Edge AI Hand Tracking: State of the Art & Research Plan (July 2026)

**Date:** 2026-07-04
**Author:** Research session (OpenCode agent + Naman)
**Goal:** Best-in-class on-device hand tracking for multi-person hack-and-slash gameplay in Godot

---

## 1. Current State of the Project

The Camera Intelligence Kit has a working pipeline:

```
Webcam -> CameraServerExtension -> SubViewport -> Image
-> MediaPipe HandLandmarker (CPU, LIVE_STREAM) -> 21 landmarks x 4 hands
-> AIInput singleton (EMA smoothing, swipe/pinch detection) -> Godot signals
```

**What works:** Multi-hand tracking (~30fps), EMA smoothing, swipe gesture detection with speed/distance thresholds, pinch detection with hysteresis state machine, launcher with hand cursors.

**What's missing for multi-person hack-and-slash:** Person-to-hand association, hand identity persistence across occlusion, high-speed slash-optimized gesture detection, mobile deployment, and the Fruit Chop game itself.

---

## 2. The Multi-Person Problem -- Why MediaPipe Falls Short

MediaPipe Hands uses a **two-stage pipeline** (Zhang et al., CVPR 2020):
1. **Palm detector** (BlazePalm) -- finds hand regions in the full frame
2. **Hand landmark model** -- extracts 21 keypoints from each detected region

The critical design choice: to save compute, MediaPipe **skips palm detection** on most frames and uses **optical-flow tracking** from the previous frame's landmarks. Re-detection only happens when tracking confidence drops.

**This creates 3 fundamental problems for multi-person gameplay:**

| Problem | Impact on Gameplay |
|---------|-------------------|
| **No person association** | MediaPipe tracks "hands," not "Person A's left hand." With 2 players' 4 hands, IDs swap constantly |
| **Tracking loss on crossing** | When Player 1's hand crosses Player 2's hand, optical flow tracking fails. Both hands get re-detected, often with swapped IDs |
| **Occlusion gaps** | When one hand occludes another (common in slash games), the occluded hand drops entirely and re-appears with a new ID |

MediaPipe issue [#5806](https://github.com/google-ai-edge/mediapipe/issues/5806) confirms incorrect hand landmarks in multi-person scenarios. Issue [#5559](https://github.com/google-ai-edge/mediapipe/issues/5559) reports accuracy regression in newer Tasks API vs legacy Solutions.

---

## 3. State-of-the-Art Approaches (2026)

### 3A. YOLO26-Pose Hand Keypoints (strongest contender)

Ultralytics released **YOLO26** with native hand keypoint support. Key facts:

- **Hand Keypoints Dataset:** 26,768 images, 21 keypoints per hand (same topology as MediaPipe), YOLO-format labels, generated with MediaPipe annotations. Auto-downloads (369MB).
- **Single-shot architecture:** Detects ALL hands + keypoints in one forward pass -- no two-stage bottleneck, no tracking dependency
- **Naturally multi-instance:** Each detection is an independent bounding box + keypoint set. No ID swapping inherent to the architecture.
- **Model sizes (COCO-Pose benchmarks):**

| Model | Params | FLOPs | CPU ONNX (ms) | T4 TensorRT (ms) |
|-------|--------|-------|---------------|-------------------|
| YOLO26n-pose | 2.9M | 7.5B | 40ms | 1.8ms |
| YOLO26s-pose | 10.4M | 23.9B | 85ms | 2.7ms |
| YOLO26m-pose | 21.5M | 73.1B | 218ms | 5.0ms |

- **Export targets:** ONNX, CoreML, TensorRT, ExecuTorch, NCNN, LiteRT (TFLite), QNN (Qualcomm), RKNN (Rockchip) -- every mobile target covered
- **Training:**
  ```python
  from ultralytics import YOLO
  model = YOLO("yolo26n-pose.pt")
  model.train(data="hand-keypoints.yaml", epochs=100, imgsz=640)
  model.export(format="onnx")
  ```

**Why this matters:** YOLO26n-pose at 2.9M params / 7.5 GFLOPs is ~4x smaller than MediaPipe's palm detector + landmark model combined, runs single-shot, and handles arbitrarily many hands naturally.

**References:**
- [Ultralytics YOLO26](https://github.com/ultralytics/ultralytics) (59.1k stars)
- [Hand Keypoints Dataset docs](https://docs.ultralytics.com/datasets/pose/hand-keypoints/)
- [Pose Estimation docs](https://docs.ultralytics.com/tasks/pose/)

### 3B. Top-Down Person-to-Hand Pipeline

For robust person-hand association:
```
YOLO26-detect (person) -> per-person crop -> YOLO26-pose-hand (keypoints)
```
- Person detection gives you natural player identity
- Each crop contains at most 2 hands from one person
- No cross-person ID swaps possible by construction
- Cost: N inference passes for N people (but N=2 for a 2-player game)

### 3C. One-Euro Filter (Casiez et al., CHI 2012)

Current EMA smoothing is a fixed-alpha low-pass filter. The **1-Euro filter** is strictly superior for hand tracking:

- **Speed-adaptive:** Low cutoff when hand is slow (removes jitter), high cutoff when hand is fast (minimizes lag)
- **Two parameters:** `mincutoff` (jitter removal at low speed) and `beta` (lag reduction at high speed)
- **Critical for slash detection:** EMA with alpha=0.5 adds ~33ms lag at 30fps. For fast slashes, that's the difference between responsive and sluggish
- **GDScript implementation exists:** [godot-xr-kit one_euro_filter.gd](https://github.com/patrykkalinowski/godot-xr-kit/blob/master/addons/xr-kit/smooth-input-filter/scripts/one_euro_filter.gd)

Tuning procedure:
1. Set `beta=0`, `mincutoff=1.0`
2. Hold hand still, decrease `mincutoff` until jitter is gone
3. Slash fast, increase `beta` until lag is acceptable

**Reference:** [1-Euro Filter page](https://cristal.univ-lille.fr/~casiez/1euro/) -- includes implementations in Python, C++, JavaScript, GDScript, and many other languages.

### 3D. Edge Runtime Landscape

| Runtime | Best For | Mobile GPU | NPU | Quantization |
|---------|----------|------------|-----|-------------|
| **ONNX Runtime** | Cross-platform, Windows/Android/iOS | DirectML, CUDA | NNAPI, CoreML, QNN | INT8, FP16 |
| **ExecuTorch** | PyTorch-native mobile | Vulkan (Android) | CoreML (iOS), QNN (Qualcomm) | INT8, INT4 |
| **LiteRT (TFLite)** | Google ecosystem, tiny models | GPU delegate | NNAPI, Edge TPU | INT8, FP16 |
| **NCNN** | Fastest pure-CPU on ARM | Vulkan | No | FP16, INT8 |

**For Godot:** ONNX Runtime is the most practical path because GDMP already provides the infrastructure pattern (C++ GDExtension wrapping a native library). A "Godot-ONNX" GDExtension running YOLO26n-pose.onnx would be the cleanest approach.

**ExecuTorch** is the long-term best option for mobile because it provides:
- XNNPACK backend for ARM CPU (highly optimized)
- Vulkan backend for Android GPUs
- CoreML backend for iOS
- QNN backend for Qualcomm Snapdragon NPUs
- Java/Kotlin bindings for Android, Swift/ObjC for iOS
- `pip install executorch` + `model.export(format="executorch")`

---

## 4. Research Investment Areas

### 4.1 [HIGH IMPACT, LOW EFFORT] Replace EMA with 1-Euro Filter

**Why:** Immediate improvement to slash responsiveness with zero model changes. The `smoothing.gd` is 35 lines -- replacing it with 1-Euro is ~80 lines.

**Effort:** 1-2 hours. Measurable latency reduction for fast movements.

### 4.2 [HIGH IMPACT, MEDIUM EFFORT] Train YOLO26n-pose on Hand Keypoints

**Why:** Single-shot, multi-hand detector with no ID-swap problem, exportable to every mobile target.

**Steps:**
1. `pip install ultralytics`
2. Train: `model = YOLO("yolo26n-pose.pt"); model.train(data="hand-keypoints.yaml", epochs=100, imgsz=640)`
3. Evaluate on multi-person test scenes
4. Export: `model.export(format="onnx")` -> ~10MB ONNX model
5. INT8 quantize for mobile: `model.export(format="onnx", quantize=True)` -> ~3MB

**Effort:** 2-4 hours training on RTX 3070 Ti. Dataset auto-downloads (369MB).

### 4.3 [HIGH IMPACT, HIGH EFFORT] Custom Multi-Person Hand Dataset

**The gap:** The Ultralytics hand-keypoints dataset has mostly single-hand-per-image annotations. For multi-person slash games, we need:
- Multiple hands in frame (2-4)
- Hands crossing/overlapping
- Fast motion blur (slashing)
- Various skin tones and lighting

**Approach:**
1. Record gameplay sessions with webcam (both players slashing)
2. Run MediaPipe on recordings to auto-annotate (VIDEO mode for better accuracy)
3. Convert annotations to YOLO keypoint format
4. Mix with existing hand-keypoints dataset
5. Fine-tune YOLO26n-pose on combined dataset

**Bonus:** Add a "gesture class" label (idle, slash, pinch, open) for end-to-end gesture + keypoint detection.

### 4.4 [MEDIUM IMPACT, HIGH EFFORT] ONNX Runtime GDExtension Backend

**Why:** Replaces MediaPipe with a general-purpose model runner in Godot.

**Architecture:**
```
Godot GDExtension (C++) wrapping ONNX Runtime
-> Load .onnx model
-> Accept Image input from SubViewport
-> Return detections + keypoints as Godot arrays
-> Use DirectML EP on Windows, NNAPI on Android, CoreML on iOS
```

### 4.5 [HIGH IMPACT, MEDIUM EFFORT] Person-Hand Association Layer

**Approaches (no ML needed):**

1. **Spatial assignment:** Player 1 = left half of screen, Player 2 = right half (simplest, works for arcade)
2. **Hungarian algorithm:** Match detected hands to previous-frame tracks using position distance + hand size. Classical assignment problem -- O(n^3) for n hands, trivially fast for n=4
3. **Body-pose anchoring:** Use YOLO26-pose (body, 17 keypoints) to detect people, assign hands to the nearest person's wrist keypoints (indices 9, 10 in COCO-Pose)

Option 2 (Hungarian matching) is the sweet spot: pure algorithmic, ~50 lines of GDScript, no extra model.

### 4.6 [MEDIUM IMPACT, HIGH EFFORT] ML Gesture Classification

**Approaches:**
1. **Temporal CNN on landmark sequences:** 10-frame windows of 21 landmarks -> 1D conv -> gesture class. ~50K params, <1ms on CPU
2. **LSTM/GRU on landmark velocities:** Better for variable-length gestures
3. **Gesture head on YOLO26:** Modify pose model to output gesture classes alongside keypoints

For the demo: rule-based is fine. For production: temporal CNN is the right investment.

### 4.7 [FUTURE] ExecuTorch Integration

When: After YOLO26 hand model is validated and maximum mobile performance is needed. ExecuTorch + QNN on Snapdragon 8 Gen 3 could run YOLO26n-pose at >60fps.

---

## 5. Priority Order

### For July 13 Demo (desktop webcam)

| Priority | Action | Time | Impact |
|----------|--------|------|--------|
| 1 | Replace EMA with 1-Euro Filter in `smoothing.gd` | 2h | HIGH |
| 2 | Build Hungarian-matching hand tracker in `ai_input.gd` | 3h | HIGH |
| 3 | Add spatial player assignment (left/right screen split) | 1h | HIGH |
| 4 | Build and polish Fruit Chop game | 2 days | CRITICAL |

### For Product (post-demo)

| Priority | Action | Time | Impact |
|----------|--------|------|--------|
| 1 | Train YOLO26n-pose on hand-keypoints dataset | 4h | VERY HIGH |
| 2 | Record multi-person slash dataset, fine-tune YOLO26 | 1 day | VERY HIGH |
| 3 | Build ONNX Runtime GDExtension backend | 1 week | VERY HIGH |
| 4 | ML gesture classifier (temporal CNN on landmarks) | 2 days | HIGH |
| 5 | ExecuTorch mobile deployment pipeline | 1 week | VERY HIGH |
| 6 | Android + iOS deployment | 1 week | HIGH |

---

## 6. Key Architectural Insight

The fundamental question is:

**MediaPipe (two-stage, tracking-dependent) vs YOLO26 (single-shot, detection-every-frame)**

For fast slashing motions from multiple people, **detection-every-frame is better than tracking-based**:

- Fast slashes move the hand 100+ pixels between frames at 30fps. Optical flow tracking fails at this velocity
- Multi-person hand crossing causes tracking ID swaps. Detection-every-frame + Hungarian matching is more robust
- YOLO26n-pose at 40ms/frame on CPU is fast enough for 25fps, and on GPU/NPU it can exceed 60fps
- Single-shot means latency is constant and predictable, unlike MediaPipe where palm re-detection causes sporadic frame spikes

The trade-off: MediaPipe's landmark model produces slightly higher quality 21-point landmarks (purpose-built). YOLO26 keypoints may be noisier. The 1-Euro filter compensates for this.

---

## Appendix: Key References

- [MediaPipe Hands paper (arXiv:2006.10214)](https://arxiv.org/abs/2006.10214) -- Zhang et al., CVPR Workshop 2020
- [1-Euro Filter (CHI 2012)](https://dl.acm.org/doi/10.1145/2207676.2208639) -- Casiez, Roussel, Vogel
- [Ultralytics YOLO26](https://github.com/ultralytics/ultralytics) -- 59.1k stars, AGPL-3.0
- [YOLO26 Hand Keypoints Dataset](https://docs.ultralytics.com/datasets/pose/hand-keypoints/) -- 26,768 images, 21 keypoints
- [ExecuTorch](https://pytorch.org/executorch/) -- PyTorch on-device runtime
- [ONNX Runtime Execution Providers](https://onnxruntime.ai/docs/execution-providers/) -- Hardware acceleration backends
- [GDMP (MediaPipe GDExtension)](https://github.com/j20001970/GDMP) -- Current backend
- [godot-xr-kit 1-Euro filter (GDScript)](https://github.com/patrykkalinowski/godot-xr-kit/blob/master/addons/xr-kit/smooth-input-filter/scripts/one_euro_filter.gd)
