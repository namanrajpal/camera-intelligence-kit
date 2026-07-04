extends Control
## Main launcher scene. Shows hand cursors and game cards.
## Hover a hand over a game card to select it.

var backend: MediaPipeBackend
var hand_cursors: Dictionary = {}  # hand_id -> HandCursor

@onready var game_cards_container: HBoxContainer = $GameCards
@onready var cursor_layer: Control = $CursorLayer
@onready var status_label: Label = $StatusLabel
@onready var hand_count_label: Label = $HandCountLabel
@onready var camera_preview: TextureRect = $CameraPreview
@onready var camera_viewport: SubViewport = $CameraViewport
@onready var camera_texture_rect: TextureRect = $CameraViewport/CameraTextureRect

func _ready() -> void:
	# Get AIInput singleton
	var ai_input = get_node("/root/AIInput")
	if ai_input == null:
		status_label.text = "ERROR: AIInput autoload not found"
		return

	# Connect AIInput signals
	ai_input.hand_tracked.connect(_on_hand_tracked)
	ai_input.hand_appeared.connect(_on_hand_appeared)
	ai_input.hand_lost.connect(_on_hand_lost)
	ai_input.hand_gesture.connect(_on_gesture)

	# Start MediaPipe backend
	backend = MediaPipeBackend.new()
	add_child(backend)
	backend.backend_ready.connect(_on_backend_ready)
	backend.backend_error.connect(_on_backend_error)
	backend.initialize(ai_input, camera_viewport, camera_texture_rect)

	status_label.text = "Starting camera..."

	# Setup game cards
	_setup_game_cards()

func _setup_game_cards() -> void:
	# Fruit Chop card
	var fruit_chop := _create_card(
		"Fruit Chop",
		"Slash fruits with your hands!\n2 players",
		"res://scenes/fruit_chop/fruit_chop.tscn",
		Color(0.9, 0.2, 0.1)
	)
	game_cards_container.add_child(fruit_chop)

	# Hand Tracking Test card
	var hand_test := _create_card(
		"Hand Test",
		"Raw hand tracking\nlandmark overlay",
		"res://examples/hand_tracking_test/hand_tracking_test.tscn",
		Color(0.1, 0.6, 0.3)
	)
	game_cards_container.add_child(hand_test)

func _create_card(title: String, desc: String, scene_path: String, color: Color) -> GameCard:
	var card := GameCard.new()
	card.game_title = title
	card.game_description = desc
	card.game_scene_path = scene_path
	card.game_color = color
	card.custom_minimum_size = Vector2(300, 400)

	# Build card UI
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var title_lbl := Label.new()
	title_lbl.name = "Title"
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.name = "Description"
	desc_lbl.text = desc
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	var progress := ProgressBar.new()
	progress.name = "Progress"
	progress.min_value = 0
	progress.max_value = 100
	progress.value = 0
	progress.custom_minimum_size = Vector2(0, 20)
	progress.show_percentage = false
	vbox.add_child(progress)

	card.add_child(vbox)
	card.title_label = title_lbl
	card.desc_label = desc_lbl
	card.progress_bar = progress
	card.modulate = color
	card.selected.connect(_on_card_selected.bind(card))

	return card

func _on_backend_ready() -> void:
	status_label.text = "Show your hands to play!"

func _on_backend_error(msg: String) -> void:
	status_label.text = "ERROR: " + msg

func _on_hand_appeared(hand: HandState) -> void:
	if not hand_cursors.has(hand.id):
		var cursor := _create_cursor(hand.id)
		hand_cursors[hand.id] = cursor
		cursor_layer.add_child(cursor)

func _on_hand_tracked(hand: HandState) -> void:
	# Update cursor
	if hand_cursors.has(hand.id):
		var cursor: HandCursor = hand_cursors[hand.id]
		cursor.update_from_hand(hand, get_viewport_rect().size)

	# Update hand count
	var ai_input = get_node("/root/AIInput")
	hand_count_label.text = "%d hands" % ai_input.get_hand_count()

func _on_hand_lost(hand_id: int) -> void:
	if hand_cursors.has(hand_id):
		hand_cursors[hand_id].queue_free()
		hand_cursors.erase(hand_id)

func _on_gesture(event: GestureEvent) -> void:
	pass  # Gestures not used in launcher (hover-to-select instead)

func _process(dt: float) -> void:
	# Update camera preview from viewport
	if backend and backend.get_camera_viewport():
		var vp := backend.get_camera_viewport()
		var vp_tex := vp.get_texture()
		if vp_tex:
			camera_preview.texture = vp_tex

	# Check hover for each cursor against each card
	for card in game_cards_container.get_children():
		if not card is GameCard:
			continue
		var any_hover := false
		for cursor in hand_cursors.values():
			if cursor.visible:
				var cursor_center: Vector2 = cursor.position + cursor.size / 2.0
				if card.check_hover(cursor_center):
					any_hover = true
					break
		card.update_hover(any_hover, dt)

func _on_card_selected(card: GameCard) -> void:
	if card.game_scene_path.is_empty():
		return
	if not ResourceLoader.exists(card.game_scene_path):
		status_label.text = "Scene not built yet: %s" % card.game_scene_path
		return
	get_tree().change_scene_to_file(card.game_scene_path)

func _create_cursor(id: int) -> HandCursor:
	var colors := [
		Color(0.0, 1.0, 0.4),
		Color(0.3, 0.6, 1.0),
		Color(1.0, 0.8, 0.0),
		Color(1.0, 0.3, 0.5),
	]

	var cursor := HandCursor.new()
	cursor.name = "Cursor_%d" % id
	cursor.hand_id = id
	cursor.hand_color = colors[id % colors.size()]
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Simple circle visual
	var circle := Panel.new()
	circle.name = "Circle"
	circle.size = Vector2(48, 48)
	circle.anchors_preset = Control.PRESET_FULL_RECT
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = colors[id % colors.size()]
	stylebox.corner_radius_top_left = 24
	stylebox.corner_radius_top_right = 24
	stylebox.corner_radius_bottom_left = 24
	stylebox.corner_radius_bottom_right = 24
	circle.add_theme_stylebox_override("panel", stylebox)
	cursor.add_child(circle)

	return cursor
