class_name GameCard
extends Panel
## A hoverable game card in the launcher.
## Hands hover over it; fills up a progress ring; selects on complete.

signal selected

@export var game_title: String = "Game"
@export var game_description: String = ""
@export var game_scene_path: String = ""
@export var game_color: Color = Color(0.2, 0.4, 0.8)

var _hover_progress: float = 0.0
var _is_hovered: bool = false
var _original_scale: Vector2

const HOVER_DURATION := 1.5  # Seconds to hold to select
const HOVER_GROW := 1.08     # Scale up when hovered

@onready var title_label: Label = $VBox/Title
@onready var desc_label: Label = $VBox/Description
@onready var progress_bar: ProgressBar = $VBox/Progress

func _ready() -> void:
	_original_scale = scale
	if title_label:
		title_label.text = game_title
	if desc_label:
		desc_label.text = game_description

func check_hover(cursor_pos: Vector2) -> bool:
	return get_global_rect().has_point(cursor_pos)

func update_hover(is_hovering: bool, dt: float) -> void:
	if is_hovering:
		_hover_progress += dt / HOVER_DURATION
		_is_hovered = true
		scale = _original_scale * HOVER_GROW
	else:
		_hover_progress = maxf(_hover_progress - dt * 2.0, 0.0)
		_is_hovered = false
		scale = _original_scale

	_hover_progress = clampf(_hover_progress, 0.0, 1.0)

	if progress_bar:
		progress_bar.value = _hover_progress * 100.0

	# Trigger selection
	if _hover_progress >= 1.0:
		_hover_progress = 0.0
		selected.emit()

	# Visual feedback
	modulate = game_color.lerp(Color.WHITE, _hover_progress * 0.3) if _is_hovered else game_color
