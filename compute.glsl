#[compute]
#version 450

/****************** DO NOT CHANGE FROM HERE *********************/

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Shared texture for output. Read by fragment shader for rendering.
layout(r32f, set = 0, binding = 0, rgba32f) uniform restrict writeonly image2D out_image;

/****************** DO NOT CHANGE TO HERE *********************/

// Simulation parameters as push constant
layout(push_constant, std430) uniform Params {
	vec2 size;
} params;

// Simulation buffer for wetness level
layout(set = 1, binding = 0, std430) restrict buffer WetnessBuffer {
    int data[];
} wet;

// Unpack the size and convert to int (as push constant is an array of floats)
int width = int(params.size.x);
int height = int(params.size.y);

const int diffusion_limit = 268435456;
const int _diagonal_reduction = 1518500249;
const int int_max = 2147483647;

int getv(int x, int y) {
    return wet.data[width * y + x];
}

void setv(int x, int y, int value) {
    wet.data[width * y + x] = value;
}

void main() {
    int x = int(gl_GlobalInvocationID.x);
    int y = int(gl_GlobalInvocationID.y);

    int cell = getv(x, y);
    float c = cell / float(int_max);

	vec4 color = vec4(c, c, c, 1.0);
	ivec2 coord = ivec2(x, y);
    imageStore(out_image, coord, color);
}
