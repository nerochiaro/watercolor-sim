extends Node2D

class Int:
	static func tof(value: int) -> float:
		return remap(value, 0, Int.MAX, 0.0, 1.0)

	static func fromf(value: float) -> int:
		return roundi(remap(value, 0.0, 1.0, 0.0, Int.MAX))

	const MAX = Vector3i.MAX.x;

class SimState:
	var _data: PackedInt32Array
	var width: int
	var height: int

	func _init(_width: int, _height: int):
		width = _width
		height = _height
		_data.resize(width * height)
		_data.fill(0)

	func getv(x: int, y: int) -> int:
		return _data[width * y + x]

	func setv(x: int, y: int, value: int):
		_data[width * y + x] = value

	func set_rect(x: int, y: int, w: int, h: int, value: int):
		for _y in range(y, y + h):
			for _x in range(x, x + w):
				setv(_x, _y, value)

	func clone() -> SimState:
		var cloned = SimState.new(width, height)
		cloned._data = self._data.duplicate()
		return cloned

@export var width := 512
@export var height := 512
var _drop_size: int = 20
var _drop_wetness: float = 80.0
var _dry_rate: float = 4.0

# The SSBO buffers used for the simulation by the compute shader.
# They are ping pong buffers: one is read from and the other written to, then at each frame they are swapped
var _sim_buffer_front: RID
var _sim_buffer_back: RID
var _sim_pigment_front: RID
var _sim_pigment_back: RID
var _front_first = true

var _debug: RID
var _print_iterations = 6
var _print_cells = true

var _click_pos := Vector2i.ZERO
var _click_button := MOUSE_BUTTON_NONE
var _iteration := 0

func prepare_initial_state() -> PackedInt32Array:
	var _sim := SimState.new(width, height)

	# Draw margin
	for i in height:
		if i == 0 or i == height - 1:
			_sim.set_rect(0, i, width, 1, Int.fromf(0.0))
		else:
			_sim.set_rect(0, i, 1, 1, Int.fromf(0.0))
			_sim.set_rect(width - 1, i, 1, 1, Int.fromf(0.0))

	#_sim.set_rect(1, 1, 3, 3, Int.fromf(0.2))
	#_sim.set_rect(2, 2, 1, 1, Int.fromf(0.9))

	_sim.set_rect(100, 100, 300, 300, Int.fromf(0.2))
	_sim.set_rect(200, 200, 100, 100, Int.fromf(0.9))

	return _sim._data

func _ready():
	RenderingServer.call_on_render_thread(_init_sim)
	RenderingServer.frame_post_draw.connect(on_frame_post_draw)
	%UI.drop_size_changed.connect(func (value: float): _drop_size = int(value))
	%UI.drop_wetness_changed.connect(func (value: float): _drop_wetness = value)
	%UI.dry_rate_changed.connect(func (value: float): _dry_rate = value)

func on_frame_post_draw():
	if _iteration < _print_iterations:
		if _print_cells:
			var rd = RenderingServer.get_rendering_device()
			var data = rd.buffer_get_data(_sim_buffer_front)
			var idata = data.to_int32_array()
			prints("================", _iteration, data.size())
			for y in min(height, 5):
				var w = min(width, 5)
				var row := idata.slice(y * w, y * w + w)
				print(Array(row).map(func (i): return "%s%1.2f" % [" " if i >= 0 else "", Int.tof(i)]))
				#print(Array(row).map(func (i): return "%s%10d" % [" " if i >= 0 else "", i]))

			var ddata = rd.buffer_get_data(_debug)
			var didata = ddata.to_int32_array()
			prints(" ")
			for y in min(height, 5):
				var w = min(width, 5)
				var row := didata.slice(y * w, y * w + w)
				#print(Array(row).map(func (i): return "%s%1.2f" % [" " if i >= 0 else "", Int.tof(i)]))
				print(Array(row).map(func (i): return "%s%10d" % [" " if i >= 0 else "", i]))
	_iteration += 1

func _init_sim():
	var rd = RenderingServer.get_rendering_device()

	var input := prepare_initial_state()
	var input_bytes := input.to_byte_array()
	_sim_buffer_front = rd.storage_buffer_create(input_bytes.size(), input_bytes)
	_sim_buffer_back = rd.storage_buffer_create(input_bytes.size(), input_bytes)

	var empty: Array[Vector4i] = []
	empty.resize(width * height)
	empty.fill(Vector4i.ZERO)

	var empty_bytes = PackedByteArray()
	empty_bytes.resize(16 * empty.size())
	for j in empty.size():
		var i = empty[j]
		empty_bytes.encode_s32(j * 16 + 0, i.x)
		empty_bytes.encode_s32(j * 16 + 4, i.y)
		empty_bytes.encode_s32(j * 16 + 8, i.z)
		empty_bytes.encode_s32(j * 16 + 12, i.w)

	_sim_pigment_front = rd.storage_buffer_create(empty_bytes.size(), empty_bytes)
	_sim_pigment_back = rd.storage_buffer_create(empty_bytes.size(), empty_bytes)

	var debug_data = PackedInt32Array([])
	debug_data.resize(width * height)
	debug_data.fill(0)
	debug_data = debug_data.to_byte_array()
	_debug = rd.storage_buffer_create(debug_data.size(), debug_data)

	%Sim.texture_size = Vector2i(width, height)
	%Sim.create_uniform_set = self._create_uniform_set
	%Sim.create_push_constant = self._create_push_constant

# This function is called at each rendering frame, since the compute shader's uniforms need to
# be swapped each frame.
func _create_uniform_set(shader: RID, index: int) -> RID:
	var rd = RenderingServer.get_rendering_device()

	var uniform_front := RDUniform.new()
	uniform_front.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_front.binding = 0
	uniform_front.add_id(_sim_buffer_front if _front_first else _sim_buffer_back)

	var uniform_back := RDUniform.new()
	uniform_back.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_back.binding = 1
	uniform_back.add_id(_sim_buffer_back if _front_first else _sim_buffer_front)

	var uniform_pigment_front := RDUniform.new()
	uniform_pigment_front.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_pigment_front.binding = 2
	uniform_pigment_front.add_id(_sim_pigment_front if _front_first else _sim_pigment_back)

	var uniform_pigment_back := RDUniform.new()
	uniform_pigment_back.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_pigment_back.binding = 3
	uniform_pigment_back.add_id(_sim_pigment_back if _front_first else _sim_pigment_front)

	_front_first = not _front_first

	var uniform_debug := RDUniform.new()
	uniform_debug.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_debug.binding = 4
	uniform_debug.add_id(_debug)

	var uniform_set = rd.uniform_set_create([
			uniform_front, uniform_back,
			uniform_pigment_front, uniform_pigment_back,
			uniform_debug
		], shader, index)
	return uniform_set

func _create_push_constant() -> PackedFloat32Array:
	var pc = PackedFloat32Array([
		width,
		height,
		_click_pos.x,
		_click_pos.y,
		_click_button,
		_drop_size,
		_drop_wetness,
		_dry_rate,
		_iteration,
		0,
		0,
		0
	])
	_click_pos = Vector2i.ZERO
	_click_button = MOUSE_BUTTON_NONE
	_iteration += 1
	return pc

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_click_pos = event.position
				_click_button = event.button_index
