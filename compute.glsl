#[compute]
#version 450

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Shared texture for output. Read by fragment shader for rendering.
layout(r32f, set = 0, binding = 0, rgba32f) uniform restrict writeonly image2D out_image;

// Simulation parameters as push constant
layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 click;
} params;

// Simulation buffers
layout(set = 1, binding = 0, std430) restrict buffer SimDataRead {
    int data[];
} sim_read;

layout(set = 1, binding = 1, std430) restrict buffer SimDataWrite {
    int data[];
} sim_write;

layout(set = 1, binding = 2, std430) restrict buffer SimDebug {
    int data[];
} debug;

// Unpack the size and convert to int (as push constant is an array of floats)
int width = int(params.size.x);
int height = int(params.size.y);
int click_x = int(params.click.x);
int click_y = int(params.click.y);

const int int_max = 2147483647;
const int diffusion_limit = 6;
const bool sample_diagonally = true;
const int diagonal_reduction = 2;

int getv(int x, int y) {
    return sim_read.data[width * y + x];
}

void setv(int x, int y, int value) {
    sim_write.data[width * y + x] = value;
}

int _wick(int from_x, int from_y, int to_x, int to_y) {
	if (from_x < 0 || from_y < 0 || from_x >= width || from_y >= height) {
		return 0;
    }

	int v = getv(to_x, to_y);
	int o = getv(from_x, from_y);
	if (v != 0 && o != 0) {
		int diff = o - v;
		if (diff != 0) {
			return diff;
        }
    }
	return 0;
}

int _process_cell(int x, int y) {
	int v = getv(x, y);
	int n = _wick(x, y - 1, x, y) / diffusion_limit;
	int s = _wick(x, y + 1, x, y) / diffusion_limit;
	int w = _wick(x - 1, y, x, y) / diffusion_limit;
	int e = _wick(x + 1, y, x, y) / diffusion_limit;
	int straight = n + s + w + e;

	int diagonal = 0;
	if (sample_diagonally) {
		int ne = (_wick(x + 1, y - 1, x, y) / diffusion_limit) / diagonal_reduction;
		int nw = (_wick(x - 1, y - 1, x, y) / diffusion_limit) / diagonal_reduction;
		int se = (_wick(x + 1, y + 1, x, y) / diffusion_limit) / diagonal_reduction;
		int sw = (_wick(x - 1, y + 1, x, y) / diffusion_limit) / diagonal_reduction;
		diagonal = ne + nw  + se + sw;
	}

	int delta = straight + diagonal;
	debug.data[x + width * y] = delta;
	return v + delta;
}

const int radius = 20;
const int radius_square = radius * radius;

bool in_circle(int x, int y) {
  int dx = x - click_x;
  int dy = y - click_y;
  return (dx * dx + dy * dy <= radius_square);
}

void main() {
    int x = int(gl_GlobalInvocationID.x);
    int y = int(gl_GlobalInvocationID.y);

    if (x >= width || y >= height) {
        return;
    }

    int cell = _process_cell(x, y);
    setv(x, y, cell);

	if (click_x > 0 && click_y > 0 && in_circle(x, y)) {
		setv(x, y, int_max);
	}

    // Assign the value as greyscale to the output image texture
    float c = cell / float(int_max);
	vec4 color = vec4(c, c, c, 1.0);
	ivec2 coord = ivec2(x, y);
    imageStore(out_image, coord, color);
}
