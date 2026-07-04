# Godot Camera Intelligence Kit — Initial Prompt (North Star)

> This is the original, verbatim project brief. It is the permanent source of truth.
> Come back here whenever scope drifts. Do not edit except to append clarifications
> in a dated "Addenda" section at the bottom.

---

You are my coding agent helping me build an open-source project tentatively called:

# Godot Camera Intelligence Kit

Positioning:

"Kinect-style camera controls for Godot, powered by modern on-device AI, running on desktop, web, and mobile."

The goal is not to build yet another generic model runner. The goal is to bring modern edge-AI perception into the Godot/game-dev ecosystem in a way that game developers can actually use.

Game developers should not need to understand tensors, ONNX graphs, ExecuTorch lowering, QNN, MediaPipe internals, or camera frame processing. They should get clean gameplay-friendly signals such as:

* hand position
* pinch started
* pinch held
* pinch released
* swipe left/right
* open palm
* fist
* point
* body lean left/right
* jump/squat
* face expression hooks
* object detected
* prop/card detected

The core idea:

Camera frame
→ perception backend
→ landmarks / boxes / logits
→ smoothing/calibration/state machine
→ Godot signals/events
→ gameplay

The important product wedge is the "perception → intent → gameplay events" layer.

Do not overfocus on raw inference at first. The initial MVP should prove that camera-based AI input can be exposed to Godot cleanly and reliably.

## Background / context

I have been researching:

* MediaPipe hand/body/face tracking demos in browser
* ONNX Runtime
* WebGPU
* Qualcomm QNN
* ExecuTorch
* React Native ExecuTorch
* YOLO11 / YOLOv11
* MobileNetV2
* edge AI on laptop and mobile
* Godot plugin architecture
* future possibility of Unity support

I want to avoid redoing what is already done. Prior art exists for running ONNX models in Godot and for some MediaPipe/Godot integrations, but I have not seen a polished open-source project focused on "camera intelligence as game input" across desktop/web/mobile.

This project should treat inference backends as implementation details. The stable product surface should be a Godot-facing API.

## Conceptual distinction between ONNX Runtime, ExecuTorch, and MediaPipe

ONNX Runtime:

* General-purpose runtime for ONNX models.
* Takes a `.onnx` model and runs it using Execution Providers.
* Relevant execution providers include CPU, WebGPU, CoreML, TensorRT, QNN, etc.
* Good for custom models, browser/desktop/mobile interoperability, YOLO-style object detection, and WebGPU experiments.
* Potential pipeline:

PyTorch model
→ export to ONNX
→ ONNX Runtime
→ CPU / WebGPU / CoreML / QNN / etc.

ExecuTorch:

* PyTorch-native edge/mobile runtime.
* Lets us stay closer to the PyTorch ecosystem.
* Relevant for Android/iOS/mobile/edge, especially if we want a PyTorch-first deployment story.
* Can delegate to XNNPACK, CoreML, QNN, Vulkan, etc.
* Potential pipeline:

PyTorch model
→ export/lower through ExecuTorch
→ ExecuTorch runtime
→ XNNPACK / CoreML / QNN / Vulkan / etc.

MediaPipe:

* More opinionated and task/pipeline-oriented.
* Not primarily "run arbitrary models," but provides ready-made perception tasks.
* Useful tasks include Hands, Pose, Face, Object Detection, Image Segmentation, etc.
* For our first MVP, MediaPipe Hands/Pose is probably the fastest route to a compelling demo.
* Potential pipeline:

Camera frame
→ MediaPipe Hand/Pose/Face Landmarker
→ landmarks
→ smoothing/gesture layer
→ Godot signals

Important framing:

* ONNX Runtime and ExecuTorch can be seen as partially competing runtimes for model deployment.
* MediaPipe is more of a prebuilt perception pipeline/task layer.
* In our architecture, all three can be treated as possible backends.
* The user-facing Godot API should not expose backend details unnecessarily.

## Project thesis

The open-source value is not:

"Here is a way to run a model in Godot."

The open-source value is:

"Here is a game-ready camera intelligence layer for Godot."

The plugin should turn noisy camera ML outputs into stable, calibrated, debounced, gameplay-friendly events.

The main differentiator should be:

* backend abstraction
* calibration UX
* smoothing and filtering
* gesture state machines
* Godot signals
* example scenes/games
* easy onboarding for game developers
* web/desktop/mobile path
* local/on-device AI focus

## Target developer experience

A Godot developer should be able to write:

