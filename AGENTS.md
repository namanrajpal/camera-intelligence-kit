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

**MVP 1 — hand tracking foundation built.** GDMP (MediaPipe GDExtension) is integrated and working on desktop with multi-hand tracking. Camera feeds via CameraServerExtension. Next: build the AIInput abstraction layer, then Fruit Chop game, then Android export.

**Demo target:** AI Tinkerers Seattle, July 13 2026.
**First game:** Fruit Chop (two-player hand-slash fruit ninja).

## Architecture (as built)

```
Godot 4.6.2 Project
├── addons/
│   ├── GDMP/                        # MediaPipe GDExtension (all platforms)
│   │   └── libs/                    # Native binaries (gitignored, ~400MB)
│   └── CameraServerExtension/       # Native webcam drivers for Windows/iOS
├── addon/
│   └── camera_intelligence/         # AIInput singleton (TODO)
├── examples/
│   └── hand_tracking_test/          # Working: camera → MediaPipe → landmarks
└── project.godot
```

**Camera pipeline:**
```
Webcam → CameraServerExtension → CameraTexture → SubViewport → Image
→ MediaPipeImage → MediaPipeHandLandmarker (C++ native, async)
→ result_callback → 21 landmarks per hand, up to 4 hands
```

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
