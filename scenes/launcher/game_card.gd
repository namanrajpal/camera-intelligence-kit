class_name GameCard
extends Panel
## A hoverable game card in the launcher.
## Shows an icon image, title, description, and hover-to-select progress ring.

signal selected

@export var game_title: String = "Game"
@export var game_description: String = ""
@export var game_scene_path: String = ""
@export var game_color: Color = Color(0.2, 0.4, 0.8)
@export var icon_path: String = ""

var _hover_progress: float = 0.0
var _is_hovered: bool = false
var _base_scale: Vector2 = Vector2.ONE
var _target_scale: Vector2 = Vector2.ONE

const HOVER_DURATION := 1.5  # Seconds to hold to select
const HOVER_GROW := 1.14     # Scale up when hovered -- big and obvious
const SCALE_SPEED := 6.0     # Lerp speed for smooth scale transitions

# Child refs (set by launcher after building)
var title_label: Label
var desc_label: Label
var progress_bar: ProgressBar
var icon_rect: TextureRect

func _ready() -> void:
	_base_scale = scale
	_target_scale = scale
	pivot_offset = size / 2.0
	if title_label:
		title_label.text = game_title
	if desc_label:
		desc_label.text = game_description

func _process(dt: float) -> void:
	# Smooth scale interpolation
	scale = scale.lerp(_target_scale, dt * SCALE_SPEED)

func check_hover(cursor_pos: Vector2) -> bool:
	return get_global_rect().has_point(cursor_pos)

func update_hover(is_hovering: bool, dt: float) -> void:
	if is_hovering:
		_hover_progress += dt / HOVER_DURATION
		_is_hovered = true
		_target_scale = _base_scale * HOVER_GROW
	else:
		_hover_progress = maxf(_hover_progress - dt * 2.0, 0.0)
		_is_hovered = false
		_target_scale = _base_scale

	_hover_progress = clampf(_hover_progress, 0.0, 1.0)

	if progress_bar:
		progress_bar.value = _hover_progress * 100.0

	# Trigger selection
	if _hover_progress >= 1.0:
		_hover_progress = 0.0
		selected.emit()

	# Card glow feedback -- border brightens and thickens as hover progresses
	var style: StyleBoxFlat = get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var glow_color := game_color.lerp(Color.WHITE, _hover_progress * 0.7)
		style.border_color = glow_color
		var bw := int(3 + _hover_progress * 5)  # border grows 3->8
		style.border_width_left = bw
		style.border_width_right = bw
		style.border_width_top = bw
		style.border_width_bottom = bw
		# Background also brightens slightly
		style.bg_color.a = 0.88 + _hover_progress * 0.1
