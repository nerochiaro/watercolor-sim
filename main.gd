extends Node2D

const Int = DiffusionSim.Int
@export var width := 512
@export var height := 512

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
	%Sim.texture_size = Vector2i(width, height)
	%Sim.create_uniform_set = self._create_uniform_set

	# Setup push constant data for the compute shader.
	# Note that the array must be padded to multiples of 4
	%Sim.push_constant = PackedFloat32Array([width, height, 0.0, 0.0])

func _create_uniform_set(shader: RID, index: int) -> RID:
	var rd = RenderingServer.get_rendering_device()

	var input := prepare_initial_state()
	var input_bytes := input.to_byte_array()
	var buffer := rd.storage_buffer_create(input_bytes.size(), input_bytes)

	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0 # this needs to match the "binding" in the shader file
	uniform.add_id(buffer)
	
	var uniform_set = rd.uniform_set_create([uniform], shader, index)
	return uniform_set
