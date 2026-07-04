extends Control
## Main launcher scene -- "Play With Air" game selector.
## Camera feed as background, hand cursors hover over game cards to select.

var backend: MediaPipeBackend
var hand_cursors: Dictionary = {}  # hand_id -> HandCursor

# Node references (from scene tree)
@onready var game_cards_container: HBoxContainer = $GameCards
@onready var cursor_layer: Control = $CursorLayer
@onready var status_label: Label = $StatusLabel
@onready var hand_count_label: Label = $HandCountLabel
@onready var camera_preview: TextureRect = $CameraPreview
@onready var camera_viewport: SubViewport = $CameraViewport
@onready var camera_texture_rect: TextureRect = $CameraViewport/CameraTextureRect
@onready var logo_rect: TextureRect = $LogoRect
@onready var title_label: TextureRect = $TitleLabel
@onready var subtitle_label: Label = $SubtitleLabel

var _ai_input: Node

# ── Design language colors ────────────────────────────────
const COLOR_MIDNIGHT := Color("0D1B2A")
const COLOR_DEEP_SEA := Color("1B2838")
const COLOR_SURFACE := Color("2A3A4E")
const COLOR_CORAL := Color("FF6B6B")
const COLOR_OCEAN := Color("4ECDC4")
const COLOR_SUNSHINE := Color("FFE66D")
const COLOR_SNOW := Color("F7F7F8")
const COLOR_MIST := Color("A8B2C1")

# Player hand colors
const HAND_COLORS := [
	Color("00E676"),  # Lime Burst (P1 dom)
	Color("448AFF"),  # Sky Flash (P2 dom)
	Color("FFAB00"),  # Amber Glow (P1 off)
	Color("FF4081"),  # Rose Pop (P2 off)
]

# Game definitions
const GAMES := [
	{
		"title": "Fruit Chop",
		"desc": "Slash fruits with\nyour hands!",
		"scene": "res://scenes/fruit_chop/fruit_chop.tscn",
		"color": Color("FF6B6B"),
		"icon": "res://assets/ui/icons/icon_fruit_chop.png",
	},
	{
		"title": "Whack-a-Mole",
		"desc": "Smash moles as\nthey pop up!",
		"scene": "res://scenes/whack_a_mole/whack_a_mole.tscn",
		"color": Color("C4A265"),
		"icon": "res://assets/ui/icons/icon_whack_a_mole.png",
	},
	{
		"title": "Bubble Pop",
		"desc": "Pop bubbles before\nthey float away!",
		"scene": "res://scenes/bubble_pop/bubble_pop.tscn",
		"color": Color("448AFF"),
		"icon": "res://assets/ui/icons/icon_bubble_pop.png",
	},
	{
		"title": "Hoops",
		"desc": "Pinch to grab,\nswipe to shoot!",
		"scene": "res://scenes/hoops/hoops.tscn",
		"color": Color("FF9800"),
		"icon": "res://assets/ui/icons/icon_hoops.png",
	},
	{
		"title": "Hand Test",
		"desc": "Raw hand tracking\nlandmark overlay",
		"scene": "res://examples/hand_tracking_test/hand_tracking_test.tscn",
		"color": Color("00E676"),
		"icon": "res://assets/ui/icons/icon_hand_test.png",
	},
]

# Fonts
var _font_title: Font
var _font_body: Font

func _ready() -> void:
	# Load custom fonts
	_font_title = _load_font("res://assets/fonts/Fredoka-Variable.ttf")
	_font_body = _load_font("res://assets/fonts/Nunito-Variable.ttf")

	# Apply fonts to subtitle / status
	if _font_body and subtitle_label:
		subtitle_label.add_theme_font_override("font", _font_body)
	if _font_body and status_label:
		status_label.add_theme_font_override("font", _font_body)
	if _font_body and hand_count_label:
		hand_count_label.add_theme_font_override("font", _font_body)

	# Setup title image (sticker logo replaces text title)
	if title_label:
		var title_tex := _load_texture("res://assets/ui/title_play_with_air.png")
		if title_tex:
			title_label.texture = title_tex

	# Setup hand logo
	if logo_rect:
		var logo_tex := _load_texture("res://assets/ui/logo_hand_transparent.png")
		if logo_tex:
			logo_rect.texture = logo_tex

	# Get AIInput singleton
	_ai_input = get_node_or_null("/root/AIInput")
	if _ai_input == null:
		status_label.text = "ERROR: AIInput autoload not found"
		return

	# Connect AIInput signals
	_ai_input.hand_tracked.connect(_on_hand_tracked)
	_ai_input.hand_appeared.connect(_on_hand_appeared)
	_ai_input.hand_lost.connect(_on_hand_lost)
	_ai_input.hand_gesture.connect(_on_gesture)

	# Start MediaPipe backend
	backend = MediaPipeBackend.new()
	add_child(backend)
	backend.backend_ready.connect(_on_backend_ready)
	backend.backend_error.connect(_on_backend_error)
	backend.initialize(_ai_input, camera_viewport, camera_texture_rect)

	status_label.text = "Starting camera..."

	# Build game cards
	_setup_game_cards()

func _exit_tree() -> void:
	if _ai_input:
		if _ai_input.hand_tracked.is_connected(_on_hand_tracked):
			_ai_input.hand_tracked.disconnect(_on_hand_tracked)
		if _ai_input.hand_appeared.is_connected(_on_hand_appeared):
			_ai_input.hand_appeared.disconnect(_on_hand_appeared)
		if _ai_input.hand_lost.is_connected(_on_hand_lost):
			_ai_input.hand_lost.disconnect(_on_hand_lost)
		if _ai_input.hand_gesture.is_connected(_on_gesture):
			_ai_input.hand_gesture.disconnect(_on_gesture)

