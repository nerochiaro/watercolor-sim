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
    int data[];
} sim_read;

layout(set = 1, binding = 1, std430) restrict buffer SimDataWrite {
    int data[];
} sim_write;

layout(set = 1, binding = 2, std430) restrict buffer SimPigmentRead {
    ivec4 data[];
} sim_pigment_read;

layout(set = 1, binding = 3, std430) restrict buffer SimPigmentWrite {
    ivec4 data[];
} sim_pigment_write;

layout(set = 1, binding = 4, std430) restrict buffer SimFibers {
    float data[];
} fibers;

layout(set = 1, binding = 5, std430) restrict buffer SimDebug {
    float data[];
} debug;

const int int_max = 2147483647;

const int water_limit = 64;
const int pigment_limit = 16;
const int fast_limit = 4;


const bool sample_diagonally = true;
const int diagonal_reduction = 2;
const int tmp_pigment = 0;

// Unpack and convert the push constant data (which is a Godot PackedFloatArray remapped to GLSL types, conceptually)
int width = int(params.size.x);
int height = int(params.size.y);
int click_x = int(params.click.x);
int click_y = int(params.click.y);
int click_button = int(params.click_button);
int radius = int(params.drop_radius);
int pigment_radius = int(params.pigment_drop_radius);
int drop_wetness = int(int_max * (params.drop_wetness / 100.0));
int pigment_drop_wetness = int(int_max * (params.pigment_drop_wetness / 100.0));
int dry_amount = int(float(int_max) * (params.dry_rate / 100000.0));
bool hide_fibers = params.hide_fibers != 0;

struct exchange {
	ivec2 fluid;
	bool along_fiber;
};

int getv(int x, int y) {
    return sim_read.data[width * y + x];
}

void setv(int x, int y, int value) {
    sim_write.data[width * y + x] = value;
}

int getp(int x, int y, int i) {
    ivec4 c = sim_pigment_read.data[width * y + x];
	return c[i];
}

void setp(int x, int y, int i, int value) {
    sim_pigment_write.data[width * y + x][i] = value;
}

float getf(int x, int y) {
    return fibers.data[width * y + x];
}

float psrdnoise(vec2 x, vec2 period, float alpha, out vec2 gradient);
const float breakthrough_threshold = 0.2 * 2.0; // compared with a value in range [0.0, 2.0]
const float noise_scale = 2.8;
float rand(int x, int y) {
	vec2 g; // this is unused, and passed to the last (out) parameter, so the psrdnoise will not calculate it at all
	float t = noise_scale;
	float a = mod(params.time * 10000, 64) * (1.0 / 64.0);
	float noise_v = psrdnoise(vec2(x, y) / t, vec2(0.0, 0.0), a, g);
	float noise_scaled = (noise_v + 1.0) / 2.0;
	debug.data[x + width * y] = noise_scaled;
	return noise_scaled;  // rescale in [0.0, 1.0] range from [-1.0, 1.0] range
}

exchange _wick(int from_x, int from_y, int to_x, int to_y, float to_fiber) {
	// prevent anything from happening at margins, where behaviour would be undefined
	if (from_x < 0 || from_y < 0 || from_x >= width || from_y >= height) {
		return exchange(ivec2(0, 0), false);
    }

	// diffuse water
	int v = getv(to_x, to_y);
	int o = getv(from_x, from_y);

	// calculate if both cells lie along the same fiber
	float from_fiber = getf(from_x, from_y);
	bool along_fiber = (from_fiber == 1.0 && to_fiber == 1.0);

	// Normally water is blocked when reaching a completely dry cell.
	// However there is a random chance for it to "break through" the barrier.
	bool breakthrough = false;
	if (v != 0 || o != 0) {
		vec2 g;
		float noise_v = rand(to_x, to_y);
		float noise_o = rand(from_x, from_y);
		float fiber_adjust = float(along_fiber) * 1.0;

		if (noise_o + noise_v + fiber_adjust > breakthrough_threshold) {
			breakthrough = true;
		}
	}

	// Don't diffuse water past dry cells unless breakthrough happened
	if ((v != 0 && o != 0) || breakthrough) {
		int diff = o - v;

		int diffp = 0;
		// pigment flows only together with water
		if (abs(diff) >= 0.0) {
			int vp = getp(to_x, to_y, tmp_pigment);
			int op = getp(from_x, from_y, tmp_pigment);
			diffp = op - vp;
		}

		return exchange(ivec2(diff, diffp), along_fiber);
    }
	return exchange(ivec2(0, 0), false);
}

ivec2 _process_cell(int x, int y) {
	float fiber = getf(x, y);

	int v = getv(x, y);
	exchange n = _wick(x, y - 1, x, y, fiber);
	exchange s = _wick(x, y + 1, x, y, fiber);
	exchange w = _wick(x - 1, y, x, y, fiber);
	exchange e = _wick(x + 1, y, x, y, fiber);

	int delta =
		n.fluid.x / (n.along_fiber ? fast_limit : water_limit) +
		s.fluid.x / (s.along_fiber ? fast_limit : water_limit) +
		w.fluid.x / (w.along_fiber ? fast_limit : water_limit) +
		e.fluid.x / (e.along_fiber ? fast_limit : water_limit) ;

	int p = getp(x, y, tmp_pigment);
	int deltap =
		n.fluid.y / (n.along_fiber ? fast_limit : pigment_limit) +
		s.fluid.y / (s.along_fiber ? fast_limit : pigment_limit) +
		w.fluid.y / (w.along_fiber ? fast_limit : pigment_limit) +
		e.fluid.y / (e.along_fiber ? fast_limit : pigment_limit) ;

	return ivec2(v + delta, p + deltap);
}