```gdscript
func _ready():
    AIInput.hand_gesture.connect(_on_hand_gesture)
    AIInput.body_event.connect(_on_body_event)
    AIInput.object_detected.connect(_on_object_detected)

func _on_hand_gesture(event):
    match event.name:
        "pinch_started":
            $Player.grab()
        "pinch_released":
            $Player.release()
        "swipe_left":
            $Player.dodge_left()
        "swipe_right":
            $Player.dodge_right()
        "open_palm":
            $Player.shield()

func _on_body_event(event):
    if event.name == "lean_left":
        $Player.steer_left()
    elif event.name == "lean_right":
        $Player.steer_right()
    elif event.name == "jump":
        $Player.jump()
```

Or:

```gdscript
func _process(delta):
    var right_hand = AIInput.get_hand("right")

    if right_hand.is_tracked:
        $Cursor.position = right_hand.screen_position

    if right_hand.is_pinch_started():
        cast_spell()
```

The Godot-facing API should be simple, stable, and game-like.

## Proposed architecture

High-level:

Godot Addon
├── AIInput singleton / autoload
├── Backend interface
├── MediaPipe backend
├── ONNX Runtime backend
├── future ExecuTorch backend
├── Gesture recognizers
├── Smoothing/filtering
├── Calibration manager
├── Debug overlay
├── Example scenes
└── Documentation

Core pipeline:

CameraSource
→ PerceptionBackend
→ RawFrameResult
→ LandmarkNormalizer
→ Smoother
→ GestureRecognizer
→ StateMachine
→ GodotSignalEmitter

## Suggested module responsibilities

### 1. CameraSource

Responsible for capturing frames or receiving frames.

For MVP, we can simplify:

* browser/web version can use JavaScript camera APIs
* native desktop/mobile can be later
* a WebSocket/UDP bridge can be used for early prototyping if Godot camera integration is hard

Possible camera source types:

* BrowserCameraSource
* GodotCameraSource
* AndroidCameraXSource
* IOSAVFoundationSource
* ExternalSocketCameraSource
* RecordedVideoSource for testing

### 2. PerceptionBackend

Abstract interface for all inference backends.

Possible methods:

```text
initialize(config)
process_frame(frame)
get_capabilities()
shutdown()
```

Backend result should be normalized into a common shape.

Capabilities might include:

```text
hands
pose
face
objects
segmentation
custom_classifier
```

Backends:

* MediaPipeBackend
* ONNXRuntimeBackend
* ExecuTorchBackend later
* MockBackend for tests
* RecordedResultsBackend for deterministic testing

### 3. Raw result types

Define common data structures independent of backend.

HandTrackingResult:

```text
hands: Array[Hand]
timestamp
frame_size
backend_name
latency_ms
```

Hand:

```text
id
handedness: left/right/unknown
confidence
landmarks_2d: 21 normalized points
landmarks_3d: optional
palm_center
wrist
index_tip
thumb_tip
middle_tip
is_tracked
```

PoseTrackingResult:

```text
pose_landmarks_2d
pose_landmarks_3d optional
confidence
timestamp
```

ObjectDetectionResult:

```text
detections: Array[Detection]
timestamp
```

Detection:

```text
label
confidence
bbox_normalized
class_id
tracking_id optional
```

### 4. Landmark normalization

Normalize all coordinates to Godot-friendly values.

Coordinate spaces:

* image space: pixel coordinates
* normalized screen space: 0..1
* centered normalized space: -1..1
* optional world-ish coordinates if backend provides 3D

Need to be careful with:

* mirrored selfie camera
* landscape vs portrait
* aspect ratio correction
* Godot viewport scaling
* camera rotation
* mobile orientation

### 5. Smoothing / filtering

Raw landmarks are noisy. We need filtering before gameplay events.

Implement options:

* exponential moving average
* one-euro filter if feasible
* dead zones
* hysteresis
* velocity smoothing
* confidence thresholding
* lost tracking timeout
* re-acquisition delay

Goal: reduce jitter while keeping latency low.

### 6. Gesture recognizers

The recognizers should convert landmarks and motion over time into semantic events.

Initial gestures:

Hands:

* pinch_started
* pinch_held
* pinch_released
* open_palm
* fist
* point
* swipe_left
* swipe_right
* swipe_up
* swipe_down
* hand_cursor_move

Body:

* lean_left
* lean_right
* jump
* squat
* arms_up

Objects:

* object_detected
* object_lost
* object_entered_region
* object_exited_region

Each gesture should have:

* confidence
* start/held/released state when applicable
* cooldown/debounce
* timestamp
* optional position
* optional velocity
* source backend
* hand/body/object id

### 7. Gesture state machine

Do not fire noisy one-frame gestures.

For example, pinch should be:

