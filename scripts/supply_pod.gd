class_name SupplyPod
extends Node3D
## An airdropped supply pod: descends on retro-rockets, lands with a beacon, and is opened with E.

const FALL_TIME := 9.0

var world: World
var target := Vector3.ZERO
var landed := false
var opened := false
var age := 0.0
var beacon: Beacon
var _flame: GPUParticles3D
var _t := 0.0


func _ready() -> void:
	var pod: Node3D = load("res://assets/models/rocket_topA.glb").instantiate()
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * 2.4
	holder.add_child(pod)
	pod.position = Vector3(-2.0, 0, -1.5)  # centre the Kenney model (its AABB starts at 1.5, 1.0)
	add_child(holder)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.0
	tm.outer_radius = 1.2
	tm.rings = 32
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1.0, 0.6, 0.2)
	rm.emission_enabled = true
	rm.emission = Color(1.0, 0.55, 0.15)
	rm.emission_energy_multiplier = 2.0
	ring.material_override = rm
	ring.position.y = 0.4
	add_child(ring)
	_flame = DustFx.make(48, 1.2)
	(_flame.process_material as ParticleProcessMaterial).direction = Vector3(0, -1, 0)
	(_flame.process_material as ParticleProcessMaterial).gravity = Vector3(0, -6, 0)
	_flame.position.y = -0.2
	_flame.emitting = true
	add_child(_flame)
	global_position = target + Vector3(0, 140.0, 0)


func _process(dt: float) -> void:
	age += dt
	if not landed:
		_t += dt
		var u := clampf(_t / FALL_TIME, 0.0, 1.0)
		var ease_out := 1.0 - pow(1.0 - u, 3.0)  # retro-rockets slow it down near the ground
		global_position = target + Vector3(0, 140.0 * (1.0 - ease_out), 0)
		rotation.y += dt * 0.6
		if u >= 1.0:
			_land()


func _land() -> void:
	landed = true
	_flame.emitting = false
	world.rust.press(target, 1.6, 1.0)  # leaves a landing dent in the rust
	world.sfx("impactMetal_002")
	beacon = Beacon.new()
	beacon.title = "Supply pod"
	beacon.color = Color(1.0, 0.65, 0.25)
	add_child(beacon)
	var body := StaticBody3D.new()
	body.collision_layer = 4
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 2.4, 2.2)
	cs.shape = box
	cs.position.y = 1.2
	body.add_child(cs)
	add_child(body)


func open() -> void:
	opened = true
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.0, 0.05, 1.0), 0.6)
	tw.tween_callback(queue_free)
