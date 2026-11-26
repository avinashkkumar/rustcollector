class_name DustFx
extends RefCounted
## Factory for GPU dust-puff emitters (shared mesh/material so they batch well).

static var _quad: QuadMesh
static var _storm_quad: QuadMesh


static func _material(tex_path: String, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = load(tex_path)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(0.8, 0.8)
		_quad.material = _material("res://assets/particles/smoke_04.png", Color(0.86, 0.56, 0.36, 1))
	return _quad


static func make(amount: int, size_scale: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 4)
	p.lifetime = 1.3
	p.randomness = 0.5
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 6, 10))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.35 * size_scale
	m.direction = Vector3(0, 1, 0)
	m.spread = 70.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 2.0 * size_scale
	m.gravity = Vector3(0, -1.0, 0)
	m.damping_min = 0.8
	m.damping_max = 1.6
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -40.0
	m.angular_velocity_max = 40.0
	m.scale_min = 0.6 * size_scale
	m.scale_max = 1.6 * size_scale
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(1, 1.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.15, Color(1, 1, 1, 0.55))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	p.draw_pass_1 = quad()
	return p


## Large wind-blown dust field that follows the camera (benchmark storm stage / ultra ambience).
static func make_storm(amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 16)
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(45, 10, 45)
	m.direction = Vector3(1, 0.05, 0.3)
	m.spread = 12.0
	m.initial_velocity_min = 9.0
	m.initial_velocity_max = 16.0
	m.gravity = Vector3(0, -0.2, 0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 2.0
	m.turbulence_noise_scale = 6.0
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.15
	m.scale_min = 1.5
	m.scale_max = 4.5
	m.angle_min = -180.0
	m.angle_max = 180.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.3, Color(1, 1, 1, 0.35))
	g.add_point(0.7, Color(1, 1, 1, 0.35))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	if _storm_quad == null:
		_storm_quad = QuadMesh.new()
		_storm_quad.size = Vector2(1.6, 1.6)
		_storm_quad.material = _material("res://assets/particles/smoke_07.png", Color(0.80, 0.50, 0.32, 1))
	p.draw_pass_1 = _storm_quad
	return p
