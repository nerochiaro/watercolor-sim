#[compute]
#version 450

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Our texture
layout(r32f, set = 0, binding = 0, rgba32f) uniform restrict writeonly image2D out_image;

// Our push PushConstant.
layout(push_constant, std430) uniform Params {
	vec2 texture_size;
} params;

// // A binding to the buffer we create in our script
// layout(set = 0, binding = 0, std430) restrict buffer WetnessBuffer {
//     int data[];
// } wet;

void main() {
    int y = int(gl_GlobalInvocationID.y);
    int x = int(gl_GlobalInvocationID.x);

	vec4 color = vec4(0.0, 1.0, 0.0, 1.0);
	ivec2 coord = ivec2(x, y);
    imageStore(out_image, coord, color);
}
