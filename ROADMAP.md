# Roadmap

> Living document. Updated as milestones are hit or priorities shift.
> See `PROGRESS.md` for what's actually done.

## Vision

**Open-source Nex Playground**: on-device camera AI that turns body/hand tracking into game events, running on phones and tablets with no custom hardware. Godot-native.

**Demo target**: AI Tinkerers Seattle, July 13 2026.
**First game**: Fruit Chop (two-player hand-slash fruit ninja).

---

## Phase 1: Foundation (July 4-6)

- [x] Prior-art research & landscape scan
- [x] GDMP integration (MediaPipe hand tracking in Godot 4.6)
- [x] CameraServerExtension for Windows webcam access
- [x] Hand tracking test scene (multi-hand, landmark overlay)
- [ ] AIInput singleton (perception-to-gameplay abstraction layer)
  - Swipe/slash detection from hand velocity
  - Smoothing (EMA filter on landmark positions)
  - Gesture state machine (debounce, hysteresis)
  - Hand position as normalized screen coordinates
  - Godot signals: `hand_gesture`, `hand_tracked`, `hand_lost`

## Phase 2: Fruit Chop Game (July 6-9)

- [ ] Fruit spawning (launch from bottom, arc trajectory)
- [ ] Slash detection (hand movement velocity + direction)
- [ ] Slash trail rendering (per-hand color)
- [ ] Fruit splitting (sprite split + particle effects)
- [ ] Two-player scoring
- [ ] Bomb/penalty fruit
- [ ] Combo counter
- [ ] Game over / restart flow
- [ ] Sound effects

## Phase 3: Mobile (July 9-11)

- [ ] Android APK export (GDMP already has Android arm64 binaries)
- [ ] Test camera + hand tracking on Android phone
- [ ] Touch fallback for devices without front camera
- [ ] iOS test (if Mac available for Xcode build)
- [ ] Performance tuning (target 30fps inference on mobile)

## Phase 4: Demo Polish (July 11-13)

- [ ] Calibration screen ("show your hands" on startup)
- [ ] Debug overlay toggle (landmarks, FPS, latency, gesture state)
- [ ] Particle effects, screen shake, juice
- [ ] Record backup demo video
- [ ] Dry run with two players
- [ ] Prepare 2-minute pitch narrative

---

## Future (Post-Demo)

### Backend Abstraction
- [ ] ONNX Runtime backend (YOLO26-pose for body tracking, custom models)
- [ ] ExecuTorch backend (PyTorch-native mobile edge, QNN/CoreML delegation)
- [ ] Google LiteRT backend (unified mobile/web/edge)
- [ ] Backend-swappable AIInput API (`AIInput.set_backend("mediapipe")` / `"onnxruntime"`)

### More Gesture/Perception
- [ ] Body pose tracking (lean, jump, squat via MediaPipePoseLandmarker or YOLO26-pose)
- [ ] Face tracking (expressions, head tilt)
- [ ] Object detection (cards, props via YOLO26-detect)
- [ ] Custom gesture training

### Platform Expansion
- [ ] Godot HTML5/Web export (blocked by Godot web camera proposal #12493)
- [ ] Godot Asset Library package
- [ ] Unity package with same event schema (long-term)

### Developer Experience
- [ ] Documentation site
- [ ] Example scenes (wizard gestures, body steering, prop detection)
- [ ] Calibration UI component
- [ ] Visual scripting nodes
