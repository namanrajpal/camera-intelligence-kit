class_name GestureEvent
extends RefCounted
## Represents a detected gesture -- emitted via AIInput signals.

## Gesture name: "swipe", "pinch_started", "pinch_held", "pinch_released", "open_palm"
var gesture_name: String = ""
## Phase: "started", "held", "released", "instant"
var phase: String = "instant"
## Confidence (0..1)
var confidence: float = 1.0
## Which hand triggered this (HandState.id)
var hand_id: int = 0
## "Left" or "Right"
var handedness: String = "Unknown"
## Position where gesture occurred (normalized screen space)
var position: Vector2 = Vector2.ZERO
## Velocity at time of gesture (for swipes)
var velocity: Vector2 = Vector2.ZERO
## Direction of gesture (normalized, for swipes)
var direction: Vector2 = Vector2.ZERO
## Speed at time of gesture
var speed: float = 0.0
## Timestamp
var timestamp_ms: int = 0

static func create(p_name: String, p_phase: String, hand: HandState) -> GestureEvent:
	var event := GestureEvent.new()
	event.gesture_name = p_name
	event.phase = p_phase
	event.hand_id = hand.id
	event.handedness = hand.handedness
	event.position = hand.screen_position
	event.velocity = hand.velocity
	event.speed = hand.speed
	if hand.velocity.length() > 0.001:
		event.direction = hand.velocity.normalized()
	event.timestamp_ms = Time.get_ticks_msec()
	return event
