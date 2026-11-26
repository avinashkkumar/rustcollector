shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Hex overlay state (see project.godot [shader_globals]).
global uniform vec2 focus_hex;
global uniform float hex_overlay;
global uniform float terrain_pom;   // parallax steps (quality preset); 0 = off
global uniform vec2 sun_xz;         // horizontal direction towards the sun

// Per-chunk R8 mask: 1 = full rust layer, 0 = cleared down to bare rock.
uniform sampler2D rust_mask : hint_default_white, filter_linear, repeat_disable;
// Per-chunk R8 dents from tyres and boots (0 = untouched). Black when nothing has passed.
uniform sampler2D track_mask : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 rock_a : source_color = vec3(0.33, 0.20, 0.13);
uniform vec3 rock_b : source_color = vec3(0.16, 0.095, 0.065);
uniform vec3 rust_a : source_color = vec3(0.88, 0.47, 0.23);
uniform vec3 rust_b : source_color = vec3(0.70, 0.33, 0.15);
uniform vec3 wall_col : source_color = vec3(0.42, 0.20, 0.10);
uniform float chunk_size = 64.0;
uniform float layer_depth = 0.14; // thickness of the rust layer in metres
uniform float hex_w = 20.0;
uniform float pom_distance = 45.0;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float mask_at(vec2 wxz, vec2 org) {
	return textureLod(rust_mask, (wxz - org) / chunk_size, 0.0).r;
}

float track_at(vec2 wxz, vec2 org) {
	return textureLod(track_mask, (wxz - org) / chunk_size, 0.0).r;
}

float coverage(vec2 wxz, vec2 org) {
	float n = texture(detail_noise, wxz * 0.47).r;
	return smoothstep(0.08, 0.5, mask_at(wxz, org) + (n - 0.5) * 0.25);
}

// Pointy-top hex grid: returns offset from the nearest centre (xy) and the centre (zw), in hex units.
vec4 hex_info(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hc.xy * s) : vec4(h.zw, (hc.zw + 0.5) * s);
}

void fragment() {
	vec2 org = MODEL_MATRIX[3].xz;
	vec3 to_cam = CAMERA_POSITION_WORLD - w_pos;
	float dist = length(to_cam);
	vec3 V = to_cam / dist;
	vec2 p = w_pos.xz;

	// Parallax occlusion: the mesh is the top of the rust layer; cleared cells are carved
	// layer_depth metres down. March the view ray into the layer until it hits the carved surface.
	int pom_steps = int(terrain_pom);
	float pom_fade = (pom_steps > 0) ? 1.0 - smoothstep(pom_distance * 0.6, pom_distance, dist) : 0.0;
	float depth = 0.0;
	if (pom_fade > 0.0) {
		vec2 dir = -V.xz / max(V.y, 0.18);
		float step_d = layer_depth / float(pom_steps);
		vec2 q = p;
		float d = 0.0;
		for (int i = 0; i < pom_steps; i++) {
			float m = mask_at(q, org);
			// Cleared cells are carved to the rock; tracks press part-way into remaining rust.
			float carved = layer_depth * max(1.0 - smoothstep(0.08, 0.5, m), track_at(q, org) * 0.55 * smoothstep(0.05, 0.3, m));
			if (d >= carved) {
				break;
			}
			d += step_d;
			q = p + dir * d;
		}
		p = mix(p, q, pom_fade);
		depth = d * pom_fade;
	}

	float cov = coverage(p, org);
	float n_big = texture(detail_noise, p * 0.013).r;
	float n_mid = texture(detail_noise, p * 0.11).r;
	float n_fine = texture(detail_noise, p * 0.9).r;

	vec3 rock = mix(rock_b, rock_a, smoothstep(0.25, 0.75, n_mid)) * (0.75 + 0.45 * n_big);
	rock *= 0.85 + 0.3 * n_fine; // gritty speckle
	vec3 rust_c = mix(rust_b, rust_a, smoothstep(0.2, 0.8, n_big * 0.6 + n_fine * 0.4));

	// Compacted rust in tyre tracks and footprints is darker and smoother.
	// Crisp edge for the dent, and a lighter berm where the rust was pushed aside.
	float raw_tr = track_at(p, org);
	float tr = smoothstep(0.28, 0.55, raw_tr) * cov;
	float berm = (smoothstep(0.04, 0.2, raw_tr) - smoothstep(0.24, 0.42, raw_tr)) * cov;
	rust_c = mix(rust_c, rust_c * vec3(0.5, 0.46, 0.44), tr * 0.95);
	rust_c = mix(rust_c, rust_c * 1.22, berm * 0.6);
	vec3 col = mix(rock, rust_c, cov);
	// Cut faces of the layer read darker than the top.
	float wall = 4.0 * cov * (1.0 - cov);
	col = mix(col, wall_col * (0.8 + 0.4 * n_fine), wall * 0.75);

	// Contact darkening on the floor next to remaining rust, and a short cast shadow from the
	// layer edge on the side away from the sun. Fades out with distance.
	float near = 1.0 - smoothstep(30.0, 60.0, dist);
	if (near > 0.0) {
		float r = 0.35;
		float around = (mask_at(p + vec2(r, 0.0), org) + mask_at(p - vec2(r, 0.0), org)
			+ mask_at(p + vec2(0.0, r), org) + mask_at(p - vec2(0.0, r), org)) * 0.25;
		float ao = 1.0 - 0.55 * smoothstep(0.1, 0.7, around) * (1.0 - cov) * near;
		float towards_sun = smoothstep(0.08, 0.5, mask_at(p + normalize(sun_xz) * layer_depth * 3.0, org));
		float shadow = clamp(towards_sun - cov, 0.0, 1.0) * 0.45 * near;
		col *= ao * (1.0 - shadow);
	}

	ALBEDO = col;
	ROUGHNESS = mix(0.66, 0.95, cov);
	SPECULAR = mix(0.42, 0.22, cov);
	vec3 nm = texture(rock_normal, p * 0.35).rgb;
	NORMAL_MAP = mix(nm, vec3(0.5, 0.5, 1.0), cov * 0.9);
	NORMAL_MAP_DEPTH = 1.1;

	// Hexagon overlay. The hex the player stands in is highlighted.
	if (hex_overlay > 0.0) {
		vec4 hi = hex_info(w_pos.xz / hex_w);
		float hd = max(dot(abs(hi.xy), vec2(0.5, 0.8660254)), abs(hi.x));
		float focus = 1.0 - step(0.5, distance(hi.zw * hex_w, focus_hex));
		float lw = mix(0.06, 0.14, focus) / hex_w;
		float aa = min(fwidth(hd), 0.02);
		float line = smoothstep(0.5 - lw - aa, 0.5 - lw, hd);
		// Distant lines thin out instead of turning into thick bands.
		float fade = (1.0 - smoothstep(20.0, 65.0, dist)) * clamp(lw / max(fwidth(hd), 1e-4), 0.0, 1.0);
		float a = line * hex_overlay * max(fade * 0.35, focus);
		ALBEDO = mix(ALBEDO, vec3(1.0, 0.88, 0.7), a * 0.5);
		EMISSION = vec3(1.0, 0.7, 0.4) * a * (0.04 + 0.45 * focus);
	}
}
