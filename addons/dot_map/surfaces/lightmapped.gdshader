shader_type spatial;
render_mode ambient_light_disabled;

// The map author's baked light (UV2 into an RGB9E5 atlas page) times a world-triplanar albedo.
// The lightmap is emission; the scene's sun adds its shadowed diffuse on top, because the author's bake of an outdoor sun is often near black.
// Ambient is the floor of the bake (the sky term), not Godot's ambient, which would count the bounce twice.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap : filter_linear, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float metres = 2.0;
uniform float sharpness = 4.0;
uniform float exposure = 1.0;
uniform float emissive = 0.0;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo2_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_blend = false;
uniform bool has_normal = false;
uniform bool has_roughness = false;
uniform bool has_ao = false;
uniform vec3 floor_light : source_color = vec3(0.0);

varying vec3 wpos;
varying vec3 wnorm;
varying float blend_w;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	blend_w = COLOR.r;
}

// A tangent normal from red and green alone: an imported normal map is two-channel (RGTC), and so is a raw one once slimmed.
vec3 unpack_normal(vec2 rg) {
	vec2 xy = rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

// Triplanar normal map by whiteout blending, in world space.
vec3 world_normal(vec3 wn, vec3 w) {
	vec3 tx = unpack_normal(texture(normal_tex, wpos.zy / metres).xy);
	vec3 ty = unpack_normal(texture(normal_tex, wpos.xz / metres).xy);
	vec3 tz = unpack_normal(texture(normal_tex, wpos.xy / metres).xy);
	vec3 sg = sign(wn);
	tx = vec3(tx.xy * sg.x + wn.zy, abs(tx.z) * wn.x);
	ty = vec3(ty.xy * sg.y + wn.xz, abs(ty.z) * wn.y);
	tz = vec3(tz.xy * sg.z + wn.xy, abs(tz.z) * wn.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

void fragment() {
	vec3 w = pow(abs(wnorm), vec3(sharpness));
	w /= w.x + w.y + w.z;
	vec3 s = (texture(albedo_tex, wpos.zy / metres).rgb * w.x
			+ texture(albedo_tex, wpos.xz / metres).rgb * w.y
			+ texture(albedo_tex, wpos.xy / metres).rgb * w.z) * tint;
	if (has_blend) {
		vec3 s2 = (texture(albedo2_tex, wpos.zy / metres).rgb * w.x
				+ texture(albedo2_tex, wpos.xz / metres).rgb * w.y
				+ texture(albedo2_tex, wpos.xy / metres).rgb * w.z) * tint;
		s = mix(s, s2, smoothstep(0.25, 0.75, blend_w));
	}
	vec3 light = emissive > 0.0 ? vec3(emissive) : max(texture(lightmap, UV2).rgb * exposure, floor_light);
	// A low sun bakes far above 1 (red 3.7 on the Atix street) and the filmic curve clips that to flat yellow: the overshoot
	// rolls off toward 1.5 and bleaches toward grey, as film does. At or below 1 nothing changes, so ordinary bakes are untouched.
	float peak = max(light.r, max(light.g, light.b));
	if (peak > 1.0) {
		float bleach = clamp((peak - 1.0) / 3.0, 0.0, 0.6);
		light *= (1.0 + 0.5 * (1.0 - exp(-(peak - 1.0) / 0.5))) / peak;
		light = mix(light, vec3(dot(light, vec3(0.3333))), bleach);
	}
	float ao = 1.0;
	if (has_ao) {
		ao = (texture(ao_tex, wpos.zy / metres).r * w.x + texture(ao_tex, wpos.xz / metres).r * w.y + texture(ao_tex, wpos.xy / metres).r * w.z);
	}
	float rough = 1.0;
	if (has_roughness) {
		rough = (texture(rough_tex, wpos.zy / metres).r * w.x + texture(rough_tex, wpos.xz / metres).r * w.y + texture(rough_tex, wpos.xy / metres).r * w.z);
	}
	if (has_normal) {
		NORMAL = normalize((VIEW_MATRIX * vec4(world_normal(normalize(wnorm), w), 0.0)).xyz);
	}
	// Where the bake is already bright the sun would count twice: its diffuse fades out.
	ALBEDO = s * (1.0 - smoothstep(0.15, 0.6, dot(light, vec3(0.3333))));
	ROUGHNESS = rough;
	SPECULAR = has_roughness ? 0.5 : 0.0;
	EMISSION = s * light * ao;
}
