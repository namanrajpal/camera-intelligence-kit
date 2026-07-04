extends Control
## Draws hand landmarks on top of the camera preview.
## Accepts Array[MediaPipeNormalizedLandmarks] from GDMP.
## Each MediaPipeNormalizedLandmarks.landmarks contains 21 MediaPipeNormalizedLandmark
## objects with .x, .y, .z (normalized 0..1).

# Hand skeleton connections as flat array of pairs [from, to, from, to, ...]
var CONNECTIONS: PackedInt32Array = PackedInt32Array([
	0, 1, 1, 2, 2, 3, 3, 4,       # Thumb
	0, 5, 5, 6, 6, 7, 7, 8,       # Index
	5, 9, 9, 10, 10, 11, 11, 12,  # Middle
	9, 13, 13, 14, 14, 15, 15, 16, # Ring
	13, 17, 0, 17, 17, 18, 18, 19, 19, 20, # Pinky + palm
])

const HAND_COLORS := [
	Color(0.0, 1.0, 0.4, 0.9),   # Green for first hand
	Color(0.3, 0.6, 1.0, 0.9),   # Blue for second hand
	Color(1.0, 0.8, 0.0, 0.9),   # Yellow for third
	Color(1.0, 0.3, 0.5, 0.9),   # Pink for fourth
]

# Fingertip landmark indices
const FINGERTIPS := [4, 8, 12, 16, 20]

var _landmarks_list: Array = []  # Array[MediaPipeNormalizedLandmarks]

func set_landmarks(data: Array) -> void:
	_landmarks_list = data
	queue_redraw()

func _draw() -> void:
	if _landmarks_list.is_empty():
		return

	for hand_idx in range(_landmarks_list.size()):
		var hand_lm: MediaPipeNormalizedLandmarks = _landmarks_list[hand_idx]
		var landmarks: Array = hand_lm.landmarks
		var color: Color = HAND_COLORS[hand_idx % HAND_COLORS.size()]

		if landmarks.size() < 21:
			continue

		# Draw connections (pairs: [from, to, from, to, ...])
		for ci in range(0, CONNECTIONS.size(), 2):
			var lm1: MediaPipeNormalizedLandmark = landmarks[CONNECTIONS[ci]]
			var lm2: MediaPipeNormalizedLandmark = landmarks[CONNECTIONS[ci + 1]]
			var from := Vector2(lm1.x * size.x, lm1.y * size.y)
			var to := Vector2(lm2.x * size.x, lm2.y * size.y)
			draw_line(from, to, color, 3.0, true)

		# Draw landmark points
		for i in range(landmarks.size()):
			var lm: MediaPipeNormalizedLandmark = landmarks[i]
			var pos := Vector2(lm.x * size.x, lm.y * size.y)
			var point_color: Color = Color.WHITE if i in FINGERTIPS else color
			var radius: float = 6.0 if i in FINGERTIPS else 4.0
			draw_circle(pos, radius, point_color)