* pinch_started once
* pinch_held while active
* pinch_released once

Do not emit pinch_started every frame.

Pinch logic:

* compute distance between thumb tip and index tip
* normalize by hand size, such as wrist-to-middle-mcp distance
* pinch activates below threshold for N consecutive frames
* pinch releases above threshold + hysteresis for N consecutive frames

Swipe logic:

* track wrist or palm center movement over recent frames
* require velocity threshold
* require minimum distance
* require cooldown
* optionally ignore if hand not confidently tracked

### 8. Calibration

Calibration is critical.

Need calibration manager for:

* neutral hand position
* body center
* camera mirror
* user distance
* gesture sensitivity
* viewport mapping
* dominant hand
* room lighting warning maybe later

Example calibration flow:

1. Ask user to stand/sit centered.
2. Capture neutral body center.
3. Ask user to show open palm.
4. Ask user to pinch.
5. Store thresholds per user/session.
6. Show debug overlay.

MVP can have manual sliders:

* pinch threshold
* smoothing strength
* min confidence
* swipe sensitivity
* mirror camera toggle
* cursor sensitivity

### 9. Debug overlay

This is very important for developers.

Debug overlay should show:

* camera preview
* landmarks
* bounding boxes
* gesture state
* FPS
* inference latency
* backend name
* confidence values
* current calibration values
* event stream log

This will help game developers tune gestures.

### 10. Godot API

Expose a simple singleton/autoload:

AIInput

Signals:

```gdscript
signal hand_tracked(hand)
signal hand_lost(hand_id)
signal hand_gesture(event)
signal body_tracked(body)
signal body_event(event)
signal object_detected(event)
signal object_lost(event)
signal backend_status_changed(status)
signal calibration_changed(profile)
```

Methods:

```gdscript
AIInput.start()
AIInput.stop()
AIInput.set_backend(name)
AIInput.get_backend()
AIInput.get_capabilities()
AIInput.get_hand("left")
AIInput.get_hand("right")
AIInput.get_body()
AIInput.get_objects()
AIInput.set_smoothing(value)
AIInput.set_mirror_camera(enabled)
AIInput.start_calibration()
AIInput.save_calibration(profile_name)
AIInput.load_calibration(profile_name)
AIInput.enable_debug_overlay(enabled)
```

Data objects:

HandState:

```text
id
handedness
is_tracked
confidence
screen_position
palm_position
landmarks
velocity
gestures
```

GestureEvent:

```text
name
phase: started/held/released/instant
confidence
handedness optional
position optional
velocity optional
timestamp
source
```

BodyEvent:

```text
name
phase
confidence
position optional
timestamp
```

ObjectEvent:

```text
name
label
confidence
bbox
position
timestamp
```

## MVP strategy

Do not start by implementing every backend.

The first goal is a compelling vertical slice.

### MVP 0: Research and repo audit

Before coding, search GitHub for:

* Godot ONNX
* Godot MediaPipe
* Godot hand tracking
* Godot pose tracking
* Godot camera ML
* Godot GDExtension ONNX Runtime
* Godot WebRTC camera input
* Godot browser JavaScript bridge
* ExecuTorch Godot
* ONNX Runtime Android Godot
* MediaPipe Godot Android

Summarize:

* what exists
* license
* supported platforms
* whether maintained
* whether Godot 3 or Godot 4
* whether GDExtension or GDNative
* whether it exposes raw tensors only or game-friendly input
* what we can reuse
* what we should not redo

Known prior art to look at:

* Godot-ONNX-AI-Models-Loaders
* godot_onnx_extension
* GDMP, a Godot MediaPipe plugin
* Godot XR Handtracking Toolkit
* Godot RL Agents, though this is a different direction

The likely project gap:

A polished game-input abstraction layer on top of perception backends.

### MVP 1: Browser/web proof of concept

Fastest demo path:

Browser camera
→ MediaPipe Hands in JavaScript
→ normalize landmarks
→ detect pinch/swipe/open palm
→ send events to Godot web export or a small Godot scene

Potentially simpler first version:

Browser camera + JS
→ WebSocket to local Godot desktop scene
→ Godot receives JSON events

Example JSON event:

```json
{
  "type": "hand_gesture",
  "name": "pinch_started",
  "phase": "started",
  "hand": "right",
  "confidence": 0.92,
  "position": [0.63, 0.42],
  "timestamp": 123456789
}
```

This avoids fighting native camera integration too early.

Build a Godot demo where:

* hand position controls cursor
* pinch grabs an object
* swipe throws/dodges
* open palm activates shield

This validates the gameplay layer.

### MVP 2: Godot addon shape

