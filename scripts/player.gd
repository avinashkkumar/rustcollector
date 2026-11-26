class_name Player
extends CharacterBody3D
## First-person colonist with a cleaning tool.

const WALK := 4.2
const SPRINT := 7.0
const JUMP := 3.4

var world: World
var camera: Camera3D
var tool_root: Node3D
var tool_head: Node3D
var yaw := 0.0
var pitch := -0.15
var active := true
var cleaning := false
var aim_valid := false
var _shape: CollisionShape3D
var _anim := 0.0
var _bob := 0.0
var _built_tool := -1
var _step := 0.0
var _left_foot := false
var torch_on := false
var torch_root: Node3D
var torch_light: SpotLight3D
var _torch_lens: StandardMaterial3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50)
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	_shape.shape = cap
	_shape.position.y = 0.875
	add_child(_shape)
	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.fov = 75.0
	camera.near = 0.05
	add_child(camera)
	tool_root = Node3D.new()
	tool_root.position = Vector3(0.36, -0.44, -0.95)
	camera.add_child(tool_root)
	refresh_tool()
	_build_torch()


## Hand torch (L): a small lamp in the left hand. The beam trails the view slightly, like a real
## torch held in a hand, and casts shadows on presets that allow light shadows.
func _build_torch() -> void:
	torch_root = Node3D.new()
	torch_root.position = Vector3(-0.42, -0.42, -0.75)
	camera.add_child(torch_root)
	var body := _mesh_node(_cyl(0.035, 0.24, 0.03), Color(0.16, 0.16, 0.18), 0.0)
	body.rotation_degrees.x = 90.0
	torch_root.add_child(body)
	var head := _mesh_node(_cyl(0.05, 0.07, 0.036), Color(0.75, 0.55, 0.2), 0.0)
	head.rotation_degrees.x = 90.0
	head.position.z = -0.15
	torch_root.add_child(head)
	var lens := _mesh_node(_cyl(0.042, 0.01), Color(1.0, 0.95, 0.8), 0.0)
	lens.rotation_degrees.x = 90.0
	lens.position.z = -0.19
	_torch_lens = lens.material_override
	torch_root.add_child(lens)
	torch_light = SpotLight3D.new()
	torch_light.top_level = true  # follows the camera with a little lag (see _process)
	torch_light.spot_range = 34.0
	torch_light.spot_angle = 26.0
	torch_light.spot_angle_attenuation = 0.6
	torch_light.spot_attenuation = 0.9
	torch_light.light_energy = 5.0
	torch_light.light_color = Color(1.0, 0.94, 0.82)
	torch_light.light_volumetric_fog_energy = 0.4
	add_child(torch_light)
	set_torch(false)


func set_torch(on: bool) -> void:
	torch_on = on
	torch_light.visible = on and active
	torch_root.visible = active
	_torch_lens.emission_enabled = on
	_torch_lens.emission = Color(1.0, 0.92, 0.75)
	_torch_lens.emission_energy_multiplier = 4.0
	if world and world.params:
		torch_light.shadow_enabled = bool(world.params.omni_shadows)


func set_active(on: bool) -> void:
	active = on
	visible = on
	_shape.disabled = not on
	set_physics_process(on)
	if on:
		camera.current = true
		velocity = Vector3.ZERO
	if torch_light:
		torch_light.visible = torch_on and on


func _unhandled_input(e: InputEvent) -> void:
	if not active or world.ui_open:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := Config.mouse_sensitivity * 0.01
		yaw -= e.relative.x * s
		pitch = clampf(pitch - e.relative.y * s, -1.45, 1.45)


func _physics_process(dt: float) -> void:
	rotation.y = yaw
	camera.rotation.x = pitch
	var inp := Vector2.ZERO
	if not world.ui_open:
		inp = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(inp.x, 0, inp.y))
	dir.y = 0
	dir = dir.normalized()
	var spd := (SPRINT if Input.is_action_pressed("sprint") else WALK) * world.state.boots_mult()
	if cleaning:
		spd *= 0.8
	var k := 1.0 - exp(-(10.0 if is_on_floor() else 2.0) * dt)
	velocity.x = lerpf(velocity.x, dir.x * spd, k)
	velocity.z = lerpf(velocity.z, dir.z * spd, k)
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not world.ui_open:
			velocity.y = JUMP
	else:
		velocity.y -= world.gravity * dt
	move_and_slide()
	if is_on_floor():
		var moved := Vector2(velocity.x, velocity.z).length() * dt
		_bob += moved * 1.8
		# Boot prints, alternating left and right.
		_step += moved
		if _step > 0.8:
			_step = 0.0
			_left_foot = not _left_foot
			var side := transform.basis.x * (0.14 if _left_foot else -0.14)
			world.rust.press(global_position + side, 0.13, 0.7)


