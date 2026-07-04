# Progress Log

> Updated after every major commit or feature milestone.
> Most recent entries first.

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

### What's next
- Build AIInput singleton (the abstraction layer)
- Build Fruit Chop game
- Test Android export

---

## Project Stats

| Metric | Value |
|---|---|
| Godot version | 4.6.2 stable |
| GDMP version | master (godot-cpp 4.6-stable, MediaPipe v0.10.35) |
| Platforms with binaries | Windows, Android, iOS, macOS, Linux, Web |
| Hand tracking | Up to 4 hands, 21 landmarks each, ~30fps |
| Model size | ~10MB (hand_landmarker float16) |
| Lines of GDScript | ~300 |