Create a Godot 4 addon with:

* AIInput autoload
* event classes/resources
* WebSocket event receiver backend
* mock backend
* smoothing
* gesture state machine
* debug overlay
* example scene

This does not need native ML yet. It proves the Godot API.

### MVP 3: Direct MediaPipe backend

Add direct MediaPipe backend.

Possible implementation paths:

* Godot web export JavaScript bridge to MediaPipe Tasks Vision
* Native desktop bridge later
* Android MediaPipe Tasks later

For first direct integration, web may be easiest.

### MVP 4: ONNX Runtime backend

Add ONNX Runtime backend for custom models.

Use cases:

* YOLO object detection
* custom gesture classifier
* prop/card detector
* segmentation
* simple MobileNetV2 classifier

Start with desktop or web depending on ease.

ONNX Runtime Web + WebGPU can be used for browser backend.

Native ONNX Runtime can be considered later for desktop/mobile.

### MVP 5: ExecuTorch backend

Do this later, not first.

Use cases:

* PyTorch-native mobile deployment
* Android/iOS edge runtime
* QNN delegation on Snapdragon
* CoreML delegation on Apple
* integration with React Native ExecuTorch learnings

This backend should conform to the same PerceptionBackend interface.

## Backend abstraction goal

The game developer should be able to switch:

```gdscript
AIInput.set_backend("mediapipe")
```

or:

```gdscript
AIInput.set_backend("onnxruntime")
```

or eventually:

```gdscript
AIInput.set_backend("executorch")
```

without changing gameplay code.

Backend configuration might look like:

```json
{
  "backend": "mediapipe",
  "tasks": ["hands", "pose"],
  "camera": {
    "mirror": true,
    "width": 640,
    "height": 480,
    "target_fps": 30
  },
  "gestures": {
    "pinch": {
      "enabled": true,
      "threshold": 0.28,
      "hysteresis": 0.06
    },
    "swipe": {
      "enabled": true,
      "min_velocity": 0.8,
      "cooldown_ms": 400
    }
  },
  "smoothing": {
    "enabled": true,
    "type": "ema",
    "alpha": 0.4
  }
}
```

## Example demo scenes

Build small examples that communicate the value quickly.

### Demo 1: Hand Cursor Playground

* User moves hand.
* Cursor follows palm/index finger.
* Pinch grabs blocks.
* Release drops blocks.

### Demo 2: Wizard Gestures

* Open palm = shield
* Pinch = charge spell
* Swipe = cast projectile
* Two-hand distance = scale spell size later

### Demo 3: Body Steering

* Lean left/right controls character or car.
* Jump gesture makes character jump.
* Squat crouches.

### Demo 4: Prop Detection

* YOLO/ONNX detects printed cards or objects.
* Detected object spawns corresponding in-game item.
* Good future demo for physical-world party games.

### Demo 5: Debug/Tuning Scene

* Shows camera preview.
* Shows landmarks.
* Shows active gestures.
* Shows latency/FPS.
* Sliders tune thresholds.

## Repository structure suggestion

```text
godot-camera-intelligence-kit/
  README.md
  docs/
    architecture.md
    backends.md
    godot-api.md
    calibration.md
    gestures.md
    roadmap.md
    prior-art.md
  addon/
    camera_intelligence/
      plugin.cfg
      AIInput.gd
      backends/
        BackendBase.gd
        MockBackend.gd
        WebSocketBackend.gd
        MediaPipeWebBackend.gd
        ONNXRuntimeBackend.gd
      gestures/
        GestureRecognizer.gd
        PinchRecognizer.gd
        SwipeRecognizer.gd
        OpenPalmRecognizer.gd
        BodyLeanRecognizer.gd
      smoothing/
        EmaFilter.gd
        OneEuroFilter.gd
      calibration/
        CalibrationManager.gd
      debug/
        DebugOverlay.gd
      types/
        HandState.gd
        GestureEvent.gd
        BodyState.gd
        ObjectDetection.gd
  examples/
    hand_cursor_playground/
    wizard_gestures/
    body_steering/
    prop_detection/
  bridge/
    browser_mediapipe/
      package.json
      src/
        index.ts
        camera.ts
        mediapipe_hands.ts
        gesture_recognizer.ts
        websocket_sender.ts
  native/
    gdextension/
      placeholder/
  research/
    prior_art_notes.md
```

## Immediate next coding task

Start with the Godot addon + external browser bridge MVP.

Why this path:

* avoids native ML complexity initially
* lets us validate the API and gameplay layer
* MediaPipe in browser is easy to demo
* Godot receives clean JSON events
* architecture remains compatible with native backends later

