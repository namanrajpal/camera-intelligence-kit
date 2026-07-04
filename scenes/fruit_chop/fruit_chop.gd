extends Control
## Fruit Chop — slash fruits with your hands!
## Camera-based fruit ninja. 60 seconds of slicing mayhem.

# ── Game States ───────────────────────────────────────────
enum GameState { INIT, COUNTDOWN, PLAYING, GAME_OVER }
var state := GameState.INIT

# ── Camera & Backend ──────────────────────────────────────
var backend: MediaPipeBackend
var _ai_input: Node

# ── Hand Tracking ─────────────────────────────────────────
var hand_cursors: Dictionary = {}      # hand_id -> HandCursor
var _prev_hand_pos: Dictionary = {}    # hand_id -> Vector2 (pixel coords from prev frame)
var _slash_trails: Dictionary = {}     # hand_id -> Line2D

# ── Game Configuration ────────────────────────────────────
const GAME_DURATION := 60.0
const SLASH_RADIUS := 80.0            # generous for arcade feel
const SLASH_MIN_SPEED := 0.6          # normalized units/sec
const SPAWN_INTERVAL_START := 2.2
const SPAWN_INTERVAL_END := 0.5
const BOMB_CHANCE := 0.12
const COMBO_WINDOW := 0.8             # seconds to chain combos
const GAME_OVER_DELAY := 6.0          # then auto-return to launcher

const FRUIT_SCALE := 0.13             # 1024px images → ~133px on screen
const BOMB_SCALE := 0.13

# ── Fruit Definitions ────────────────────────────────────
const FRUIT_TYPES := [
	{
		"name": "Watermelon", "points": 1,
		"whole": "res://assets/fruit_chop/fruit/watermelon_whole.png",
		"half": "res://assets/fruit_chop/fruit/watermelon_half.png",
		"splash": "res://assets/fruit_chop/vfx/splash_red.png",
	},
	{
		"name": "Orange", "points": 1,
		"whole": "res://assets/fruit_chop/fruit/orange_whole.png",
		"half": "res://assets/fruit_chop/fruit/orange_half.png",
		"splash": "res://assets/fruit_chop/vfx/splash_orange.png",
	},
	{
		"name": "Lime", "points": 1,
		"whole": "res://assets/fruit_chop/fruit/lime_whole.png",
		"half": "res://assets/fruit_chop/fruit/lime_half.png",
		"splash": "res://assets/fruit_chop/vfx/splash_green.png",
	},
	{
		"name": "Banana", "points": 1,
		"whole": "res://assets/fruit_chop/fruit/banana.png",
		"half": "res://assets/fruit_chop/fruit/banana_half.png",
		"splash": "res://assets/fruit_chop/vfx/splash_yellow.png",
	},
	{
		"name": "Pineapple", "points": 2,
		"whole": "res://assets/fruit_chop/fruit/pineapple_whole.png",
		"half": "res://assets/fruit_chop/fruit/pineapple_half.png",
		"splash": "res://assets/fruit_chop/vfx/splash_gold.png",
	},
	{
		"name": "Grapes", "points": 3,
		"whole": "res://assets/fruit_chop/fruit/grape_cluster.png",
		"half": "",
		"splash": "res://assets/fruit_chop/vfx/splash_purple.png",
	},
]

# ── Design Language ───────────────────────────────────────
const COLOR_CORAL := Color("FF6B6B")
const COLOR_OCEAN := Color("4ECDC4")
const COLOR_SUNSHINE := Color("FFE66D")
const COLOR_SNOW := Color("F7F7F8")
const COLOR_MIST := Color("A8B2C1")
const HAND_COLORS := [
	Color("00E676"), Color("448AFF"), Color("FFAB00"), Color("FF4081"),
]

# ── Game State Variables ──────────────────────────────────
var score: int = 0
var combo_count: int = 0
var combo_timer: float = 0.0
var max_combo: int = 0
var fruits_sliced: int = 0
var fruits_missed: int = 0
var game_timer: float = GAME_DURATION
var spawn_timer: float = 0.0
var _countdown_elapsed: float = 0.0
var _game_over_elapsed: float = 0.0

