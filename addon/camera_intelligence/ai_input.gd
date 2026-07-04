extends Node
## AIInput — the core singleton of the Camera Intelligence Kit.
##
## Game developers connect to signals and never touch MediaPipe/ONNX directly:
##
##   func _ready():
##       AIInput.hand_tracked.connect(_on_hand)
##       AIInput.hand_gesture.connect(_on_gesture)
##
##   func _on_hand(hand: HandState):
##       cursor.position = hand.screen_position * viewport_size
##
##   func _on_gesture(event: GestureEvent):
##       if event.gesture_name == "swipe":
##           slash_at(event.position, event.direction)

# ── Signals ────────────────────────────────────────────────

## Emitted every frame for each tracked hand (smoothed state).
signal hand_tracked(hand: HandState)
## Emitted when a hand is first detected.
signal hand_appeared(hand: HandState)
## Emitted when a hand is lost (after grace period).
signal hand_lost(hand_id: int)
## Emitted when a gesture is detected (swipe, pinch, etc.)
signal hand_gesture(event: GestureEvent)
## Emitted when backend status changes.
signal status_changed(message: String)

# ── Configuration ──────────────────────────────────────────

## Smoothing alpha: 0.3 (smooth, laggy) to 0.8 (responsive, jittery).
@export var smoothing_alpha: float = 0.5
## Mirror the camera horizontally (selfie mode).
@export var mirror_camera: bool = true
## Maximum number of hands to track.
@export var max_hands: int = 4

# ── Internal State ─────────────────────────────────────────

var _hands: Dictionary = {}           # hand_id -> HandState
var _smoothers: Dictionary = {}       # hand_id -> LandmarkSmoother
var _gesture_detector: GestureDetector
var _is_running: bool = false
var _last_process_ms: int = 0

func _ready() -> void:
	_gesture_detector = GestureDetector.new()

# ── Public API ─────────────────────────────────────────────

func get_hand(id: int) -> HandState:
	## Get a specific hand by id. Returns null if not tracked.
	return _hands.get(id)

func get_hand_by_side(side: String) -> HandState:
	## Get the first tracked hand matching "Left" or "Right".
	for hand in _hands.values():
		if hand.is_tracked and hand.handedness == side:
			return hand
	return null

func get_tracked_hands() -> Array[HandState]:
	## Get all currently tracked hands.
	var result: Array[HandState] = []
	for hand in _hands.values():
		if hand.is_tracked:
			result.append(hand)
	return result

func get_hand_count() -> int:
	## Number of currently tracked hands.
	var count := 0
	for hand in _hands.values():
		if hand.is_tracked:
			count += 1
	return count

func set_smoothing(alpha: float) -> void:
	smoothing_alpha = clampf(alpha, 0.1, 1.0)
	for smoother in _smoothers.values():
		smoother.alpha = smoothing_alpha

func set_swipe_sensitivity(min_speed: float, min_distance: float, cooldown_ms: int) -> void:
	_gesture_detector.swipe_min_speed = min_speed
	_gesture_detector.swipe_min_distance = min_distance
	_gesture_detector.swipe_cooldown_ms = cooldown_ms

# ── Backend Interface (called by MediaPipe backend) ────────

func process_hand_result(
	hand_landmarks_array: Array,
	handedness_array: Array,
	timestamp_ms: int
) -> void:
	## Called by the backend when new hand tracking results arrive.
	## hand_landmarks_array: Array[MediaPipeNormalizedLandmarks]
	## handedness_array: Array[MediaPipeClassifications]

	var now := Time.get_ticks_msec()
	var dt: float = (now - _last_process_ms) / 1000.0 if _last_process_ms > 0 else 0.033
	_last_process_ms = now

	# Clamp dt to avoid spikes
	dt = clampf(dt, 0.001, 0.1)

	# Track which hands were seen this frame
	var seen_ids: Array[int] = []

	for i in range(hand_landmarks_array.size()):
		var mp_landmarks: MediaPipeNormalizedLandmarks = hand_landmarks_array[i]
		var raw_points: Array = mp_landmarks.landmarks

		# Extract raw Vector3 positions
		var raw_positions: Array[Vector3] = []
		for lm in raw_points:
			var x: float = lm.x
			var y: float = lm.y
			var z: float = lm.z
			if mirror_camera:
				x = 1.0 - x
			raw_positions.append(Vector3(x, y, z))

		# Get or create hand state
		var hand_id := i
		seen_ids.append(hand_id)

		if not _hands.has(hand_id):
			_hands[hand_id] = HandState.new()
			_hands[hand_id].id = hand_id
			_smoothers[hand_id] = LandmarkSmoother.new(smoothing_alpha)

		var hand: HandState = _hands[hand_id]
		var smoother: LandmarkSmoother = _smoothers[hand_id]

		# Smooth landmarks
		var smoothed := smoother.smooth(raw_positions)

		# Update handedness
		if i < handedness_array.size():
			var categories = handedness_array[i].categories
			if categories.size() > 0:
				hand.handedness = categories[0].display_name
				hand.handedness_confidence = categories[0].score

		# Track if this is a new hand
		var was_tracked := hand.is_tracked

		# Update hand state from smoothed landmarks
		hand.update_from_landmarks(smoothed, dt)

		# Emit signals
		if not was_tracked:
			hand_appeared.emit(hand)
		hand_tracked.emit(hand)

		# Detect gestures
		var events := _gesture_detector.detect(hand)
		for event in events:
			hand_gesture.emit(event)

	# Mark unseen hands as lost
	for hand_id in _hands.keys():
		if hand_id not in seen_ids:
			var hand: HandState = _hands[hand_id]
			if hand.is_tracked:
				hand.mark_lost()
				if not hand.is_tracked:
					hand_lost.emit(hand_id)
					_smoothers[hand_id].reset()
