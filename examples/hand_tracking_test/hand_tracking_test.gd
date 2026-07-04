extends Control
## Hand tracking test scene using GDMP + CameraServerExtension.

var task: MediaPipeHandLandmarker
var camera_feed: CameraFeed
var camera_extension: CameraServerExtension
var is_task_ready := false

const MODEL_PATH := "hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"

@onready var status_label: Label = $StatusLabel
@onready var fps_label: Label = $FPSLabel
@onready var landmark_canvas: Control = $LandmarkCanvas
@onready var camera_viewport: SubViewport = $CameraViewport
@onready var camera_texture_rect: TextureRect = $CameraViewport/CameraTextureRect
@onready var camera_preview: TextureRect = $CameraPreview

var _frame_count := 0
var _fps_timer := 0.0

func _ready() -> void:
	_log("Initializing...")

	# Connect all camera signals first
	CameraServer.camera_feed_added.connect(_on_feed_added)
	CameraServer.camera_feed_removed.connect(_on_feed_removed)
	CameraServer.camera_feeds_updated.connect(_on_feeds_updated)

	# On Windows, create CameraServerExtension and request permission
	if OS.get_name() == "Windows":
		_log("Windows detected, creating CameraServerExtension...")
		camera_extension = CameraServerExtension.new()
		camera_extension.permission_result.connect(_on_permission_result)
		if camera_extension.permission_granted():
			_log("Camera permission already granted.")
			_start_monitoring()
		else:
			_log("Requesting camera permission...")
			camera_extension.request_permission()
	else:
		_start_monitoring()

func _start_monitoring() -> void:
	_log("Starting feed monitoring...")
	CameraServer.monitoring_feeds = true
	# Also try immediately in case feeds are already available
	await get_tree().create_timer(1.0).timeout
	_check_feeds()

func _on_permission_result(granted: bool) -> void:
	if granted:
		_log("Permission granted!")
		_start_monitoring()
	else:
		_log("ERROR: Camera permission denied!")

func _on_feed_added(id: int) -> void:
	_log("Feed added: id=%d" % id)
	if CameraServer.monitoring_feeds:
		_check_feeds()

func _on_feed_removed(id: int) -> void:
	_log("Feed removed: id=%d" % id)

func _on_feeds_updated() -> void:
	_log("Feeds updated signal received.")
	_check_feeds()

func _check_feeds() -> void:
	if camera_feed != null:
		return  # Already connected

	var feeds := CameraServer.feeds()
	_log("Available feeds: %d" % feeds.size())

	for i in range(feeds.size()):
		var f: CameraFeed = feeds[i]
		_log("  Feed %d: '%s' (id=%d)" % [i, f.get_name(), f.get_id()])

	if feeds.is_empty():
		return

	# Prefer external webcam (NexiGo) over built-in laptop camera
	camera_feed = feeds[0]
	for f in feeds:
		if "NexiGO" in f.get_name() or "USB" in f.get_name() or "Webcam" in f.get_name():
			camera_feed = f
			break
	_log("Using feed: '%s'" % camera_feed.get_name())

	# Pick first format
	var formats = camera_feed.get_formats()
	_log("Available formats: %d" % formats.size())
	for i in range(mini(formats.size(), 5)):
		_log("  Format %d: %s" % [i, str(formats[i])])
	if formats.size() > 0:
		camera_feed.set_format(0, {})

	# Setup camera texture
	var cam_tex := CameraTexture.new()
	cam_tex.camera_feed_id = camera_feed.get_id()
	cam_tex.which_feed = CameraServer.FEED_RGBA_IMAGE
	camera_texture_rect.texture = cam_tex

	if camera_feed.get_position() != CameraFeed.FEED_BACK:
		camera_texture_rect.flip_h = true

	# Connect frame signal
	camera_feed.format_changed.connect(_on_format_changed, ConnectFlags.CONNECT_DEFERRED)
	camera_feed.frame_changed.connect(_on_frame_changed, ConnectFlags.CONNECT_DEFERRED)

	# Activate
	camera_feed.feed_is_active = true
	_on_format_changed()

	_log("Camera activated! Loading ML model...")
	_init_hand_model()

