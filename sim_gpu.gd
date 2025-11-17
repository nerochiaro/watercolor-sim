extends Object
class_name SimGPU

@export var width: int
@export var height: int
@export var fiber_count: int 

class PingPongUniformSet:
	var uni_water_front: RDUniform
	var uni_water_back: RDUniform
	var uni_pigment_front: RDUniform
	var uni_pigment_back: RDUniform
	var uniform_set: RID
	
	func _init(rd: RenderingDevice, shader: RID, index: int,
			   buf_water_front: RID, buf_water_back: RID,
			   buf_pigment_front: RID, buf_pigment_back: RID,
			   uni_fibers: RDUniform, uni_debug: RDUniform,
			   swapped: bool):
		uni_water_front = RDUniform.new()
		uni_water_front.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uni_water_front.binding = 0 if not swapped else 1
		uni_water_front.add_id(buf_water_front)
		
		uni_water_back = RDUniform.new()
		uni_water_back.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uni_water_back.binding = 1 if not swapped else 0
		uni_water_back.add_id(buf_water_back)
		
		uni_pigment_front = RDUniform.new()
		uni_pigment_front.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uni_pigment_front.binding = 2 if not swapped else 3
		uni_pigment_front.add_id(buf_pigment_front)
		
		uni_pigment_back = RDUniform.new()
		uni_pigment_back.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uni_pigment_back.binding = 3 if not swapped else 2
		uni_pigment_back.add_id(buf_pigment_back)
		
		uniform_set = rd.uniform_set_create([
			uni_water_front if not swapped else uni_water_back,
			uni_water_back if not swapped else uni_water_front,
			uni_pigment_front if not swapped else uni_pigment_back,
			uni_pigment_back if not swapped else uni_pigment_front,
			uni_fibers,
			uni_debug
		], shader, index)


# The SSBO buffers used for the simulation by the compute shader.
# They are ping pong buffers: one is read from and the other written to, then at each frame they are swapped
var buf_water_front: RID
var buf_water_back: RID
var buf_pigment_front: RID
var buf_pigment_back: RID
var buf_fibers: RID
var buf_debug: RID

var uni_fibers: RDUniform
var uni_debug: RDUniform
var uni_ping_pong: Array[PingPongUniformSet] = []

var _front_first: bool = true

func _init(w: int, h: int, fibers: int):
	width = w
	height = h
	fiber_count = fibers

func _prepare_fibers() -> PackedFloat32Array:
	var fibers = PackedFloat32Array()
	fibers.resize(width * height)
	fibers.fill(0.0)
	for i in fiber_count:
		var from = Vector2i(randi() % width, randi() % height)
		var to = Vector2i(randi() % width, randi() % height)
		var line = Geometry2D.bresenham_line(from, to)
		for p in line:
			fibers[p.x + width * p.y] = 1.0
	return fibers

# Call on rendering thread only
func create_buffers(rd: RenderingDevice):
	var input := PackedFloat32Array()
	input.resize(width * height)
	input.fill(0.0)
	var input_bytes := input.to_byte_array()
	buf_water_front = rd.storage_buffer_create(input_bytes.size(), input_bytes)
	buf_water_back = rd.storage_buffer_create(input_bytes.size(), input_bytes)

	var empty: PackedVector4Array = []
	empty.resize(width * height)
	empty.fill(Vector4.ZERO)
	var empty_bytes := empty.to_byte_array()

	buf_pigment_front = rd.storage_buffer_create(empty_bytes.size(), empty_bytes)
	buf_pigment_back = rd.storage_buffer_create(empty_bytes.size(), empty_bytes)

	var fibers = _prepare_fibers()
	var fiber_bytes = PackedByteArray()
	fiber_bytes.resize(4 * fibers.size())
	for i in fibers.size():
		fiber_bytes.encode_float(i * 4, fibers[i])
	buf_fibers = rd.storage_buffer_create(fiber_bytes.size(), fiber_bytes)
	
	var debug_data = PackedFloat32Array([])
	debug_data.resize(width * height)
	debug_data.fill(0.0)
	debug_data = debug_data.to_byte_array()
	buf_debug = rd.storage_buffer_create(debug_data.size(), debug_data)

func create_uniforms(rd: RenderingDevice, shader: RID, index: int):
	uni_fibers = RDUniform.new()
	uni_fibers.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uni_fibers.binding = 4
	uni_fibers.add_id(buf_fibers)
	
	uni_debug = RDUniform.new()
	uni_debug.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uni_debug.binding = 5
	uni_debug.add_id(buf_debug)

	uni_ping_pong.append(PingPongUniformSet.new(
		rd, shader, index,
		buf_water_front, buf_water_back,
		buf_pigment_front, buf_pigment_back,
		uni_fibers, uni_debug,
		false
	))
	uni_ping_pong.append(PingPongUniformSet.new(
		rd, shader, index,
		buf_water_front, buf_water_back,
		buf_pigment_front, buf_pigment_back,
		uni_fibers, uni_debug,
		true
	))

func get_current_uniform_set() -> RID:
	var index = 0 if _front_first else 1
	_front_first = not _front_first
	return uni_ping_pong[index].uniform_set