# ── Node References ───────────────────────────────────────
@onready var camera_preview: TextureRect = $CameraPreview
@onready var game_layer: Node2D = $GameLayer
@onready var slash_trail_layer: Node2D = $SlashTrailLayer
@onready var ui_layer: Control = $UILayer
@onready var score_label: Label = $UILayer/ScoreLabel
@onready var timer_label: Label = $UILayer/TimerLabel
@onready var combo_label: Label = $UILayer/ComboLabel
@onready var countdown_label: Label = $UILayer/CountdownLabel
@onready var screen_flash: ColorRect = $ScreenFlash
@onready var cursor_layer: Control = $CursorLayer
@onready var camera_viewport: SubViewport = $CameraViewport
@onready var camera_texture_rect: TextureRect = $CameraViewport/CameraTextureRect

# Fonts (loaded at runtime)
var _font_title: Font
var _font_body: Font

# Game over UI (built dynamically)
var _game_over_container: Control

# ══════════════════════════════════════════════════════════
# LIFECYCLE
# ══════════════════════════════════════════════════════════

func _ready() -> void:
	_font_title = _load_font("res://assets/fonts/Fredoka-Variable.ttf")
	_font_body = _load_font("res://assets/fonts/Nunito-Variable.ttf")

	_setup_ui()
	_setup_camera()
	_start_countdown()

func _exit_tree() -> void:
	if _ai_input:
		if _ai_input.hand_tracked.is_connected(_on_hand_tracked):
			_ai_input.hand_tracked.disconnect(_on_hand_tracked)
		if _ai_input.hand_appeared.is_connected(_on_hand_appeared):
			_ai_input.hand_appeared.disconnect(_on_hand_appeared)
		if _ai_input.hand_lost.is_connected(_on_hand_lost):
			_ai_input.hand_lost.disconnect(_on_hand_lost)

func _process(dt: float) -> void:
	_update_camera_preview()

	match state:
		GameState.COUNTDOWN:
			_process_countdown(dt)
		GameState.PLAYING:
			_process_playing(dt)
		GameState.GAME_OVER:
			_process_game_over(dt)

	# Always sync hand positions at end of frame (for next frame's slash check)
	_sync_hand_positions()

# ══════════════════════════════════════════════════════════
# SETUP
# ══════════════════════════════════════════════════════════

func _setup_ui() -> void:
	# Score label — top left
	if _font_title:
		score_label.add_theme_font_override("font", _font_title)
	score_label.add_theme_font_size_override("font_size", 48)
	score_label.add_theme_color_override("font_color", COLOR_SNOW)
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	score_label.add_theme_constant_override("shadow_offset_x", 2)
	score_label.add_theme_constant_override("shadow_offset_y", 2)

	# Timer label — top right
	if _font_title:
		timer_label.add_theme_font_override("font", _font_title)
	timer_label.add_theme_font_size_override("font_size", 36)
	timer_label.add_theme_color_override("font_color", COLOR_SUNSHINE)
	timer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	timer_label.add_theme_constant_override("shadow_offset_x", 2)
	timer_label.add_theme_constant_override("shadow_offset_y", 2)

	# Combo label — center top
	if _font_title:
		combo_label.add_theme_font_override("font", _font_title)
	combo_label.add_theme_font_size_override("font_size", 56)
	combo_label.add_theme_color_override("font_color", COLOR_CORAL)
	combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	combo_label.add_theme_constant_override("shadow_offset_x", 2)
	combo_label.add_theme_constant_override("shadow_offset_y", 2)
	combo_label.visible = false

	# Countdown label — large center
	if _font_title:
		countdown_label.add_theme_font_override("font", _font_title)
	countdown_label.add_theme_font_size_override("font_size", 120)
	countdown_label.add_theme_color_override("font_color", COLOR_SNOW)
	countdown_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	countdown_label.add_theme_constant_override("shadow_offset_x", 3)
	countdown_label.add_theme_constant_override("shadow_offset_y", 3)

	# Screen flash starts invisible
	screen_flash.color = Color(0, 0, 0, 0)
	screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Set pivot for scale animations (deferred so layout is resolved)
	call_deferred("_setup_pivots")

func _setup_pivots() -> void:
	countdown_label.pivot_offset = countdown_label.size / 2.0
	combo_label.pivot_offset = combo_label.size / 2.0

