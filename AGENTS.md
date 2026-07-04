# Godot Camera Intelligence Kit

**Positioning:** "Open-source Nex Playground — on-device camera AI that turns body/hand tracking into game events for Godot, running on phones and tablets with no custom hardware."

**Source of truth:** [`INITIAL_PROMPT.md`](./INITIAL_PROMPT.md) — the original ChatGPT brainstorm. Read it for the full vision. Do not edit it except to append dated addenda.

## Key documents

| File | Purpose | When to update |
|---|---|---|
| [`INITIAL_PROMPT.md`](./INITIAL_PROMPT.md) | Original vision/brief. Permanent. | Never edit, only append addenda. |
| [`ROADMAP.md`](./ROADMAP.md) | What we plan to build, in priority order. | When priorities shift or milestones are added. |
| [`PROGRESS.md`](./PROGRESS.md) | What was actually built, with dates and decisions. | After every major commit or feature. |
| [`AGENTS.md`](./AGENTS.md) | Agent context (this file). | When conventions or architecture change. |

## The wedge

Not a generic model runner. The value is the **perception → intent → gameplay events** layer: turn noisy camera ML output into stable, calibrated, debounced Godot signals game devs can use without knowing anything about tensors/ONNX/MediaPipe.

```
Camera frame → PerceptionBackend → landmarks/boxes → smoothing/calibration/state machine → Godot signals → gameplay
```

Backends (MediaPipe / ONNX Runtime / ExecuTorch) are swappable implementation details behind one stable `AIInput` Godot API.

## Current phase

**MVP 2 — Fruit Chop game playable.** AIInput singleton built with 1-Euro smoothing + gesture detection. Fruit Chop game complete (60s, 6 fruit types, bombs, combos, slash trails, game over). Launcher with "Play With Air" branding and hover-to-select cards. Next: polish for demo, two-player scoring, Android export.

**Demo target:** AI Tinkerers Seattle, July 13 2026.
**First game:** Fruit Chop (hand-slash fruit ninja).

## Architecture (as built)

```
Godot 4.6.2 Project
├── addons/
│   ├── GDMP/                        # MediaPipe GDExtension (all platforms)
│   │   └── libs/                    # Native binaries (gitignored, ~400MB)
│   └── CameraServerExtension/       # Native webcam drivers for Windows/iOS
├── addon/
│   └── camera_intelligence/         # AIInput singleton + backend
│       ├── ai_input.gd              # Autoload: signals, hand state, gesture dispatch
│       ├── hand_state.gd            # Per-hand data (position, velocity, landmarks, pinch)
│       ├── gesture_detector.gd      # Swipe + pinch detection (state machines)
│       ├── gesture_event.gd         # Gesture data class
│       ├── mediapipe_backend.gd     # Camera + MediaPipe integration, feed hot-swap
│       └── smoothing.gd             # 1-Euro filter (per-landmark, speed-adaptive)
├── scenes/
│   ├── launcher/                    # "Play With Air" game selector
│   │   ├── launcher.gd/tscn         # 5 game cards, hover-to-select, camera bg
│   │   ├── game_card.gd             # Animated card with progress bar
│   │   └── hand_cursor.gd           # Ring+dot cursor, per-player color
│   └── fruit_chop/                  # Fruit Chop game (PLAYABLE)
│       ├── fruit_chop.gd/tscn       # Game controller (729 lines)
│       └── fruit_item.gd            # Fruit/bomb physics + slice VFX
├── assets/
│   ├── fruit_chop/                  # 20 game assets (fruits, bomb, splashes, star)
│   ├── ui/                          # 20 UI assets (icons, cursors, buttons, branding)
│   └── fonts/                       # Fredoka + Nunito variable TTFs
├── tools/                           # Asset generation scripts (OpenAI API)
├── docs/research/                   # SOTA research (YOLO26, 1-Euro, edge runtimes)
├── examples/
│   └── hand_tracking_test/          # Raw landmark overlay test scene
└── project.godot
```

**Full pipeline (as built):**
```
Webcam → CameraServerExtension → CameraTexture → SubViewport → Image
→ MediaPipeImage → MediaPipeHandLandmarker (C++ native, async)
→ result_callback → 21 landmarks per hand (up to 4 hands)
→ AIInput.process_hand_result() → 1-Euro smooth → HandState
→ 3-frame confirm → hand_appeared/hand_tracked signals
→ GestureDetector.detect() → swipe/pinch events → hand_gesture signal
→ Game scenes connect to signals → gameplay
```

**Slash detection (Fruit Chop):**
```
Each frame: for each hand with speed > 0.6:
  for each unsliced fruit within 80px of hand position:
    → slice fruit, show halves + splash, score + combo
```
This is faster and more responsive than relying on GestureDetector's swipe events (which have 300ms cooldown).

**Camera feed hot-swap:** When preferred feed (NexiGo/USB/Webcam) arrives after a non-preferred feed was already opened, the backend automatically disconnects the old feed and switches to the preferred one.

**GDMP binaries:** Not from the v0.6 release (built for godot-cpp 4.4). Sourced from [GDMP-demo](https://github.com/j20001970/GDMP-demo) master, which CI-builds from GDMP master against godot-cpp 4.6-stable. To refresh: `git clone --depth 1 https://github.com/j20001970/GDMP-demo.git` and copy `project/addons/GDMP/` and `project/addons/CameraServerExtension/`.

## Conventions

- Godot 4.6, GDScript for the addon and game code.
- GL Compatibility renderer (widest platform support).
- GDMP native libs are **gitignored** (`addons/GDMP/libs/`, `addons/CameraServerExtension/`). Cloned from GDMP-demo for setup.
- MediaPipe models auto-download from Google Cloud Storage on first run, cached in `user://`.
- Normalize all backend output into shared types; keep backend specifics out of gameplay code.
- Every gesture uses debounce/hysteresis/state machine — no one-frame firing.
- Calibration + debug overlay are first-class, not afterthoughts.

## Environment

- Windows 11, PowerShell 5.1. No `&&` chaining.
- Godot 4.6.2 at `C:\Users\naman\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe`
- GPU: NVIDIA GeForce RTX 3070 Ti Laptop
- Webcams: HD Camera (built-in), NexiGo N660 FHD (external, preferred)
- This repo lives under the workspace root; see `../AGENTS.md` for the agent stack.
