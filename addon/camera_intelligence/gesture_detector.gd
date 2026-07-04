class_name GestureDetector
extends RefCounted
## Detects gestures from smoothed hand state.
## Uses state machines with debounce/hysteresis to avoid noisy one-frame firing.

## Swipe config
var swipe_min_speed: float = 1.5       # Normalized units/sec (tune this!)
var swipe_min_distance: float = 0.08   # Min distance traveled for a valid swipe
var swipe_cooldown_ms: int = 300       # Cooldown between swipe events per hand

## Pinch config
var pinch_threshold: float = 0.35      # Pinch activates below this (normalized by hand size)
var pinch_release_threshold: float = 0.50  # Pinch releases above this (hysteresis)
var pinch_min_frames: int = 3          # Must hold for N frames to count

## State per hand (indexed by hand id)
var _swipe_last_ms: Dictionary = {}
var _swipe_trail: Dictionary = {}       # Recent positions for distance check

var _pinch_state: Dictionary = {}       # "none", "pending", "active"
var _pinch_frames: Dictionary = {}

func detect(hand: HandState) -> Array[GestureEvent]:
	var events: Array[GestureEvent] = []

	if not hand.is_tracked:
		# Reset states when hand is lost
		_pinch_state[hand.id] = "none"
		_pinch_frames[hand.id] = 0
		_swipe_trail.erase(hand.id)
		return events

	# Detect swipe/slash
	var swipe_event := _detect_swipe(hand)
	if swipe_event != null:
		events.append(swipe_event)

	# Detect pinch
	var pinch_events := _detect_pinch(hand)
	events.append_array(pinch_events)

	return events

func _detect_swipe(hand: HandState) -> GestureEvent:
	var now := Time.get_ticks_msec()

	# Cooldown check
	var last_swipe: int = _swipe_last_ms.get(hand.id, 0)
	if now - last_swipe < swipe_cooldown_ms:
		return null

	# Track trail for distance check
	if not _swipe_trail.has(hand.id):
		_swipe_trail[hand.id] = []
	var trail: Array = _swipe_trail[hand.id]
	trail.append(hand.screen_position)
	if trail.size() > 10:
		trail.pop_front()

	# Need minimum speed
	if hand.speed < swipe_min_speed:
		return null

	# Check distance traveled over recent trail
	if trail.size() < 3:
		return null
	var total_dist: float = 0.0
	for i in range(1, trail.size()):
		total_dist += (trail[i] as Vector2).distance_to(trail[i - 1] as Vector2)

	if total_dist < swipe_min_distance:
		return null

	# Valid swipe!
	_swipe_last_ms[hand.id] = now
	_swipe_trail[hand.id] = []  # Reset trail

	var event := GestureEvent.create("swipe", "instant", hand)
	event.confidence = clampf(hand.speed / (swipe_min_speed * 3.0), 0.5, 1.0)
	return event

func _detect_pinch(hand: HandState) -> Array[GestureEvent]:
	var events: Array[GestureEvent] = []
	var state: String = _pinch_state.get(hand.id, "none")
	var frames: int = _pinch_frames.get(hand.id, 0)

	if state == "none" or state == "released":
		# Check for pinch start
		if hand.pinch_distance < pinch_threshold:
			frames += 1
			if frames >= pinch_min_frames:
				_pinch_state[hand.id] = "active"
				events.append(GestureEvent.create("pinch", "started", hand))
		else:
			frames = 0
		_pinch_frames[hand.id] = frames

	elif state == "active":
		# Check for pinch release (with hysteresis)
		if hand.pinch_distance > pinch_release_threshold:
			_pinch_state[hand.id] = "none"
			_pinch_frames[hand.id] = 0
			events.append(GestureEvent.create("pinch", "released", hand))
		else:
			# Still pinching
			events.append(GestureEvent.create("pinch", "held", hand))

	return events