func _setup_camera() -> void:
	_ai_input = get_node_or_null("/root/AIInput")
	if _ai_input == null:
		print("[FruitChop] ERROR: AIInput autoload not found")
		return

	_ai_input.hand_tracked.connect(_on_hand_tracked)
	_ai_input.hand_appeared.connect(_on_hand_appeared)
	_ai_input.hand_lost.connect(_on_hand_lost)

	backend = MediaPipeBackend.new()
	add_child(backend)
	backend.backend_ready.connect(func(): print("[FruitChop] Backend ready!"))
	backend.backend_error.connect(func(msg: String): print("[FruitChop] Backend error: ", msg))
	backend.initialize(_ai_input, camera_viewport, camera_texture_rect)

# ══════════════════════════════════════════════════════════
# GAME STATE MACHINE
# ══════════════════════════════════════════════════════════

func _start_countdown() -> void:
	state = GameState.COUNTDOWN
	_countdown_elapsed = 0.0
	countdown_label.visible = true
	countdown_label.text = "3"
	countdown_label.modulate = Color.WHITE
	score_label.text = "0"
	timer_label.text = str(int(GAME_DURATION))
	combo_label.visible = false

func _process_countdown(dt: float) -> void:
	_countdown_elapsed += dt
	# Re-center pivot each frame to handle late layout
	countdown_label.pivot_offset = countdown_label.size / 2.0

	if _countdown_elapsed < 1.0:
		countdown_label.text = "3"
		countdown_label.add_theme_color_override("font_color", COLOR_SNOW)
		countdown_label.scale = Vector2.ONE * lerpf(1.4, 1.0, _countdown_elapsed)
	elif _countdown_elapsed < 2.0:
		countdown_label.text = "2"
		countdown_label.scale = Vector2.ONE * lerpf(1.4, 1.0, _countdown_elapsed - 1.0)
	elif _countdown_elapsed < 3.0:
		countdown_label.text = "1"
		countdown_label.scale = Vector2.ONE * lerpf(1.4, 1.0, _countdown_elapsed - 2.0)
	elif _countdown_elapsed < 3.6:
		countdown_label.text = "CHOP!"
		countdown_label.add_theme_color_override("font_color", COLOR_CORAL)
		countdown_label.add_theme_font_size_override("font_size", 100)
		var t := (_countdown_elapsed - 3.0) / 0.6
		countdown_label.scale = Vector2.ONE * lerpf(1.6, 1.0, t)
	else:
		countdown_label.visible = false
		countdown_label.add_theme_color_override("font_color", COLOR_SNOW)
		countdown_label.add_theme_font_size_override("font_size", 120)
		countdown_label.scale = Vector2.ONE
		_begin_playing()

func _begin_playing() -> void:
	state = GameState.PLAYING
	score = 0
	combo_count = 0
	combo_timer = 0.0
	max_combo = 0
	fruits_sliced = 0
	fruits_missed = 0
	game_timer = GAME_DURATION
	spawn_timer = 0.8  # Brief pause before first wave
	_update_score_display()

func _process_playing(dt: float) -> void:
	# Timer
	game_timer -= dt
	var display_time := ceili(maxf(game_timer, 0.0))
	timer_label.text = str(display_time)

	# Flash timer red when low
	if game_timer <= 10.0:
		var pulse := absf(sin(game_timer * 3.0))
		timer_label.add_theme_color_override("font_color", Color(1.0, pulse * 0.4 + 0.5, 0.2))
	else:
		timer_label.add_theme_color_override("font_color", COLOR_SUNSHINE)

	if game_timer <= 0.0:
		_end_game()
		return

	# Spawn waves
	spawn_timer -= dt
	if spawn_timer <= 0.0:
		_spawn_wave()
		var progress := 1.0 - (game_timer / GAME_DURATION)
		spawn_timer = lerpf(SPAWN_INTERVAL_START, SPAWN_INTERVAL_END, progress)

	# Combo decay
	if combo_count > 0:
		combo_timer -= dt
		if combo_timer <= 0.0:
			combo_count = 0
			combo_label.visible = false

	# Slash detection
	_check_slashes()

	# Visual slash trails
	_update_slash_trails()

