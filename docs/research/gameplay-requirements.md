# Gameplay Requirements: What Camera Tracking Actually Needs

**Date:** 2026-07-04
**Status:** Foundational spec — drives model selection and benchmark design
**Cross-references:** [Nex Playground Analysis](./nex-playground-analysis.md) · [SOTA Survey](./edge-hand-tracking-sota-2026.md) · [Ecosystem Scan R2](./ecosystem-scan-round2.md) · [Benchmark Notebook](../../notebooks/hand_tracking_benchmark.ipynb)

---

## The Core Insight: Hand as Pointer, Not Skeleton

For Nex Playground-style motion games, the hand is a **pointer/blob**, not an articulated skeleton. Think of the hand as a **stick**: bottom of palm to the topmost point (fingertips as a group). Players fist-up, point, wave, and slash with their **whole hand**. Nobody plays Fruit Ninja with individual finger movements.

We spent effort training a 21-keypoint hand model before internalizing this. The trained model is still useful (precision fallback), but it solves a harder problem than the games require.

## Physical Setup (the target scenario)

```
┌─────────────────────────────────┐
│  Phone propped on desk/table    │
│  (front camera facing players)  │
└─────────────────────────────────┘
              ▲
              │  1–3 meters
              ▼
     🧍 Player 1   🧍 Player 2
     (standing side by side,
      upper body visible,
      waving hands to play)
```

- Phone/webcam static, propped up (no one holds it)
- 1–2 players (up to 4 later), standing 1–3 m away
- Upper body visible — we can *ask* players to stand correctly (Active Arcade does: "Make sure it sees your upper body")
- Indoor lighting, living-room conditions
- Fast, erratic hand motion is the norm, not the exception

## What We NEED

| Requirement | Why | Acceptance target |
|---|---|---|
| **Whole-hand position** (one point per hand) | The cursor/blade position | Wrist or palm center, ±half-hand accuracy is fine |
| **Hand velocity + direction** | Slash detection, slash direction | Derived from position across frames |
| **Player identity** | Two-player scoring — P1's slash must not credit P2 | Stable across the whole session |
| **Fast-motion reliability** | Slashing IS the game; a dropped detection = a missed slash = game feels broken | Dropout ≤ 5% during aggressive slashing at 2 m |
| **Low latency** | Hand-eye feel | P95 inference ≤ 33 ms (30 fps frame budget, per [Ultralytics real-time guidance](https://www.ultralytics.com/glossary/real-time-inference#the-importance-of-low-latency)) |
| **Range 1–3 m** | Living-room variance; Nex recommends ~6 ft (1.8 m) | Full function at 2 m; graceful at 1 m and 3 m |
| **Low jitter at rest** | Hover-to-select menus | Cursor visually stable when hand is still |
| **Mobile deployment path** | The whole point: phones, no custom hardware | ONNX/TFLite/CoreML/ncnn export |

## What We DON'T Need

| Non-requirement | Why it doesn't matter |
|---|---|
| 21-point finger articulation | Nobody plays with individual fingers; the hand moves as a unit |
| Pinch distance (thumb–index) | Not a gameplay mechanic at 2 m — too small to detect reliably anyway |
| Finger curl / open-palm vs fist classification | Nice-to-have someday, not needed for slash/point/wave games |
| 3D depth per joint | Games are 2D screen-space interactions |
| Handedness (left vs right) | The game doesn't care which hand slashes |
| Sub-centimeter keypoint accuracy | Slash radius is ~80 px; half-a-hand error is invisible |

## Implication for Model Choice

**Body pose (17–18 keypoints per person) likely beats hand-specific models for this use case:**

1. **Wrist keypoints (COCO 9, 10) = hand position.** That's all the game needs.
2. **Person detection = free player identity.** Each detected person carries their own wrists — no hand-to-player assignment problem.
3. **Fast hands blur; torsos don't.** A slashing hand is a motion smear that hand detectors miss; the body it's attached to is nearly static. (Benchmark hypothesis H1.)
4. **Range: at 3 m a hand is ~30 px, a person is ~300 px.** Hand detectors degrade with distance much faster. (Hypothesis H3.)
5. **Production-validated:** Nex Playground tracks **18 body points**, not hand skeletons, for this exact game catalog — see [nex-playground-analysis.md](./nex-playground-analysis.md).

Optional enhancement: shoulder→wrist vector gives arm direction ("sword angle") for free.

## Calibration UX (adopted pattern)

Like Active Arcade: before gameplay, show camera preview with a stand-here zone. Detect shoulders + wrists visible → outline turns green → "Raise both hands to start." This turns the tracking constraint (upper body visible) into a game ritual instead of a failure mode.

## How This Drives the Benchmark

The benchmark ([notebook](../../notebooks/hand_tracking_benchmark.ipynb)) evaluates every model **at the wrist point only** (the common semantic point across MediaPipe, YOLO hand, YOLO body, RTMPose), using metrics ordered by the table above: slash dropout → latency P95 → identity stability → jitter → range.
