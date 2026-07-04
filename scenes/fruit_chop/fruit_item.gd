class_name FruitItem
extends Node2D
## A single tossed fruit or bomb. Handles physics, slicing, and VFX.

signal missed  # Emitted when an unsliced fruit falls off-screen

var velocity: Vector2 = Vector2.ZERO
var angular_velocity: float = 0.0
var is_sliced: bool = false
var is_bomb: bool = false
var point_value: int = 1
var fruit_data: Dictionary = {}

const GRAVITY := 580.0  # pixels/sec²

# ── Internal sprites ──────────────────────────────────────
var _whole_sprite: Sprite2D
var _half_sprites: Array[Sprite2D] = []
var _half_velocities: Array[Vector2] = []
var _splash_sprite: Sprite2D

# Slice animation
var _slice_timer: float = 0.0
var _has_notified_miss: bool = false

# ── Setup ─────────────────────────────────────────────────

func setup_fruit(data: Dictionary, scale_factor: float) -> void:
	fruit_data = data
	is_bomb = false
	point_value = data.get("points", 1)

	_whole_sprite = Sprite2D.new()
	var tex := _load_tex(data.get("whole", ""))
	if tex:
		_whole_sprite.texture = tex
		_whole_sprite.scale = Vector2.ONE * scale_factor
	add_child(_whole_sprite)

func setup_bomb(bomb_path: String, scale_factor: float) -> void:
	is_bomb = true
	point_value = 0

	_whole_sprite = Sprite2D.new()
	var tex := _load_tex(bomb_path)
	if tex:
		_whole_sprite.texture = tex
		_whole_sprite.scale = Vector2.ONE * scale_factor
	add_child(_whole_sprite)

# ── Physics ───────────────────────────────────────────────

func _process(dt: float) -> void:
	if not is_sliced:
		velocity.y += GRAVITY * dt
		position += velocity * dt
		rotation += angular_velocity * dt

		# Fell off-screen → missed
		if position.y > 850 and not _has_notified_miss:
			_has_notified_miss = true
			if not is_bomb:
				missed.emit()
			queue_free()
	else:
		_process_slice_animation(dt)

func _process_slice_animation(dt: float) -> void:
	_slice_timer += dt

	# Halves tumble apart
	for i in _half_sprites.size():
		var half := _half_sprites[i]
		if is_instance_valid(half):
			_half_velocities[i].y += GRAVITY * 0.7 * dt
			half.position += _half_velocities[i] * dt
			half.rotation += (3.5 if i == 0 else -3.5) * dt
			half.modulate.a = maxf(0.0, 1.0 - _slice_timer * 0.7)

	# Splash expands then fades
	if _splash_sprite and is_instance_valid(_splash_sprite):
		var t := minf(_slice_timer * 6.0, 1.0)
		_splash_sprite.scale = Vector2.ONE * t * 0.45
		_splash_sprite.modulate.a = maxf(0.0, 1.0 - _slice_timer * 1.3)

	if _slice_timer > 2.0:
		queue_free()

# ── Slice / Explode ──────────────────────────────────────

func slice(slash_direction: Vector2) -> void:
	if is_sliced:
		return
	is_sliced = true
	_slice_timer = 0.0

	if _whole_sprite:
		_whole_sprite.visible = false

	# Create two halves that fly apart
	var half_path: String = fruit_data.get("half", "")
	if not half_path.is_empty():
		var half_tex := _load_tex(half_path)
		if half_tex:
			var fscale: float = _whole_sprite.scale.x if _whole_sprite else 0.13
			var perp := Vector2(-slash_direction.y, slash_direction.x).normalized()

			for i in 2:
				var half := Sprite2D.new()
				half.texture = half_tex
				half.scale = Vector2.ONE * fscale * 0.9
				if i == 1:
					half.flip_h = true
				add_child(half)
				_half_sprites.append(half)

				var dir := perp if i == 0 else -perp
				_half_velocities.append(dir * 130.0 + Vector2(0, -90))
	else:
		# No half texture (grapes) — fade whole
		if _whole_sprite:
			_whole_sprite.visible = true
			var tw := create_tween()
			tw.tween_property(_whole_sprite, "modulate:a", 0.0, 0.5)

	# Splash VFX
	var splash_path: String = fruit_data.get("splash", "")
	if not splash_path.is_empty():
		var splash_tex := _load_tex(splash_path)
		if splash_tex:
			_splash_sprite = Sprite2D.new()
			_splash_sprite.texture = splash_tex
			_splash_sprite.scale = Vector2(0.05, 0.05)
			_splash_sprite.z_index = -1
			add_child(_splash_sprite)

func explode() -> void:
	if is_sliced:
		return
	is_sliced = true
	_slice_timer = 0.0

	if _whole_sprite:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_whole_sprite, "scale", _whole_sprite.scale * 1.8, 0.2)
		tw.tween_property(_whole_sprite, "modulate", Color(1, 0.3, 0.3, 0), 0.5)
		tw.chain().tween_callback(queue_free)

# ── Helpers ───────────────────────────────────────────────

func _load_tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null
