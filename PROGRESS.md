# Progress Log

> Updated after every major commit or feature milestone.
> Most recent entries first.

---

## 2026-07-04 — GamePose Experiments 1–2: Mobile Operating Point Found

### What was done

Reframed the narrative per review: the hand-model training is a **controlled ablation** (hand-scale vs person-scale paradigm), and the contribution track is **GamePose — specializing YOLO26-pose for room-scale motion games** ([plan + results](docs/plan/gamepose-enhancements.md)).

**Experiment 1 — resolution operating point (DONE, major win):**
- CPU: imgsz **320 = 2.2× faster than 640** (~26ms vs ~57ms P50), **~0% slash dropout preserved**, median wrist deviation ≤14px (vs 80px slash radius). **320 is the mobile export size.**
- GPU: latency flat across sizes (nano model is overhead-bound on RTX 3070 Ti) — operating points must be chosen on target-class hardware.
- Fixed deviation metric: largest-person matching + median (ghost-flicker robust).

**Experiment 2 — velocity-predictive tracking (DONE, honest nuance):**
- Constant-velocity prediction is WORSE than hold-last (−4.3%) on erratic slash motion; damped velocity only +5.4%. Prediction is not a free win; small optional AIInput feature at best.

**Next (deferred):** Exp 3–4 wrist-weighted fine-tune + motion-blur augmentation (needs COCO-pose download).

### Decision
Godot integration proceeds with pretrained `yolo26n-pose`: **imgsz 640 desktop / 320 mobile**, wrists (kpts 9,10) → hand positions, person boxes (largest-N + calibration lock-in) → player identity.

---

## 2026-07-04 — BENCHMARK COMPLETE: YOLO26 Body Pose Wins Decisively

### What was done

**Recorded the 10-clip test corpus** (two people, 1280×720@30fps, ~5,500 frames): idle/slash at 1/2/3m, two-person idle/slash/crossing, walk-on. Every model evaluated on identical frames.

**Ran the full 4-model benchmark** (executed headlessly, outputs baked into the notebook):

| Model | P95 ms | Slash drop @2m | 2-player drop | Verdict |
|---|---|---|---|---|
| **yolo26_body (pretrained)** | **21.6** | **0.0%** | **0.0%** | **WINNER — passes all gates** |
| yolo26_hand (ours, mAP50 90.3%) | 21.5 | 98.7% | 100% | FAIL — can't see room-scale hands |
| mediapipe_hands (Tasks VIDEO) | 43.4 | 69.7% | 92.8% | FAIL — explains the unplayable game |
| rtmpose_body (ONNX CPU) | 51.6 | 0.0% | 0.0% | FAIL on latency only |

**Hypotheses:** H1 (body beats hand under fast motion) and H3 (hand detectors die with distance) CONFIRMED decisively. H4 confirmed by outcome. Full analysis: [`docs/research/benchmark-results-2026-07.md`](docs/research/benchmark-results-2026-07.md).

**The headline finding (blog post core):** our custom hand model scores 90.3% mAP50 on its dataset and detects **zero hands** in the actual deployment scenario — static dataset metrics are dangerously misleading for room-scale motion games. The temporal, in-situ benchmark caught what mAP could not.

**MediaPipe fixes during the run:** MediaPipe 0.10.35 removed the legacy `solutions` API; the adapter was ported to the Tasks `HandLandmarker` VIDEO API — the same API GDMP uses in Godot, making the baseline more representative. Also fixed jitter metric (per-wrist-slot) and per-clip tracker reset.

### Decision
**YOLO26n-pose (body) is the perception backend.** Wrists = hand positions, person boxes = player identity. Next: ONNX Runtime integration in Godot, calibration screen (also filters ghost detections), mobile round 2 on-device.

---

## 2026-07-04 — YOLO26 Hand Training Complete; Strategy Pivot to Body Pose; Benchmark Design

### What was done

