class_name MediaPipeBackend
extends Node
## Connects GDMP's MediaPipeHandLandmarker to AIInput.
## Manages camera setup, model loading, and frame processing.

signal backend_ready
signal backend_error(message: String)

var task: MediaPipeHandLandmarker
var camera_feed: CameraFeed
var camera_extension: CameraServerExtension
var ai_input: Node  # Reference to AIInput singleton

var _is_ready := false
var _camera_viewport: SubViewport
var _camera_texture_rect: TextureRect

const MODEL_PATH := "hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"
const MODEL_CACHE := "user://hand_landmarker.task"

func initialize(p_ai_input: Node, p_viewport: SubViewport, p_texture_rect: TextureRect) -> void:
	ai_input = p_ai_input
	_camera_viewport = p_viewport
	_camera_texture_rect = p_texture_rect

	# Setup camera
	CameraServer.camera_feed_added.connect(_on_feed_added)
	CameraServer.camera_feeds_updated.connect(_on_feeds_updated)

	if OS.get_name() == "Windows":
		_log("Windows detected, creating CameraServerExtension")
		camera_extension = CameraServerExtension.new()
		camera_extension.permission_result.connect(_on_permission)
		if camera_extension.permission_granted():
			_log("Permission already granted")
			_start_monitoring()
		else:
			_log("Requesting camera permission")
			camera_extension.request_permission()
	else:
		_start_monitoring()

func _start_monitoring() -> void:
	_log("Starting feed monitoring")
	CameraServer.monitoring_feeds = true
	_delayed_check()

func _delayed_check() -> void:
	await Engine.get_main_loop().create_timer(1.0).timeout
	_try_open_camera()

func _on_permission(granted: bool) -> void:
	if granted:
		_log("Permission granted")
		_start_monitoring()
	else:
		backend_error.emit("Camera permission denied")

func _on_feed_added(_id: int) -> void:
	_log("Feed added: %d" % _id)
	if CameraServer.monitoring_feeds:
		_try_open_camera()

func _on_feeds_updated() -> void:
	if CameraServer.monitoring_feeds:
		_try_open_camera()

func _try_open_camera() -> void:
	if camera_feed != null:
		return

	var feeds := CameraServer.feeds()
	_log("Available feeds: %d" % feeds.size())
	if feeds.is_empty():
		return

	# Prefer external webcam
	camera_feed = feeds[0]
	for f in feeds:
		var fname: String = f.get_name()
		if "NexiGO" in fname or "USB" in fname or "Webcam" in fname:
			camera_feed = f
			break

	_log("Using feed: '%s' (id=%d)" % [camera_feed.get_name(), camera_feed.get_id()])

	var formats = camera_feed.get_formats()
	_log("Formats available: %d" % formats.size())
	if formats.size() > 0:
		camera_feed.set_format(0, {})

	# Connect signals
	camera_feed.format_changed.connect(_on_format_changed, ConnectFlags.CONNECT_DEFERRED)
	camera_feed.frame_changed.connect(_on_frame_changed, ConnectFlags.CONNECT_DEFERRED)

	# Mirror for front camera
	if camera_feed.get_position() != CameraFeed.FEED_BACK:
		_camera_texture_rect.flip_h = true

	# Activate
	camera_feed.feed_is_active = true
	_log("Feed activated, datatype=%d" % camera_feed.get_datatype())
	_on_format_changed()

	# Load ML model
	_load_model()

