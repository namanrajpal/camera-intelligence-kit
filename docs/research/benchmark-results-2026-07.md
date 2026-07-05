# Benchmark Results: Camera Input for Motion Games (July 2026)

**Date:** 2026-07-04
**Winner:** `yolo26_body` — pretrained YOLO26n-pose (COCO body keypoints), wrists as hand positions
**Artifacts:** [notebook](../../notebooks/hand_tracking_benchmark.ipynb) (executed, outputs baked in) · corpus + raw JSON + overlay videos in local `corpus/` and `benchmark_results/` (published with blog release)
**Methodology:** [gameplay-requirements.md](./gameplay-requirements.md) · pre-registered hypotheses in the notebook header

---

## Setup

- **Corpus:** 10 recorded clips (idle/slash × 1/2/3 m, two-person idle/slash/cross, walk-on), 1280×720 @30 fps, ~5,500 frames. Every model evaluated on identical frames.
- **Hardware:** RTX 3070 Ti Laptop GPU / i9-12900H. YOLO models on CUDA; MediaPipe Tasks (VIDEO mode — same API as our Godot GDMP backend) and RTMPose ONNX on CPU.
- **Common evaluation point:** the wrist (every model reports one).

## Headline Table

| Model | P50 ms | P95 ms | Slash drop @2m | Slash drop @3m | 2-player slash drop | Track churn | Jitter px |
|---|---|---|---|---|---|---|---|
| **yolo26_body** | **11.9** | **21.6** | **0.0%** | **0.0%** | **0.0%** | 65 | 48.4 |
| yolo26_hand (ours) | 12.1 | 21.5 | 98.7% | 100% | 100% | 13* | — |
| mediapipe_hands | 29.1 | 43.4 | 69.7% | 78.5% | 92.8% | 252 | — |
| rtmpose_body | 35.8 | 51.6 | 0.0% | 0.0% | 0.0% | 65 | 44.5 |

\* churn meaningless when almost nothing is detected.

## Gates (G1 P95 ≤ 33 ms · G2 slash drop ≤ 5% @2m · G3 two players @2m)

| Model | G1 | G2 | G3 | Verdict |
|---|---|---|---|---|
| **yolo26_body** | PASS | PASS | PASS | **WINNER** |
| yolo26_hand | pass | FAIL | FAIL | out |
| mediapipe_hands | FAIL | FAIL | FAIL | out |
| rtmpose_body | FAIL | PASS | PASS | out (latency only) |

## Dropout by clip (% of frames with fewer detections than protocol guarantees)

| Clip | yolo26_body | yolo26_hand | mediapipe | rtmpose_body |
|---|---|---|---|---|
| idle_1m | 0.2 | 100.0 | 9.7 | 0.2 |
| idle_2m | 0.0 | 100.0 | 100.0 | 0.0 |
| idle_3m | 0.0 | 100.0 | 4.7 | 0.0 |
| slash_1m | 0.2 | 96.5 | 42.9 | 0.2 |
| slash_2m | 0.0 | 98.7 | 69.7 | 0.0 |
| slash_3m | 0.0 | 100.0 | 78.5 | 0.0 |
| two_idle_2m | 0.0 | 100.0 | 3.8 | 0.0 |
| two_slash_2m | 0.0 | 100.0 | 92.8 | 0.0 |
| two_cross_2m | 3.4 | 100.0 | 98.2 | 3.4 |

## Hypotheses — outcomes

- **H1 (body pose beats hand detectors under fast motion): CONFIRMED, decisively.** Body: 0% slash dropout at every distance. Hand detectors: 43–100%.
- **H2 (detection-per-frame beats tracking-based on identity):** supported — MediaPipe track churn 252 vs body models 65 on the crossing clip — but confounded by MediaPipe's dropout; treat as directional.
- **H3 (hand detectors degrade with distance): CONFIRMED, brutally.** Our hand model (mAP50 90.3% on its dataset!) detects **~0 hands even idle at 1 m** — its training data is close-up hands; at room scale a hand is ~30–60 px and it simply never fires. MediaPipe: usable at 1 m, halves at 2 m, worse at 3 m.
- **H4 (21-keypoint precision unnecessary): CONFIRMED by outcome** — the winner has no finger keypoints at all, mirroring Nex's production choice of body tracking.

## Key findings beyond the hypotheses

1. **The hand-model ablation quantifies *why* body pose is the right paradigm.** A hand-specialized detector (90.3% mAP50 on its close-range dataset) produces ~0 detections at room scale — a hand at 1–3 m is a 30–60 px, often motion-blurred patch. This is a controlled demonstration that the *paradigm* (person-level detection with wrist keypoints), not model quality, is what makes room-scale tracking work. It also validates the metric gap: static dataset mAP cannot predict deployment behavior; temporal in-situ benchmarking can.
2. **MediaPipe's numbers explain the unplayable game.** P95 43 ms (> 33 ms budget) + 70–93% slash dropout at 2 m is exactly the laggy, choppy feel we experienced in Fruit Chop.
3. **RTMPose ties on reliability, loses only on latency** — our adapter runs YOLO person detection + sequential CPU-ONNX crops. With a GPU execution provider or batched crops it could compete. Optimization noted as future work.
4. **Body models slightly over-detect** (mean 1.3–1.9 persons when 1 expected on some clips — background false positives/reflections). Doesn't affect dropout, but the game layer should keep the N largest person boxes and require calibration lock-in. Handled by the planned calibration screen.
5. **Jitter ~45–48 px raw** at 720p for body wrists at rest — noticeable, but the 1-Euro filter in `AIInput` exists precisely for this.

## Beyond model selection: the GamePose enhancement track

Selecting a pretrained model is table stakes. The actual contribution is **specializing YOLO26-pose for room-scale motion games** — see [gamepose-enhancements.md](../plan/gamepose-enhancements.md): resolution operating-point study, velocity-predictive wrist tracking (effective-latency reduction), wrist-weighted fine-tuning, and motion-blur augmentation, each measured on this corpus.

## Decision

**Adopt YOLO26n-pose (body) as the primary perception backend.** Wrists (keypoints 9, 10) become hand positions; person boxes give player identity; shoulders enable arm-direction if needed.

### Engineering consequences

1. Build the ONNX Runtime path for `yolo26n-pose` body in Godot (GDExtension) — replaces GDMP MediaPipe as the game backend.
2. `AIInput` gains a person-level model: `player_tracked(player)`, wrists as `hand` positions — the game-facing signal API barely changes.
3. Calibration screen filters ghost detections (top-N person boxes + lock-in) — already on the roadmap.
4. Our trained hand model remains useful for close-range (< 1 m) use cases — tabletop/kiosk interactions, not room-scale games.
5. Mobile round 2: export `yolo26n-pose` to LiteRT/ExecuTorch/CoreML and rerun this same corpus on-device.

## Limitations

Model-only latency (not photon-to-photon); one hardware target; two subjects, one room, one lighting condition; track churn is a proxy metric — see overlay videos (`benchmark_results/overlay_*.mp4`) for the qualitative identity check; body-model over-detection not penalized by the dropout metric.
