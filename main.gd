extends Node2D

const Int = DiffusionSim.Int
@export var width := 512
@export var height := 512

# The SSBO buffers used for the simulation by the compute shader.
# They are ping pong buffers: one is read from and the other written to, then at each frame they are swapped
var _sim_buffer_front: RID
var _sim_buffer_back: RID
var _debug: RID
func prepare_initial_state() -> PackedInt32Array:
	var _sim := DiffusionSim.SimState.new(width, height)

	# Draw margin
	for i in height:
		if i == 0 or i == height - 1:
			_sim.set_rect(0, i, width, 1, Int.fromf(1.0))
		else:
			_sim.set_rect(0, i, 1, 1, Int.fromf(1.0))
			_sim.set_rect(width - 1, i, 1, 1, Int.fromf(1.0))

	_sim.set_rect(100, 100, 200, 200, Int.fromf(0.2))
	_sim.set_rect(200, 200, 50, 50, Int.fromf(0.9))

	return _sim._data

func _ready():
	RenderingServer.call_on_render_thread(_init_sim)
	RenderingServer.frame_post_draw.connect(on_frame_post_draw)
func on_frame_post_draw():
	_swap_buffers()

func _swap_buffers():
	var swap := _sim_buffer_back
	_sim_buffer_back = _sim_buffer_front
	_sim_buffer_front = swap

func _init_sim():
	var rd = RenderingServer.get_rendering_device()

	var input := prepare_initial_state()
	var input_bytes := input.to_byte_array()
	_sim_buffer_front = rd.storage_buffer_create(input_bytes.size(), input_bytes)
	_sim_buffer_back = rd.storage_buffer_create(input_bytes.size(), input_bytes)

	var debug_data = PackedInt32Array([])
	debug_data.resize(width * height)
	debug_data.fill(0)
	debug_data = debug_data.to_byte_array()
	_debug = rd.storage_buffer_create(debug_data.size(), debug_data)

	%Sim.texture_size = Vector2i(width, height)
	%Sim.create_uniform_set = self._create_uniform_set

	# Setup push constant data for the compute shader.
	# Note that the array must be padded to multiples of 4
	%Sim.push_constant = PackedFloat32Array([width, height, 0.0, 0.0])

# This function is called at each rendering frame, since the compute shader's uniforms need to
# be swapped each frame.
func _create_uniform_set(shader: RID, index: int) -> RID:
	var rd = RenderingServer.get_rendering_device()

	var uniform_front := RDUniform.new()
	uniform_front.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_front.binding = 0
	uniform_front.add_id(_sim_buffer_front)

	var uniform_back := RDUniform.new()
	uniform_back.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_back.binding = 1
	uniform_back.add_id(_sim_buffer_back)

	var uniform_debug := RDUniform.new()
	uniform_debug.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_debug.binding = 2
	uniform_debug.add_id(_debug)

	var uniform_set = rd.uniform_set_create([uniform_front, uniform_back, uniform_debug], shader, index)
	return uniform_set