Build:

1. Godot 4 project/addon.
2. AIInput singleton.
3. WebSocketBackend that listens for JSON events.
4. GestureEvent type.
5. HandState type.
6. Example scene where:

   * hand position controls cursor
   * pinch grabs/releases object
   * swipe moves/throws object
7. Browser bridge using MediaPipe Hands:

   * captures webcam
   * runs hand tracking
   * computes pinch/swipe/open palm
   * sends JSON events over WebSocket
8. Debug overlay in Godot:

   * connection status
   * latest event
   * active gesture
   * hand position
   * FPS/event rate

## Important implementation principles

* Keep backend-specific logic out of gameplay code.
* Treat MediaPipe, ONNX Runtime, and ExecuTorch as swappable backends.
* Normalize all outputs into shared types.
* Prefer Godot signals and resources over raw dictionaries where possible.
* Use JSON over WebSocket for the first bridge because it is easy to debug.
* Avoid premature native GDExtension complexity.
* Build one delightful demo before adding many models.
* Make calibration and debugging first-class, not an afterthought.
* Design for noisy real-world conditions.
* Use debounce/hysteresis/state machines for all gestures.
* Track latency and event rate from the beginning.

## Questions to answer during implementation

1. What is the cleanest Godot 4 addon structure for an AIInput autoload?
2. Should the WebSocket server live inside Godot, or should Godot connect as a client to the browser bridge?
3. What Godot WebSocket APIs are available and stable for this use?
4. What event schema should be frozen for MVP?
5. How do we represent hand landmarks in GDScript efficiently?
6. How much smoothing should happen in the browser bridge versus in Godot?
7. Should gesture recognition happen in the bridge, in Godot, or both?
8. Can we initially send both raw landmarks and derived gestures?
9. What is the minimal demo that feels magical?
10. What prior art can we reuse without fighting licenses or maintenance issues?

## Preferred MVP event schema

Send both raw hand state and semantic gestures.

Hand state event:

```json
{
  "type": "hand_state",
  "timestamp": 123456789,
  "backend": "mediapipe_web",
  "frame": {
    "width": 640,
    "height": 480
  },
  "hands": [
    {
      "id": "right_0",
      "handedness": "right",
      "confidence": 0.94,
      "palm_position": [0.62, 0.41],
      "index_tip": [0.66, 0.36],
      "thumb_tip": [0.61, 0.37],
      "landmarks": [
        [0.50, 0.80, 0.0],
        [0.51, 0.73, -0.02]
      ]
    }
  ]
}
```

Gesture event:

```json
{
  "type": "gesture",
  "timestamp": 123456789,
  "backend": "mediapipe_web",
  "name": "pinch_started",
  "phase": "started",
  "handedness": "right",
  "confidence": 0.91,
  "position": [0.63, 0.39],
  "metadata": {
    "pinch_distance": 0.18
  }
}
```

Object detection event, future:

```json
{
  "type": "object_detection",
  "timestamp": 123456789,
  "backend": "onnxruntime_web",
  "detections": [
    {
      "label": "card_fire",
      "confidence": 0.88,
      "bbox": [0.2, 0.3, 0.1, 0.15]
    }
  ]
}
```

## Long-term vision

This could become a general "camera intelligence" layer for game engines.

Godot first.

Unity later.

Possible future features:

* Unity package with same event schema
* browser package independent of Godot
* native Android backend with CameraX
* iOS backend with AVFoundation
* ONNX Runtime QNN backend for Snapdragon
* ExecuTorch QNN backend for PyTorch-native mobile
* CoreML backend for iOS
* YOLO prop/card detector templates
* custom gesture training UI
* local calibration profiles
* multiplayer camera tracking
* phone-as-camera input device
* networked camera input for couch co-op games
* visual scripting nodes for non-programmers
* Godot Asset Library package

## What not to do first

Do not start by trying to support every model/runtime.

Do not start with QNN.

Do not start with ExecuTorch native mobile integration.

Do not start with a generic "run any model in Godot" plugin.

Do not expose raw tensors as the primary API.

Do not make game developers write ML post-processing.

Do not ignore smoothing/calibration.

Do not build without example games.

## First deliverable

Create a repo skeleton and MVP plan.

Then implement the smallest vertical slice:

Browser MediaPipe Hands
→ WebSocket JSON events
→ Godot AIInput addon
→ hand cursor demo with pinch grab/release

The resulting demo should make the project positioning obvious:

"Kinect-style camera controls for Godot, powered by modern on-device AI."

---

## Addenda

_(Append dated clarifications below; never rewrite the brief above.)_
