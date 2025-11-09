extends Sprite2D
class_name ComputeSprite2D

@export var compute_script: RDShaderFile
@export var texture_size: Vector2i = Vector2i(512, 512)
@export var iterations_per_frame: int = 4
@export var group_size: int = 16;

## If a [@class Callable] is passed, it will be called on the rendering thread
## before the first compute iteration.
## It should create an additional uniform set to match additional data
## needed by your compute shader.
## 
## The Callable should have this signature:
## [code]func _name(shader: RID, int index) -> void[/code]
## 
## It should create a uniform set (for shader and index) on the main
## `[@class RenderingDevice] (i.e. using [@method RenderingServer.get_rendering_device])
@export var create_uniform_set: Callable

## If a [@class Callable] is passed, it will be called on the rendering thread
## for each compute iteration (of which there can be multiple per frame).
##
## The Callable should have this signature:
## [code]func _name(shader: RID, int index) -> void[/code]
##
## It should return the uniform set (for shader and index) created by
## [@method create_uniform_set] (and potentially updated as needed for this iteration).
@export var update_uniform_set: Callable

## Same as [@method update_uniform_set] but for the push constant
## The Callable should have this signature:
## [code]func _name() -> PackedFloat32Array[/code]
##
## The byte array should match the data declared in the shader's push constant declaration,
## padded to multiples of 4 elements.
@export var update_push_constant: Callable

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var shared_texture: Texture2DRD = Texture2DRD.new()
var shared_texture_rid: RID
var extra_uniform_set_initialized: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# The sprite node takes its size from its "main" texture (not any of the ones assigned to shader uniforms)
	# So assign an empty image texture of the right size as a placeholder to allow the node size to initialize.
	var image = Image.create_empty(texture_size.x, texture_size.y, false, Image.FORMAT_RGBAF)
	self.texture = ImageTexture.create_from_image(image)

	if self.material:
		# This Texture2DRD for now is just an empty reference to a rendering device texture.
		# Later we will assign to it the RID of an actual texture shared with the compute shader.
		self.material.set_shader_parameter(&"effect_texture_size", texture_size)
		self.material.set_shader_parameter(&"effect_texture", shared_texture)

	# Compute shader initialization needs to happen on the rendering thread
	RenderingServer.call_on_render_thread(_initialize_compute_code)

func _process(_delta: float) -> void:
	RenderingServer.call_on_render_thread(_render_process)

func _exit_tree() -> void:
	if shared_texture:
		shared_texture.texture_rd_rid = RID()

	RenderingServer.call_on_render_thread(_free_compute_resources)

###############################################################################
# Everything after this point is designed to run on our rendering thread.

func _initialize_compute_code():
	# As this becomes part of our normal frame rendering,
	# we use our main rendering device here.
	rd = RenderingServer.get_rendering_device()

	# Create our shader.
	var shader_spirv: RDShaderSPIRV = compute_script.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

	# Create our texture to manage our sim.
	var tf: RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = texture_size.x
	tf.height = texture_size.y
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT |
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		)

	# Create the shared texture in the rendering device, which returns its RID.
	# Then make shared_texture point to this RID.
	shared_texture_rid = rd.texture_create(tf, RDTextureView.new(), [])
	if shared_texture:
		shared_texture.texture_rd_rid = shared_texture_rid

	# Clear the shared texture to prevent it from starting with garbage in it.
	rd.texture_clear(shared_texture_rid, Color(0, 0, 0.0, 0.0), 0, 1, 0, 1)

func _render_process() -> void:
	# Calculate our dispatch group size.
	# We do `(n - 1) / (8 + 1)` in case our texture size is not nicely divisible by 8.
	# In combination with a discard check in the shader this ensures we cover the entire texture.
	@warning_ignore("integer_division")
	var x_groups := (texture_size.x - 1) / group_size + 1
	@warning_ignore("integer_division")
	var y_groups := (texture_size.y - 1) / group_size + 1

	# Pass the shared texture to the compute shader
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(shared_texture_rid)
	var uniform_set = rd.uniform_set_create([uniform], shader, 0)

	# Call the user-defined function to initialize the extra uniform set for the
	# shader.
	if not extra_uniform_set_initialized and create_uniform_set != null:
		create_uniform_set.call(shader, 1)
		extra_uniform_set_initialized = true

	# Run the compute shader.
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)

	for i in iterations_per_frame:
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

		if update_uniform_set:
			var extra_uniform_set = update_uniform_set.call(shader, 1)
			rd.compute_list_bind_uniform_set(compute_list, extra_uniform_set, 1)

		if update_push_constant:
			var push_constant = update_push_constant.call()
			rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)

		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)

	rd.compute_list_end()

func _free_compute_resources():
	# Note that our sets and pipeline are cleaned up automatically as they are dependencies
	if shared_texture_rid:
		rd.free_rid(shared_texture_rid)

	if shader:
		rd.free_rid(shader)
