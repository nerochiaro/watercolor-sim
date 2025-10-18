extends Sprite2D
class_name ComputeSprite2D

@export var compute_script: RDShaderFile
@export var texture_size: Vector2i = Vector2i(512, 512)

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var shared_texture: Texture2DRD = Texture2DRD.new()
var shared_texture_rid: RID

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
	RenderingServer.call_on_render_thread(_initialize_compute_code.bind(texture_size))

func _process(_delta: float) -> void:
	RenderingServer.call_on_render_thread(_render_process.bind(texture_size))

func _exit_tree() -> void:
	if shared_texture:
		shared_texture.texture_rd_rid = RID()

	RenderingServer.call_on_render_thread(_free_compute_resources)

###############################################################################
# Everything after this point is designed to run on our rendering thread.

func _initialize_compute_code(init_with_texture_size: Vector2i):
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
	tf.width = init_with_texture_size.x
	tf.height = init_with_texture_size.y
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

func _render_process(tex_size: Vector2i) -> void:
	# Calculate our dispatch group size.
	# We do `(n - 1) / (8 + 1)` in case our texture size is not nicely divisible by 8.
	# In combination with a discard check in the shader this ensures we cover the entire texture.
	@warning_ignore("integer_division")
	var x_groups := (tex_size.x - 1) / 8 + 1
	@warning_ignore("integer_division")
	var y_groups := (tex_size.y - 1) / 8 + 1

	# Build the push constant by adding fields in order and making sure it's
	# padded to multiples of 4 elements of 4bytes each.
	var push_constant := PackedFloat32Array()
	push_constant.push_back(tex_size.x)
	push_constant.push_back(tex_size.y)
	push_constant.push_back(0.0)
	push_constant.push_back(0.0)

	# Pass the shaded texture to the compute shader
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(shared_texture_rid)
	var next_set = rd.uniform_set_create([uniform], shader, 0)

	# Run the compute shader.
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, next_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()

func _free_compute_resources():
	# Note that our sets and pipeline are cleaned up automatically as they are dependencies
	if shared_texture_rid:
		rd.free_rid(shared_texture_rid)

	if shader:
		rd.free_rid(shader)