# ── Card Setup ────────────────────────────────────────────

func _setup_game_cards() -> void:
	for g in GAMES:
		var card := _create_card(g)
		game_cards_container.add_child(card)

func _create_card(game: Dictionary) -> GameCard:
	var card := GameCard.new()
	card.game_title = game.title
	card.game_description = game.desc
	card.game_scene_path = game.scene
	card.game_color = game.color
	card.icon_path = game.icon
	card.custom_minimum_size = Vector2(200, 320)

	# ── Card panel style ──
	var style := StyleBoxFlat.new()
	style.bg_color = Color(game.color.r * 0.15, game.color.g * 0.15, game.color.b * 0.15, 0.88)
	style.border_color = game.color
	style.set_border_width_all(3)
	style.set_corner_radius_all(20)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 40
	style.content_margin_bottom = 20
	# Subtle shadow
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	card.add_theme_stylebox_override("panel", style)

	# ── Build card contents ──
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	# PRESET_FULL_RECT ignores content_margin, so set offsets manually for padding
	vbox.anchor_left = 0
	vbox.anchor_top = 0
	vbox.anchor_right = 1
	vbox.anchor_bottom = 1
	vbox.offset_left = 16
	vbox.offset_top = 24
	vbox.offset_right = -16
	vbox.offset_bottom = -16
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)

	# Icon container -- dark rounded panel that clips the white icon background
	var icon_panel := Panel.new()
	icon_panel.name = "IconPanel"
	icon_panel.custom_minimum_size = Vector2(120, 120)
	icon_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(game.color.r * 0.2, game.color.g * 0.2, game.color.b * 0.2, 0.9)
	icon_style.set_corner_radius_all(16)
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	icon_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW

	# Icon image inside the panel
	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_tex := _load_texture(game.icon)
	if icon_tex:
		icon_rect.texture = icon_tex
	icon_panel.add_child(icon_rect)
	vbox.add_child(icon_panel)
	card.icon_rect = icon_rect

	# Title
	var title_lbl := Label.new()
	title_lbl.name = "Title"
	title_lbl.text = game.title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size_flags_horizontal = Control.SIZE_FILL
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", COLOR_SNOW)
	if _font_title:
		title_lbl.add_theme_font_override("font", _font_title)
	vbox.add_child(title_lbl)
	card.title_label = title_lbl

	# Description
	var desc_lbl := Label.new()
	desc_lbl.name = "Description"
	desc_lbl.text = game.desc
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.size_flags_horizontal = Control.SIZE_FILL
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", COLOR_MIST)
	if _font_body:
		desc_lbl.add_theme_font_override("font", _font_body)
	vbox.add_child(desc_lbl)
	card.desc_label = desc_lbl

	# Flexible spacer pushes progress bar to bottom
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Progress bar (hover fill) -- pinned to bottom, tall and bold
	var progress := ProgressBar.new()
	progress.name = "Progress"
	progress.min_value = 0
	progress.max_value = 100
	progress.value = 0
	progress.custom_minimum_size = Vector2(0, 14)
	progress.show_percentage = false
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(1, 1, 1, 0.15)
	pb_bg.set_corner_radius_all(7)
	pb_bg.content_margin_top = 0
	pb_bg.content_margin_bottom = 0
	progress.add_theme_stylebox_override("background", pb_bg)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = game.color
	pb_fill.set_corner_radius_all(7)
	pb_fill.content_margin_top = 0
	pb_fill.content_margin_bottom = 0
	progress.add_theme_stylebox_override("fill", pb_fill)
	vbox.add_child(progress)
	card.progress_bar = progress

	card.add_child(vbox)
	card.modulate = Color.WHITE
	card.selected.connect(_on_card_selected.bind(card))

	return card

# ── Callbacks ─────────────────────────────────────────────

func _on_backend_ready() -> void:
	status_label.text = "Show your hands to play!"

func _on_backend_error(msg: String) -> void:
	status_label.text = "ERROR: " + msg

func _on_hand_appeared(hand: HandState) -> void:
	if not is_inside_tree():
		return
	if not hand_cursors.has(hand.id):
		var cursor := _create_cursor(hand.id)
		hand_cursors[hand.id] = cursor
		cursor_layer.add_child(cursor)

func _on_hand_tracked(hand: HandState) -> void:
	if not is_inside_tree():
		return
	if hand_cursors.has(hand.id):
		var cursor: HandCursor = hand_cursors[hand.id]
		cursor.update_from_hand(hand, get_viewport_rect().size)

	hand_count_label.text = "%d hands" % _count_tracked_hands()

func _on_hand_lost(hand_id: int) -> void:
	if not is_inside_tree():
		return
	if hand_cursors.has(hand_id):
		hand_cursors[hand_id].queue_free()
		hand_cursors.erase(hand_id)

func _count_tracked_hands() -> int:
	var count := 0
	for cursor in hand_cursors.values():
		if cursor.visible:
			count += 1
	return count

func _on_gesture(_event: GestureEvent) -> void:
	pass  # Hover-to-select in launcher, gestures not used

func _process(dt: float) -> void:
	# Camera preview
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
		status_label.text = "Coming soon: %s" % card.game_title
		return
	get_tree().change_scene_to_file(card.game_scene_path)

func _create_cursor(id: int) -> HandCursor:
	var cursor := HandCursor.new()
	cursor.name = "Cursor_%d" % id
	cursor.hand_id = id
	cursor.hand_color = HAND_COLORS[id % HAND_COLORS.size()]
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cursor

# ── Helpers ───────────────────────────────────────────────

func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path) as Font
	return null