bool in_circle(int x, int y, int radius) {
  int dx = x - click_x;
  int dy = y - click_y;
  return (dx * dx + dy * dy <= radius * radius);
}

const int trace_pigment_limit = int(int_max * (25 / 100.0));

void main() {
    int x = int(gl_GlobalInvocationID.x);
    int y = int(gl_GlobalInvocationID.y);

    if (x >= width || y >= height) {
        return;
    }

	/* Diffuse the water and pigment */
    ivec2 d = _process_cell(x, y);

	int cell = d.x;
	// Dry water as needed.
	cell = int(max(cell - dry_amount, 0));
    setv(x, y, cell);

	int cellp = d.y;
	//if (cell == 0 && cellp < trace_pigment_limit && getf(x, y) != 1.0) cellp = 0;
	setp(x, y, tmp_pigment, cellp);


	/* Process input */
	if (click_x > 0 && click_y > 0) {
		if (in_circle(x, y, radius / 2)) {
			int v = drop_wetness;
			setv(x, y, v);
		}
		if (in_circle(x, y, pigment_radius / 2)) {
			int p = pigment_drop_wetness;
			setp(x, y, tmp_pigment, p);
		}
	}

	if (click_button > 0) {
		if (click_x > 0 && click_y > 0) {
			if (in_circle(x, y, radius) && ((click_button & 1) > 0 || (click_button & 4) > 0)) {
				int v = int_max - drop_wetness >= cell ? cell + drop_wetness : int_max;
				setv(x, y, v);
			}

			if (in_circle(x, y, pigment_radius) && ((click_button & 2) > 0 || (click_button & 4) > 0)) {
				int p = int_max - pigment_drop_wetness >= cellp ? cellp + pigment_drop_wetness : int_max;
				setp(x, y, tmp_pigment, p);
			}
		}
	}

    /* Assign the values to the output image texture */
    float c = cell / float(int_max);
	float cp = cellp / float(int_max);
	float f = hide_fibers ? 0.0 : fibers.data[x + y * width];
	vec4 color = vec4(c, cp, f, 1.0);
	ivec2 coord = ivec2(x, y);
    imageStore(out_image, coord, color);
}


// ---------------------------------------------------------------------------

// psrdnoise (c) Stefan Gustavson and Ian McEwan,
// ver. 2021-12-02, published under the MIT license:
// https://github.com/stegu/psrdnoise/

float psrdnoise(vec2 x, vec2 period, float alpha, out vec2 gradient)
{
  vec2 uv = vec2(x.x+x.y*0.5, x.y);
  vec2 i0 = floor(uv), f0 = fract(uv);
  float cmp = step(f0.y, f0.x);
  vec2 o1 = vec2(cmp, 1.0-cmp);
  vec2 i1 = i0 + o1, i2 = i0 + 1.0;
  vec2 v0 = vec2(i0.x - i0.y*0.5, i0.y);
  vec2 v1 = vec2(v0.x + o1.x - o1.y*0.5, v0.y + o1.y);
  vec2 v2 = vec2(v0.x + 0.5, v0.y + 1.0);
  vec2 x0 = x - v0, x1 = x - v1, x2 = x - v2;
  vec3 iu, iv, xw, yw;
  if(any(greaterThan(period, vec2(0.0)))) {
    xw = vec3(v0.x, v1.x, v2.x);
    yw = vec3(v0.y, v1.y, v2.y);
    if(period.x > 0.0)
    xw = mod(vec3(v0.x, v1.x, v2.x), period.x);
    if(period.y > 0.0)
      yw = mod(vec3(v0.y, v1.y, v2.y), period.y);
    iu = floor(xw + 0.5*yw + 0.5); iv = floor(yw + 0.5);
  } else {
    iu = vec3(i0.x, i1.x, i2.x); iv = vec3(i0.y, i1.y, i2.y);
  }
  vec3 hash = mod(iu, 289.0);
  hash = mod((hash*51.0 + 2.0)*hash + iv, 289.0);
  hash = mod((hash*34.0 + 10.0)*hash, 289.0);
  vec3 psi = hash*0.07482 + alpha;
  vec3 gx = cos(psi); vec3 gy = sin(psi);
  vec2 g0 = vec2(gx.x, gy.x);
  vec2 g1 = vec2(gx.y, gy.y);
  vec2 g2 = vec2(gx.z, gy.z);
  vec3 w = 0.8 - vec3(dot(x0, x0), dot(x1, x1), dot(x2, x2));
  w = max(w, 0.0); vec3 w2 = w*w; vec3 w4 = w2*w2;
  vec3 gdotx = vec3(dot(g0, x0), dot(g1, x1), dot(g2, x2));
  float n = dot(w4, gdotx);
  vec3 w3 = w2*w; vec3 dw = -8.0*w3*gdotx;
  vec2 dn0 = w4.x*g0 + dw.x*x0;
  vec2 dn1 = w4.y*g1 + dw.y*x1;
  vec2 dn2 = w4.z*g2 + dw.z*x2;
  gradient = 10.9*(dn0 + dn1 + dn2);
  return 10.9*n;
}