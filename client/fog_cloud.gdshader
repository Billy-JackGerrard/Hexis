shader_type spatial;
// depth_test_disabled is the fix for real occlusion: alpha blending alone
// isn't enough when the fog mesh sits low (FOG_SHEET_HEIGHT, see
// fog_of_war.gd) to stay hex-aligned under the tilted camera — any taller
// 3D content (trees, buildings) fails the depth test against this near-
// ground plane and wins regardless of this shader's ALPHA output, since the
// depth test discards a fragment before blending ever runs. Disabling it
// makes this material always paint over whatever's beneath it in draw
// order (guaranteed after the opaque pass, since blend_mix material always
// sorts into the transparent queue) — occlusion now comes purely from
// ALPHA, which is what the "unexplored is always fully opaque" guarantee
// in fragment() actually relies on.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled;

// Continuous fog-of-war cloud layer for a single flat plane spanning the
// whole map (see fog_of_war.gd) — one seamless procedural cloud pattern
// (hash-based value noise FBM, so it never repeats/tiles the way one gltf
// prop per hex did) whose opacity is driven by fog_state: a small texture
// rebuilt from PlayerVision only when state.tick changes, roughly one texel
// every few HexView pixels. GPU bilinear sampling of that low-res texture
// is what gives the smooth, seamless transition between visible/haze/
// unexplored instead of a hard edge at every hex boundary.
// This material is the reliable occlusion backstop for fog_of_war.gd's
// scattered cloud_big/cloud_small props (see that file's class doc comment):
// props are decorative art that could leave gaps between instances, this
// plane's ALPHA math never does. ALBEDO follows the same cloud noise as
// ALPHA (see `shaped` below) so explored haze reads as an actual — just
// much more transparent — cloud layer rather than a flat grey tint, and so
// this plane's own look matches the props sitting on top of it instead of
// being a plain backdrop behind them.
uniform sampler2D fog_state : hint_default_black, filter_linear, repeat_disable;
uniform float time_scale : hint_range(0.0, 1.0) = 0.015;
uniform float cloud_scale = 5.0;
// Cut hard from 0.6 — "explored but not visible" is meant to be a light veil
// over remembered terrain, not a haze thick enough to hide what's under it;
// see BUILDING_DEPTH_FADE below for the other half of that same complaint
// (a building poking up through the haze getting dimmed just as much as the
// bare ground next to it).
uniform float haze_alpha = 0.28;
uniform float edge_jitter = 0.42;
// Depth-buffer readback: lets this fragment tell whether the opaque pass
// already drew something NEARER than this flat sheet at the same screen
// pixel — i.e. a building, tree, or hill poking up through the low fog
// plane. Only used to exempt HAZE (explored-but-not-visible) from covering
// tall things; unexplored_amt is never touched by this, so the "unexplored
// is always fully opaque" guarantee (see fragment()'s own comment) still
// holds regardless of height — a true fog-of-war blackout still hides
// everything, this only stops the light haze from dimming a remembered
// base the player has already scouted.
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	float state = texture(fog_state, UV).r; // 0 visible, 0.5 explored-haze, 1 unexplored
	vec2 drift = vec2(TIME * time_scale, TIME * time_scale * 0.6);
	float cloud = fbm(UV * cloud_scale + drift);
	// A separate, higher-frequency noise sample (not `cloud` itself — reusing
	// it here would lock the edge wobble and the interior color pattern into
	// the same phase, reading as one repeating motif instead of two
	// independent textures) perturbs the vision-state threshold before the
	// smoothstep below. Without this, the boundary between visible/haze/
	// unexplored is exactly fog_state's own smooth bilinear gradient — a
	// clean blurred ring, not a cloud edge. Jittering the threshold makes
	// the boundary itself wobble unevenly, the same puffy-irregular silhouette
	// a real cloud bank has, while the underlying vision data (what's true
	// fog vs. what's visible) is unchanged — only where exactly the line is
	// drawn within the existing soft transition band moves.
	float edge_noise = fbm(UV * cloud_scale * 1.6 - drift * 1.4) - 0.5;
	float jittered_state = state + edge_noise * edge_jitter;
	// Unexplored is always fully opaque regardless of the cloud pattern —
	// the noise only varies its COLOR, not whether it hides anything, so
	// this stays a reliable occlusion guarantee even where the pattern
	// happens to sample low. Haze is the opposite: alpha itself follows the
	// cloud pattern, since it's meant to be a wispy, uneven veil over
	// remembered terrain, not a uniform flat tint.
	float unexplored_amt = smoothstep(0.62, 0.85, jittered_state);
	float haze_amt = clamp(smoothstep(0.15, 0.4, jittered_state) - unexplored_amt, 0.0, 1.0);
	// Raw fbm output sits in a narrow mid-range band (rarely near 0 or 1) —
	// multiplying haze alpha straight by that band made the haze read as
	// barely-there (average around haze_alpha*0.5, and dipping toward
	// invisible wherever the pattern happened to sample low). mix(0.55, 1.0,
	// ...) puts a floor under it so haze is always clearly present, with the
	// cloud pattern only modulating the remaining range on top of that floor.
	float shaped = smoothstep(0.32, 0.68, cloud);
	// Depth exemption for haze only (see depth_tex's own doc comment above):
	// this plane sits just FOG_SHEET_HEIGHT above bare ground everywhere, so
	// under a normal flat tile the opaque pass's own depth at this pixel is
	// always very slightly FARTHER than this fragment's (ground sits a hair
	// behind the sheet) — tall_here stays 0 there. Only where something
	// genuinely tall (a building, a tree, a hillside) was drawn well in front
	// of that thin margin does scene_depth end up nearer than FRAGCOORD.z,
	// flipping tall_here to 1 and zeroing the haze contribution right at that
	// pixel, so a scouted base reads through the haze instead of being
	// dimmed exactly as much as the bare ground beside it.
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	float tall_here = step(scene_depth, FRAGCOORD.z);
	ALPHA = unexplored_amt + haze_amt * mix(0.55, 1.0, shaped) * haze_alpha * (1.0 - tall_here);
	// Flat grey read as a plain tint rather than cloud — explored haze is
	// meant to be "clouds too, just a lot more transparent" (same texture as
	// unexplored, not a different-looking fog). ALBEDO now follows the same
	// `shaped` noise as ALPHA (darker wisps to brighter puffs), tinted white
	// rather than mid-grey since it's meant to read as cloud, not shadow.
	ALBEDO = mix(vec3(0.68, 0.70, 0.74), vec3(0.94, 0.95, 0.97), shaped);
}