**YOLO26n-pose hand training COMPLETE (100 epochs):**
- Final: Box mAP50 **99.2%** / mAP50-95 89.1%, Pose mAP50 **90.3%** / mAP50-95 77.1%
- Inference: 2.9ms/image on RTX 3070 Ti
- Exported to ONNX: `runs/pose/hand-yolo26n/weights/best.onnx` (12.3 MB, opset 20)

**Strategy pivot — hand as pointer, not skeleton:**
- Realized the games need whole-hand position + velocity + player identity, NOT 21-point finger articulation
- Documented in [`docs/research/gameplay-requirements.md`](docs/research/gameplay-requirements.md)
- Nex Playground's own published specs confirm: they track **18 body points** (not hand skeletons) for the same game catalog (Fruit Ninja, Sword Slash, Whack-a-Mole) — [`docs/research/nex-playground-analysis.md`](docs/research/nex-playground-analysis.md)
- Active Arcade (Nex's iPhone app) is the existence proof for phone-based tracking: prop phone up, stand 2m back, "make sure it sees your upper body"
- New primary candidate: **YOLO26n-pose body (pretrained COCO)** — wrists (kpts 9,10) as hand positions, person detection = free player identity

**Benchmark methodology designed (pre-registered):**
- Hypotheses H1-H4 (body pose beats hand detectors under fast motion / at distance)
- Recorded test corpus (~10 clips) instead of live webcam — fair, reproducible, publishable
- Metrics: latency P50/P95/P99, dropout rate + burst length, identity swaps/min, jitter, range 1-3m
- Common wrist-point evaluation across all models
- Gates (P95 ≤ 33ms per Ultralytics 30fps guidance, dropout ≤ 5% @ 2m) → lexicographic ranking
- Deliverable: blog post + open benchmark repo

**Apple ecosystem findings:**
- Apple has an official Godot plugin repo ([apple/plugins-for-godot](https://github.com/apple/plugins-for-godot), MIT) with GDExtension architecture and visionOS hand tracking — the template for an iOS Vision framework backend ([plan](docs/plan/apple-vision-ios-backend.md))

### Technical decisions made
- **Body pose primary, hand model fallback**: trained hand model solves a harder problem than the games need; kept as precision layer
- **Recorded corpus over live benchmarking**: every model sees identical frames; corpus becomes a publishable artifact
- **Lexicographic ranking over weighted scores**: dropout → latency → identity → jitter → range; ordering encodes gameplay priorities
- **No patent research on Nex**: their tech noted as proprietary, nothing more

### What's next
- Record benchmark corpus (~20 min webcam session)
- Run 4-model benchmark, pick winner
- Calibration screen in Godot
- Blog post + benchmark repo

---

## 2026-07-04 — Deep Research: Edge Hand Tracking, YOLO26 Training, Ecosystem Scan

### Research goal

Best on-device edge AI hand tracking for multi-person hack-and-slash gameplay in Godot, targeting both laptop and mobile devices. Full research documented in [docs/research/](docs/research/) and [docs/plan/](docs/plan/).

### What was done

**SOTA survey (round 1):**
- Analyzed MediaPipe Hands limitations for multi-person (two-stage pipeline, ID swaps on crossing, tracking-dependent)
- Identified YOLO26n-pose as single-shot alternative (2.9M params, 21 hand keypoints, exports everywhere)
- Found 1-Euro filter as strictly superior smoothing for hand tracking (speed-adaptive, CHI 2012)
- Mapped edge runtime landscape: ONNX Runtime, ExecuTorch, LiteRT, NCNN
- Published: [`docs/research/edge-hand-tracking-sota-2026.md`](docs/research/edge-hand-tracking-sota-2026.md)

**Ecosystem scan (round 2):**
- Discovered **RTMPose** (mmpose, 7.7k stars): pretrained hand ONNX models, 200+ FPS CPU, 9-14ms on Snapdragon 865, C++ ONNX Runtime examples, Android ncnn examples
- Discovered **Kazuhito00's gesture classifier** (750 stars): keypoint MLP + point history LSTM pattern for gesture classification on top of any hand tracker
- Found **NVIDIA trt_pose_hand** (233 stars): ResNet18 hand pose + SVM gesture on Jetson
- Found **HandLocator**: YOLOv8 + ONNX Runtime CUDA in C++ -- reference for our GDExtension
- Published: [`docs/research/ecosystem-scan-round2.md`](docs/research/ecosystem-scan-round2.md)

**YOLO26n-pose training (in progress):**
- Set up Python venv with ultralytics + PyTorch CUDA on RTX 3070 Ti
- Training on Ultralytics Hand Keypoints dataset (26,768 images, 21 keypoints, 369MB auto-download)
- Training script: `tools/train_hand_model.py`
- Validation script: `tools/validate_hand_model.py`
- Progress at epoch 57/100:
  - Box mAP50: **99.1%** (hand detection near-perfect)
  - Pose mAP50: **89.0%** (keypoint accuracy, up from 84.1% at epoch 25)
  - Pose mAP50-95: **74.9%** (strict keypoint accuracy)
- 384 images (2%) skipped due to out-of-bounds keypoint labels in dataset -- normal, no impact
- Checkpoints saved every 10 epochs + best.pt + last.pt in `runs/pose/hand-yolo26n/weights/`

**Gesture classifier plan (documented for later):**
- Architecture documented: static pose MLP + dynamic motion LSTM/1D-CNN (Kazuhito00 pattern)
- Data collection plan: built-in recording mode during gameplay
- Target gestures: idle, slash_right, slash_left, slash_down, slash_up, stab, circular
- Published: [`docs/plan/gesture-classifier.md`](docs/plan/gesture-classifier.md)

**Infrastructure:**
- Added `.gdignore` to `runs/` and `.venv/` (Godot was trying to import YOLO training artifacts)
- Added `runs/`, `.venv/`, `datasets/`, `*.pt` to `.gitignore`

### Technical decisions made
- **Evaluate RTMPose pretrained models before committing to YOLO26-only**: RTMPose hand models are 10-20x faster per-inference (top-down on cropped hand region vs full-frame). May be the better production path.
- **Gesture classifier deferred to pre/post-demo, not abandoned**: Rule-based works for Fruit Chop. ML classifier adds slash direction, custom gestures. Architecture documented now so it's ready when we need it.
- **Benchmark all three approaches**: MediaPipe (current) vs YOLO26 (training) vs RTMPose (pretrained). Pick winner based on latency, accuracy, multi-hand reliability.

### What's next
- Finish YOLO26 training (epoch 57 → 100, ~3 more hours)
- Download and benchmark RTMPose hand ONNX models
- Run comparative benchmarks (tools/benchmark_models.py)
- Export YOLO26 to ONNX when training completes
- Pick winner model for production

---

## 2026-07-04 — Fruit Chop Game Complete, Launcher Polished, Latency Improvements

### What was done

**Fruit Chop game (complete, playable e2e):**
- Built `scenes/fruit_chop/fruit_chop.gd` (729 lines) — full game controller
- Built `scenes/fruit_chop/fruit_item.gd` (157 lines) — individual fruit/bomb with parabolic physics, slice animation, splash VFX
- Built `scenes/fruit_chop/fruit_chop.tscn` — scene tree with camera background, game layer, UI, cursor layer
- 6 fruit types: Watermelon, Orange, Lime, Banana, Pineapple (2pts), Grapes (3pts)
- Bomb mechanics: 12% spawn chance, -5 penalty, red screen flash, combo reset
- Combo system: chain slashes within 0.8s, multiplier up to 8x, animated "COMBO!" label
- Per-frame slash detection: hand speed > 0.6 + proximity < 80px = slice (no reliance on gesture events for responsiveness)
- Slash VFX: fruit halves tumble apart with gravity, juice splash expands and fades, floating score popups
- Colored slash trails: Line2D per hand with gradient fade, width scales with hand speed
- Progressive difficulty: spawn interval 2.2s → 0.5s, wave size 1-2 → 3-5 fruits
- 60-second game timer with flashing red pulse in final 10 seconds
- 3-2-1-CHOP countdown with scale-bounce animations
- Game Over screen: final score, stats (sliced/missed/best combo), auto-returns to launcher in 6 seconds
- Camera + MediaPipe backend setup (same pattern as launcher, each scene owns its backend)
- Hand cursors with per-player colors (reuses HandCursor from launcher)

**AIInput singleton (the abstraction layer):**
- `addon/camera_intelligence/ai_input.gd` — signals: `hand_tracked`, `hand_appeared`, `hand_lost`, `hand_gesture`, `status_changed`
- `addon/camera_intelligence/hand_state.gd` — per-hand data: screen_position, velocity, speed, 21 landmarks, fingertip positions, pinch_distance, handedness
- `addon/camera_intelligence/gesture_detector.gd` — swipe detection (speed + distance + cooldown), pinch detection (hysteresis state machine, 3-frame confirm)
- `addon/camera_intelligence/gesture_event.gd` — gesture data: name, phase, position, direction, speed, hand_id
- `addon/camera_intelligence/mediapipe_backend.gd` — camera management, model download/cache, frame processing, format handling (RGB/YCbCr/YUV420)
- Registered as Godot autoload at `/root/AIInput`

**1-Euro filter (replaced EMA smoothing):**
- `addon/camera_intelligence/smoothing.gd` — LandmarkSmoother with per-landmark 1-Euro filters (21 x Vector3)
- Speed-adaptive: low cutoff at rest (removes jitter), high cutoff during fast slashes (minimizes lag)
- Parameters: `mincutoff=1.0`, `beta=0.007` — tunable at runtime via `AIInput.set_smoothing()`

**Latency fixes (5 optimizations):**
- Downscale inference frames to 320x240 (smaller image = faster MediaPipe)
- Frame throttling to avoid queueing
- Aggressive 1-Euro filter tuning for fast motion
- Fingertip tracking for slash detection
- Reduced MediaPipe confidence thresholds

**Camera feed switching fix:**
- `mediapipe_backend.gd` now hot-swaps to preferred feed (NexiGo/USB/Webcam) when it arrives after initial feed is already open
- Previous behavior: early return if any feed was already open → stuck on built-in HD Camera
- New behavior: `_on_feed_added` checks if arriving feed is preferred, `_switch_to_feed` disconnects old and opens new

**Launcher UI ("Play With Air" branding):**
- `scenes/launcher/launcher.gd` — 5 game cards (Fruit Chop, Whack-a-Mole, Bubble Pop, Hoops, Hand Test), hover-to-select with progress bar fill
- `scenes/launcher/game_card.gd` — smooth scale lerp, animated border glow (3→8px), background brightens on hover
- `scenes/launcher/hand_cursor.gd` — programmatic ring + center dot (56px), per-player color, speed-reactive pulse
- Hand logo (`logo_hand_transparent.png`) + sticker title (`title_play_with_air.png`) — generated via gpt-image-2, white backgrounds removed with Pillow
- Fonts: Fredoka (headlines), Nunito (body) — variable TTFs
- Design language: Midnight backgrounds, Electric Coral/Ocean/Sunshine/Snow/Mist palette

**Asset generation (37 PNGs):**
- `tools/generate_fruit_chop_assets.py` — 20 game assets: 6 whole fruits, 5 halves, 1 bomb, 6 splashes, 1 star, 1 score popup
- `tools/generate_ui_assets.py` — 20 UI assets: 5 game icons, 3 cursors, 4 buttons, 2 decorations, branding
- All generated via OpenAI image API (gpt-image-1 for game assets, gpt-image-2 medium for UI)
- White background removal via Pillow pixel loop (brightness > 245 → transparent)

**Research:**
- `docs/research/edge-hand-tracking-sota-2026.md` — comprehensive SOTA survey: YOLO26-pose hand keypoints, 1-Euro filter, top-down person-to-hand pipeline, edge runtime landscape (ONNX/ExecuTorch/LiteRT/NCNN), priority roadmap for demo and post-demo

### Technical decisions made
- **Per-frame proximity slash detection over gesture events**: The GestureDetector's swipe events have 300ms cooldown — too slow for fruit ninja. Instead, each frame checks hand speed + distance to fruits directly. Instant, responsive, can slice multiple fruits per swipe.
- **Each scene owns its MediaPipeBackend**: When `change_scene_to_file` is called, the old scene (and its backend) is freed. The new scene creates its own backend. AIInput persists as an autoload.
- **Player-facing brand is "Play With Air"**: Not "Camera Intelligence Kit" (that's the SDK name).
- **Programmatic hand cursor (not image sprite)**: Generated hand images had white backgrounds that looked bad over camera feed. Ring + dot drawn with StyleBoxFlat is cleaner.
- **1-Euro filter over EMA**: Speed-adaptive smoothing — nearly zero lag on fast slashes, good jitter removal at rest.

### What's next
- Polish Fruit Chop for demo (sound effects, screen shake, particle juice)
- Two-player scoring and player assignment
- Android export and mobile testing
- Demo dry run (July 11-12)

---

## 2026-07-04 — Foundation: GDMP + Hand Tracking Working

### What was done

**Research (MVP 0 complete):**
- Scanned all Godot + ML prior art on GitHub (GDMP, Godot-ONNX, godot-webcam-hand-tracking, HibachiHavoc, gridstorm-polepad-ai)
- Mapped the 2026 edge AI landscape: YOLO26 (latest Ultralytics), ExecuTorch v1.3.1, Google LiteRT, ONNX Runtime Web + WebGPU
- Studied Nex Playground ($299 hardware cube, body tracking games including Fruit Ninja) as the commercial benchmark
- Confirmed the gap: nobody has built a perception-to-gameplay abstraction layer for Godot
- Identified GDMP as the fastest path to a working demo

**Build (MVP 1 foundation):**
- Created Godot 4.6.2 project with GL Compatibility renderer
- Integrated GDMP plugin (MediaPipe GDExtension, built from master for Godot 4.6 compatibility)
  - Source: cloned from [GDMP-demo](https://github.com/j20001970/GDMP-demo) which CI-builds from GDMP master
  - Platforms included: Windows x86_64, Android arm64/x86_64, iOS, macOS, Linux, Web (WASM)
- Integrated CameraServerExtension (provides native webcam access on Windows/iOS where Godot lacks built-in drivers)
- Built hand tracking test scene:
  - Camera feed via CameraTexture + SubViewport pipeline
  - MediaPipe HandLandmarker running in LIVE_STREAM mode (async, C++ native)
  - Model auto-download from Google Cloud Storage on first run, cached at `user://hand_landmarker.task`
  - 21-point hand skeleton rendering with color-coded hands and fingertip highlights
  - Multi-hand support: up to 4 hands tracked simultaneously (2 players x 2 hands)
  - External webcam preference (NexiGo over built-in laptop camera)
  - FPS counter

### Technical decisions made
- **GDMP over browser bridge**: Native C++ GDExtension, not a WebSocket hack. Same code runs on desktop and mobile.
- **CameraServerExtension required on Windows**: Godot's built-in CameraServer has no Windows camera driver.
- **GDMP-demo master binaries over v0.6 release**: v0.6 was built against godot-cpp 4.4, incompatible with Godot 4.6.2. Demo repo CI builds from master targeting godot-cpp 4.6-stable.
- **CPU delegate for now**: MediaPipe GPU delegate only available on Android/iOS/Linux. CPU is reliable cross-platform and fast enough for hand tracking.
- **GL Compatibility renderer**: Widest platform support (Android, iOS, Web, desktop).

---

## Project Stats

| Metric | Value |
|---|---|
| Godot version | 4.6.2 stable |
| GDMP version | master (godot-cpp 4.6-stable, MediaPipe v0.10.35) |
| Platforms with binaries | Windows, Android, iOS, macOS, Linux, Web |
| Hand tracking | Up to 4 hands, 21 landmarks each, ~30fps |
| Model size | ~10MB (hand_landmarker float16) |
| Lines of GDScript | ~2,500 |
| Game assets | 37 PNGs (fruit, bomb, splash, UI, branding) |
| Games playable | 1 (Fruit Chop) + 1 test scene (Hand Test) |
| Custom fonts | 2 (Fredoka, Nunito) |