func _end_game() -> void:
	state = GameState.GAME_OVER
	_game_over_elapsed = 0.0
	countdown_label.visible = false
	combo_label.visible = false

	# Count any remaining unsliced fruits as missed
	for node in game_layer.get_children():
		if node is FruitItem and not node.is_sliced and not node.is_bomb:
			fruits_missed += 1

	# Clear fruits
	for node in game_layer.get_children():
		node.queue_free()

	# Clear slash trails
	for trail in _slash_trails.values():
		if is_instance_valid(trail):
			trail.queue_free()
	_slash_trails.clear()

	_show_game_over()

func _process_game_over(dt: float) -> void:
	_game_over_elapsed += dt
	if _game_over_elapsed > GAME_OVER_DELAY:
		get_tree().change_scene_to_file("res://scenes/launcher/launcher.tscn")

# ══════════════════════════════════════════════════════════
# SPAWNING
# ══════════════════════════════════════════════════════════

func _spawn_wave() -> void:
	var progress := 1.0 - (game_timer / GAME_DURATION)
	var count: int
	if progress < 0.25:
		count = randi_range(1, 2)
	elif progress < 0.5:
		count = randi_range(2, 3)
	elif progress < 0.75:
		count = randi_range(2, 4)
	else:
		count = randi_range(3, 5)

	for i in count:
		var is_bomb := randf() < BOMB_CHANCE
		_spawn_single(is_bomb, i, count)

func _spawn_single(is_bomb: bool, index: int, total: int) -> void:
	var fruit := FruitItem.new()
	var vp_size := get_viewport_rect().size

	if is_bomb:
		fruit.setup_bomb("res://assets/fruit_chop/bomb/bomb.png", BOMB_SCALE)
	else:
		var type_data: Dictionary = FRUIT_TYPES[randi() % FRUIT_TYPES.size()]
		fruit.setup_fruit(type_data, FRUIT_SCALE)

	# Spread across the screen
	var margin := 120.0
	var spread := vp_size.x - margin * 2.0
	var base_x := margin + spread * (float(index) + 0.5) / float(total)
	base_x += randf_range(-50, 50)

	fruit.position = Vector2(
		clampf(base_x, margin, vp_size.x - margin),
		vp_size.y + 60.0
	)

	# Toss upward with curve toward center
	var center_pull := (vp_size.x / 2.0 - fruit.position.x) * randf_range(0.15, 0.4)
	fruit.velocity = Vector2(
		center_pull + randf_range(-40, 40),
		randf_range(-830, -680)
	)
	fruit.angular_velocity = randf_range(-4.0, 4.0)

	fruit.missed.connect(_on_fruit_missed)
	game_layer.add_child(fruit)

func _on_fruit_missed() -> void:
	fruits_missed += 1

# ══════════════════════════════════════════════════════════
# SLASH DETECTION
# ══════════════════════════════════════════════════════════

func _check_slashes() -> void:
	if _ai_input == null:
		return

	var vp_size := get_viewport_rect().size
	var sliced_this_frame: Array[FruitItem] = []

	for hand_id in _prev_hand_pos.keys():
		var hand: HandState = _ai_input.get_hand(hand_id)
		if hand == null or not hand.is_tracked:
			continue

		# Use index fingertip for slash detection — reacts faster than palm center
		var current_pos := hand.fingertip_position * vp_size
		var prev_pos: Vector2 = _prev_hand_pos[hand_id]

		# Need minimum speed to count as a slash (use fingertip speed)
		if hand.fingertip_speed < SLASH_MIN_SPEED:
			continue

		# Check proximity to each unsliced fruit
		for node in game_layer.get_children():
			if not (node is FruitItem):
				continue
			var fi := node as FruitItem
			if fi.is_sliced or fi in sliced_this_frame:
				continue

			var dist := current_pos.distance_to(fi.position)
			if dist < SLASH_RADIUS:
				sliced_this_frame.append(fi)
				var slash_dir := (current_pos - prev_pos).normalized()
				if slash_dir.is_zero_approx():
					slash_dir = Vector2.DOWN
				_on_fruit_hit(fi, current_pos, slash_dir, hand_id)

