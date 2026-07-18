// Procedural surface detail for terrain ground plates (TerrainView3D's
// GROUND_DETAIL_SHADER). The Kenney pack's atlas is a flat colour-swatch sheet
// — every grass tile is one uniform fill, with no grain at all — so Plains,
// which is the majority of the board, rendered as a large area of dead colour.
// Scattering props on it was tried and read as clutter (see TerrainView3D's
// OCEAN_DECOR_CHANCE doc comment); this adds the missing texture to the
// surface itself instead, where it can't compete with units for attention.
//
// Samples the same atlas the imported material used, so UVs, the seasonal
// variant swap, and the tile's own painted details (river channels, road
// surfaces, beach sand) all still work — this only modulates the result.
//
// Noise is evaluated in WORLD space, not UV space. Every hex in the pack shares
// one small atlas region, so UV-space noise would stamp the identical pattern on
// every tile and read as an obvious repeat; world space makes the grain
// continuous across tile boundaries, so it looks like ground rather than tiling.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 albedo_tint : source_color = vec4(1.0);

// River plates carry the channel and its banks on ONE mesh surface with one
// material, separated only by UV region, so the seasonal swap can't be applied
// per-surface: swapping the whole plate matches the banks to the surrounding
// land (the point) but also drags the water with it — the Fall atlas recolours
// the pack's blues to teal, which reads as a different liquid, not as autumn.
//
// So the swap is applied and the water is then restored from the default atlas.
// water_guard_texture is that default atlas; where ITS sample is blue-dominant
// the pixel is water and keeps its original colour. Detecting on the default
// rather than on the seasonal sample matters: Fall's teal is much weaker
// evidence of "this is water" than the blue it replaced.
uniform sampler2D water_guard_texture : source_color, filter_nearest;
uniform bool preserve_water = false;

// Coarse blotches (broad soil/grass variation) and a finer grain on top. Two
// octaves at very different scales, rather than one: a single frequency reads
// as either mush or static, never as ground.
// Strengths are high for a "subtle detail" effect on purpose. The art is flat-
// shaded, fully saturated and unlit-looking, so there is no shading gradient for
// a gentle modulation to ride on — at ~10% the variation was measurably present
// and visually invisible. These values are what actually read as ground at the
// game's normal zoom.
uniform float coarse_scale = 0.42;
uniform float coarse_strength = 0.22;
uniform float fine_scale = 6.0;
uniform float fine_strength = 0.09;

varying vec3 world_pos;

// Cheap 2D value noise. Hash is the usual sin-fract trick — precision is
// irrelevant here, this only ever perturbs brightness by a few percent.
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// Smoothstep the interpolant so cell boundaries don't show as a grid.
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 base = texture(albedo_texture, UV) * albedo_tint;

	if (preserve_water) {
		vec4 unswapped = texture(water_guard_texture, UV) * albedo_tint;
		// smoothstep rather than a threshold: the atlas is filter_nearest, but
		// UV interpolation across a triangle still lands samples on the
		// shoreline boundary, and a hard cutoff there shimmers as the camera
		// moves. The band is narrow enough that grass (blue is its LOWEST
		// channel) never enters it.
		float water = smoothstep(0.04, 0.12, unswapped.b - max(unswapped.r, unswapped.g));
		base = mix(base, unswapped, water);
	}

	vec2 p = world_pos.xz;
	// Centred on 0 so the noise darkens and lightens equally — a 0..1 range
	// would only ever brighten, washing the palette out.
	float coarse = value_noise(p * coarse_scale) - 0.5;
	float fine = value_noise(p * fine_scale) - 0.5;
	float detail = coarse * coarse_strength + fine * fine_strength;

	// Multiplicative, so the variation is proportional to the swatch's own
	// colour: dark tiles stay dark and the tint reads as the same material
	// under uneven light, rather than as a grey haze laid over everything.
	ALBEDO = clamp(base.rgb * (1.0 + detail), vec3(0.0), vec3(1.0));
	ALPHA = base.a;
}