func _on_format_changed() -> void:
	if camera_feed == null:
		return

	var frame_size := Vector2i.ZERO
	var datatype: int = camera_feed.get_datatype()
	_log("Format changed, datatype=%d" % datatype)

	match datatype:
		CameraFeed.FEED_RGB:
			_log("Camera format: RGB")
			var tex := CameraTexture.new()
			tex.camera_feed_id = camera_feed.get_id()
			tex.which_feed = CameraServer.FEED_RGBA_IMAGE
			frame_size = tex.get_size()
			_camera_texture_rect.material = null
			_camera_texture_rect.texture = tex

		CameraFeed.FEED_YCBCR:
			_log("Camera format: YCbCr (YUY2)")
			var tex_yuy2 := CameraTexture.new()
			tex_yuy2.camera_feed_id = camera_feed.get_id()
			tex_yuy2.which_feed = CameraServer.FEED_YCBCR_IMAGE
			frame_size = tex_yuy2.get_size()
			var mat := ShaderMaterial.new()
			mat.shader = load("res://addon/camera_intelligence/yuy2_to_rgb.gdshader")
			mat.set_shader_parameter("texture_yuy2", tex_yuy2)
			_camera_texture_rect.material = mat
			var image := Image.create_empty(frame_size.x, frame_size.y, false, Image.FORMAT_RGB8)
			_camera_texture_rect.texture = ImageTexture.create_from_image(image)

		CameraFeed.FEED_YCBCR_SEP:
			_log("Camera format: YCbCr Separated (YUV420)")
			var tex_y := CameraTexture.new()
			var tex_uv := CameraTexture.new()
			tex_y.camera_feed_id = camera_feed.get_id()
			tex_uv.camera_feed_id = camera_feed.get_id()
			tex_y.which_feed = CameraServer.FEED_Y_IMAGE
			tex_uv.which_feed = CameraServer.FEED_CBCR_IMAGE
			frame_size = tex_y.get_size()
			var mat := ShaderMaterial.new()
			mat.shader = load("res://addon/camera_intelligence/yuv420_to_rgb.gdshader")
			mat.set_shader_parameter("texture_y", tex_y)
			mat.set_shader_parameter("texture_uv", tex_uv)
			_camera_texture_rect.material = mat
			var image := Image.create_empty(frame_size.x, frame_size.y, false, Image.FORMAT_RGB8)
			_camera_texture_rect.texture = ImageTexture.create_from_image(image)

		_:
			_log("WARNING: Unknown camera datatype: %d" % datatype)
			return

	if frame_size == Vector2i.ZERO:
		frame_size = Vector2i(640, 480)
	_log("Frame size: %s" % str(frame_size))
	_camera_viewport.size = frame_size

func _on_frame_changed() -> void:
	if not _is_ready:
		return

	await RenderingServer.frame_post_draw

	if _camera_viewport == null:
		return
	var texture := _camera_viewport.get_texture()
	if texture == null:
		return
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return

	image.convert(Image.FORMAT_RGB8)
	var mp_image := MediaPipeImage.new()
	mp_image.set_image(image)
	task.detect_async(mp_image, Time.get_ticks_msec())

func _load_model() -> void:
	if FileAccess.file_exists(MODEL_CACHE):
		_log("Loading cached model")
		_init_task(MODEL_CACHE)
		return

	_log("Downloading model...")
	var url := "https://storage.googleapis.com/mediapipe-models/" + MODEL_PATH
	var http := HTTPRequest.new()
	http.download_file = MODEL_CACHE
	add_child(http)
	http.request_completed.connect(_on_model_downloaded.bind(http))
	http.request(url)

func _on_model_downloaded(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		backend_error.emit("Model download failed: %d/%d" % [result, response_code])
		return
	_log("Model downloaded")
	_init_task(MODEL_CACHE)

func _init_task(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		backend_error.emit("Cannot open model file")
		return

	var base_options := MediaPipeTaskBaseOptions.new()
	base_options.delegate = MediaPipeTaskBaseOptions.DELEGATE_CPU
	base_options.model_asset_buffer = file.get_buffer(file.get_length())
	file.close()

	task = MediaPipeHandLandmarker.new()
	task.initialize(
		base_options,
		MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM,
		ai_input.max_hands,
		0.5, 0.5, 0.5
	)
	task.result_callback.connect(_on_result)

	_is_ready = true
	_log("Hand tracking ready!")
	backend_ready.emit()

func _on_result(result: MediaPipeHandLandmarkerResult, _image: MediaPipeImage, timestamp_ms: int) -> void:
	ai_input.process_hand_result(
		result.hand_landmarks,
		result.handedness,
		timestamp_ms
	)

func get_camera_viewport() -> SubViewport:
	return _camera_viewport

func _log(msg: String) -> void:
	print("[MediaPipeBackend] ", msg)