func _on_format_changed() -> void:
	if camera_feed == null:
		return
	var cam_tex := CameraTexture.new()
	cam_tex.camera_feed_id = camera_feed.get_id()
	cam_tex.which_feed = CameraServer.FEED_RGBA_IMAGE
	var frame_size: Vector2i = cam_tex.get_size()
	if frame_size == Vector2i.ZERO:
		frame_size = Vector2i(640, 480)
	_log("Frame size: %s" % str(frame_size))
	camera_viewport.size = frame_size
	camera_texture_rect.texture = cam_tex

func _on_frame_changed() -> void:
	if not is_task_ready:
		return

	await RenderingServer.frame_post_draw

	if camera_viewport == null:
		return
	var texture := camera_viewport.get_texture()
	if texture == null:
		return
	var image: Image = texture.get_image()
	if image == null:
		return

	# Update preview
	if camera_preview.texture == null or Vector2i(camera_preview.texture.get_size()) != image.get_size():
		camera_preview.texture = ImageTexture.create_from_image(image)
	else:
		camera_preview.texture.update(image)

	# Send to MediaPipe
	image.convert(Image.FORMAT_RGB8)
	var mp_image := MediaPipeImage.new()
	mp_image.set_image(image)
	task.detect_async(mp_image, Time.get_ticks_msec())

func _init_hand_model() -> void:
	var local_path := "user://hand_landmarker.task"

	# Check if model is already cached locally
	if FileAccess.file_exists(local_path):
		_log("Loading cached model...")
		_load_model(local_path)
		return

	# Download from Google Cloud Storage
	var url := "https://storage.googleapis.com/mediapipe-models/" + MODEL_PATH
	_log("Downloading model (first run)...\n%s" % url)

	var http := HTTPRequest.new()
	http.download_file = local_path
	add_child(http)
	http.request_completed.connect(_on_model_downloaded.bind(http, local_path))
	var err := http.request(url)
	if err != OK:
		_log("ERROR: HTTP request failed: %d" % err)

func _on_model_downloaded(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest, local_path: String) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_log("ERROR: Download failed (result=%d, code=%d)" % [result, response_code])
		return
	_log("Model downloaded!")
	_load_model(local_path)

func _load_model(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_log("ERROR: Could not open model: %s" % path)
		return

	var base_options := MediaPipeTaskBaseOptions.new()
	base_options.delegate = MediaPipeTaskBaseOptions.DELEGATE_CPU
	base_options.model_asset_buffer = file.get_buffer(file.get_length())
	file.close()

	task = MediaPipeHandLandmarker.new()
	task.initialize(
		base_options,
		MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM,
		4,    # num_hands: track up to 4 hands (2 players x 2 hands)
		0.5,  # min_hand_detection_confidence
		0.5,  # min_hand_presence_confidence
		0.5   # min_tracking_confidence
	)
	task.result_callback.connect(_on_hand_result)

	is_task_ready = true
	_log("HAND TRACKING ACTIVE! Show up to 4 hands.")

func _on_hand_result(result: MediaPipeHandLandmarkerResult, _image: MediaPipeImage, _timestamp_ms: int) -> void:
	_frame_count += 1

	var num_hands := result.hand_landmarks.size()
	if num_hands == 0:
		landmark_canvas.set_landmarks([])
		status_label.text = "No hands detected - show your hands!"
		return

	var info := "Tracking %d hand(s)\n" % num_hands
	for i in range(result.handedness.size()):
		var categories = result.handedness[i].categories
		if categories.size() > 0:
			info += "  %s (%.0f%%)\n" % [categories[0].display_name, categories[0].score * 100]
	status_label.text = info

	landmark_canvas.set_landmarks(result.hand_landmarks)

func _process(delta: float) -> void:
	_fps_timer += delta
	if _fps_timer >= 1.0:
		fps_label.text = "FPS: %d" % _frame_count
		_frame_count = 0
		_fps_timer = 0.0

func _log(msg: String) -> void:
	print("[HandTrack] ", msg)
	status_label.text = msg
