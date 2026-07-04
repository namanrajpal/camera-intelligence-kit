class_name HandState
extends RefCounted
## Represents the current state of a single tracked hand.
## Smoothed, game-ready data derived from raw MediaPipe landmarks.

## Which hand (0-3). Stable across frames.
var id: int = 0
## "Left" or "Right" or "Unknown"
var handedness: String = "Unknown"
## Confidence of handedness classification (0..1)
var handedness_confidence: float = 0.0
## Whether this hand is currently being tracked
var is_tracked: bool = false
## Smoothed palm center position in normalized screen space (0..1, 0..1)
var screen_position: Vector2 = Vector2.ZERO
## Velocity of palm center in normalized units per second
var velocity: Vector2 = Vector2.ZERO
## Speed (magnitude of velocity)
var speed: float = 0.0
## All 21 smoothed landmark positions (normalized 0..1)
var landmarks: Array[Vector3] = []
## Key finger positions (smoothed, normalized)
var wrist: Vector2 = Vector2.ZERO
var thumb_tip: Vector2 = Vector2.ZERO
var index_tip: Vector2 = Vector2.ZERO
var middle_tip: Vector2 = Vector2.ZERO
var ring_tip: Vector2 = Vector2.ZERO
var pinky_tip: Vector2 = Vector2.ZERO
## Pinch distance (thumb tip to index tip, normalized by hand size)
var pinch_distance: float = 1.0
## Timestamp of last update
var last_seen_ms: int = 0
## How many consecutive frames this hand has been tracked
var tracked_frames: int = 0
## How many frames since this hand was last seen
var lost_frames: int = 0

# Landmark indices (MediaPipe hand model)
const WRIST := 0
const THUMB_TIP := 4
const INDEX_TIP := 8
const MIDDLE_TIP := 12
const RING_TIP := 16
const PINKY_TIP := 20
const INDEX_MCP := 5
const MIDDLE_MCP := 9
const RING_MCP := 13
const PINKY_MCP := 17

func update_from_landmarks(raw_landmarks: Array[Vector3], dt: float) -> void:
	## Compute derived values from smoothed landmarks.
	if raw_landmarks.size() < 21:
		return

	landmarks = raw_landmarks

	# Key positions
	wrist = Vector2(landmarks[WRIST].x, landmarks[WRIST].y)
	thumb_tip = Vector2(landmarks[THUMB_TIP].x, landmarks[THUMB_TIP].y)
	index_tip = Vector2(landmarks[INDEX_TIP].x, landmarks[INDEX_TIP].y)
	middle_tip = Vector2(landmarks[MIDDLE_TIP].x, landmarks[MIDDLE_TIP].y)
	ring_tip = Vector2(landmarks[RING_TIP].x, landmarks[RING_TIP].y)
	pinky_tip = Vector2(landmarks[PINKY_TIP].x, landmarks[PINKY_TIP].y)

	# Palm center = average of wrist and MCP joints
	var palm := (wrist + Vector2(landmarks[INDEX_MCP].x, landmarks[INDEX_MCP].y)
		+ Vector2(landmarks[MIDDLE_MCP].x, landmarks[MIDDLE_MCP].y)
		+ Vector2(landmarks[RING_MCP].x, landmarks[RING_MCP].y)
		+ Vector2(landmarks[PINKY_MCP].x, landmarks[PINKY_MCP].y)) / 5.0

	# Velocity
	if dt > 0.0 and is_tracked:
		var new_velocity := (palm - screen_position) / dt
		velocity = new_velocity
		speed = velocity.length()

	screen_position = palm

	# Pinch distance normalized by hand size
	var hand_size := wrist.distance_to(Vector2(landmarks[MIDDLE_MCP].x, landmarks[MIDDLE_MCP].y))
	if hand_size > 0.001:
		pinch_distance = thumb_tip.distance_to(index_tip) / hand_size
	else:
		pinch_distance = 1.0

	is_tracked = true
	tracked_frames += 1
	lost_frames = 0
	last_seen_ms = Time.get_ticks_msec()

func mark_lost() -> void:
	lost_frames += 1
	if lost_frames > 10:  # ~10 frames grace period
		is_tracked = false
		tracked_frames = 0
		speed = 0.0
		velocity = Vector2.ZERO
