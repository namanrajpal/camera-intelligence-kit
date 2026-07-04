# Roadmap

> Living document. Updated as milestones are hit or priorities shift.
> See `PROGRESS.md` for what's actually done.

## Vision

**Open-source Nex Playground**: on-device camera AI that turns body/hand tracking into game events, running on phones and tablets with no custom hardware. Godot-native.

**Demo target**: AI Tinkerers Seattle, July 13 2026.
**First game**: Fruit Chop (two-player hand-slash fruit ninja).

---

## Phase 1: Foundation (July 4-6) -- COMPLETE

- [x] Prior-art research & landscape scan
- [x] GDMP integration (MediaPipe hand tracking in Godot 4.6)
- [x] CameraServerExtension for Windows webcam access
- [x] Hand tracking test scene (multi-hand, landmark overlay)
- [x] AIInput singleton (perception-to-gameplay abstraction layer)
  - Swipe/slash detection from hand velocity + distance + cooldown
  - 1-Euro filter smoothing (replaced EMA — speed-adaptive, near-zero lag on fast slashes)
  - Gesture state machine (debounce, hysteresis, 3-frame confirm)
  - Hand position as normalized screen coordinates
  - Godot signals: `hand_gesture`, `hand_tracked`, `hand_appeared`, `hand_lost`, `status_changed`
- [x] Launcher UI ("Play With Air" branding, 5 game cards, hover-to-select, hand cursors)
- [x] Asset generation pipeline (37 PNGs via OpenAI image API)
- [x] Camera feed hot-swap (prefer NexiGo/USB over built-in webcam)
- [x] Edge AI research document (`docs/research/edge-hand-tracking-sota-2026.md`)

## Phase 2: Fruit Chop Game (July 4-9) -- CORE COMPLETE, POLISH REMAINING

- [x] Fruit spawning (launch from bottom, parabolic arc, progressive waves)
- [x] Slash detection (per-frame hand proximity + speed, not gesture events)
- [x] Slash trail rendering (Line2D per hand, gradient fade, speed-reactive width)
- [x] Fruit splitting (half sprites tumble apart, splash VFX expands/fades)
- [ ] Two-player scoring (currently single-score; need per-player assignment)
- [x] Bomb/penalty fruit (12% chance, -5 pts, red flash, combo reset)
- [x] Combo counter (0.8s window, multiplier up to 8x, animated label)
- [x] Game over / restart flow (60s timer, stats screen, auto-return to launcher)
- [ ] Sound effects
- [ ] Screen shake / extra juice on slice
- [ ] Back-to-menu button during gameplay

## Phase 3: Mobile (July 9-11)

- [ ] Android APK export (GDMP already has Android arm64 binaries)
- [ ] Test camera + hand tracking on Android phone
- [ ] Touch fallback for devices without front camera
- [ ] iOS test (if Mac available for Xcode build)
- [ ] Performance tuning (target 30fps inference on mobile)

## Phase 4: Demo Polish (July 11-13)

- [ ] Calibration screen ("show your hands" on startup)
- [ ] Debug overlay toggle (landmarks, FPS, latency, gesture state)
- [ ] Particle effects polish
- [ ] Record backup demo video
- [ ] Dry run with two players
- [ ] Prepare 2-minute pitch narrative

## Research & ML Track (parallel, ongoing)

> Goal: best on-device edge AI hand tracking for multi-person hack-and-slash gameplay.
> See [docs/research/](docs/research/) for SOTA surveys, [docs/plan/](docs/plan/) for implementation plans.

- [x] SOTA survey: MediaPipe limitations, YOLO26, 1-Euro filter, edge runtimes ([edge-hand-tracking-sota-2026.md](docs/research/edge-hand-tracking-sota-2026.md))
- [x] Ecosystem scan: RTMPose, Kazuhito00 gesture pattern, NVIDIA trt_pose_hand ([ecosystem-scan-round2.md](docs/research/ecosystem-scan-round2.md))
- [x] 1-Euro filter (replaced EMA smoothing in `smoothing.gd`)
- [x] Latency optimizations (downscale, throttling, fingertip tracking)
- [ ] YOLO26n-pose training on hand-keypoints dataset (in progress, epoch 57/100, mAP50 89%)
- [ ] RTMPose pretrained hand model evaluation (benchmark against YOLO26 and MediaPipe)
- [ ] Pick winner model based on benchmarks
- [ ] ONNX Runtime GDExtension backend (replaces MediaPipe for production)
- [ ] ML gesture classifier — Kazuhito00 pattern ([gesture-classifier.md](docs/plan/gesture-classifier.md))
- [ ] Custom multi-person slash dataset collection and fine-tuning
- [ ] Mobile deployment (ExecuTorch / LiteRT / ncnn)

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
