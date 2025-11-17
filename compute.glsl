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
	float click_button;
	float drop_radius;
	float drop_wetness;
	float pigment_drop_radius;
	float pigment_drop_wetness;
	float dry_rate;
	float iteration;
	float hide_fibers;
	float time;
} params;

// Simulation buffers
layout(set = 1, binding = 0, std430) restrict buffer SimDataRead {
    float data[];
} sim_read;

layout(set = 1, binding = 1, std430) restrict buffer SimDataWrite {
    float data[];
} sim_write;

layout(set = 1, binding = 2, std430) restrict buffer SimPigmentRead {
    vec4 data[];
} sim_pigment_read;

layout(set = 1, binding = 3, std430) restrict buffer SimPigmentWrite {
    vec4 data[];
} sim_pigment_write;

layout(set = 1, binding = 4, std430) restrict buffer SimFibers {
    float data[];
} fibers;

layout(set = 1, binding = 5, std430) restrict buffer SimDebug {
    float data[];
} debug;

const float water_limit = 1.0 / 64.0;
const float pigment_limit = 1.0 / 16.0;
const float fast_limit = 1.0 / 4.0;

const int tmp_pigment = 0;

// Unpack and convert the push constant data (which is a Godot PackedFloatArray remapped to GLSL types, conceptually)
int width = int(params.size.x);
int height = int(params.size.y);
int click_x = int(params.click.x);
int click_y = int(params.click.y);
int click_button = int(params.click_button);
int radius = int(params.drop_radius);
int pigment_radius = int(params.pigment_drop_radius);
float drop_wetness = params.drop_wetness / 100.0;
float pigment_drop_wetness = params.pigment_drop_wetness / 100.0;
float dry_amount = params.dry_rate / 100000.0;
bool hide_fibers = params.hide_fibers != 0;

struct exchange {
	vec2 fluid;
	bool along_fiber;
};

float getv(int x, int y) {
    return sim_read.data[width * y + x];
}

void setv(int x, int y, float value) {
    sim_write.data[width * y + x] = value;
}

float getp(int x, int y, int i) {
    vec4 c = sim_pigment_read.data[width * y + x];
	return c[i];
}

void setp(int x, int y, int i, float value) {
    sim_pigment_write.data[width * y + x][i] = value;
}

float getf(int x, int y) {
    return fibers.data[width * y + x];
}

exchange _wick(int from_x, int from_y, int to_x, int to_y, float to_fiber) {
	// prevent anything from happening at margins, where behaviour would be undefined
	if (from_x < 0 || from_y < 0 || from_x >= width || from_y >= height) {
		return exchange(vec2(0, 0), false);
    }

	// diffuse water
	float v = getv(to_x, to_y);
	float o = getv(from_x, from_y);

	// calculate if both cells lie along the same fiber
	float from_fiber = getf(from_x, from_y);
	bool along_fiber = (from_fiber == 1.0 && to_fiber == 1.0);

	// If both cells have dried out, don't diffuse.
	// Note: if dry rate is 0, diffusion will continue outwards, eventually filling the entire space
	// The faster the dry rate is, the faster diffusion will hit the dry boundary and stop, generating a patch.
	if (v != 0.0 || o != 0.0) {
		float diff = o - v;

		float diffp = 0;
		// pigment flows only together with water
		if (abs(diff) >= 0.0) {
			float vp = getp(to_x, to_y, tmp_pigment);
			float op = getp(from_x, from_y, tmp_pigment);
			diffp = op - vp;
		}

		return exchange(vec2(diff, diffp), along_fiber);
    }
	return exchange(vec2(0, 0), along_fiber);
}

