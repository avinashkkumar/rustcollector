class_name Handcart
extends Node3D
## A two-wheeled rust cart you push by hand. Park it near where you clean, tip your tank into it
## (Q), then push it to the export depot. While parked it is solid; while pushed it rolls in front
## of you and follows the ground.

const AHEAD := 1.55  # metres in front of the player while pushing

var world: World
var pushing := false
var load_kg := 0.0
var _body: StaticBody3D
var _fill: MeshInstance3D
var _wheels: Array[Node3D] = []
var _label: Label3D
var _label_text := ""
var _roll := 0.0


func _ready() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.92, 0.62, 0.18)
	paint.roughness = 0.6
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.35, 0.36, 0.38)
	steel.metallic = 0.6
	steel.roughness = 0.4
	# Tray: floor and four sloped sides.
	_box(Vector3(1.2, 0.05, 0.9), Vector3(0, 0.5, 0), paint)
	_box(Vector3(1.3, 0.42, 0.05), Vector3(0, 0.72, 0.47), paint)
	_box(Vector3(1.3, 0.42, 0.05), Vector3(0, 0.72, -0.47), paint)
	_box(Vector3(0.05, 0.42, 0.95), Vector3(0.64, 0.72, 0), paint)
	_box(Vector3(0.05, 0.42, 0.95), Vector3(-0.64, 0.72, 0), paint)
	# Load: a heap of rust that rises as it fills.
	_fill = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.2, 0.4, 0.86)
	_fill.mesh = fm
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.62, 0.24, 0.1)
	rust.roughness = 1.0
	_fill.material_override = rust
	add_child(_fill)
	# Handles towards the player (+z is the back of the cart).
	for x in [-0.45, 0.45]:
		_box(Vector3(0.04, 0.04, 0.8), Vector3(x, 0.92, 0.85), steel)
	_box(Vector3(0.94, 0.05, 0.05), Vector3(0, 0.92, 1.25), steel)
	# Two chunky wheels.
	for x in [-0.72, 0.72]:
		var w := Node3D.new()
		w.position = Vector3(x, 0.32, 0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.32
		cm.bottom_radius = 0.32
		cm.height = 0.12
		cm.radial_segments = 20
		mi.mesh = cm
		mi.rotation_degrees.z = 90
		var tyre := StandardMaterial3D.new()
		tyre.albedo_color = Color(0.1, 0.1, 0.11)
		mi.material_override = tyre
		w.add_child(mi)
		var hub := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.14, 0.5, 0.08)
		hub.mesh = hm
		hub.material_override = steel
		w.add_child(hub)
		add_child(w)
		_wheels.append(w)
	_body = StaticBody3D.new()
	_body.collision_layer = 4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.5, 1.0, 1.0)
	cs.shape = bs
	cs.position.y = 0.6
	_body.add_child(cs)
	add_child(_body)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.font_size = 24
	_label.pixel_size = 0.0011
	_label.outline_size = 8
	_label.position.y = 1.5
	add_child(_label)
	_update_fill()


func _box(size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = m
	add_child(mi)


func capacity() -> float:
	return world.state.cart_capacity()


func space() -> float:
	return maxf(capacity() - load_kg, 0.0)


func set_pushing(on: bool) -> void:
	pushing = on
	_label.visible = not on  # the prompt line shows the load while pushing
	_body.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	(_body.get_child(0) as CollisionShape3D).disabled = on


## Tips up to `kg` into the cart; returns how much went in.
func add(kg: float) -> float:
	var put := minf(kg, space())
	load_kg += put
	_update_fill()
	return put


func empty() -> float:
	var kg := load_kg
	load_kg = 0.0
	_update_fill()
	return kg


func _update_fill() -> void:
	var f := clampf(load_kg / maxf(capacity(), 1.0), 0.0, 1.0) if world else 0.0
	_fill.visible = f > 0.01
	_fill.scale = Vector3(1.0, maxf(f, 0.02), 1.0)
	_fill.position.y = 0.52 + 0.2 * f
	var t := "Handcart  %.0f / %.0f kg" % [load_kg, capacity()] if world else ""
	if t != _label_text:
		_label_text = t
		_label.text = t


func place(pos: Vector3, yaw: float) -> void:
	global_position = Vector3(pos.x, world.terrain.height_at(pos.x, pos.z), pos.z)
	rotation = Vector3(0, yaw, 0)
	_align()


func _process(dt: float) -> void:
	if not pushing:
		return
	var p := world.player
	var fwd := -Vector3(sin(p.yaw), 0, cos(p.yaw))
	var target := p.global_position + fwd * AHEAD
	var before := global_position
	global_position = Vector3(target.x, world.terrain.height_at(target.x, target.z), target.z)
	rotation.y = lerp_angle(rotation.y, p.yaw, 1.0 - exp(-10.0 * dt))
	_align()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_roll += moved / 0.32
	for w in _wheels:
		w.rotation.x = -_roll
	if moved > 0.01:
		for w in _wheels:
			world.rust.press(w.global_position, 0.07, 0.6)  # thin wheel ruts


## Tilt with the ground under the cart.
func _align() -> void:
	var n := world.terrain.normal_at(global_position.x, global_position.z)
	var b := Basis(Vector3.UP, rotation.y)
	var right := b.x
	var fwd := n.cross(right).normalized()
	right = fwd.cross(n).normalized()
	global_basis = Basis(right, n, -fwd).orthonormalized()