func _on_fruit_hit(fruit: FruitItem, hit_pos: Vector2, slash_dir: Vector2, _hand_id: int) -> void:
	if fruit.is_bomb:
		# Penalty!
		score = maxi(0, score - 5)
		combo_count = 0
		combo_label.visible = false
		fruit.explode()
		_flash_screen(Color(1.0, 0.15, 0.1, 0.4))
		_show_score_popup(hit_pos, -5, 0)
	else:
		# Score!
		combo_count += 1
		combo_timer = COMBO_WINDOW
		max_combo = maxi(max_combo, combo_count)

		var points := fruit.point_value
		if combo_count >= 3:
			points = fruit.point_value * mini(combo_count, 8)

		score += points
		fruits_sliced += 1

		fruit.slice(slash_dir)
		_show_score_popup(hit_pos, points, combo_count)

		if combo_count >= 3:
			_show_combo(combo_count)

	_update_score_display()

# ══════════════════════════════════════════════════════════
# VFX
# ══════════════════════════════════════════════════════════

func _show_score_popup(pos: Vector2, points: int, combo: int) -> void:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if points >= 0:
		label.text = "+%d  x%d" % [points, combo] if combo >= 3 else "+%d" % points
	else:
		label.text = str(points)

	if _font_title:
		label.add_theme_font_override("font", _font_title)

	var fsize := 32
	var color := COLOR_SNOW
	if points < 0:
		fsize = 36; color = COLOR_CORAL
	elif combo >= 5:
		fsize = 48; color = COLOR_SUNSHINE
	elif combo >= 3:
		fsize = 40; color = COLOR_OCEAN

	label.add_theme_font_size_override("font_size", fsize)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = pos - Vector2(80, 25)
	label.size = Vector2(160, 50)

	ui_layer.add_child(label)

	var tw := create_tween()
	tw.tween_property(label, "position:y", pos.y - 100, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tw.tween_callback(label.queue_free)

func _show_combo(count: int) -> void:
	combo_label.visible = true
	combo_label.text = "%dx COMBO!" % count
	combo_label.pivot_offset = combo_label.size / 2.0

	var color := COLOR_OCEAN
	if count >= 8:
		color = COLOR_SUNSHINE
	elif count >= 5:
		color = COLOR_CORAL
	combo_label.add_theme_color_override("font_color", color)

	# Punch scale
	combo_label.scale = Vector2.ONE * 1.4
	var tw := create_tween()
	tw.tween_property(combo_label, "scale", Vector2.ONE, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

func _flash_screen(color: Color) -> void:
	screen_flash.color = color
	var tw := create_tween()
	tw.tween_property(screen_flash, "color:a", 0.0, 0.4)

func _update_score_display() -> void:
	score_label.text = str(score)

# ── Slash Trails ──────────────────────────────────────────

func _update_slash_trails() -> void:
	if _ai_input == null:
		return
	var vp_size := get_viewport_rect().size

	for hand_id in hand_cursors.keys():
		var hand: HandState = _ai_input.get_hand(hand_id) if _ai_input else null

		# Create trail if needed
		if not _slash_trails.has(hand_id):
			var trail := Line2D.new()
			trail.width = 6.0
			var trail_color: Color = HAND_COLORS[hand_id % HAND_COLORS.size()]
			trail.default_color = trail_color
			trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
			trail.end_cap_mode = Line2D.LINE_CAP_ROUND
			trail.joint_mode = Line2D.LINE_JOINT_ROUND
			var gradient := Gradient.new()
			gradient.set_color(0, Color(trail_color.r, trail_color.g, trail_color.b, 0.0))
			gradient.set_color(1, Color(trail_color.r, trail_color.g, trail_color.b, 0.8))
			trail.gradient = gradient
			slash_trail_layer.add_child(trail)
			_slash_trails[hand_id] = trail

		var trail: Line2D = _slash_trails[hand_id]

		if hand and hand.is_tracked and hand.speed > 0.3:
			var pos := hand.screen_position * vp_size
			trail.add_point(pos)
			trail.width = remap(clampf(hand.speed, 0.5, 4.0), 0.5, 4.0, 4.0, 14.0)

		# Trim old points
		while trail.get_point_count() > 15:
			trail.remove_point(0)

		# Shrink trail if hand is slow / gone
		if hand == null or not hand.is_tracked or hand.speed < 0.3:
			if trail.get_point_count() > 0:
				trail.remove_point(0)

# ══════════════════════════════════════════════════════════
# GAME OVER SCREEN
# ══════════════════════════════════════════════════════════

func _show_game_over() -> void:
	_game_over_container = Control.new()
	_game_over_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_game_over_container)

	# Dark backdrop
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.1, 0.16, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_over_container.add_child(bg)

	# Centered VBox
	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.5; vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5; vbox.anchor_bottom = 0.5
	vbox.offset_left = -300; vbox.offset_right = 300
	vbox.offset_top = -220; vbox.offset_bottom = 220
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	_game_over_container.add_child(vbox)

	# "Game Over!" title
	var title := Label.new()
	title.text = "Game Over!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font_title:
		title.add_theme_font_override("font", _font_title)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", COLOR_CORAL)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	vbox.add_child(title)

	# Big score number
	var score_lbl := Label.new()
	score_lbl.text = str(score)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font_title:
		score_lbl.add_theme_font_override("font", _font_title)
	score_lbl.add_theme_font_size_override("font_size", 96)
	score_lbl.add_theme_color_override("font_color", COLOR_SUNSHINE)
	score_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	score_lbl.add_theme_constant_override("shadow_offset_x", 3)
	score_lbl.add_theme_constant_override("shadow_offset_y", 3)
	vbox.add_child(score_lbl)

	# Stats line
	var stats := Label.new()
	stats.text = "Fruits sliced: %d  |  Missed: %d  |  Best combo: %dx" % [
		fruits_sliced, fruits_missed, max_combo
	]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font_body:
		stats.add_theme_font_override("font", _font_body)
	stats.add_theme_font_size_override("font_size", 22)
	stats.add_theme_color_override("font_color", COLOR_MIST)
	vbox.add_child(stats)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(spacer)

	# Return hint
	var hint := Label.new()
	hint.text = "Returning to menu..."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font_body:
		hint.add_theme_font_override("font", _font_body)
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(COLOR_MIST.r, COLOR_MIST.g, COLOR_MIST.b, 0.6))
	vbox.add_child(hint)

	# Fade in
	_game_over_container.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_game_over_container, "modulate:a", 1.0, 0.6)

