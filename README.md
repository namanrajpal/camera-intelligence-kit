# Godot Camera Intelligence Kit

**Kinect-style camera controls for Godot, powered by modern on-device AI — desktop, web, and mobile.**

Game developers shouldn't need to understand tensors, ONNX graphs, or MediaPipe internals to use camera-based input. This kit turns noisy camera ML output into clean, calibrated, gameplay-friendly Godot signals — hand position, pinch, swipe, open palm, body lean, jump, object detection, and more — behind one simple `AIInput` API with swappable perception backends (MediaPipe, ONNX Runtime, ExecuTorch).

```gdscript
func _ready():
    AIInput.hand_gesture.connect(_on_hand_gesture)

func _on_hand_gesture(event):
    match event.name:
        "pinch_started": $Player.grab()
        "pinch_released": $Player.release()
        "swipe_left": $Player.dodge_left()
        "open_palm": $Player.shield()
```

## Status

Early development — **MVP 0 (prior-art research)**. See [`INITIAL_PROMPT.md`](./INITIAL_PROMPT.md) for the full vision and [`AGENTS.md`](./AGENTS.md) for current context.

## License

TBD.
