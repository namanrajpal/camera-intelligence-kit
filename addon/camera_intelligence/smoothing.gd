class_name LandmarkSmoother
extends RefCounted
## 1-Euro Filter for landmark positions.
##
## Speed-adaptive low-pass filter (Casiez et al., CHI 2012).
## Reduces jitter during slow movements (idle hand) while preserving
## responsiveness during fast movements (slashes, swipes).
##
## Parameters:
##   mincutoff — cutoff frequency when speed is zero.
##               Lower = smoother but laggier at rest. (default 1.0 Hz)
##   beta      — speed coefficient. Higher = less lag during fast motion.
##               0 = constant cutoff (behaves like EMA). (default 0.007)
##   dcutoff   — cutoff frequency for the speed (derivative) filter.
##               Usually left at 1.0. (default 1.0 Hz)
##
## Tuning guide:
##   1. Set beta=0, hold hand still, decrease mincutoff until jitter is gone.
##   2. Slash fast, increase beta until lag is acceptable.
##
## Reference: https://cristal.univ-lille.fr/~casiez/1euro/

var mincutoff: float
var beta: float
var dcutoff: float

var _filters: Array = []  # Array of _OneEuroVec3 instances
var _initialized: bool = false

func _init(p_mincutoff: float = 1.0, p_beta: float = 0.007, p_dcutoff: float = 1.0) -> void:
	mincutoff = p_mincutoff
	beta = p_beta
	dcutoff = p_dcutoff

func smooth(raw: Array[Vector3], dt: float = 0.033) -> Array[Vector3]:
	## Filter an array of 21 landmark positions.
	## dt = time since last frame in seconds (used for frequency calculation).
	if not _initialized or _filters.size() != raw.size():
		_filters.clear()
		for i in range(raw.size()):
			_filters.append(_OneEuroVec3.new(mincutoff, beta, dcutoff, raw[i]))
		_initialized = true
		# Return raw on first frame (no history to filter against)
		return raw.duplicate()

	var result: Array[Vector3] = []
	for i in range(mini(raw.size(), _filters.size())):
		result.append(_filters[i].filter(raw[i], dt))
	return result

func reset() -> void:
	_filters.clear()
	_initialized = false

func set_params(p_mincutoff: float, p_beta: float, p_dcutoff: float = 1.0) -> void:
	mincutoff = p_mincutoff
	beta = p_beta
	dcutoff = p_dcutoff
	for f in _filters:
		f.mincutoff = p_mincutoff
		f.beta = p_beta
		f.dcutoff = p_dcutoff


# ── Internal: 1-Euro filter for a single Vector3 ──────────

class _OneEuroVec3:
	var mincutoff: float
	var beta: float
	var dcutoff: float
	# Low-pass filter state for position (x, y, z)
	var _x_hat: Vector3
	# Low-pass filter state for derivative (dx, dy, dz)
	var _dx_hat: Vector3
	var _prev_raw: Vector3
	var _first: bool

	func _init(p_mincutoff: float, p_beta: float, p_dcutoff: float, initial: Vector3) -> void:
		mincutoff = p_mincutoff
		beta = p_beta
		dcutoff = p_dcutoff
		_x_hat = initial
		_dx_hat = Vector3.ZERO
		_prev_raw = initial
		_first = true

	func filter(raw: Vector3, dt: float) -> Vector3:
		if _first:
			_prev_raw = raw
			_x_hat = raw
			_first = false
			return raw

		# Clamp dt to sane values
		dt = clampf(dt, 0.001, 0.2)

		# 1. Estimate speed (derivative)
		var dx := (raw - _prev_raw) / dt
		_prev_raw = raw

		# 2. Low-pass filter the derivative with fixed cutoff
		var alpha_d := _smoothing_factor(dt, dcutoff)
		_dx_hat = _lerp_vec3(alpha_d, dx, _dx_hat)

		# 3. Compute adaptive cutoff based on filtered speed
		var speed := _dx_hat.length()
		var cutoff := mincutoff + beta * speed

		# 4. Low-pass filter the position with adaptive cutoff
		var alpha := _smoothing_factor(dt, cutoff)
		_x_hat = _lerp_vec3(alpha, raw, _x_hat)

		return _x_hat

	static func _smoothing_factor(dt: float, cutoff: float) -> float:
		## Compute the EMA alpha from a cutoff frequency and time step.
		## alpha = 1 / (1 + tau/dt), where tau = 1/(2*PI*cutoff)
		var tau := 1.0 / (TAU * cutoff)  # TAU = 2*PI in Godot
		return 1.0 / (1.0 + tau / dt)

	static func _lerp_vec3(alpha: float, raw: Vector3, prev: Vector3) -> Vector3:
		## Standard EMA step: result = alpha * raw + (1-alpha) * prev
		return Vector3(
			alpha * raw.x + (1.0 - alpha) * prev.x,
			alpha * raw.y + (1.0 - alpha) * prev.y,
			alpha * raw.z + (1.0 - alpha) * prev.z,
		)