# ══════════════════════════════════════════════════════════
# HAND TRACKING
# ══════════════════════════════════════════════════════════

func _on_hand_appeared(hand: HandState) -> void:
	if not is_inside_tree():
		return
	if not hand_cursors.has(hand.id):
		var cursor := _create_cursor(hand.id)
		hand_cursors[hand.id] = cursor
		cursor_layer.add_child(cursor)
	_prev_hand_pos[hand.id] = hand.fingertip_position * get_viewport_rect().size

func _on_hand_tracked(hand: HandState) -> void:
	if not is_inside_tree():
		return
	if hand_cursors.has(hand.id):
		var cursor: HandCursor = hand_cursors[hand.id]
		cursor.update_from_hand(hand, get_viewport_rect().size)

func _on_hand_lost(hand_id: int) -> void:
	if not is_inside_tree():
		return
	if hand_cursors.has(hand_id):
		hand_cursors[hand_id].queue_free()
		hand_cursors.erase(hand_id)
	_prev_hand_pos.erase(hand_id)
	if _slash_trails.has(hand_id):
		_slash_trails[hand_id].queue_free()
		_slash_trails.erase(hand_id)

func _sync_hand_positions() -> void:
	## Called at end of each frame to store current fingertip positions for next frame's slash check.
	if _ai_input == null:
		return
	var vp_size := get_viewport_rect().size
	for hand_id in _prev_hand_pos.keys():
		var hand: HandState = _ai_input.get_hand(hand_id)
		if hand and hand.is_tracked:
			_prev_hand_pos[hand_id] = hand.fingertip_position * vp_size

func _create_cursor(id: int) -> HandCursor:
	var cursor := HandCursor.new()
	cursor.name = "Cursor_%d" % id
	cursor.hand_id = id
	cursor.hand_color = HAND_COLORS[id % HAND_COLORS.size()]
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cursor

# ══════════════════════════════════════════════════════════
# CAMERA
# ══════════════════════════════════════════════════════════

func _update_camera_preview() -> void:
	if backend and backend.get_camera_viewport():
		var vp := backend.get_camera_viewport()
		var vp_tex := vp.get_texture()
		if vp_tex:
			camera_preview.texture = vp_tex

# ══════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════

func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path) as Font
	return null