vec2 _process_cell(int x, int y) {
	float fiber = getf(x, y);

	float v = getv(x, y);
	exchange n = _wick(x, y - 1, x, y, fiber);
	exchange s = _wick(x, y + 1, x, y, fiber);
	exchange w = _wick(x - 1, y, x, y, fiber);
	exchange e = _wick(x + 1, y, x, y, fiber);

	float delta =
		n.fluid.x * (n.along_fiber ? fast_limit : water_limit) +
		s.fluid.x * (s.along_fiber ? fast_limit : water_limit) +
		w.fluid.x * (w.along_fiber ? fast_limit : water_limit) +
		e.fluid.x * (e.along_fiber ? fast_limit : water_limit) ;

	float p = getp(x, y, tmp_pigment);
	float deltap =
		n.fluid.y * (n.along_fiber ? fast_limit : pigment_limit) +
		s.fluid.y * (s.along_fiber ? fast_limit : pigment_limit) +
		w.fluid.y * (w.along_fiber ? fast_limit : pigment_limit) +
		e.fluid.y * (e.along_fiber ? fast_limit : pigment_limit) ;

	return vec2(v + delta, p + deltap);
}


bool in_circle(int x, int y, int radius) {
  int dx = x - click_x;
  int dy = y - click_y;
  return (dx * dx + dy * dy <= radius * radius);
}

bool in_circle_at(int x, int y, int cx, int cy, int radius) {
  int dx = x - cx;
  int dy = y - cy;
  return (dx * dx + dy * dy <= radius * radius);
}

ivec2 shift_by_angle(ivec2 c, float a, float r) {
	float angle = a * 6.28318530718; // angle in radians, using 2 * PI
    vec2 offset = vec2(cos(angle), sin(angle)) * r;
    return c + ivec2(round(offset)); // round to int
}

void splatter(int x, int y, int click_x, int click_y) {
	const float once_every_n_iterations = 16 * 40;
	const float dist_base = 30;
	const int water_radius = 25;
	const int pigment_radius = 20;
	const float water_content = 0.8;
	const float pigment_content = 1.0;

	float secs = mod(params.iteration, once_every_n_iterations);

	float tri;
	float tr = modf((params.time / 100000), tri);
	debug.data[x + width * y] = tr;

	if (int(secs) == 0) {
		ivec2 tg = shift_by_angle(ivec2(click_x, click_y), tr, dist_base);
		if (in_circle_at(x, y, tg.x, tg.y, water_radius)) {
			setv(x, y, water_content);
		}
		if (in_circle_at(x, y, tg.x, tg.y, pigment_radius)) {
			setp(x, y, tmp_pigment, pigment_content);
		}
	}
}

void main() {
    int x = int(gl_GlobalInvocationID.x);
    int y = int(gl_GlobalInvocationID.y);

    if (x >= width || y >= height) {
        return;
    }

	/* Diffuse the water and pigment */
    vec2 d = _process_cell(x, y);

	float cell = d.x;
	// Dry water as needed.
	cell = max(cell - dry_amount, 0);
    setv(x, y, cell);

	float cellp = d.y;
	setp(x, y, tmp_pigment, cellp);

	splatter(x, y, click_x, click_y);

	/* Process input */
	if (click_x > 0 && click_y > 0) {
		if (in_circle(x, y, radius / 2)) {
			float v = drop_wetness;
			setv(x, y, v);
		}
		if (in_circle(x, y, pigment_radius / 2)) {
			float p = pigment_drop_wetness;
			setp(x, y, tmp_pigment, p);
		}
	}

	if (click_button > 0) {
		if (click_x > 0 && click_y > 0) {
			if (in_circle(x, y, radius) && ((click_button & 1) > 0 || (click_button & 4) > 0)) {
				float v = min(cell + drop_wetness, 1.0);
				setv(x, y, v);
			}

			if (in_circle(x, y, pigment_radius) && ((click_button & 2) > 0 || (click_button & 4) > 0)) {
				float p = max(cellp + pigment_drop_wetness, 1.0);
				setp(x, y, tmp_pigment, p);
			}
		}
	}

    /* Assign the values to the output image texture */
    float c = cell;
	float cp = cellp;
	float f = hide_fibers ? 0.0 : fibers.data[x + y * width];
	vec4 color = vec4(c, cp, f, 1.0);
	ivec2 coord = ivec2(x, y);
    imageStore(out_image, coord, color);
}

