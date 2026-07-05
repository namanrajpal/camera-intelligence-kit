# Nex Playground / Active Arcade: Technical & Competitive Analysis

**Date:** 2026-07-04
**Sources:** [nexplayground.com/how-it-works](https://www.nexplayground.com/how-it-works) (their own published specs), App Store (Active Arcade), press coverage
**Cross-references:** [Gameplay Requirements](./gameplay-requirements.md) · [SOTA Survey](./edge-hand-tracking-sota-2026.md) · [ROADMAP](../../ROADMAP.md)

---

## Why This Matters

Nex is the commercial benchmark for exactly what we're building: camera-based motion games for families, no controllers, no wearables. Everything they've published about *how* it works is direct validation (or correction) of our technical approach.

## The Products

### 1. Nex Playground (hardware, $299 + Play Pass subscription)
A small cube with a built-in wide-angle camera. Connects to TV via HDMI. Android-based internally. Games downloaded to device, playable offline.

### 2. Active Arcade (iPhone app, free-ish, proprietary)
**The existence proof for our approach.** Same tracking tech on a plain iPhone: prop the phone up, stand ~2 m back, play on the phone screen (or cast). Its setup flow instructs: **"Make sure it sees your upper body."** No custom hardware needed — which is precisely our thesis for the Godot kit.

## Published Technical Specs (from their How It Works page)

| Claim | Detail | Implication for us |
|---|---|---|
| **"Tracks 18 points on your body"** | Body pose, NOT hand skeletons. 18 ≈ COCO-17 + 1 (likely neck/mid-hip) | **Their production choice is body pose.** Validates our pivot away from 21-point hand models |
| **"Automatically tracks the active player"** | Player identity/association built in | We need identity stability as a first-class metric |
| **"Up to 4 concurrent players"** | Multi-person from one camera | Matches our max target |
| **"Super low-latency, tracks high speed movements"** | Fast-motion reliability is their headline feature | This is the hard problem; our benchmark's slash-stress phase measures exactly this |
| **"Just 6 feet of space"** (~1.8 m) | Recommended play distance | Anchors our 1–3 m range requirement; 2 m is the canonical test distance |
| **Wide-angle camera** | Wider FOV fits 4 players at 2 m | Phone front cameras are narrower — 2 players is realistic for us at 2–3 m |
| **"Never store any video"** + magnetic privacy cover | All inference on-device | Same privacy story we get for free with on-device Godot inference |

Their tech is proprietary (they mention patents in passing); we build from open models and publish openly — no further analysis needed or wanted there.

## Their Game Catalog = Our Design Reference

Directly overlapping with our roadmap:

| Nex game | Our equivalent | Tracking needed |
|---|---|---|
| **Fruit Ninja** (licensed!) | Fruit Chop | Hand position + velocity |
| **Sword Slash Adventure** | (future) | Hand position + direction |
| **Whack-a-Mole** | Whack-a-Mole card (planned) | Hand position |
| NHL Puck Rush, Go Keeper | (future sports) | Hand/body position |
| Homerun Heroes | (future) | Arm swing = shoulder→wrist vector |
| Barbie Dance Party, Zumba | (future dance) | Full body pose |
| Starri, Party Fowl, Air Racer | (future) | Body lean / hand position |

Every single game is playable with **body keypoints + wrists as hands**. None require finger articulation. This is the strongest possible confirmation of [gameplay-requirements.md](./gameplay-requirements.md).

## Their Calibration UX (adopt this)

- Active Arcade: "Make sure it sees your upper body" with live preview
- Nex: "just a little elbow room required," auto-detects active player
- Pattern: **turn the tracking constraint into an onboarding ritual** — stand-here zone, green outline when detected, raise-hands-to-start gesture

## Our Differentiation

| | Nex | Us (Camera Intelligence Kit) |
|---|---|---|
| Hardware | $299 cube (or their own iPhone app) | Any phone/tablet/laptop with a camera |
| Content model | Closed catalog + Play Pass subscription | Open-source SDK — any Godot dev can build games |
| Tech | Proprietary | Open models (YOLO26/MediaPipe/RTMPose), published benchmark |
| Engine | Internal | Godot-native (`AIInput` signals) |
| The wedge | Consumer product | **Developer tool**: perception → intent → gameplay events layer |

We are not competing with Nex for living rooms; we're building the open toolkit that lets anyone make Nex-style games.

## Actionable Takeaways

1. **Body pose (wrists as hands) is the production-proven tracking approach** — benchmark it as the primary candidate.
2. **2 m is the canonical test distance** (their 6-ft guidance).
3. **Fast-motion reliability is the headline feature** to get right — it's what they advertise.
4. **Adopt the calibration ritual** (upper-body check + raise-hands-to-start) — planned in [ROADMAP](../../ROADMAP.md).
5. **Player identity stability** must be a first-class metric ("automatically tracks the active player").
