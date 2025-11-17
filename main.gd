extends Node2D

var width: int:
	get:
		return %Sim.texture_size.x
var height: int:
	get:
		return %Sim.texture_size.y

var _sim: SimGPU

var _print_frames = 4
var _print_cells = false

var _click_pos := Vector2i.ZERO
var _click_button := MOUSE_BUTTON_NONE
var _movement_speed = 10

var _hide_fibers := true
var _iteration := 0
var _frame := 0

func _ready():
	RenderingServer.call_on_render_thread(_init_sim)
	RenderingServer.frame_post_draw.connect(on_frame_post_draw)
	%Background.texture.width = width
	%Background.texture.height = height

func on_frame_post_draw():
	if _frame < _print_frames:
		if _print_cells:
			var rd = RenderingServer.get_rendering_device()
			var data = rd.buffer_get_data(_sim.buf_water_front)
			var idata = data.to_int32_array()
			prints("================", _frame, _iteration, Time.get_unix_time_from_system())
			for y in min(height, 5):
				var w = min(width, 5)
				var row := idata.slice(y * w, y * w + w)
				print(Array(row).map(func (i): return "%s%1.2f" % [" " if i >= 0 else "", i]))

			var ddata = rd.buffer_get_data(_sim.buf_debug)
			var didata = ddata.to_float32_array()
			prints(" ")
			for y in min(height, 5):
				var w = min(width, 5)
				var row := didata.slice(y * w, y * w + w)
				print(Array(row).map(func (i): return "%s%1.4f" % [" " if i >= 0 else "", i]))
	_frame += 1

func _init_sim():
	var rd = RenderingServer.get_rendering_device()

	_sim = SimGPU.new(width, height)
	_sim.create_buffers(rd)

	%Sim.texture_size = Vector2i(width, height)
	%Sim.create_uniform_set = func (shader: RID, index: int):
		_sim.create_uniforms(rd, shader, index)
	%Sim.update_uniform_set = func (_shader: RID, _index: int) -> RID:
		return _sim.get_current_uniform_set()
	%Sim.update_push_constant = func () -> PackedFloat32Array:
		var pc = PackedFloat32Array([
			width,
			height,
			_click_pos.x,
			_click_pos.y,
			_click_button,
			%UI.drop_size,
			%UI.drop_wetness,
			%UI.pigment_drop_size,
			%UI.pigment_drop_wetness,
			%UI.dry_rate,
			_iteration,
			_hide_fibers,
			float(Time.get_ticks_usec()),
			0.0,
			0.0,
			0.0
		])
		#_click_pos = Vector2i.ZERO
		_click_button = MOUSE_BUTTON_NONE
		_iteration += 1
		return pc

func _unhandled_input(event: InputEvent) -> void:
	#if event is InputEventMouseMotion:
		#if event.button_mask > 0:
			#_click_pos = event.position
			#_click_button = event.button_mask
	if event is InputEventMouseButton:
		if event.pressed:
			#_click_pos = event.position
			_click_button = event.button_mask
	if event is InputEventKey:
		if event.keycode == Key.KEY_A:
			_hide_fibers = true
		elif event.keycode == Key.KEY_S:
			_hide_fibers = false
		
		if event.pressed:
			print(event)
			if event.keycode == Key.KEY_LEFT:
				_click_pos += Vector2i(-1 * _movement_speed, 0)
			elif event.keycode == Key.KEY_RIGHT:
				_click_pos += Vector2i(+1 * _movement_speed, 0)
			elif event.keycode == Key.KEY_UP:
				_click_pos += Vector2i(0, -1 * _movement_speed)
			elif event.keycode == Key.KEY_DOWN:
				_click_pos += Vector2i(0, +1 * _movement_speed)
			_click_pos = _click_pos.clampi(0, width)
