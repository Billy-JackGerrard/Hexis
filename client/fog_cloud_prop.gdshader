shader_type spatial;
// Soft-edges the cloud_big/cloud_small props scattered by fog_of_war.gd.
// Those meshes are low-poly blobs with a flat-color atlas texture and no
// baked alpha feathering, so at constant alpha every instance's silhouette
// reads as its own crisp edge — with PROP_CELL_SIZE_PIXELS packing several
// overlapping instances into view at once, that read as "millions of
// distinct clouds" rather than one bank. This fades ALPHA to 0 as a
// fragment nears the mesh's own local-space extent (aabb_center/aabb_radius,
// set per part in fog_of_war.gd's _collect_prop_parts since cloud_big and
// cloud_small differ in size), so each instance's rim blends into whatever
// is behind/around it instead of cutting a hard line — overlapping instances
// then build up toward solid the way real overlapping cloud puffs do.
render_mode unshaded, blend_mix, depth_draw_never;

uniform sampler2D albedo_texture : source_color, filter_linear, hint_default_white;
uniform vec3 aabb_center;
uniform float aabb_radius;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.45; // fraction of aabb_radius where the fade begins

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	float dist_ratio = clamp(length(local_pos - aabb_center) / aabb_radius, 0.0, 1.0);
	float edge_fade = 1.0 - smoothstep(edge_softness, 1.0, dist_ratio);
	ALBEDO = tex.rgb * COLOR.rgb;
	ALPHA = tex.a * COLOR.a * edge_fade;
}
