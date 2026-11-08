shader_type spatial;

// The unlit path's two-layer terrain: a world-triplanar albedo mixed with a second by the vertex weight (COLOR.r),
// lit by the scene like any StandardMaterial3D. lightmapped.gdshader does the same under a bake.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo2_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float metres = 2.0;
uniform float sharpness = 4.0;

varying vec3 wpos;
varying vec3 wnorm;
varying float blend_w;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	blend_w = COLOR.r;
}

vec3 tri(sampler2D t, vec3 w) {
	return texture(t, wpos.zy / metres).rgb * w.x + texture(t, wpos.xz / metres).rgb * w.y + texture(t, wpos.xy / metres).rgb * w.z;
}

void fragment() {
	vec3 w = pow(abs(wnorm), vec3(sharpness));
	w /= w.x + w.y + w.z;
	ALBEDO = mix(tri(albedo_tex, w), tri(albedo2_tex, w), smoothstep(0.25, 0.75, blend_w));
	ROUGHNESS = 0.9;
}
