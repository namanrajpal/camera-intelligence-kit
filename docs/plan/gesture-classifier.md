# Plan: ML Gesture Classifier (Kazuhito00 Pattern)

**Date:** 2026-07-04
**Status:** Documented, implementation deferred to pre-demo or post-demo
**Priority:** Medium (rule-based detection works for Fruit Chop demo)
**Reference:** [Kazuhito00/hand-gesture-recognition-using-mediapipe](https://github.com/Kazuhito00/hand-gesture-recognition-using-mediapipe) (750 stars)
**Research context:** [ecosystem-scan-round2.md](../research/ecosystem-scan-round2.md)

---

## High-Level Goal

Replace rule-based gesture detection (speed threshold + distance) with a lightweight ML classifier that can distinguish slash directions, differentiate jabs from swings, and learn custom game gestures. Must run in microseconds on top of whatever hand tracker we use (MediaPipe, YOLO26, or RTMPose).

---

## Architecture

Two classifiers, both running on the 21 landmarks output by the hand tracker:

### A. Static Pose Classifier (keypoint_classifier)

**Purpose:** Classify the current hand shape (fist, open palm, peace, point, etc.)

```
Input:  21 landmarks (x,y) -> flatten to 42 floats
        Normalize: subtract wrist position, divide by max distance
Output: gesture class ID (0..N)
```

**Model:** Simple MLP
```
Input(42) -> Dense(20, ReLU) -> Dropout(0.2) -> Dense(10, ReLU) -> Dropout(0.2) -> Dense(N, Softmax)
```

**Game gestures to classify:**
- 0: open_palm (idle, not slashing)
- 1: fist (grab)
- 2: point (select/aim)
- 3: peace (two-player signal)
- 4: no_hand (background)

**Model size:** <30KB TFLite. Inference: <0.1ms.

### B. Dynamic Gesture Classifier (point_history_classifier)

**Purpose:** Classify finger motion patterns over time (slash directions, circular motions, stabs)

```
Input:  Last 16 frames of index fingertip (x,y) position deltas
        = 16 x 2 = 32 floats
        Normalize: relative to first frame, scale by hand size
Output: motion class ID (0..N)
```

**Model option 1: LSTM**
```
Input(16, 2) -> LSTM(32) -> Dense(16, ReLU) -> Dense(N, Softmax)
```

**Model option 2: 1D CNN (preferred for edge)**
```
Input(16, 2) -> Conv1D(16, k=3, ReLU) -> Conv1D(8, k=3, ReLU) -> Flatten -> Dense(N, Softmax)
```

**Game gestures to classify:**
- 0: idle (no significant motion)
- 1: slash_right
- 2: slash_left
- 3: slash_down
- 4: slash_up
- 5: stab (forward thrust -- z-axis motion)
- 6: circular (for special moves)

**Model size:** <50KB TFLite. Inference: <0.1ms.

---

## Data Collection Plan

### Built-in recording mode (Kazuhito00 pattern)

Add a mode to the game where pressing a key starts recording labeled gesture data:

1. **Keypoint mode ('k'):** Each frame saves `[class_id, x0, y0, x1, y1, ..., x20, y20]` to `data/keypoint.csv`
2. **History mode ('h'):** Each frame saves `[class_id, dx0, dy0, dx1, dy1, ..., dx15, dy15]` to `data/point_history.csv`
3. Press '0'-'9' to set the class label while recording

### Collection sessions

- Session 1: Both developers making each gesture 50x in various positions/angles
- Session 2: During actual Fruit Chop gameplay -- natural slash patterns
- Session 3: Edge cases -- fast motion, partial occlusion, distance variation

**Target:** ~200 samples per class, ~1400 total for 7 motion classes.

---

## Training Pipeline

```python
# keypoint_classification.py
import tensorflow as tf
import numpy as np
import csv

# Load data
data = np.loadtxt('data/keypoint.csv', delimiter=',')
X, y = data[:, 1:], data[:, 0].astype(int)

# Train
model = tf.keras.Sequential([
    tf.keras.layers.Input(shape=(42,)),
    tf.keras.layers.Dense(20, activation='relu'),
    tf.keras.layers.Dropout(0.2),
    tf.keras.layers.Dense(10, activation='relu'),
    tf.keras.layers.Dropout(0.2),
    tf.keras.layers.Dense(NUM_CLASSES, activation='softmax')
])
model.compile(optimizer='adam', loss='sparse_categorical_crossentropy', metrics=['accuracy'])
model.fit(X, y, epochs=100, batch_size=32, validation_split=0.2)

# Export to TFLite
converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()
with open('model/keypoint_classifier.tflite', 'wb') as f:
    f.write(tflite_model)
```

Same pattern for `point_history_classification.py` with LSTM/1D-CNN.

---

## Integration into Godot

### Option A: GDScript inference (simplest)

The models are so tiny (<50KB, <100 weights) that we could implement inference directly in GDScript:

```gdscript
# In gesture_detector.gd
func classify_motion(history: Array[Vector2]) -> String:
    # Flatten 16 frames of (dx, dy) deltas
    var input := PackedFloat32Array()
    for i in range(mini(history.size(), 16)):
        input.append(history[i].x)
        input.append(history[i].y)
    # Run through pre-loaded weight matrices (hardcoded or loaded from JSON)
    var h1 := _matmul(input, _weights_1) # 32 -> 16
    h1 = _relu(h1)
    var h2 := _matmul(h1, _weights_2)    # 16 -> 8
    h2 = _relu(h2)
    var out := _matmul(h2, _weights_3)   # 8 -> 7
    return GESTURE_NAMES[_argmax(out)]
```

### Option B: ONNX Runtime (if we build the GDExtension anyway)

Run the TFLite/ONNX model through the same ONNX Runtime GDExtension used for hand tracking. More robust but depends on the backend being built first.

---

## Timeline

| When | What |
|------|------|
| Now | Document architecture (this file) |
| Pre-demo (if time) | Add data collection mode to Fruit Chop |
| Post-demo week 1 | Collect gesture data, train classifiers |
| Post-demo week 2 | Integrate into GestureDetector, A/B test vs rule-based |

---

## Cross-References

- [Ecosystem Scan Round 2](../research/ecosystem-scan-round2.md) -- where this pattern was discovered
- [Initial SOTA Survey](../research/edge-hand-tracking-sota-2026.md) -- section 4.6 on ML gesture classification
- [ROADMAP.md](../../ROADMAP.md) -- tracked under Research & ML section
