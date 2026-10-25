shader_type spatial;
render_mode unshaded;

// The map author's baked light (UV2 into an RGB9E5 atlas page) times a world-triplanar albedo.
// Unshaded: the lightmap already holds the sun, the lamps and the bounce, so Godot's lights would count them twice.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap : filter_linear, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float metres = 2.0;
uniform float sharpness = 4.0;
uniform float exposure = 1.0;
uniform float emissive = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 w = pow(abs(wnorm), vec3(sharpness));
	w /= w.x + w.y + w.z;
	vec3 s = (texture(albedo_tex, wpos.zy / metres).rgb * w.x
			+ texture(albedo_tex, wpos.xz / metres).rgb * w.y
			+ texture(albedo_tex, wpos.xy / metres).rgb * w.z) * tint;
	vec3 light = emissive > 0.0 ? vec3(emissive) : texture(lightmap, UV2).rgb * exposure;
	ALBEDO = s * light;
}
