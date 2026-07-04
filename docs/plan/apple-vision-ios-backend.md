# Plan: Apple Vision Framework iOS Backend

**Date:** 2026-07-04
**Status:** Planned (requires Mac -- available)
**Priority:** Medium (post-demo, when iOS support is needed)
**Prerequisites:** Mac with Xcode, iOS device for testing, Apple Developer account
**Research context:** [ecosystem-scan-round2.md](../research/ecosystem-scan-round2.md) section 6

> **Major discovery:** Apple has an [official Godot plugin repo](https://github.com/apple/plugins-for-godot) (68 stars, MIT license) with GDExtension plugins for visionOS (RealityKit renderer) and spatial audio (PHASE). GodotRealityKit **already supports hand tracking** on visionOS/Vision Pro. Their Objective-C++ / Swift / GDExtension architecture is the exact template we'd follow for an iOS Vision framework hand tracking plugin.

---

## High-Level Goal

Build a Godot iOS plugin that uses Apple's Vision framework (`VNDetectHumanHandPoseRequest`) for hand tracking, bypassing MediaPipe/YOLO entirely on Apple devices. The Vision API runs on Apple Neural Engine (ANE) -- purpose-built silicon for ML inference -- which should be faster and more battery-efficient than any model we ship ourselves.

**Why this could be the best iOS path:**
- Zero model file to ship (Vision framework is built into iOS)
- Runs on dedicated neural engine hardware (not competing with GPU/CPU)
- Apple optimizes it per-chip generation (A14, A15, A16, M1, M2...)
- Same 21 keypoints as MediaPipe (wrist + 4 per finger)
- No ONNX/CoreML/TFLite conversion needed

**Why it's unproven:**
- Nobody has integrated Vision hand tracking with Godot (zero repos on GitHub)
- No public benchmarks for fast-motion multi-hand tracking at game speeds
- Requires native Objective-C/Swift iOS plugin development
- Only works on iOS 14+ / macOS 11+ (not Android, not Windows, not Web)

---

## Key Discovery: apple/plugins-for-godot

**[github.com/apple/plugins-for-godot](https://github.com/apple/plugins-for-godot)** (68 stars, MIT license)

Apple has an official repo with Godot plugins. Two plugins currently:

1. **GodotRealityKit** -- renders Godot games with RealityKit on visionOS (Apple Vision Pro). Written in Objective-C++, C++, Swift, GDScript. Built as a **GDExtension** (not the old `.gdip` system).
2. **PhaseGodot** -- Apple PHASE spatial audio framework for Godot (macOS, iOS, tvOS, visionOS).

**Why this matters for us:**

- **Hand tracking is already supported.** GodotRealityKit's feature table lists "Hand Tracking & Spatial Controllers" as supported in both RealityKit and CompositorServices modes. Apple has already solved the "bridge hand tracking to Godot" problem for visionOS.
- **The architecture is our template.** Their GDExtension is built with Objective-C++ (bridging Godot's C++ API to Apple's Swift/ObjC frameworks). This is exactly the pattern we need for an iOS Vision framework plugin.
- **It's a GDExtension, not `.gdip`.** This is the modern Godot plugin approach (same as GDMP). GDExtensions are more powerful, support cross-platform, and don't require the old iOS plugin export workflow.
- **MIT licensed.** We can study, fork, or adapt their code freely.

**What's different for our use case:**
- GodotRealityKit's hand tracking is for **visionOS spatial hand tracking** (3D hands in space around Vision Pro). We need **2D hand pose from camera** on iPhone/iPad.
- visionOS hand tracking uses ARKit's `HandTrackingProvider`. We need Vision framework's `VNDetectHumanHandPoseRequest` on iOS.
- But the GDExtension structure, build system, Swift-to-Godot bridging, and project layout are all reusable.

**Recommended approach:** Fork or study `apple/plugins-for-godot`, use their GDExtension scaffolding, and add a new `godothandvision/` plugin directory that wraps Vision framework's hand pose API for iOS.

### Apple's Official Hand Pose Documentation

**[developer.apple.com/documentation/vision/detecting-hand-poses-with-vision](https://developer.apple.com/documentation/vision/detecting-hand-poses-with-vision)**

Apple provides a complete sample project for hand pose detection with Vision framework. Key details:
- Uses `VNDetectHumanHandPoseRequest` for 2D hand pose from camera frames
- Returns `VNHumanHandPoseObservation` with 21 recognized points per hand
- Joint groups: `.all` (21 points), `.thumbFinger`, `.indexFinger`, `.middleFinger`, `.ringFinger`, `.littleFinger`
- Each point has `.location` (normalized CGPoint) and `.confidence` (Float)
- Supports `maximumHandCount` for multi-hand detection
- Works with both live camera (`AVCaptureSession`) and static images

---

## Architecture

```
iOS Camera (AVCaptureSession)
  -> CMSampleBuffer (video frame)
  -> VNImageRequestHandler
  -> VNDetectHumanHandPoseRequest (up to 4 hands)
  -> [VNHumanHandPoseObservation] (21 keypoints per hand)
  -> Convert to normalized coordinates
  -> Pass to Godot via plugin singleton
  -> AIInput.process_hand_result() (same signal pipeline as MediaPipe)
```

The plugin replaces `MediaPipeBackend` on iOS. `AIInput` and everything above it (smoothing, gesture detection, game code) stays identical.

---

## Implementation Steps

### Step 1: Scaffold the GDExtension (using Apple's template)

**Where:** Mac with Xcode
**Output:** `addons/VisionHandTracking/` directory (GDExtension, not old `.gdip`)

1. Clone [apple/plugins-for-godot](https://github.com/apple/plugins-for-godot) as reference
2. Study the `godotrealitykit/` structure -- how they set up SCons/CMake, bridge Swift to Godot C++ API, register GDExtension classes
3. Create a new directory `godothandvision/` following the same pattern
4. Create the `.gdextension` manifest (similar to GDMP's `GDMP.gdextension`):

```ini
[configuration]
entry_symbol = "vision_hand_tracking_init"
compatibility_minimum = "4.6"

[libraries]
ios.arm64 = "res://addons/VisionHandTracking/libVisionHandTracking.ios.a"
macos.arm64 = "res://addons/VisionHandTracking/libVisionHandTracking.macos.dylib"
```

5. Link against `Vision.framework`, `AVFoundation.framework`, `CoreVideo.framework`

### Step 2: Implement the Vision Hand Tracking Singleton

**File:** `VisionHandTracking.mm` (Objective-C++)

The singleton exposes these methods to GDScript:

```objc
// Methods callable from Godot
- (void)startTracking:(int)maxHands;
- (void)stopTracking;
- (bool)isTracking;
- (Array)getLatestResults;  // Returns array of hand landmark data
```

Core implementation:

```objc
#import <Vision/Vision.h>
#import <AVFoundation/AVFoundation.h>

@interface VisionHandTracking : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic) AVCaptureSession *captureSession;
@property (nonatomic) VNSequenceRequestHandler *sequenceHandler;
@property (nonatomic) int maxHands;
@property (nonatomic) NSArray<VNHumanHandPoseObservation *> *latestObservations;

@end

@implementation VisionHandTracking

- (void)startTracking:(int)maxHands {
    self.maxHands = maxHands;
    
    // Set up AVCaptureSession with front camera
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPreset640x480;
    
    AVCaptureDevice *camera = [AVCaptureDevice
        defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
        mediaType:AVMediaTypeVideo
        position:AVCaptureDevicePositionFront];
    
    NSError *error;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    [self.captureSession addInput:input];
    
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    output.alwaysDiscardsLateVideoFrames = YES;  // Critical: don't queue frames
    [output setSampleBufferDelegate:self queue:dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0)];
    [self.captureSession addOutput:output];
    
    [self.captureSession startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
    fromConnection:(AVCaptureConnection *)connection {
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    VNDetectHumanHandPoseRequest *request = [[VNDetectHumanHandPoseRequest alloc] init];
    request.maximumHandCount = self.maxHands;
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc]
        initWithCVPixelBuffer:pixelBuffer
        orientation:kCGImagePropertyOrientationUp
        options:@{}];
    
    [handler performRequests:@[request] error:nil];
    
    self.latestObservations = request.results;
    
    // Convert to Godot-friendly format and signal AIInput
    [self sendResultsToGodot];
}

- (void)sendResultsToGodot {
    // Convert VNHumanHandPoseObservation to Array of landmark positions
    // Each observation has .recognizedPoints(forGroupKey:) returning 21 joints
    //
    // Joint keys: .wrist, .thumbTip, .thumbIP, .thumbMP, .thumbCMC,
    //             .indexTip, .indexDIP, .indexPIP, .indexMCP,
    //             .middleTip, .middleDIP, .middlePIP, .middleMCP,
    //             .ringTip, .ringDIP, .ringPIP, .ringMCP,
    //             .littleTip, .littleDIP, .littlePIP, .littleMCP
    //
    // Each joint: .location (CGPoint, normalized 0..1), .confidence (float)
}

@end
```

### Step 3: Bridge to AIInput

The plugin singleton should match the interface that `mediapipe_backend.gd` uses to call `AIInput.process_hand_result()`. Two options:

**Option A: Plugin calls AIInput directly (simplest)**

```objc
// In the plugin, call the Godot singleton
Object *ai_input = Engine::get_singleton("AIInput");
if (ai_input) {
    // Pack landmarks into Godot Array format
    Array hand_landmarks_array;
    Array handedness_array;
    // ... fill arrays ...
    ai_input->call("process_hand_result", hand_landmarks_array, handedness_array, timestamp_ms);
}
```

**Option B: GDScript wrapper (more flexible)**

```gdscript
# ios_vision_backend.gd
extends Node

var _plugin = null

func _ready():
    if Engine.has_singleton("VisionHandTracking"):
        _plugin = Engine.get_singleton("VisionHandTracking")
        _plugin.startTracking(AIInput.max_hands)

func _process(_dt):
    if _plugin and _plugin.isTracking():
        var results = _plugin.getLatestResults()
        if results.size() > 0:
            AIInput.process_vision_result(results)
```

Option B is better because it keeps the native code minimal and handles data conversion in GDScript.

### Step 4: Handle the Keypoint Mapping

Vision framework uses different joint names than MediaPipe. The mapping:

| Vision Framework Joint | Index | MediaPipe Landmark |
|------------------------|-------|--------------------|
| wrist | 0 | WRIST |
| thumbCMC | 1 | THUMB_CMC |
| thumbMP | 2 | THUMB_MCP |
| thumbIP | 3 | THUMB_IP |
| thumbTip | 4 | THUMB_TIP |
| indexMCP | 5 | INDEX_FINGER_MCP |
| indexPIP | 6 | INDEX_FINGER_PIP |
| indexDIP | 7 | INDEX_FINGER_DIP |
| indexTip | 8 | INDEX_FINGER_TIP |
| middleMCP | 9 | MIDDLE_FINGER_MCP |
| middlePIP | 10 | MIDDLE_FINGER_PIP |
| middleDIP | 11 | MIDDLE_FINGER_DIP |
| middleTip | 12 | MIDDLE_FINGER_TIP |
| ringMCP | 13 | RING_FINGER_MCP |
| ringPIP | 14 | RING_FINGER_PIP |
| ringDIP | 15 | RING_FINGER_DIP |
| ringTip | 16 | RING_FINGER_TIP |
| littleMCP | 17 | PINKY_MCP |
| littlePIP | 18 | PINKY_PIP |
| littleDIP | 19 | PINKY_DIP |
| littleTip | 20 | PINKY_TIP |

The indices are the same! Both use 21 points in the same order. The plugin just needs to read `recognizedPoint(forKey:)` for each joint and pack them as `Vector3(x, y, confidence)`.

**Important coordinate difference:** Vision framework returns `y` with origin at bottom-left (Core Graphics convention). MediaPipe uses top-left. The plugin must flip: `y = 1.0 - point.location.y`.

### Step 5: Build and Test

1. Build the static library for both `arm64` (device) and `x86_64` (simulator)
2. Create `.xcframework`: `xcodebuild -create-xcframework -library device.a -library sim.a -output VisionHandTracking.xcframework`
3. Copy `.xcframework` + `.gdip` to `res://ios/plugins/VisionHandTracking/`
4. Export Godot project to iOS, open in Xcode, deploy to device
5. Test:
   - Single hand idle: verify 21 keypoints are correct
   - Two hands: verify both detected
   - Fast slashing: measure FPS, dropout rate
   - Compare against GDMP MediaPipe on same device

### Step 6: Benchmark vs MediaPipe on iOS

On the iOS device, run both backends and compare:

| Metric | Vision Framework | MediaPipe (GDMP) |
|--------|-----------------|------------------|
| FPS (idle) | ? | ? |
| FPS (slash stress) | ? | ? |
| Dropout rate (slash) | ? | ? |
| Battery usage (5 min) | ? | ? |
| Latency P50 | ? | ? |

Only switch to Vision if it wins on at least FPS + dropout rate.

---

## Key Risks

1. **Vision framework may not support enough hands.** `maximumHandCount` exists but Apple's docs don't specify the limit. MediaPipe does 4, Vision may cap at 2.
2. **Coordinate system differences.** Vision uses bottom-left origin, different from MediaPipe's top-left. Need careful flipping.
3. **No z-depth.** Vision framework returns 2D (x, y) keypoints. MediaPipe provides (x, y, z). The z-coordinate is used for pinch distance normalization. We'd need to estimate depth from hand scale instead.
4. **Camera ownership conflict.** If both CameraServerExtension (for camera preview) and Vision's AVCaptureSession try to own the camera, they'll conflict. The plugin needs to either share the camera feed or own it exclusively.
5. **Godot iOS export pipeline complexity.** Building, signing, and deploying iOS apps requires the full Apple developer toolchain. Iterating is slower than desktop development.

---

## Estimated Effort

| Task | Time | Requires |
|------|------|----------|
| Plugin scaffolding + .gdip | 2 hours | Mac + Xcode |
| Vision API integration | 4 hours | Mac + Xcode |
| Godot bridge + AIInput integration | 3 hours | Mac + Xcode |
| Build xcframework + test on device | 2 hours | Mac + Xcode + iPhone |
| Benchmark vs MediaPipe | 2 hours | Mac + iPhone |
| **Total** | **~13 hours** | **Mac + Xcode + iPhone** |

---

## File Structure

```
ios/
  plugins/
    VisionHandTracking/
      VisionHandTracking.xcframework/    # Built static library
      VisionHandTracking.gdip            # Plugin config
addon/
  camera_intelligence/
    ios_vision_backend.gd                # GDScript wrapper (Option B)
```

---

## Cross-References

- [Ecosystem Scan Round 2](../research/ecosystem-scan-round2.md#6-apple-vision-framework-ios-native-hand-tracking----unproven-for-godot) -- initial research
- [apple/plugins-for-godot](https://github.com/apple/plugins-for-godot) -- Apple's official Godot plugins (GDExtension template, hand tracking on visionOS)
- [GodotRealityKit README](https://github.com/apple/plugins-for-godot/blob/main/godotrealitykit/README.md) -- RealityKit renderer with hand tracking support
- [Apple VNDetectHumanHandPoseRequest](https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest)
- [Apple Hand Pose Detection Guide](https://developer.apple.com/documentation/vision/detecting-hand-poses-with-vision)
- [Swift Hand Pose Tutorial](https://www.createwithswift.com/detecting-hand-pose-with-the-vision-framework/)
- [Godot iOS Plugin Docs](https://docs.godotengine.org/en/stable/tutorials/platform/ios/ios_plugin.html) -- old `.gdip` system (we'll use GDExtension instead)
- [ROADMAP.md](../../ROADMAP.md) -- Phase 3: Mobile
