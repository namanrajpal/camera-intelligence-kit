class_name HandCursor
extends Control
## A visual cursor that follows a tracked hand.
## Shows a circle that fills up when hovering over a selectable element.

var circle: Panel
var fill_ring: Control  # placeholder, not used yet

var hand_id: int = 0
var hand_color: Color = Color.WHITE
var hover_target: Control = null
var hover_time: float = 0.0

const HOVER_DURATION := 1.0  # Seconds to hold to select
const CURSOR_SIZE := 48.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(CURSOR_SIZE, CURSOR_SIZE)
	pivot_offset = size / 2.0

func update_from_hand(hand: HandState, viewport_size: Vector2) -> void:
	visible = hand.is_tracked
	if not hand.is_tracked:
		hover_time = 0.0
		return

	# Convert normalized position to screen position
	var screen_pos := hand.screen_position * viewport_size
	position = screen_pos - size / 2.0

	# Scale based on speed (pulse when moving fast)
	var speed_scale := remap(clampf(hand.speed, 0.0, 5.0), 0.0, 5.0, 1.0, 1.5)
	scale = Vector2.ONE * speed_scale

func get_hover_progress() -> float:
	return clampf(hover_time / HOVER_DURATION, 0.0, 1.0)

func add_hover_time(dt: float) -> void:
	hover_time += dt

func reset_hover() -> void:
	hover_time = 0.0
