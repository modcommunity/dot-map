shader_type spatial;
// A liquid's surface (water, slime, lava): translucent, moving, lit, seen from both sides.
// No texture, so no licence: ripples are travelling sines in world metres, so a pool's waves are one size whatever it measures.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.10, 0.34, 0.42, 1.0);
uniform vec4 deep_tint : source_color = vec4(0.03, 0.12, 0.20, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.62, 0.78, 0.92, 1.0);
uniform vec4 foam_tint : source_color = vec4(0.92, 0.97, 1.0, 1.0);
// A volume's top face in world x and z, for the foam lip; lip_width 0 draws none (a converted map's own faces).
uniform vec4 extent = vec4(-1.0, -1.0, 1.0, 1.0);
uniform float alpha_down : hint_range(0.0, 1.0) = 0.5;
uniform float alpha_grazing : hint_range(0.0, 1.0) = 0.9;
uniform float wave_height : hint_range(0.0, 0.5) = 0.10;
uniform float flow_speed : hint_range(0.0, 4.0) = 1.0;
uniform float lip_width : hint_range(0.0, 2.0) = 0.45;
// Lava glows by itself: the body colour times this goes to emission.
uniform float glow : hint_range(0.0, 8.0) = 0.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.06;

varying vec3 world;

float height(vec2 p, float t) {
	float h = 0.0;
	h += sin(dot(p, vec2(0.86, 0.51)) * 1.7 + t * 0.9) * 0.50;
	h += sin(dot(p, vec2(-0.36, 0.93)) * 2.3 - t * 1.1) * 0.35;
	h += sin(dot(p, vec2(0.97, -0.23)) * 5.1 + t * 1.9) * 0.18;
	h += sin(dot(p, vec2(-0.71, -0.71)) * 9.3 - t * 2.7) * 0.08;
	return h * wave_height;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * flow_speed;
	vec2 p = world.xz;
	float e = 0.05;
	float h0 = height(p, t);
	float dx = height(p + vec2(e, 0.0), t) - h0;
	float dz = height(p + vec2(0.0, e), t) - h0;
	vec3 n_world = normalize(vec3(-dx / e, 1.0, -dz / e));
	if (!FRONT_FACING) {
		n_world = -n_world;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	float facing = clamp(abs(dot(NORMAL, normalize(VIEW))), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 3.0);

	float lip = 0.0;
	if (lip_width > 0.0) {
		float edge = min(min(world.x - extent.x, extent.z - world.x), min(world.z - extent.y, extent.w - world.z));
		float ragged = 0.5 + 0.5 * sin(world.x * 3.7 + world.z * 2.9 + t * 1.6) * sin(world.z * 4.3 - world.x * 1.7 - t * 1.1);
		lip = 1.0 - smoothstep(0.0, lip_width * (0.55 + 0.45 * ragged), edge);
	}

	vec3 body = mix(tint.rgb, deep_tint.rgb, 0.35 * (1.0 - facing));
	vec3 col = mix(body, sky_tint.rgb, clamp(fresnel * 0.9 + 0.12, 0.0, 1.0));
	col = mix(col, foam_tint.rgb, lip * 0.85);
	if (!FRONT_FACING) {
		// From below: a silver ceiling the light comes through.
		col = mix(deep_tint.rgb * 1.6, sky_tint.rgb, fresnel * 0.6 + 0.15);
	}

	ALBEDO = col;
	ROUGHNESS = mix(roughness_base, 0.4, lip);
	SPECULAR = 0.9;
	METALLIC = 0.0;
	// Glints where the fine ripples line up; the sample point is warped first or they sit in rows.
	vec2 q = p + vec2(sin(p.y * 0.43 + t * 0.31), cos(p.x * 0.37 - t * 0.27)) * 1.6;
	float fine = sin(dot(q, vec2(0.93, 0.37)) * 7.0 + t * 3.1) * sin(dot(q, vec2(-0.41, 0.91)) * 8.3 - t * 2.3)
		* sin(dot(q, vec2(0.71, -0.70)) * 4.9 + t * 1.3);
	float patch = 0.5 + 0.5 * sin(p.x * 0.11 + t * 0.07) * sin(p.y * 0.13 - t * 0.05);
	EMISSION = sky_tint.rgb * smoothstep(0.72, 0.97, fine) * 0.45 * (1.0 - lip) * (0.4 + 0.6 * patch);
	ALBEDO = mix(ALBEDO, deep_tint.rgb, 0.25 * (1.0 - patch));
	if (glow > 0.0) {
		EMISSION += mix(deep_tint.rgb, tint.rgb, 0.5 + 0.5 * patch + h0 * 3.0) * glow;
	}
	ALPHA = clamp(mix(alpha_down, alpha_grazing, fresnel) + lip * 0.35, 0.0, 1.0);
}
