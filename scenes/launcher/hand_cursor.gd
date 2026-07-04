class_name HandCursor
extends Control
## A visual cursor that follows a tracked hand.
## Renders as a big bright colored circle -- simple, bold, impossible to miss.

var hand_id: int = 0
var hand_color: Color = Color.WHITE

const CURSOR_SIZE := 56.0

var _circle: Panel
var _dot: Panel

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(CURSOR_SIZE, CURSOR_SIZE)
	pivot_offset = size / 2.0

	# ── Outer ring ──
	_circle = Panel.new()
	_circle.name = "Circle"
	_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_circle.position = Vector2.ZERO
	_circle.size = Vector2(CURSOR_SIZE, CURSOR_SIZE)
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(hand_color.r, hand_color.g, hand_color.b, 0.3)
	ring_style.set_corner_radius_all(int(CURSOR_SIZE / 2.0))
	ring_style.border_color = hand_color
	ring_style.set_border_width_all(4)
	ring_style.shadow_color = Color(hand_color.r, hand_color.g, hand_color.b, 0.4)
	ring_style.shadow_size = 10
	_circle.add_theme_stylebox_override("panel", ring_style)
	add_child(_circle)

	# ── Center dot ──
	var dot_size := 14.0
	_dot = Panel.new()
	_dot.name = "Dot"
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.position = Vector2((CURSOR_SIZE - dot_size) / 2.0, (CURSOR_SIZE - dot_size) / 2.0)
	_dot.size = Vector2(dot_size, dot_size)
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = hand_color
	dot_style.set_corner_radius_all(int(dot_size / 2.0))
	_dot.add_theme_stylebox_override("panel", dot_style)
	add_child(_dot)

func update_from_hand(hand: HandState, viewport_size: Vector2) -> void:
	visible = hand.is_tracked
	if not hand.is_tracked:
		return

	# Convert normalized position to screen position
	var screen_pos := hand.screen_position * viewport_size
	position = screen_pos - size / 2.0

	# Scale based on speed (pulse when moving fast)
	var speed_scale := remap(clampf(hand.speed, 0.0, 5.0), 0.0, 5.0, 1.0, 1.5)
	scale = Vector2.ONE * speed_scale

	# Ring brightens when moving
	if _circle:
		var style: StyleBoxFlat = _circle.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			var alpha := remap(clampf(hand.speed, 0.0, 3.0), 0.0, 3.0, 0.25, 0.6)
			style.bg_color = Color(hand_color.r, hand_color.g, hand_color.b, alpha)