func _process(dt: float) -> void:
	if not active:
		return
	cleaning = false
	aim_valid = false
	var t: Dictionary = world.state.tool()
	if not world.ui_open:
		var from := camera.global_position
		var to := from - camera.global_transform.basis.z * float(t.reach)
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit and hit.collider.collision_layer == 1:
			aim_valid = world.rust.value_at(hit.position.x, hit.position.z) > 0
			if Input.is_action_pressed("clean"):
				cleaning = world.player_clean(hit.position, t, dt)
	_animate_tool(dt)


func refresh_tool() -> void:
	var lvl: int = world.state.tool_lvl if world and world.state else 0
	if lvl == _built_tool:
		return
	_built_tool = lvl
	for c in tool_root.get_children():
		c.queue_free()
	var colors := [Color(0.85, 0.75, 0.35), Color(0.3, 0.6, 0.9), Color(0.9, 0.45, 0.2), Color(0.55, 0.85, 0.4), Color(0.6, 0.9, 1.0)]
	var handle := _mesh_node(_cyl(0.022, 0.75), Color(0.85, 0.85, 0.88), 0.0)
	handle.rotation_degrees = Vector3(62, 0, 0)
	tool_root.add_child(handle)
	tool_head = Node3D.new()
	tool_head.position = Vector3(0, -0.17, -0.33)
	tool_root.add_child(tool_head)
	var col: Color = colors[lvl]
	match lvl:
		0:
			var b := BoxMesh.new()
			b.size = Vector3(0.16, 0.06, 0.07)
			tool_head.add_child(_mesh_node(b, col, 0.0))
		1:
			var b := BoxMesh.new()
			b.size = Vector3(0.42, 0.07, 0.08)
			tool_head.add_child(_mesh_node(b, col, 0.0))
		2:
			var n := _mesh_node(_cyl(0.06, 0.32, 0.03), col, 0.0)
			n.rotation_degrees.x = 62
			tool_head.add_child(n)
		3:
			var n := _mesh_node(_cyl(0.05, 0.45, 0.09), col, 0.2)
			n.rotation_degrees.x = 62
			tool_head.add_child(n)
		_:
			var s := SphereMesh.new()
			s.radius = 0.09
			s.height = 0.18
			s.radial_segments = 24
			s.rings = 12
			tool_head.add_child(_mesh_node(s, col, 2.5))


func _update_torch(dt: float) -> void:
	if not torch_on:
		return
	var src := torch_root.global_transform
	var t := torch_light.global_transform
	# Position follows the hand exactly; the aim catches up with the view over ~0.1 s.
	t.origin = src.origin + src.basis.z * -0.2
	t.basis = t.basis.slerp(camera.global_basis.orthonormalized(), 1.0 - exp(-12.0 * dt)).orthonormalized()
	torch_light.global_transform = t


func _animate_tool(dt: float) -> void:
	_update_torch(dt)
	torch_root.position.y = -0.42 + sin(_bob + 1.3) * 0.01
	_anim += dt * (16.0 if cleaning else 0.0)
	var target := Vector3(0.36, -0.44, -0.95)
	if cleaning:
		target += Vector3(sin(_anim) * 0.05, cos(_anim * 2.0) * 0.015, -0.06)
	target.y += sin(_bob) * 0.012
	tool_root.position = tool_root.position.lerp(target, 1.0 - exp(-14.0 * dt))


static func _cyl(r: float, h: float, r_bottom := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r_bottom < 0.0 else r_bottom
	c.height = h
	c.radial_segments = 24
	c.rings = 1
	return c


static func _mesh_node(mesh: Mesh, color: Color, emission: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	m.metallic = 0.2
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
