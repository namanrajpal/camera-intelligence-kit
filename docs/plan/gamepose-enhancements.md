# GamePose: Specializing YOLO26-Pose for Room-Scale Motion Games

**Date:** 2026-07-04
**Status:** Active — experiments 1–2 runnable immediately, 3–4 need COCO-pose
**Baseline:** pretrained `yolo26n-pose` (benchmark winner: P95 21.6 ms, 0% slash dropout — [results](../research/benchmark-results-2026-07.md))
**Goal:** Genuine advancements over the stock model for our use case (whole-hand pointer, 1–3 m, fast motion, mobile targets) — each measured on the recorded corpus.

---

## Why enhance at all?

The stock model wins the benchmark on a laptop GPU. But:
- **Mobile budgets are 5–10× tighter.** 21.6 ms P95 on an RTX 3070 Ti becomes 60–150 ms on a phone CPU/NPU. We need the smallest model/input that still tracks wrists reliably.
- **Perceived latency > inference latency.** Even a 20 ms model feels laggy when camera capture + display add 50+ ms. Prediction can cut *effective* latency below inference latency.
- **COCO optimizes the wrong objective for us.** All 17 keypoints weighted equally; we care about wrists ≫ elbows/shoulders ≫ everything else. Faces and ankles are wasted capacity.
- **COCO images are mostly sharp.** Our regime is fast, motion-blurred limbs. Train for the domain.

## Experiment 1: Resolution operating-point study — **DONE, major win**

Ran `yolo26n-pose` on the corpus at `imgsz` ∈ {640, 480, 384, 320}, GPU and CPU.

**CPU results (mobile-relevant), slash clips:**

| imgsz | P50 ms | P95 ms | slash drop | wrist dev vs 640 (median px) |
|---|---|---|---|---|
| 640 | ~57 | ~64 | 0–0.2% | ref |
| 480 | ~44 | ~52 | 0–0.5% | 4–7 px |
| 384 | ~34 | ~41 | 0–0.7% | 6–13 px |
| **320** | **~26** | **~31** | **0–0.2%** | **8–14 px** |

**Findings:**
- **imgsz=320 is the mobile operating point: 2.2× faster than 640 on CPU, ~0% dropout, ≤14 px median wrist deviation** — negligible vs the 80 px slash radius. Person detection at room scale is robust down to 320 (a person is still ~150 px tall in a 320 input; this is exactly why hand-scale detection failed).
- On the discrete GPU, latency is flat across sizes (~11 ms p50) — the nano model is overhead-bound there; resolution only pays off on CPU/NPU. Operating-point choices MUST be made on target-class hardware.
- Ship: `imgsz=320` for mobile exports, `640` for desktop GPU (no cost either way).

Tool: `tools/exp1_resolution_study.py` (`--device cpu`). Raw: `benchmark_results/exp1_resolution_{gpu,cpu}/`.

## Experiment 2: Velocity-predictive wrist tracking — **DONE, honest negative-ish result**

Measured offline on the yolo26_body corpus JSON (slash clips, horizons k=1–3 frames):

| Predictor | Mean error (all slash clips/horizons) | vs hold-last |
|---|---|---|
| P0 hold-last (today's behavior) | 24.2 px | — |
| P1 constant velocity | 25.2 px | **−4.3% (worse)** |
| P2 damped velocity (EMA α=0.5) | 22.9 px | **+5.4% (better)** |

**Finding:** erratic slash motion defeats constant-velocity extrapolation (direction reversals cause overshoot). Damped velocity yields only a modest ~5% error reduction. **Prediction is not the free win it appears to be** — worth a small `AIInput` option (P2), but not a headline feature. This is a useful negative result for the writeup.

Tool: `tools/exp2_predictive_tracking.py`. Raw: `benchmark_results/exp2_prediction/`.

## Experiment 3: Wrist-weighted fine-tune *(needs COCO-pose download)*

Fine-tune `yolo26n-pose` on COCO-pose with per-keypoint loss weights biased to the game skeleton: wrists 3.0, elbows 1.5, shoulders 1.5, others 0.5 (Ultralytics `kpt` weighting / custom loss hook). Short schedule (10–20 epochs, low LR) from pretrained weights.

**Measure:** wrist-only OKS on COCO val + slash dropout / wrist deviation on our corpus. Ship only if corpus metrics improve.

## Experiment 4: Motion-blur augmentation *(with #3)*

Add synthetic directional motion blur (random kernel 5–25 px, random angle, applied to limb regions or whole image p=0.3) to the fine-tune pipeline. Hypothesis: recovers wrist accuracy on blurred frames — measured on slash clips at 3 m where blur is worst relative to hand size.

## Sequencing

1. Exp 1 + 2 now (no training, ~30 min compute total)
2. Exp 3 + 4 as one fine-tune run once COCO-pose is downloaded (~20 GB, overnight)
3. Mobile round: export the winning configuration (size × weights) to LiteRT/CoreML, rerun corpus on-device

## Honest framing

The earlier hand-keypoint training is reported as a **controlled ablation** (hand-specific vs person-level paradigm at room scale), not a product step. The contribution narrative is: *benchmark → paradigm selection → task-specialized enhancements, each with corpus-measured deltas.*
