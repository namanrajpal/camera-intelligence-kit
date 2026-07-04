class_name LandmarkSmoother
extends RefCounted
## Exponential Moving Average (EMA) filter for landmark positions.
## Reduces jitter from raw MediaPipe output while keeping latency low.
##
## Higher alpha = more responsive but more jittery.
## Lower alpha = smoother but more laggy.
## Recommended range: 0.3 (smooth) to 0.7 (responsive).

var alpha: float = 0.5
var _smoothed: Array[Vector3] = []
var _initialized: bool = false

func _init(p_alpha: float = 0.5) -> void:
	alpha = p_alpha

func smooth(raw: Array[Vector3]) -> Array[Vector3]:
	if not _initialized or _smoothed.size() != raw.size():
		# First frame or size changed -- initialize with raw values
		_smoothed = raw.duplicate()
		_initialized = true
		return _smoothed

	for i in range(mini(raw.size(), _smoothed.size())):
		_smoothed[i] = Vector3(
			alpha * raw[i].x + (1.0 - alpha) * _smoothed[i].x,
			alpha * raw[i].y + (1.0 - alpha) * _smoothed[i].y,
			alpha * raw[i].z + (1.0 - alpha) * _smoothed[i].z,
		)

	return _smoothed

func reset() -> void:
	_smoothed.clear()
	_initialized = false
