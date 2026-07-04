# Godot Camera Intelligence Kit

**Positioning:** "Kinect-style camera controls for Godot, powered by modern on-device AI, running on desktop, web, and mobile."

**Source of truth:** [`INITIAL_PROMPT.md`](./INITIAL_PROMPT.md) — the full brief. Read it before major work. Do not edit it except to append dated addenda.

## The wedge

Not a generic model runner. The value is the **perception → intent → gameplay events** layer: turn noisy camera ML output into stable, calibrated, debounced Godot signals game devs can use without knowing anything about tensors/ONNX/MediaPipe.

```
Camera frame → PerceptionBackend → landmarks/boxes → smoothing/calibration/state machine → Godot signals → gameplay
```

Backends (MediaPipe / ONNX Runtime / ExecuTorch) are swappable implementation details behind one stable `AIInput` Godot API.

## Current phase

**MVP 0 — prior-art research & repo audit.** Nothing built yet. Next: audit existing Godot ML integrations (see INITIAL_PROMPT.md "MVP 0"), then MVP 1 = browser MediaPipe Hands → WebSocket JSON → Godot `AIInput` addon → hand-cursor demo with pinch grab/release.

Do **not** jump to native GDExtension or multiple backends first. One delightful vertical slice.

## Conventions (evolving)

- Godot 4, GDScript for the addon. Browser bridge in TypeScript.
- Freeze the MVP event schema early (JSON over WebSocket) — see INITIAL_PROMPT.md "Preferred MVP event schema".
- Normalize all backend output into shared types; keep backend specifics out of gameplay code.
- Every gesture uses debounce/hysteresis/state machine — no one-frame firing.
- Calibration + debug overlay are first-class, not afterthoughts.

## Environment

Windows, PowerShell 5.1. No `&&` chaining. This repo lives under the workspace root; see `../AGENTS.md` for the agent stack (OpenChamber / Telegram / TUI all share one `opencode serve`).
