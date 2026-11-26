class_name World
extends Node3D
## Builds the colony base on an endless Martian plain and owns the gameplay systems.
## mode = "play" or "benchmark".

signal quit_to_menu

const KIT := 2.6  # Kenney kit unit -> metres
const DEPOT := Vector3(10, 0, 3)
const TERMINAL := Vector3(-6, 0, 7)
const GARAGE := Vector3(2, 0, 13)  # open to the south (+z)
const BAYS := [Vector3(-1.5, 0, 13.5), Vector3(5.5, 0, 13.5)]  # parking spots: sweeper, charger
const POSTS := [Vector3(-1.5, 0, 8.3), Vector3(5.5, 0, 8.3)]  # charging posts at the back wall
const SOLAR_ORIGIN := Vector3(-18, 0, -25)
const DEPOT_DRIVE_R := 13.0  # a vehicle this close to the depot can export (the props crowd its east side)
const BED := Vector3(2, 0, 8.75)  # the garage bunk, against the back wall between the bays
const SLEEP_COST := 500  # ₹ for a night in the bunk (air, heat and water), x the difficulty's cost
const SACK_REACH := 1.9  # metres: pick a sack up on foot
const SACK_SCOOP := 2.6  # metres from the Sweeper's centre: its brush scoops a sack up

var mode := "play"
var seed_value := 4242
var world_name := ""
var difficulty := "standard"
var _hex_half := {}  # hexagons we already announced as half clean (this session)
var cart: Handcart
var _sack_nodes: Array[Node3D] = []
var _haul_t := GameState.HAUL_INTERVAL
var load_save := false
var params: Dictionary
var terrain: Terrain
var rust: RustField
var state := GameState.new()
var missions := Missions.new()
var env: Environment
var sun: DirectionalLight3D
var player: Player
var sweeper: Vehicle
var charger: Vehicle
var hud: Hud
var drones: Array[Drone] = []
var drone_hexes: Array[Vector2i] = []
var hex_cache := {}  # Vector2i -> clean fraction
var base_lights: Array[OmniLight3D] = []
var player_fx: GPUParticles3D
var sweeper_fx: GPUParticles3D
var chimney_fx: GPUParticles3D
var solar: MultiMesh
var plugged := {}  # Vehicle -> post index (cable connected)
var cart_linked := false  # charger cart cable connected to the sweeper
var _cables: Array[MeshInstance3D] = []
var _post_screens: Array[StandardMaterial3D] = []
var ui_open := false
var gravity := 3.72
var cleaned_kg_total := 0.0

var _sfx := {}
var _clean_loop: AudioStreamPlayer
var _player_fx_t := 0.0
var _sweeper_fx_t := 0.0
var _autosave_t := 0.0
var _hex_t := 0.0
var _toast_cd := 0.0
var _act := ""
var _act_vehicle: Vehicle
var _post_index := 0
var _labels := {}
var waypoint: Beacon
var pod: SupplyPod
var _pod_timer := 120.0
var _last_rank := 0
var _near_vehicle: Vehicle
var _solar_label: Label3D


func _ready() -> void:
	params = Config.preset_params(Config.resolved_preset())
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 3.72)
	_build_environment()
	state.difficulty = difficulty
	RenderingServer.global_shader_parameter_set("crust_scale", float(state.diff().crust) if mode == "play" else 1.0)
	rust = RustField.new()
	rust.setup(seed_value)
	if mode == "play" and load_save:
		state.load_into(rust)
	terrain = Terrain.new()
	terrain.seed_value = seed_value
	terrain.rust = rust
	add_child(terrain)
	terrain.setup()
	rust.on_track_created = terrain.set_track_texture
	terrain.set_view(params.view_dist)
	if mode == "benchmark":
		# Everything the benchmark visits is built up front at full detail: no streaming
		# during measurement, so both operating systems render exactly the same scene.
		terrain.streaming = false
		terrain.force_hi = true
		terrain.preload_area(Vector3.ZERO, 4)
		state.panels = 24
		state.panel_spots = _legacy_panel_spots(24)
		state.sweeper_owned = true
		state.charger_owned = true
	else:
		terrain.preload_area(state.player_pos, 2)
	_build_base()
	_build_solar_field()
	player_fx = DustFx.make(64, 1.0)
	add_child(player_fx)
	sweeper_fx = DustFx.make(160, 2.2)
	add_child(sweeper_fx)
	_build_cables()
	_setup_audio()
	sweeper = _make_vehicle("sweeper", BAYS[0])
	charger = _make_vehicle("charger", BAYS[1])
	set_drone_zone(Vector2.ZERO, state.drone_range)
	_set_vehicle_present(sweeper, owns(sweeper))
	_set_vehicle_present(charger, owns(charger))
	if mode == "play":
		_start_play()
	apply_quality()
	Config.settings_changed.connect(apply_quality)


func _make_vehicle(kind: String, slot: Vector3) -> Vehicle:
	var v := Vehicle.new()
	v.kind = kind
	v.world = self
	var saved: Array = state.vehicles.get(kind, [])
	var pos := Vector3(saved[0], saved[1], saved[2]) if saved.size() == 4 else slot
	v.heading = float(saved[3]) if saved.size() == 4 else 0.0
	v.rotation.y = v.heading
	v.position = Vector3(pos.x, terrain.height_at(pos.x, pos.z) + 0.3, pos.z)
	add_child(v)
	v.cond = state.wear[kind]  # same dictionary: wear is saved with the game
	if kind == "sweeper":
		v.battery = state.sweeper_battery()
		v.energy = minf(state.sweeper_energy, v.battery)
	else:
		v.battery = GameState.CHARGER_BATT
		v.energy = state.charger_energy
	var l := _label("", Vector3.ZERO, Color(1.0, 0.85, 0.5), 40)
	l.top_level = true
	_labels[kind] = l
	return v


## Vehicles only exist in the world once bought.
func _set_vehicle_present(v: Vehicle, on: bool) -> void:
	v.visible = on
	v.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	v.collision_layer = 8 if on else 0
	(_labels[v.kind] as Label3D).visible = on


func owns(v: Vehicle) -> bool:
	return state.sweeper_owned if v == sweeper else state.charger_owned


func _start_play() -> void:
	player = Player.new()
	player.world = self
	add_child(player)
	player.global_position = state.player_pos
	player.yaw = state.player_yaw
	player.camera.current = true
	for i in state.drones:
		spawn_drone(i)
	if state.sol_start.is_empty():
		state.start_sol_report()
	if state.cart_lvl >= 0:
		_spawn_cart()
	for sk in state.sacks:
		_sack_nodes.append(_make_sack(Vector3(sk[0], sk[1], sk[2]), float(sk[3])))
	_last_rank = state.rank_index()
	for v in [sweeper, charger]:
		apply_livery(v)
	hud = Hud.new()
	hud.world = self
	add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not load_save:
		hud.toast("Aim at rusty ground (crosshair turns orange) and hold LMB to clean.", 8.0)
		hud.toast("Bring the rust to the EXPORT DEPOT [E]. Missions are listed top-left.", 9.0)


# ---------------------------------------------------------------- quality

func apply_quality() -> void:
	params = Config.preset_params(Config.resolved_preset())
	Config.apply_viewport(get_viewport(), params)
	var splits: int = params.shadow_splits
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if splits == 1 else (
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if splits == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	sun.directional_shadow_max_distance = params.shadow_dist
	env.ssao_enabled = params.ssao
	env.ssil_enabled = params.ssil
	env.glow_enabled = params.glow
	env.volumetric_fog_enabled = params.vol_fog
	for l in base_lights:
		l.shadow_enabled = params.omni_shadows
	for d in drones:
		d.set_light(params.drone_lights)
	for v in [sweeper, charger]:
		v.set_headlights(params.headlights)
		v.camera.far = params.view_dist
	if player:
		player.camera.far = params.view_dist
	if mode == "play" and terrain.view_dist != float(params.view_dist):
		terrain.set_view(params.view_dist)
	RenderingServer.global_shader_parameter_set("terrain_pom", float(params.pom))
	RenderingServer.global_shader_parameter_set("hex_overlay", 1.0 if Config.hex_overlay else 0.0)
	var ratio := clampf(float(params.particles) / 1.5, 0.05, 1.0)
	for p in [player_fx, sweeper_fx, chimney_fx]:
		p.amount_ratio = ratio


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.40, 0.29, 0.25)
	sm.sky_horizon_color = Color(0.86, 0.63, 0.46)
	sm.ground_bottom_color = Color(0.22, 0.12, 0.08)
	sm.ground_horizon_color = Color(0.80, 0.56, 0.40)
	sm.sun_angle_max = 12.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.84, 0.60, 0.44)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.35
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.85, 0.6, 0.45)
	env.volumetric_fog_length = 80.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -145, 0)
	sun.light_color = Color(1.0, 0.88, 0.74)
	sun.light_energy = 1.3
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	var to_sun := sun.basis.z
	RenderingServer.global_shader_parameter_set("sun_xz", Vector2(to_sun.x, to_sun.z).normalized())


# ---------------------------------------------------------------- props

func _local_aabb(inst: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D()
		var n: Node = m
		while n != inst and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		var a: AABB = t * (m as MeshInstance3D).get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


## Places a Kenney model centred on its footprint, standing on the ground.
func prop(model: String, x: float, z: float, yaw_deg := 0.0, scl := KIT, collide := true, y_off := 0.0) -> Node3D:
	var holder := Node3D.new()
	var inst: Node3D = load("res://assets/models/%s.glb" % model).instantiate()
	holder.add_child(inst)
	var aabb := _local_aabb(inst)
	inst.position = -Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	holder.scale = Vector3.ONE * scl
	holder.rotation.y = deg_to_rad(yaw_deg)
	holder.position = Vector3(x, terrain.height_at(x, z) + y_off, z)
	add_child(holder)
	holder.set_meta("size", aabb.size * scl)
	if collide:
		# Collide with the model's real surfaces (not its bounding box), so roofs, ramps and
		# openings behave as they look. The Kenney models are low-poly, so this is cheap.
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			var body := StaticBody3D.new()
			body.collision_layer = 4
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			cs.shape = _trimesh_for(mesh)
			body.add_child(cs)
			mi.add_child(body)
	return holder


var _trimesh_cache := {}


func _trimesh_for(mesh: Mesh) -> Shape3D:
	if not _trimesh_cache.has(mesh):
		var sh := mesh.create_trimesh_shape()
		sh.backface_collision = true  # thin shells: solid from both sides
		_trimesh_cache[mesh] = sh
	return _trimesh_cache[mesh]


# ---------------------------------------------------------------- ladders

var ladders: Array[Dictionary] = []  # {base: Vector3 (foot of the ladder), out: Vector3 (away from the wall), h: float}


## A ladder on the face of `holder` that points along `out` (world, horizontal), up to `h` metres.
func _ladder_on(holder: Node3D, out: Vector3, h: float, along := 0.0) -> void:
	var size: Vector3 = holder.get_meta("size")
	var b := holder.global_basis.orthonormalized()
	var half := absf(b.x.dot(out)) * size.x * 0.5 + absf(b.z.dot(out)) * size.z * 0.5
	var side := out.cross(Vector3.UP).normalized()
	var p := holder.global_position + out * (half + 0.12) + side * along
	_ladder(Vector3(p.x, terrain.height_at(p.x, p.z), p.z), out, h)


func _ladder(base: Vector3, out: Vector3, h: float) -> void:
	ladders.append({base = base, out = out.normalized(), h = h})
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.75, 0.2)
	m.metallic = 0.5
	m.roughness = 0.4
	var root := Node3D.new()
	add_child(root)
	root.global_position = base
	root.global_basis = Basis.looking_at(-out, Vector3.UP)
	for x in [-0.28, 0.28]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.06, h + 1.0, 0.06)
		rail.mesh = rm
		rail.material_override = m
		rail.position = Vector3(x, (h + 1.0) * 0.5, 0)
		root.add_child(rail)
	var rung := BoxMesh.new()
	rung.size = Vector3(0.56, 0.04, 0.04)
	var y := 0.3
	while y < h + 0.2:
		var r := MeshInstance3D.new()
		r.mesh = rung
		r.material_override = m
		r.position = Vector3(0, y, 0)
		root.add_child(r)
		y += 0.35


## The ladder the player can climb from here, or {}.
func ladder_near(p: Vector3) -> Dictionary:
	for l in ladders:
		var d: Vector3 = p - l.base
		var lateral := absf(d.dot((l.out as Vector3).cross(Vector3.UP)))
		var front := d.dot(l.out)
		if lateral < 0.55 and front > -0.1 and front < 0.9 and d.y > -0.3 and d.y < float(l.h) + 0.2:
			return l
	return {}


func _label(text: String, pos: Vector3, color: Color, size := 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = size
	l.pixel_size = 0.01
	l.outline_size = 12
	l.modulate = color
	l.outline_modulate = Color(0.1, 0.05, 0.03, 0.9)
	add_child(l)
	return l


func _lamp(pos: Vector3, color: Color, energy := 1.6, rng_m := 11.0) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_m
	add_child(l)
	base_lights.append(l)


func _build_base() -> void:
	var pad := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(38, 0.3, 38)
	pad.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.74, 0.70)
	mat.roughness = 0.85
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	nt.noise = fn
	nt.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.78, 0.76, 0.74))
	ramp.set_color(1, Color(0.95, 0.94, 0.92))
	nt.color_ramp = ramp
	mat.albedo_texture = nt
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.08, 0.08, 0.08)
	pad.material_override = mat
	pad.position = Vector3(0, -0.05, 0)
	add_child(pad)
	var pad_body := StaticBody3D.new()
	pad_body.collision_layer = 4
	# Collide with a bevelled slab: a 1 m ramp all round lets vehicles (whose bodies cannot step
	# up) drive on and off the pad; its vertical edge used to stop them dead.
	var pcs := CollisionShape3D.new()
	var slab := ConvexPolygonShape3D.new()
	var top_h := pm.size.x * 0.5
	var top_y := pad.position.y + pm.size.y * 0.5
	var pts := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			pts.append(Vector3(sx * top_h, top_y, sz * top_h))
			pts.append(Vector3(sx * (top_h + 1.2), -0.25, sz * (top_h + 1.2)))
	slab.points = pts
	pcs.shape = slab
	pad_body.add_child(pcs)
	add_child(pad_body)

	_ladder_on(prop("hangar_largeA", -13, -5, 90, 4.2), Vector3.RIGHT, 4.2, 2.5)
	_ladder_on(prop("hangar_roundGlass", 11, -12, 0, 3.0), Vector3.FORWARD * -1.0, 3.6, 3.0)
	_ladder_on(prop("hangar_smallA", -13, 11, 0, 3.0), Vector3.RIGHT, 3.0)
	prop("machine_generatorLarge", DEPOT.x + 2.5, DEPOT.z, -90, 4.5)
	prop("machine_barrelLarge", DEPOT.x + 4, DEPOT.z + 6, 0, 4.0)
	prop("machine_barrel", DEPOT.x + 5.5, DEPOT.z - 6, 30, 3.5)
	var chimney := prop("chimney_detailed", DEPOT.x + 6, DEPOT.z - 2, 0, 3.0)
	prop("machine_wireless", TERMINAL.x - 1, TERMINAL.z, 90, 2.6)
	prop("satelliteDish_large", -14, -16, 30, 5.0)
	prop("barrels", 4, -9, 10, 3.0)
	prop("structure", 15, 13, 0, 3.0)
	prop("craft_cargoA", -1, -13, 200, 3.2)
	prop("astronautA", TERMINAL.x - 1.5, TERMINAL.z + 2.2, 200, 2.3, false)
	prop("astronautA", DEPOT.x - 1.0, DEPOT.z + 3.5, 140, 2.3, false)
	var y := 0.0
	for part in ["rocket_baseA", "rocket_fuelA", "rocket_sidesA", "rocket_topA"]:
		var h := prop(part, 15, -2, 0, 2.6, part == "rocket_baseA", y)
		y += (h.get_meta("size") as Vector3).y
	chimney_fx = DustFx.make(48, 2.5)
	chimney_fx.emitting = true
	(chimney_fx.process_material as ParticleProcessMaterial).gravity = Vector3(0.6, 0.8, 0.2)
	chimney_fx.lifetime = 4.0
	chimney_fx.position = chimney.position + Vector3(0, (chimney.get_meta("size") as Vector3).y, 0)
	add_child(chimney_fx)

	_build_garage()
	_build_bunk()
	# Outside the roof's overhang (the roof reaches x + 7.3), so your head clears the eave.
	_ladder(Vector3(GARAGE.x + 7.42, terrain.height_at(GARAGE.x + 7.42, GARAGE.z), GARAGE.z - 2.0), Vector3.RIGHT, 5.3)

	_label("EXPORT DEPOT  [E]", DEPOT + Vector3(2.5, 4.5, 0), Color(1.0, 0.75, 0.45))
	_label("BASE TERMINAL  [E]", TERMINAL + Vector3(-1, 2.8, 0), Color(0.6, 0.9, 1.0))
	_label("GARAGE · CHARGING", GARAGE + Vector3(0, 6.2, 5.5), Color(0.5, 1.0, 0.65))
	_solar_label = _label("SOLAR FIELD", SOLAR_ORIGIN + Vector3(18, 4.5, -2), Color(0.6, 0.8, 1.0))

	_lamp(DEPOT + Vector3(0, 3.5, 2), Color(1.0, 0.7, 0.4))
	_lamp(TERMINAL + Vector3(0, 3.0, 0), Color(0.5, 0.8, 1.0))
	_lamp(GARAGE + Vector3(0, 4.2, 0), Color(0.85, 1.0, 0.9), 2.0, 12.0)
	_lamp(Vector3(-10, 4, -2), Color(1.0, 0.8, 0.6))
	_lamp(Vector3(8, 4, -9), Color(0.7, 1.0, 0.8))
	_lamp(Vector3(16, 4, 8), Color(1.0, 0.75, 0.5))


## Solar panels you buy appear here; they feed the base battery bank.
func _build_solar_field() -> void:
	if state.panels > 0 and state.panel_spots.is_empty():
		state.panel_spots = _legacy_panel_spots(state.panels)  # saves from before panels were placed by hand
	var panel := BoxMesh.new()
	panel.size = Vector3(3.0, 0.08, 1.8)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.08, 0.12, 0.25)
	pmat.metallic = 0.7
	pmat.roughness = 0.25
	panel.material = pmat
	var pole := BoxMesh.new()
	pole.size = Vector3(0.15, 1.4, 0.15)
	var polemat := StandardMaterial3D.new()
	polemat.albedo_color = Color(0.7, 0.7, 0.72)
	pole.material = polemat
	var mms: Array[MultiMesh] = []
	for mesh in [panel, pole]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = GameState.MAX_PANELS
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		mms.append(mm)
	for i in GameState.MAX_PANELS:
		var x := SOLAR_ORIGIN.x + (i % 10) * 4.0
		var z := SOLAR_ORIGIN.z - (i / 10) * 4.5
		var h := terrain.height_at(x, z)
		mms[0].set_instance_transform(i, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-25)), Vector3(x, h + 1.45, z)))
		mms[1].set_instance_transform(i, Transform3D(Basis(), Vector3(x, h + 0.7, z)))
	solar = mms[0]
	solar.set_meta("poles", mms[1])
	_refresh_solar()


## Older saves (and the benchmark) had panels on a fixed grid: keep them where they were.
func _legacy_panel_spots(n: int) -> Array:
	var out := []
	for i in n:
		out.append([SOLAR_ORIGIN.x + (i % 10) * 4.0, SOLAR_ORIGIN.z - (i / 10) * 4.5, 0.0])
	return out


static func panel_transform(t: Terrain, spot: Array) -> Array[Transform3D]:
	var x: float = spot[0]
	var z: float = spot[1]
	var h := t.height_at(x, z)
	var yb := Basis(Vector3.UP, float(spot[2]))
	return [Transform3D(yb * Basis(Vector3.RIGHT, deg_to_rad(-25)), Vector3(x, h + 1.45, z)), Transform3D(yb, Vector3(x, h + 0.7, z))]


var _panel_bodies: Array[StaticBody3D] = []


func _refresh_solar() -> void:
	state.panels = state.panel_spots.size()
	_solar_label.visible = false
	var poles: MultiMesh = solar.get_meta("poles")
	for i in state.panel_spots.size():
		var tr := panel_transform(terrain, state.panel_spots[i])
		solar.set_instance_transform(i, tr[0])
		poles.set_instance_transform(i, tr[1])
	solar.visible_instance_count = state.panels
	poles.visible_instance_count = state.panels
	# Solid panels: you can't walk through them (and can climb onto them).
	for b in _panel_bodies:
		b.queue_free()
	_panel_bodies.clear()
	for spot in state.panel_spots:
		var tr := panel_transform(terrain, spot)
		var body := StaticBody3D.new()
		body.collision_layer = 4
		for part in [[Vector3(3.0, 0.08, 1.8), tr[0]], [Vector3(0.15, 1.4, 0.15), tr[1]]]:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = part[0]
			cs.shape = bs
			cs.transform = part[1]
			body.add_child(cs)
		add_child(body)
		_panel_bodies.append(body)


# ---------------------------------------------------------------- placing solar panels

const PANEL_RANGE := 60.0  # metres from the base centre: panels must be on the base grid
var placing := false
var _ghost: Node3D
var _ghost_mat: StandardMaterial3D
var _ghost_yaw := 0.0
var _ghost_spot := []
var _ghost_why := ""


func toggle_placing() -> void:
	if placing:
		_end_placing()
		return
	if state.panel_stock <= 0:
		hud.toast("No solar panels to place. Buy them at the base terminal (Power tab).", 2.5)
		return
	if driven() or (cart and cart.pushing):
		return
	placing = true
	if _ghost == null:
		_ghost = Node3D.new()
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for part in [[Vector3(3.0, 0.08, 1.8), "panel"], [Vector3(0.15, 1.4, 0.15), "pole"]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = part[0]
			mi.mesh = bm
			mi.material_override = _ghost_mat
			mi.name = part[1]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ghost.add_child(mi)
		add_child(_ghost)
	_ghost.visible = true


func _end_placing() -> void:
	placing = false
	if _ghost:
		_ghost.visible = false


func _update_placing() -> String:
	var cam := get_viewport().get_camera_3d()
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 14.0, 1 | 4)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3
	if hit:
		at = hit.position
	else:
		at = from - cam.global_basis.z * 14.0
	at = Vector3(snappedf(at.x, 0.5), 0.0, snappedf(at.z, 0.5))
	_ghost_spot = [at.x, at.z, _ghost_yaw]
	var tr := panel_transform(terrain, _ghost_spot)
	(_ghost.get_node("panel") as Node3D).global_transform = tr[0]
	(_ghost.get_node("pole") as Node3D).global_transform = tr[1]
	_ghost_why = _panel_spot_problem(_ghost_spot, hit)
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.45, 0.45) if _ghost_why == "" else Color(1.0, 0.3, 0.25, 0.45)
	if _ghost_why != "":
		return "Can't place here: %s   ·   R rotate · Esc/P cancel" % _ghost_why
	return "[LMB] Place solar panel (%d left)   ·   R rotate · Esc/P cancel" % state.panel_stock


func _panel_spot_problem(spot: Array, hit: Dictionary) -> String:
	var p := Vector3(spot[0], 0, spot[1])
	if hit.is_empty() or (hit.collider as CollisionObject3D).collision_layer != 1:
		return "aim at open ground"
	if Vector2(p.x, p.z).length() > PANEL_RANGE:
		return "too far from the base grid (max %d m)" % int(PANEL_RANGE)
	if terrain.normal_at(p.x, p.z).y < 0.95:
		return "too steep"
	if absf(p.x - GARAGE.x) < 8.5 and p.z > GARAGE.z - 7.0 and p.z < GARAGE.z + 12.0:
		return "keep the garage and its entrance clear"
	for keep in [DEPOT, TERMINAL]:
		if _flat_dist(p, keep) < 5.5:
			return "too close to the %s" % ("export depot" if keep == DEPOT else "terminal")
	for other in state.panel_spots:
		if Vector2(float(other[0]) - p.x, float(other[1]) - p.z).length() < 3.3:
			return "too close to another panel"
	var tr := panel_transform(terrain, spot)
	var sq := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.1, 1.6, 2.0)
	sq.shape = box
	sq.transform = Transform3D(tr[1].basis, tr[1].origin + Vector3(0, 0.25, 0))
	sq.collision_mask = 4 | 8
	if not get_world_3d().direct_space_state.intersect_shape(sq, 1).is_empty():
		return "something is in the way"
	return ""


func place_panel() -> void:
	if not placing or _ghost_why != "" or state.panel_stock <= 0:
		if placing and _ghost_why != "":
			_warn("Can't place here: " + _ghost_why)
		return
	state.panel_spots.append(_ghost_spot.duplicate())
	state.panel_stock -= 1
	_refresh_solar()
	sfx("impactMetal_002")
	hud.toast("Solar panel placed: %d installed, +%.0f kW in daylight." % [state.panels, state.gen_kw()], 2.5)
	if state.panel_stock <= 0:
		_end_placing()


func _panel_near(p: Vector3) -> int:
	for i in state.panel_spots.size():
		var s: Array = state.panel_spots[i]
		if Vector2(float(s[0]) - p.x, float(s[1]) - p.z).length() < 2.4:
			return i
	return -1


## Garage: back wall, side walls and roof, open to the south, with a charging post per bay.
## A steel-framed bunk with a mattress, pillow and blanket, plus a reading lamp.
func _build_bunk() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.34, 0.37)
	steel.metallic = 0.6
	steel.roughness = 0.45
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.86, 0.84, 0.8)
	cloth.roughness = 1.0
	var blanket := StandardMaterial3D.new()
	blanket.albedo_color = Color(0.18, 0.27, 0.42)
	blanket.roughness = 1.0
	var bunk := Node3D.new()
	bunk.position = Vector3(BED.x, terrain.height_at(BED.x, BED.z) + 0.1, BED.z)
	add_child(bunk)
	for part in [
		[Vector3(1.0, 0.08, 2.1), Vector3(0, 0.38, 0), steel],  # base
		[Vector3(0.06, 0.42, 0.06), Vector3(-0.47, 0.21, -1.02), steel], [Vector3(0.06, 0.42, 0.06), Vector3(0.47, 0.21, -1.02), steel],
		[Vector3(0.06, 0.42, 0.06), Vector3(-0.47, 0.21, 1.02), steel], [Vector3(0.06, 0.42, 0.06), Vector3(0.47, 0.21, 1.02), steel],
		[Vector3(1.0, 0.5, 0.06), Vector3(0, 0.62, -1.04), steel],  # headboard (wall side)
		[Vector3(0.94, 0.16, 2.0), Vector3(0, 0.5, 0), cloth],  # mattress
		[Vector3(0.6, 0.1, 0.32), Vector3(0, 0.63, -0.78), cloth],  # pillow
		[Vector3(0.98, 0.06, 1.3), Vector3(0, 0.6, 0.33), blanket]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		mi.mesh = bm
		mi.position = part[1]
		mi.material_override = part[2]
		bunk.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 0.6, 2.1)
	cs.shape = bs
	cs.position.y = 0.3
	body.add_child(cs)
	bunk.add_child(body)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.45, 1.6, -1.0)
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.light_energy = 0.8
	lamp.omni_range = 3.5
	bunk.add_child(lamp)
	var l := Label3D.new()
	l.text = "Bunk  ·  sleep at night"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.font_size = 22
	l.pixel_size = 0.0011
	l.outline_size = 8
	l.modulate = Color(0.75, 0.85, 1.0)
	l.position = Vector3(0, 1.5, -0.6)
	bunk.add_child(l)


# ---------------------------------------------------------------- sleeping

var sleeping := false


## Night runs from 17:15 to 05:15; you can only sleep then.
func is_bedtime() -> bool:
	return state.time_of_day >= 0.72 or state.time_of_day < 0.22


func sleep_cost() -> float:
	return roundf(SLEEP_COST * float(state.diff().cost) / 50.0) * 50.0


static func clock(t: float) -> String:
	var mins := int(t * 24.0 * 60.0) % (24 * 60)
	return "%02d:%02d" % [mins / 60, mins % 60]


## Pay for the bunk, fade out, run the night forward to 06:30 (plugged-in vehicles charge from
## the base battery, the hauler still calls, the Sol report fires at midnight), then wake up.
func go_to_sleep() -> void:
	if sleeping or not is_bedtime():
		return
	var cost := sleep_cost()
	if state.credits < cost:
		hud.toast("A night in the bunk costs %s (air, heat and water). Export some rust first." % GameState.inr(cost), 3.5)
		return
	state.credits -= cost
	sleeping = true
	ui_open = true
	player.set_torch(false)
	await hud.fade(1.0, 1.4, "Sleeping...")
	var wake := 0.27
	var left := fposmod(wake - state.time_of_day, 1.0) * GameState.SOL_SECONDS
	var steps := 96
	for i in steps:
		var dt := left / steps
		_update_daycycle(dt)
		_update_power(dt)
		_update_hauler(dt)
	state.time_of_day = wake
	_sky_t = 0.0
	_update_daycycle(0.0)
	save_game()
	await get_tree().create_timer(0.6).timeout
	await hud.fade(0.0, 1.6, "")
	ui_open = false
	sleeping = false
	var plugged_note := ""
	for v in plugged.keys():
		plugged_note += "  ·  %s %d%%" % [v.display_name(), roundi(v.energy / v.battery * 100.0)]
	hud.toast("Good morning: Sol %d, %s. The bunk cost %s.%s" % [state.sol, clock(state.time_of_day), GameState.inr(cost), plugged_note], 5.0)
	sfx("bell")


func _build_garage() -> void:
	var wall_m := StandardMaterial3D.new()
	wall_m.albedo_color = Color(0.86, 0.86, 0.84)
	wall_m.roughness = 0.6
	wall_m.metallic = 0.3
	var roof_m := StandardMaterial3D.new()
	roof_m.albedo_color = Color(0.55, 0.57, 0.6)
	roof_m.metallic = 0.5
	roof_m.roughness = 0.4
	var stripe_m := StandardMaterial3D.new()
	stripe_m.albedo_color = Color(0.95, 0.5, 0.15)
	var back := GARAGE.z - 5.5
	var parts := [
		[Vector3(14.0, 5.0, 0.3), Vector3(GARAGE.x, 2.5, back), wall_m],
		[Vector3(0.3, 5.0, 11.0), Vector3(GARAGE.x - 7.0, 2.5, GARAGE.z), wall_m],
		[Vector3(0.3, 5.0, 11.0), Vector3(GARAGE.x + 7.0, 2.5, GARAGE.z), wall_m],
		[Vector3(14.6, 0.25, 11.3), Vector3(GARAGE.x, 5.1, GARAGE.z), roof_m],
		[Vector3(14.62, 0.5, 0.1), Vector3(GARAGE.x, 4.6, GARAGE.z + 5.6), stripe_m],
	]
	var body := StaticBody3D.new()
	body.collision_layer = 4
	add_child(body)
	for part in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		mi.mesh = bm
		mi.material_override = part[2]
		mi.position = part[1]
		add_child(mi)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = part[0]
		cs.shape = box
		cs.position = part[1]
		body.add_child(cs)
	# Bay floor markings.
	var line_m := StandardMaterial3D.new()
	line_m.albedo_color = Color(1.0, 0.85, 0.3)
	line_m.emission_enabled = true
	line_m.emission = Color(1.0, 0.8, 0.3)
	line_m.emission_energy_multiplier = 0.4
	for x in [GARAGE.x - 6.8, GARAGE.x, GARAGE.x + 6.8]:
		var l := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.12, 0.02, 10.5)
		l.mesh = lm
		l.material_override = line_m
		l.position = Vector3(x, 0.11, GARAGE.z + 0.2)
		add_child(l)
	# Charging posts: a pillar with a status screen and a cable holster.
	var post_m := StandardMaterial3D.new()
	post_m.albedo_color = Color(0.2, 0.22, 0.25)
	post_m.metallic = 0.6
	post_m.roughness = 0.35
	for i in POSTS.size():
		var p: Vector3 = POSTS[i]
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.5, 1.7, 0.4)
		post.mesh = pm
		post.material_override = post_m
		post.position = p + Vector3(0, 0.95, 0)
		add_child(post)
		var scr_m := StandardMaterial3D.new()
		scr_m.albedo_color = Color(0.1, 0.3, 0.2)
		scr_m.emission_enabled = true
		scr_m.emission = Color(0.2, 0.9, 0.5)
		scr_m.emission_energy_multiplier = 0.3
		var scr := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.36, 0.3, 0.02)
		scr.mesh = sm
		scr.material_override = scr_m
		scr.position = p + Vector3(0, 1.45, 0.21)
		add_child(scr)
		_post_screens.append(scr_m)
		var pcs := CollisionShape3D.new()
		var pb := BoxShape3D.new()
		pb.size = pm.size
		pcs.shape = pb
		pcs.position = post.position
		body.add_child(pcs)


func _build_cables() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.08, 0.09)
	m.roughness = 0.6
	m.emission_enabled = true
	m.emission = Color(0.2, 0.8, 0.4)
	m.emission_energy_multiplier = 0.25
	for i in 6:  # three cables x two sagging segments
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.035
		cm.height = 1.0
		cm.radial_segments = 10
		c.mesh = cm
		c.material_override = m
		c.visible = false
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		_cables.append(c)


func _segment(c: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.UP)
	x = Vector3.RIGHT if x.length_squared() < 0.0001 else x.normalized()
	c.global_transform = Transform3D(Basis(x, y * d.length(), x.cross(y)), (a + b) * 0.5)
	c.visible = true


## Draws cable `slot` (0..2) from a to b with a little sag.
func _draw_cable(slot: int, a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5 - Vector3(0, 0.35 + a.distance_to(b) * 0.06, 0)
	_segment(_cables[slot * 2], a, mid)
	_segment(_cables[slot * 2 + 1], mid, b)


func charge_port(v: Vehicle) -> Vector3:
	return v.global_position + v.forward() * (1.7 if v == sweeper else 1.5) + Vector3(0, 1.0, 0)


func bay_of(v: Vehicle) -> int:
	for i in BAYS.size():
		if _flat_dist(v.global_position, BAYS[i]) < 2.6:
			return i
	return -1


func is_tethered(v: Vehicle) -> bool:
	return plugged.has(v) or (cart_linked and (v == sweeper or v == charger))


# ---------------------------------------------------------------- audio

func _setup_audio() -> void:
	for n in ["impactMetal_002", "doorOpen_001", "thrusterFire_000"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/sfx/%s.ogg" % n)
		p.volume_db = -8.0
		add_child(p)
		_sfx[n] = p
	# Synthesised, natural-sounding effects (no bleeps): see SoundBank.
	for n in ["latch", "click", "ratchet", "sack", "bell"]:
		var p := AudioStreamPlayer.new()
		p.stream = SoundBank.make(n)
		p.volume_db = -4.0 if n != "bell" else -7.0
		add_child(p)
		_sfx[n] = p
	_pour = AudioStreamPlayer.new()
	_pour.stream = SoundBank.make("pour")
	_pour.volume_db = -10.0
	add_child(_pour)
	_clean_loop = AudioStreamPlayer.new()
	var st: AudioStreamOggVorbis = load("res://assets/sfx/spaceEngineLow_000.ogg")
	st.loop = true
	_clean_loop.stream = st
	_clean_loop.volume_db = -50.0
	add_child(_clean_loop)


func sfx(n: String) -> void:
	if _sfx.has(n) and mode == "play" and not _sfx[n].playing:
		_sfx[n].play()


# ---------------------------------------------------------------- timed jobs (unloading takes time)

var _pour: AudioStreamPlayer
var _pouring := false  # set each frame by whatever is moving rust right now
var task := {}  # {label, t, dur, done: Callable, who: Node3D, at: Vector3}

const TASK_RATES := {tank = 15.0, cart = 40.0, hopper = 110.0, sack = 15.0}  # kg per second
const TASK_MAX := {tank = 7.0, cart = 8.0, hopper = 10.0, sack = 6.0}  # seconds, at most
const SCOOP_RATE := 150.0  # kg/s the Sweeper's brush lifts out of a sack


## Seconds to move `kg` of rust by `how` (tank, cart, hopper or sack): a second to get set, then
## the pour itself.
static func task_time(how: String, kg: float) -> float:
	return minf(1.0 + kg / float(TASK_RATES[how]), float(TASK_MAX[how]))


func busy() -> bool:
	return not task.is_empty()


## Starts a job that runs `done` after `dur` seconds unless `who` (the player or a vehicle) moves.
func start_task(label: String, dur: float, who: Node3D, done: Callable) -> void:
	if busy():
		return
	task = {label = label, t = 0.0, dur = dur, done = done, who = who, at = who.global_position}


func cancel_task(why := "") -> void:
	if not busy():
		return
	task = {}
	if why != "":
		hud.toast(why, 2.0)


func _update_task(dt: float) -> void:
	if busy():
		var who: Node3D = task.who
		var moved := _flat_dist(who.global_position, task.at) > 0.7
		if who is Vehicle and (absf((who as Vehicle).speed) > 0.8 or driven() != who):
			moved = true
		if who == player and not player.active:
			moved = true
		if moved:
			cancel_task("Stopped: %s. Stand still until it finishes." % String(task.label).to_lower())
		else:
			task.t += dt
			_pouring = true
			if task.t >= task.dur:
				var done: Callable = task.done
				task = {}
				done.call()
				sfx("latch")
	if _pouring and mode == "play":
		if not _pour.playing:
			_pour.play()
	elif _pour.playing:
		_pour.stop()
	_pouring = false


func task_prompt() -> String:
	var f := clampf(task.t / task.dur, 0.0, 1.0)
	var bars := roundi(f * 20.0)
	return "%s  %s%s  %d%%   ·  moving cancels" % [task.label, "|".repeat(bars), ".".repeat(20 - bars), roundi(f * 100.0)]


# ---------------------------------------------------------------- cleaning (every cleaner yields rust)

func player_clean(pos: Vector3, tool: Dictionary, dt: float) -> bool:
	if busy():
		return false
	var free := state.capacity() - state.tank
	if free <= 0.01:
		_warn("Rust tank full! Export it at the depot, tip it into your handcart (Q), or Q to drop a sack for the hauler.")
		return false
	var h := state.crust_at(pos.x, pos.z)
	var cf := GameState.crust_factor(state.tool_lvl, h)
	if cf < 1.0 and mode == "play":
		_warn("%s: too hard for the %s (cleaning at %d%%). Needs the %s or better." % [
			GameState.CRUST_NAMES[h], tool.name, roundi(cf * 100.0), GameState.TOOLS[h].name])
	var kg := rust.paint(pos, tool.radius, float(tool.rate) * dt * cf)
	if kg <= 0.0:
		return false
	var lvl0 := state.mastery_level()
	var key := str(state.tool_lvl)
	state.mastery_kg[key] = float(state.mastery_kg.get(key, 0.0)) + kg
	if state.mastery_level() > lvl0 and mode == "play":
		var lv := state.mastery_level()
		hud.toast("%s mastery %s  ·  +%d%% speed  ·  upgrades up to level %d unlocked" % [
			tool.name, "★".repeat(lv), roundi(lv * GameState.MASTERY_BONUS * 100.0), lv], 5.0, Color(1.0, 0.85, 0.35))
		sfx("bell")
	state.tank = minf(state.tank + kg, state.capacity())
	state.collected += kg
	state.sol_kg.you += kg
	_dig(kg)
	cleaned_kg_total += kg
	_player_fx_t = 0.12
	player_fx.global_position = pos
	return true


func vehicle_clean(_v: Vehicle, pos: Vector3, radius: float, strength: float) -> void:
	if mode == "play" and state.hopper >= GameState.SWEEPER_HOPPER:
		_warn("Sweeper hopper full! Press Q at the export depot, or Q anywhere to bag it into a sack.")
		return
	var cf := GameState.crust_factor(GameState.SWEEPER_TIER, state.crust_at(pos.x, pos.z))
	if cf < 1.0 and mode == "play":
		_warn("Crust IV is too hard for the Sweeper's roller. Clean it on foot with a top-tier tool.")
	var kg := rust.paint(pos, radius, strength * cf)
	if kg > 0.0:
		state.hopper = minf(state.hopper + kg, GameState.SWEEPER_HOPPER)
		state.collected += kg
		state.sol_kg.sweeper += kg
		_dig(kg)
		cleaned_kg_total += kg
		_sweeper_fx_t = 0.12
		sweeper_fx.global_position = pos


func drone_clean(pos: Vector3, radius: float, strength: float) -> bool:
	var kg := rust.paint(pos, radius, strength * GameState.crust_factor(GameState.DRONE_TIER, state.crust_at(pos.x, pos.z)))
	if kg > 0.0:
		var c := kg * state.price_now() * GameState.DRONE_SHARE
		state.credits += c
		state.earned += c
		state.total_sold += kg
		state.collected += kg
		state.sol_kg.drones += kg
		cleaned_kg_total += kg
		return true
	return false


## Every so often, cleaning uncovers something buried under the rust.
func _dig(kg: float) -> void:
	if mode != "play":
		return
	state.dig_meter += kg
	if state.dig_meter < state.next_relic_kg:
		return
	state.dig_meter = 0.0
	state.next_relic_kg = randf_range(70.0, 160.0) * (1.0 + state.relics_found.size() * 0.25)
	var left := []
	for r in GameState.RELICS:
		if not state.relics_found.has(r.name):
			left.append(r)
	var found: Dictionary = left.pick_random() if not left.is_empty() else {name = "Meteorite fragment", value = 600}
	if not left.is_empty():
		state.relics_found.append(found.name)
	state.credits += found.value
	state.earned += found.value
	hud.toast("Found under the rust: %s  +%s   (relics %d/%d)" % [found.name, GameState.inr(found.value),
		state.relics_found.size(), GameState.RELICS.size()], 5.0, Color(1.0, 0.85, 0.4))
	sfx("bell")


func vehicle_broken(v: Vehicle) -> void:
	if hud:
		hud.toast("%s drive motor has failed! Tow it to the garage (%s) and repair it in the Workshop." % [v.display_name(), GameState.inr(GameState.TOW_COST)], 7.0, Color(1, 0.55, 0.4))


var _wear_warned := {}


## Warns once per part as it passes 50%, 25% and failure.
func _check_wear() -> void:
	for v in [sweeper, charger]:
		if not owns(v):
			continue
		for part in v.cond:
			var c: float = v.cond[part]
			for level in [0.5, 0.25, 0.0]:
				var key := "%s/%s/%.2f" % [v.kind, part, level]
				if c <= level and not _wear_warned.has(key):
					_wear_warned[key] = true
					if hud and level < 0.5 or hud and v.driving:
						var what: String = GameState.PART_NAMES[part]
						var msg := "%s: %s %s" % [v.display_name(), what, "FAILED" if level == 0.0 else "worn to %d%%" % roundi(c * 100.0)]
						hud.toast(msg + "  ·  repair at the garage Workshop", 4.0, Color(1, 0.7, 0.4))
				elif c > level + 0.05:
					_wear_warned.erase(key)


func vehicle_flat(v: Vehicle) -> void:
	if hud:
		hud.toast("%s battery is flat! Bring the charger cart, or tow it from the terminal (%s)." % [v.display_name(), GameState.inr(GameState.TOW_COST)], 6.0)


func _warn(msg: String) -> void:
	if _toast_cd <= 0.0 and hud:
		hud.toast(msg, 2.5)
		_toast_cd = 4.0


## Q in the sweeper: export at the depot, otherwise bag the load into a sack behind the Sweeper.
## The sack keeps every kilogram: drive over it with the brush on to scoop it back up, pick it up
## on foot (E), or leave it for the hauler.
func empty_hopper() -> void:
	if state.hopper <= 0.05:
		hud.toast("Hopper is already empty.", 2.0)
		return
	if busy():
		return
	var kg := state.hopper
	if absf(sweeper.speed) > 0.8:
		hud.toast("Stop the Sweeper to empty the hopper.", 2.0)
		return
	if _flat_dist(sweeper.global_position, DEPOT) < DEPOT_DRIVE_R:
		start_task("Tipping %.0f kg into the depot" % kg, task_time("hopper", kg), sweeper, func():
			var c := state.sell(state.hopper)
			hud.toast("Exported %.0f kg from the hopper  ->  +%s" % [state.hopper, GameState.inr(c)], 3.0)
			state.hopper = 0.0)
	else:
		start_task("Bagging %.0f kg into a sack" % kg, task_time("hopper", kg), sweeper, func():
			# Behind the Sweeper, so the brush (at the front) does not scoop it straight back up.
			_drop_sack(sweeper.global_position - sweeper.forward() * 3.6, state.hopper)
			hud.toast("Bagged %.0f kg into a rust sack. Scoop it up later with the brush, carry it (E), or leave it for the hauler (%d%% fee)." % [
				state.hopper, roundi(state.haul_fee() * 100.0)], 4.5)
			state.hopper = 0.0
			sfx("sack"))


# ---------------------------------------------------------------- hexagons and drones

static func hex_ring_dist(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return dy + maxi(0, (dx - dy) / 2)


## Drones may only work inside hexagons within `rings` steps of the hex containing `center`.
func set_drone_zone(center: Vector2, rings: int) -> void:
	drone_hexes.clear()
	var c := RustField.hex_key(center.x, center.y)
	for ky in range(c.y - rings, c.y + rings + 1):
		for kx in range(c.x - 2 * rings, c.x + 2 * rings + 1):
			var k := Vector2i(kx, ky)
			if (kx - c.x + ky - c.y) % 2 == 0 and hex_ring_dist(k, c) <= rings:
				drone_hexes.append(k)


func spawn_drone(i: int, home := Vector3.INF) -> Drone:
	var d := Drone.new()
	if home == Vector3.INF:
		home = DEPOT + Vector3(-2.0 + (i % 5) * 1.2, 0, 4.0 + (i / 5) * 1.2)
	d.setup(self, home, seed_value * 31 + i, float(params.particles) if params else 1.0)
	d.position = home + Vector3(0, terrain.height_at(home.x, home.z) + 2.0, 0)
	add_child(d)
	if params:
		d.set_light(params.drone_lights)
	drones.append(d)
	return d


func _poll_hexes() -> void:
	for k in rust.touched_hexes:
		var c := rust.hex_clean(k)
		hex_cache[k] = c
		if mode != "play":
			continue
		var hn := RustField.hex_name(k)
		if state.hexes_cleared.has(hn) or rust.hex_pristine_kg(k) < 40.0:
			continue  # already paid, or nothing much there (the landing pad)
		var bonus := hex_bonus(k)
		if c >= GameState.HEX_CLEAR:
			state.hexes_cleared.append(hn)
			state.credits += bonus
			state.earned += bonus
			hud.toast("HEXAGON %s CLEARED  ·  bonus +%s" % [hn, GameState.inr(bonus)], 5.0, Color(1.0, 0.85, 0.35))
			sfx("bell")
		elif c >= 0.5 and not _hex_half.has(k):
			_hex_half[k] = true
			hud.toast("Hexagon %s is half clean  ·  %s bonus at 90%%" % [hn, GameState.inr(bonus)], 3.5)
	rust.touched_hexes.clear()


# ---------------------------------------------------------------- handcart, sacks and the hauler

func _spawn_cart() -> void:
	cart = Handcart.new()
	cart.world = self
	add_child(cart)
	var cp: Array = state.cart.pos
	cart.place(Vector3(cp[0], cp[1], cp[2]), float(state.cart.yaw))
	cart.load_kg = float(state.cart.kg)
	cart._update_fill()


## kg in the handcart if it is parked (or pushed) close enough to the depot to export.
func _cart_at_depot() -> float:
	if cart and cart.load_kg > 0.0 and _flat_dist(cart.global_position, DEPOT) < 9.0:
		return cart.load_kg
	return 0.0


## Q on foot: tip the tank into the handcart if it is close, otherwise drop a sack for the hauler.
func unload_tank() -> void:
	if state.tank < 0.5:
		_warn("Your rust tank is empty.")
		return
	if busy():
		return
	if cart and _flat_dist(player.global_position, cart.global_position) < 3.2:
		if cart.space() <= 0.5:
			hud.toast("The handcart is full. Push it to the export depot.", 2.5)
			return
		var kg := minf(state.tank, cart.space())
		start_task("Tipping %.0f kg into the handcart" % kg, task_time("tank", kg), player, func():
			var put := cart.add(state.tank)
			state.tank -= put
			hud.toast("Tipped %.0f kg into the handcart (%.0f / %.0f kg)." % [put, cart.load_kg, cart.capacity()], 2.0))
		return
	if _flat_dist(player.global_position, DEPOT) < 6.5:
		return  # at the depot E exports at full price
	start_task("Filling a sack with %.0f kg" % state.tank, task_time("tank", state.tank), player, func():
		_drop_sack(player.global_position - Vector3(sin(player.yaw), 0, cos(player.yaw)) * 0.9, state.tank)
		hud.toast("Dropped a %.0f kg rust sack. The hauler collects sacks every %d min (%d%% haulage fee)." % [
			state.tank, roundi(GameState.HAUL_INTERVAL / 60.0), roundi(state.haul_fee() * 100.0)], 4.0)
		state.tank = 0.0
		sfx("sack"))


func _drop_sack(at: Vector3, kg: float) -> void:
	var p := Vector3(at.x, terrain.height_at(at.x, at.z), at.z)
	state.sacks.append([p.x, p.y, p.z, kg])
	_sack_nodes.append(_make_sack(p, kg))


## Index of the closest sack within `reach` metres of `p`, or -1.
func sack_near(p: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in state.sacks.size():
		var sk: Array = state.sacks[i]
		var d := Vector2(float(sk[0]) - p.x, float(sk[2]) - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best


## Takes up to `kg` out of sack `i` (removing it once empty); returns how much came out.
func take_from_sack(i: int, kg: float) -> float:
	var sk: Array = state.sacks[i]
	var got := minf(kg, float(sk[3]))
	sk[3] = float(sk[3]) - got
	if float(sk[3]) < 0.05:
		_sack_nodes[i].queue_free()
		_sack_nodes.remove_at(i)
		state.sacks.remove_at(i)
	else:
		_size_sack(_sack_nodes[i], float(sk[3]))
	return got


## On foot: empty sack `i` into the handcart if it is beside you, otherwise into your tank. Takes
## a few seconds; moving away cancels.
func pick_up_sack(i: int) -> void:
	if busy():
		return
	var into_cart := cart and (cart.pushing or _flat_dist(player.global_position, cart.global_position) < 3.2) and cart.space() > 0.5
	var kg := minf(float(state.sacks[i][3]), cart.space() if into_cart else state.capacity() - state.tank)
	var sack: Node3D = _sack_nodes[i]
	start_task("Emptying the sack into your %s" % ("handcart" if into_cart else "tank"), task_time("sack", kg), player, func():
		var j := _sack_nodes.find(sack)
		if j >= 0:
			_take_sack(j))


func _take_sack(i: int) -> void:
	var kg := float(state.sacks[i][3])
	if cart and (cart.pushing or _flat_dist(player.global_position, cart.global_position) < 3.2) and cart.space() > 0.5:
		var put := take_from_sack(i, cart.space())
		cart.add(put)
		hud.toast("Loaded %.0f kg into the handcart (%.0f / %.0f kg)%s." % [put, cart.load_kg, cart.capacity(),
			"" if put >= kg - 0.05 else ", the rest stays in the sack"], 2.5)
	else:
		var put := take_from_sack(i, state.capacity() - state.tank)
		state.tank += put
		hud.toast("Emptied %.0f kg into your tank (%.0f / %.0f kg)%s." % [put, state.tank, state.capacity(),
			"" if put >= kg - 0.05 else ", the rest stays in the sack"], 2.5)


## The Sweeper's brush scoops up any sack it drives over, as far as the hopper has room.
## Lifting takes time: park over the sack (or crawl across it) until it is gone.
func _sweeper_scoop(dt: float) -> void:
	if driven() != sweeper or not sweeper.tool_on or state.hopper >= GameState.SWEEPER_HOPPER - 0.5:
		return
	var front := sweeper.global_position + sweeper.forward() * 1.2
	var i := sack_near(front, SACK_SCOOP)
	if i < 0:
		return
	var last := float(state.sacks[i][3]) <= SCOOP_RATE * dt
	var got := take_from_sack(i, minf(SCOOP_RATE * dt, GameState.SWEEPER_HOPPER - state.hopper))
	state.hopper += got
	_pouring = true
	if last:
		hud.toast("Scooped up the sack (hopper %.0f / %.0f kg)." % [state.hopper, GameState.SWEEPER_HOPPER], 2.0)
		sfx("latch")


## Bigger loads make bigger sacks; the label shows the weight.
func _size_sack(n: Node3D, kg: float) -> void:
	var k := clampf(pow(maxf(kg, 1.0) / 30.0, 1.0 / 3.0), 0.75, 2.4)
	(n.get_meta("bag") as Node3D).scale = Vector3.ONE * k
	var l := n.get_meta("label") as Label3D
	l.text = "Rust sack  %.0f kg" % kg
	l.position.y = 0.95 * k + 0.1


func _make_sack(p: Vector3, kg: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = p
	var bag := Node3D.new()
	n.add_child(bag)
	n.set_meta("bag", bag)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.36
	sm.height = 0.62
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	mi.position.y = 0.28
	mi.scale = Vector3(1.0, 1.0, 0.85)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.72, 0.52)
	m.roughness = 1.0
	mi.material_override = m
	bag.add_child(mi)
	var tie := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.05
	tm.bottom_radius = 0.09
	tm.height = 0.16
	tie.mesh = tm
	tie.position.y = 0.64
	tie.material_override = m
	bag.add_child(tie)
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.font_size = 22
	l.pixel_size = 0.0011
	l.outline_size = 8
	n.add_child(l)
	n.set_meta("label", l)
	_size_sack(n, kg)
	return n


func _update_hauler(dt: float) -> void:
	if state.sacks.is_empty():
		_haul_t = GameState.HAUL_INTERVAL
		return
	_haul_t -= dt
	if _haul_t > 0.0:
		return
	_haul_t = GameState.HAUL_INTERVAL
	var kg := 0.0
	for sk in state.sacks:
		kg += float(sk[3])
	var gross := kg * state.price_now()
	var net := gross * (1.0 - state.haul_fee())
	state.credits += net
	state.earned += net
	state.total_sold += kg
	hud.toast("The hauler picked up %d sack%s (%.0f kg): +%s after a %s fee." % [
		state.sacks.size(), "" if state.sacks.size() == 1 else "s", kg, GameState.inr(net), GameState.inr(gross - net)], 4.5)
	for n in _sack_nodes:
		var tw := n.create_tween()
		tw.tween_property(n, "position:y", n.position.y + 30.0, 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(n.queue_free)
	_sack_nodes.clear()
	state.sacks.clear()
	sfx("thrusterFire_000")


func hex_bonus(k: Vector2i) -> int:
	var c := RustField.key_center(k)
	return state.hex_bonus(rust.hex_pristine_kg(k), state.crust_at(c.x, c.y))


# ---------------------------------------------------------------- per frame

func focus_point() -> Vector3:
	if mode == "benchmark":
		var cam := get_viewport().get_camera_3d()
		return cam.global_position if cam else Vector3.ZERO
	var v := driven()
	return v.global_position if v else player.global_position


func driven() -> Vehicle:
	if sweeper.driving:
		return sweeper
	if charger.driving:
		return charger
	return null


func _process(dt: float) -> void:
	rust.upload()
	var fp := focus_point()
	terrain.update(fp)
	RenderingServer.global_shader_parameter_set("focus_hex", RustField.hex_center(fp.x, fp.z))
	_player_fx_t -= dt
	_sweeper_fx_t -= dt
	_toast_cd -= dt
	player_fx.emitting = _player_fx_t > 0.0
	sweeper_fx.emitting = _sweeper_fx_t > 0.0
	_update_power(dt)
	_hex_t -= dt
	if _hex_t <= 0.0:
		_hex_t = 0.25
		_poll_hexes()
		if mode == "play":
			_check_wear()
			var r := state.rank_index()
			if r > _last_rank:
				_last_rank = r
				hud.toast("RANK UP: %s  ·  exports now pay +%d%%" % [state.rank_name(), roundi(r * GameState.RANK_BONUS * 100.0)], 6.0, Color(1.0, 0.85, 0.35))
				sfx("bell")
			for m in missions.check(state):
				hud.mission_complete(m)
				sfx("bell")
	_update_labels()
	if mode != "play":
		return
	state.play_time += dt
	_update_daycycle(dt)
	var busy := player.cleaning or (sweeper.sweeping and sweeper.driving)
	_clean_loop.volume_db = move_toward(_clean_loop.volume_db, -16.0 if busy else -50.0, dt * 80.0)
	if _clean_loop.volume_db > -49.0 and not _clean_loop.playing:
		_clean_loop.play()
	elif _clean_loop.volume_db <= -49.5 and _clean_loop.playing:
		_clean_loop.stop()
	_update_pods(dt)
	_update_hauler(dt)
	_sweeper_scoop(dt)
	_update_task(dt)
	_update_interaction()
	_autosave_t += dt
	if _autosave_t > 60.0:
		_autosave_t = 0.0
		save_game()


var _sky_t := 0.0
var _dark_hinted := false


## Slow, relaxed day/night cycle. Panels only generate while the sun is up.
func _update_daycycle(dt: float) -> void:
	state.time_of_day += dt / GameState.SOL_SECONDS
	if state.time_of_day >= 1.0:
		state.time_of_day -= 1.0
		hud.sol_report(_sol_summary())
		state.sol += 1
		state.start_sol_report()
	var t := state.time_of_day
	var elev := sin((t - 0.25) * TAU)  # -1 midnight .. 1 noon
	var day := smoothstep(-0.08, 0.3, elev)
	var dusk := 1.0 - absf(elev) * 3.0
	sun.rotation_degrees = Vector3(-maxf(elev * 62.0, 4.0), 200.0 - t * 360.0, 0.0)
	sun.light_energy = 1.3 * day
	sun.light_color = Color(1.0, 0.88, 0.74).lerp(Color(1.0, 0.55, 0.3), clampf(dusk, 0.0, 1.0))
	env.ambient_light_energy = lerpf(0.12, 0.75, day)
	env.fog_light_color = Color(0.84, 0.60, 0.44).lerp(Color(0.12, 0.1, 0.14), 1.0 - day)
	for l in base_lights:
		l.light_energy = lerpf(3.0, 1.2, day)
	var night := 1.0 - day
	# Once per evening, remind the player about the torch if it is off.
	if night > 0.45 and not _dark_hinted and not sleeping:
		_dark_hinted = true
		if player.active:
			hud.toast("It's getting dark. %sOr sleep through the night in the garage bunk (%s)." % [
				"" if player.torch_on else "Press L for your torch. ", GameState.inr(sleep_cost())], 6.0)
	elif night < 0.2:
		_dark_hinted = false
	for v in [sweeper, charger]:
		v.set_headlights(night > 0.3 or params.headlights and night > 0.05)
	# Sky colours change slowly; updating them is cheap only if done rarely.
	_sky_t -= dt
	if _sky_t <= 0.0:
		_sky_t = 1.5
		var sm := env.sky.sky_material as ProceduralSkyMaterial
		sm.sky_top_color = Color(0.40, 0.29, 0.25).lerp(Color(0.03, 0.025, 0.04), night)
		sm.sky_horizon_color = Color(0.86, 0.63, 0.46).lerp(Color(0.12, 0.08, 0.1), night).lerp(Color(0.95, 0.5, 0.3), clampf(dusk, 0.0, 1.0) * 0.6)
		sm.ground_horizon_color = sm.sky_horizon_color.darkened(0.1)


## Solar panels charge the base battery; the battery charges vehicles plugged in at the
## garage posts; the charger cart charges the sweeper through its own cable.
func _update_power(dt: float) -> void:
	var h := dt / GameState.TIME_SCALE
	var sun_factor := state.daylight() if mode == "play" else 1.0
	state.bank = minf(state.bank + state.gen_kw() * sun_factor * h, state.bank_cap())
	for v in [sweeper, charger]:
		v.charging = false
	for c in _cables:
		c.visible = false
	var post_state := [0, 0]  # 0 idle, 1 plugged/full, 2 charging
	for v in plugged.keys():
		var i: int = plugged[v]
		if _flat_dist(v.global_position, POSTS[i]) > 7.0:
			plugged.erase(v)
			if hud:
				hud.toast("The charging cable popped out of the %s." % v.display_name(), 3.0)
			continue
		post_state[i] = 1
		if v.energy < v.battery and state.bank > 0.0:
			var amt := minf(minf(GameState.PAD_CHARGE_KW * h, v.battery - v.energy), state.bank)
			v.energy += amt
			state.bank -= amt
			v.charging = true
			post_state[i] = 2
		_draw_cable(i, POSTS[i] + Vector3(0, 1.1, 0.2), charge_port(v))
	for i in _post_screens.size():
		var col: Color = [Color(0.2, 0.5, 0.35), Color(0.3, 0.6, 1.0), Color(0.2, 1.0, 0.45)][post_state[i]]
		_post_screens[i].emission = col
		_post_screens[i].emission_energy_multiplier = [0.3, 1.2, 1.5 + 0.8 * sin(Time.get_ticks_msec() * 0.006)][post_state[i]]
	if cart_linked:
		var a := charger.global_position + Vector3(0, 1.2, 0) + charger.right() * 1.05
		var b: Vector3 = charge_port(sweeper)
		if a.distance_to(b) > 10.0:
			cart_linked = false
			if hud:
				hud.toast("The charger cart cable disconnected.", 3.0)
		else:
			if charger.energy > 0.0 and sweeper.energy < sweeper.battery:
				var amt := minf(minf(GameState.CART_CHARGE_KW * h, sweeper.battery - sweeper.energy), charger.energy)
				sweeper.energy += amt
				charger.energy -= amt
				sweeper.charging = true
			_draw_cable(2, a, b)
	state.sweeper_energy = sweeper.energy
	state.charger_energy = charger.energy


func _update_labels() -> void:
	for v in [sweeper, charger]:
		var l: Label3D = _labels[v.kind]
		l.visible = owns(v) and not v.driving and mode == "play"
		if l.visible:
			l.global_position = v.global_position + Vector3(0, 3.2, 0)
			var worst: Array = v.worst_part()
			var cond_txt := "" if float(worst[1]) >= 0.7 else "\n%s %d%%" % [GameState.PART_NAMES[worst[0]], roundi(float(worst[1]) * 100.0)]
			var t := "%s  %d%%%s%s" % [v.display_name(), roundi(v.energy / v.battery * 100.0), "  (charging)" if v.charging else "", cond_txt]
			if l.text != t:
				l.text = t  # re-shaping text is not free; only when it changes


func _update_interaction() -> void:
	var prompt := ""
	_act = ""
	_act_vehicle = null
	if busy():
		hud.set_prompt(task_prompt())
		return
	var v := driven()
	if placing:
		if v or not player.active:
			_end_placing()
		else:
			hud.set_prompt(_update_placing())
			return
	if v == null:
		var p := player.global_position
		if _flat_dist(p, DEPOT) < 6.5:
			var kg := state.tank + _cart_at_depot()
			if kg > 0.05:
				prompt = "[E] Export %.1f kg of rust%s at %s/kg  (+%s)" % [kg, " (tank + handcart)" if _cart_at_depot() > 0.0 else "",
					GameState.inr(state.price_now()), GameState.inr(kg * state.price_now())]
				_act = "export"
			else:
				prompt = "Export depot: bring rust here to ship it off-world"
		elif _flat_dist(p, TERMINAL) < 4.0:
			prompt = "[E] Open base terminal  (upgrades · solar · vehicles)"
			_act = "shop"
		elif _panel_near(p) >= 0:
			prompt = "[E] Pick up this solar panel (to move it)"
			_act = "panel_pickup"
		elif _flat_dist(p, BED) < 2.0:
			if is_bedtime():
				prompt = "[E] Sleep until 06:30  (%s for the night)" % GameState.inr(sleep_cost())
				_act = "sleep"
			else:
				prompt = "Bunk: you can sleep once it is dark (17:15 to 05:15). It is %s." % clock(state.time_of_day)
		elif sack_near(p, SACK_REACH) >= 0 and _sack_prompt(sack_near(p, SACK_REACH)) != "":
			prompt = _sack_prompt(sack_near(p, SACK_REACH))
			_act = "sack_pickup"
		elif cart and cart.pushing:
			prompt = "[E] Let go of the handcart  (%.0f / %.0f kg)" % [cart.load_kg, cart.capacity()]
			_act = "cart_release"
		elif cart and _flat_dist(p, cart.global_position) < 2.6:
			prompt = "[E] Push the handcart  (%.0f / %.0f kg)" % [cart.load_kg, cart.capacity()]
			if state.tank > 0.05:
				prompt += "  ·  [Q] tip your tank in"
			_act = "cart_grab"
		elif pod and pod.landed and not pod.opened and _flat_dist(p, pod.global_position) < 3.8:
			prompt = "[E] Open the supply pod"
			_act = "open_pod"
		else:
			prompt = _charging_prompt(p)
			_near_vehicle = null
			if _act == "":
				for veh in [sweeper, charger]:
					if owns(veh) and _flat_dist(p, veh.global_position) < 4.5:
						var pct := roundi(veh.energy / veh.battery * 100.0)
						if is_tethered(veh):
							prompt = "%s (%d%%) is plugged in: unplug the cable first" % [veh.display_name(), pct]
						else:
							prompt = "[E] Drive %s  (battery %d%%)" % [veh.display_name(), pct]
							_act = "enter"
							_act_vehicle = veh
						_near_vehicle = veh
						if state.repair_kits > 0:
							prompt += "  ·  [G] repair kit ×%d" % state.repair_kits
						if state.battery_cells > 0:
							prompt += "  ·  [B] battery cell ×%d" % state.battery_cells
						break
	else:
		# Controls are in the hint bar; the prompt only shows what this spot offers.
		if v == sweeper and _flat_dist(v.global_position, DEPOT) < DEPOT_DRIVE_R and state.hopper > 0.05:
			prompt = "[Q] Export the hopper here: %.0f kg  (+%s)" % [state.hopper, GameState.inr(state.hopper * state.price_now())]
		elif bay_of(v) >= 0 and absf(v.speed) < 0.5:
			prompt = "[E] Get out, then plug in at the charging post"
		_act = "exit"
	hud.set_prompt(prompt)


## "[E] ..." for the sack at index i, or "" when neither the handcart nor your tank has room.
func _sack_prompt(i: int) -> String:
	var kg := float(state.sacks[i][3])
	if cart and (cart.pushing or _flat_dist(player.global_position, cart.global_position) < 3.2) and cart.space() > 0.5:
		return "[E] Load the %.0f kg rust sack into the handcart  (%.0f kg free)" % [kg, cart.space()]
	var room := state.capacity() - state.tank
	if room > 0.5:
		return "[E] Pick up the %.0f kg rust sack into your tank  (%.0f kg free)" % [kg, room]
	return ""


## Prompts for the garage posts and the charger cart cable. Sets _act when actionable.
func _charging_prompt(p: Vector3) -> String:
	for i in POSTS.size():
		if _flat_dist(p, POSTS[i]) < 2.8:
			var v: Vehicle = null
			for veh in [sweeper, charger]:
				if owns(veh) and bay_of(veh) == i:
					v = veh
			if v == null:
				return "Charging post: park a vehicle in this bay to charge it"
			var pct := roundi(v.energy / v.battery * 100.0)
			_act_vehicle = v
			_post_index = i
			if plugged.get(v, -1) == i:
				_act = "unplug"
				return "[E] Unplug the %s  (%d%%%s)" % [v.display_name(), pct, ", charging" if v.charging else ""]
			_act = "plug"
			return "[E] Plug in the %s  (%d%%)" % [v.display_name(), pct]
	if state.charger_owned and state.sweeper_owned and _flat_dist(p, charger.global_position) < 4.0:
		if cart_linked:
			_act = "unlink"
			return "[E] Disconnect the charger cart cable"
		if charger.global_position.distance_to(sweeper.global_position) < 8.0:
			_act = "link"
			return "[E] Connect the charger cart cable to the Sweeper  (cart %d%%)" % roundi(charger.energy / charger.battery * 100.0)
		return "Charger cart: park it next to the Sweeper to connect the cable"
	return ""


func _unhandled_input(e: InputEvent) -> void:
	if mode != "play" or ui_open:
		return
	if e.is_action_pressed("interact"):
		_do_action()
	elif e.is_action_pressed("vehicle_tool") and driven() == sweeper:
		sweeper.tool_on = not sweeper.tool_on
		hud.toast("Brush %s" % ("ON" if sweeper.tool_on else "OFF"), 1.5)
		sfx("click")
	elif e.is_action_pressed("vehicle_empty") and driven() == sweeper:
		empty_hopper()
	elif e.is_action_pressed("vehicle_empty") and player.active:
		unload_tank()
	elif e.is_action_pressed("torch") and not ui_open:
		var dv := driven()
		if dv:
			dv.lights_override = 0 if dv.headlights_lit() else 1
			dv.set_headlights(false)
			hud.toast("Headlights %s." % ("on" if dv.headlights_lit() else "off"), 1.2)
		elif player.active:
			player.set_torch(not player.torch_on)
		sfx("click")
	elif e.is_action_pressed("place_panel") and player.active:
		toggle_placing()
	elif placing and e.is_action_pressed("clean"):
		place_panel()
	elif placing and e.is_action_pressed("vehicle_tool"):
		_ghost_yaw = fmod(_ghost_yaw + PI / 4.0, TAU)
	elif e.is_action_pressed("waypoint"):
		_place_waypoint()
	elif e.is_action_pressed("use_kit") and _near_vehicle and player.active and state.repair_kits > 0:
		var worst: Array = _near_vehicle.worst_part()
		_near_vehicle.cond[worst[0]] = minf(float(worst[1]) + 0.5, 1.0)
		state.repair_kits -= 1
		_near_vehicle.flat_warned = false
		_near_vehicle._update_wear_visuals()
		hud.toast("Repair kit used on the %s %s." % [_near_vehicle.display_name(), str(GameState.PART_NAMES[worst[0]]).to_lower()], 3.0)
		sfx("ratchet")
	elif e.is_action_pressed("use_cell") and _near_vehicle and player.active and state.battery_cells > 0:
		_near_vehicle.energy = minf(_near_vehicle.energy + 10.0, _near_vehicle.battery)
		state.battery_cells -= 1
		hud.toast("Battery cell installed: +10 kWh for the %s." % _near_vehicle.display_name(), 3.0)
		sfx("latch")
	elif e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _do_action() -> void:
	match _act:
		"export":
			var dur := minf(task_time("tank", state.tank) + (task_time("cart", _cart_at_depot()) if _cart_at_depot() > 0.0 else 0.0), 10.0)
			start_task("Unloading %.0f kg at the depot" % (state.tank + _cart_at_depot()), dur, player, func():
				var kg := state.tank + _cart_at_depot()
				if _cart_at_depot() > 0.0:
					cart.empty()
				var c := state.sell(kg)
				hud.toast("Exported %.1f kg of rust  ->  +%s" % [kg, GameState.inr(c)], 3.0)
				state.tank = 0.0)
		"shop":
			hud.open_shop()
			sfx("click")
		"open_pod":
			_open_pod()
		"sleep":
			go_to_sleep()
		"sack_pickup":
			var si := sack_near(player.global_position, SACK_REACH)
			if si >= 0:
				pick_up_sack(si)
		"panel_pickup":
			var i := _panel_near(player.global_position)
			if i >= 0:
				state.panel_spots.remove_at(i)
				state.panel_stock += 1
				_refresh_solar()
				hud.toast("Panel picked up. Press P to place it somewhere else.", 2.5)
		"cart_grab":
			cart.set_pushing(true)
			hud.toast("Pushing the handcart. You can't clean or sprint while pushing; E to let go.", 3.0)
		"cart_release":
			cart.set_pushing(false)
		"plug":
			plugged[_act_vehicle] = _post_index
			hud.toast("%s plugged in. It charges from the base battery." % _act_vehicle.display_name(), 2.5)
			sfx("doorOpen_001")
		"unplug":
			plugged.erase(_act_vehicle)
			hud.toast("%s unplugged." % _act_vehicle.display_name(), 2.0)
			sfx("doorOpen_001")
		"link":
			cart_linked = true
			hud.toast("Cable connected: the cart is charging the Sweeper.", 2.5)
			sfx("doorOpen_001")
		"unlink":
			cart_linked = false
			hud.toast("Charger cart cable disconnected.", 2.0)
			sfx("doorOpen_001")
		"enter":
			player.set_active(false)
			_act_vehicle.set_driving(true)
			sfx("doorOpen_001")
		"exit":
			if driven():
				_exit_vehicle(driven())
				sfx("doorOpen_001")


func _exit_vehicle(v: Vehicle) -> void:
	v.set_driving(false)
	var p := v.global_position + v.right() * 2.8
	player.global_position = Vector3(p.x, terrain.height_at(p.x, p.z) + 0.6, p.z)
	player.yaw = v.heading
	player.set_active(true)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Price of the next level of an item, or -1 if it can't be bought right now.
## What a shop item costs right now (difficulty applied), or -1 if it can't be bought.
func price(item: String) -> int:
	if lock_reason(item) != "":
		return -1
	var c := _base_price(item)
	if c <= 0 or item.begins_with("paint_"):
		return c
	return int(round(c * float(state.diff().cost) / 100.0)) * 100


## Why an item is locked ("" when it isn't): rank, hexagons or tool mastery still needed.
func lock_reason(item: String) -> String:
	match item:
		"tool":
			return state.lock_reason("tool_%d" % (state.tool_lvl + 1))
		"tank":
			return state.lock_reason("tank_%d" % (state.tank_lvl + 1))
		"sweeper", "charger", "drone":
			if item == "drone" and state.drones > 0:
				return ""
			var r := state.lock_reason(item)
			if item == "charger" and not state.sweeper_owned:
				r = "own the Sweeper" + (" · " + r if r != "" else "")
			return r
		"power", "width", "reach":
			if state.mods[item] < int(GameState.TOOL_MODS[item].max) and state.mods[item] >= state.mastery_level():
				return "%s mastery %s (%.0f kg more rust)" % [state.tool().name, "★".repeat(state.mods[item] + 1), state.mastery_next_kg()]
	return ""


func _base_price(item: String) -> int:
	match item:
		"tool":
			return GameState.TOOLS[state.tool_lvl + 1].cost if state.tool_lvl < GameState.TOOLS.size() - 1 else -1
		"power", "width", "reach":
			return state.mod_cost(item) if state.mods[item] < int(GameState.TOOL_MODS[item].max) else -1
		"tank":
			return GameState.TANKS[state.tank_lvl + 1].cost if state.tank_lvl < GameState.TANKS.size() - 1 else -1
		"boots":
			return GameState.BOOTS[state.boots_lvl + 1].cost if state.boots_lvl < GameState.BOOTS.size() - 1 else -1
		"cart":
			return GameState.CARTS[state.cart_lvl + 1].cost if state.cart_lvl < GameState.CARTS.size() - 1 else -1
		"panel":
			return state.panel_cost() if state.panels + state.panel_stock < GameState.MAX_PANELS else -1
		"sweeper":
			return GameState.SWEEPER_COST if not state.sweeper_owned else -1
		"charger":
			return GameState.CHARGER_COST if not state.charger_owned else -1
		"sweeper_batt":
			return GameState.SWEEPER_BATT[state.sweeper_batt_lvl + 1].cost if state.sweeper_owned and state.sweeper_batt_lvl < GameState.SWEEPER_BATT.size() - 1 else -1
		"drone":
			return state.drone_cost() if state.drones < GameState.MAX_DRONES else -1
		"drone_range":
			return GameState.DRONE_RANGE[state.drone_range].cost if state.drone_range < GameState.DRONE_RANGE.size() else -1
		"repair_sweeper_tyres", "repair_sweeper_brush", "repair_sweeper_motor", "repair_charger_tyres", "repair_charger_motor":
			var parts := item.split("_")
			var veh := sweeper if parts[1] == "sweeper" else charger
			# Repairs happen in the garage workshop: the vehicle must be parked in a bay.
			if not owns(veh) or float(state.wear[parts[1]][parts[2]]) >= 0.995 or bay_of(veh) < 0:
				return -1
			return state.repair_cost(parts[1], parts[2])
		_ when item.begins_with("paint_"):
			var parts := item.split("_")
			var veh := sweeper if parts[1] == "sweeper" else charger
			if not owns(veh) or state.livery[parts[1]] == parts[2]:
				return -1
			if (state.liveries[parts[1]] as Array).has(parts[2]):
				return 0
			for lv in GameState.LIVERIES:
				if lv.id == parts[2]:
					return lv.cost
			return -1
		"tow_sweeper":
			return GameState.TOW_COST if state.sweeper_owned and bay_of(sweeper) < 0 else -1
		"tow_charger":
			return GameState.TOW_COST if state.charger_owned and bay_of(charger) < 0 else -1
	return -1


func buy(item: String) -> bool:
	var cost := price(item)
	if cost < 0 or state.credits < cost:
		return false
	state.credits -= cost
	match item:
		"tool":
			state.tool_lvl += 1
			player.refresh_tool()
		"power", "width", "reach":
			state.mods[item] += 1
		"tank":
			state.tank_lvl += 1
		"boots":
			state.boots_lvl += 1
		"cart":
			state.cart_lvl += 1
			if cart == null:
				state.cart = {pos = [DEPOT.x - 4.0, 0.0, DEPOT.z + 4.0], yaw = 0.0, kg = 0.0}
				_spawn_cart()
				hud.toast("Your handcart is waiting by the export depot. E to push it; Q next to it tips your tank in.", 5.0)
			else:
				cart._update_fill()
		"panel":
			state.panel_stock += 1
			hud.toast("Solar panel bought. Press P outside to place it (within %d m of the base)." % int(PANEL_RANGE), 4.0)
		"sweeper":
			state.sweeper_owned = true
			sweeper.energy = sweeper.battery
			_set_vehicle_present(sweeper, true)
			hud.toast("Your Sweeper is in the garage. Plug it in at the post to charge it.", 5.0)
		"charger":
			state.charger_owned = true
			charger.energy = charger.battery
			_set_vehicle_present(charger, true)
			hud.toast("The Charger cart is in the garage. Charge it at its post; in the field, connect its cable to the Sweeper.", 6.0)
		"sweeper_batt":
			state.sweeper_batt_lvl += 1
			sweeper.battery = state.sweeper_battery()
		"drone":
			spawn_drone(state.drones)
			state.drones += 1
		"drone_range":
			state.drone_range += 1
			set_drone_zone(Vector2.ZERO, state.drone_range)
		"repair_sweeper_tyres", "repair_sweeper_brush", "repair_sweeper_motor", "repair_charger_tyres", "repair_charger_motor":
			var parts := item.split("_")
			state.wear[parts[1]][parts[2]] = 1.0
			state.repairs_done += 1
			var veh := sweeper if parts[1] == "sweeper" else charger
			veh.flat_warned = false
			veh._update_wear_visuals()
		_ when item.begins_with("paint_"):
			var parts := item.split("_")
			if not (state.liveries[parts[1]] as Array).has(parts[2]):
				(state.liveries[parts[1]] as Array).append(parts[2])
			state.livery[parts[1]] = parts[2]
			apply_livery(sweeper if parts[1] == "sweeper" else charger)
		"tow_sweeper", "tow_charger":
			var v := sweeper if item == "tow_sweeper" else charger
			if v.driving:
				_exit_vehicle(v)
			plugged.erase(v)
			cart_linked = false
			var slot: Vector3 = BAYS[0] if v == sweeper else BAYS[1]
			v.global_position = Vector3(slot.x, terrain.height_at(slot.x, slot.z) + 0.3, slot.z)
			v.heading = 0.0
			v.rotation.y = 0.0
			v.speed = 0.0
	sfx("latch")
	return true


func apply_livery(v: Vehicle) -> void:
	for lv in GameState.LIVERIES:
		if lv.id == state.livery[v.kind]:
			v.apply_livery(lv)


# ---------------------------------------------------------------- waypoints and supply pods

## T: drop a waypoint where you are looking (T on the waypoint again removes it).
func _place_waypoint() -> void:
	var cam := get_viewport().get_camera_3d()
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 800.0, 1 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var pos: Vector3
	if hit:
		pos = hit.position
	else:
		var far := from - cam.global_basis.z * 300.0
		pos = Vector3(far.x, terrain.height_at(far.x, far.z), far.z)
	if waypoint and _flat_dist(waypoint.global_position, pos) < 10.0:
		waypoint.queue_free()
		waypoint = null
		hud.toast("Waypoint removed.", 1.5)
		return
	if waypoint == null:
		waypoint = Beacon.new()
		waypoint.title = "Waypoint"
		add_child(waypoint)
	waypoint.global_position = pos
	hud.toast("Waypoint set, %d m %s." % [roundi(_flat_dist(from, pos)), compass_word(pos - from)], 2.0)
	sfx("click")


static func compass_word(d: Vector3) -> String:
	var deg := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(deg / 45.0)) % 8]


func _update_pods(dt: float) -> void:
	if pod and is_instance_valid(pod):
		if pod.landed and pod.age > GameState.SOL_SECONDS:
			hud.toast("An unopened supply pod was recovered by the company.", 3.0)
			pod.queue_free()
			pod = null
		return
	pod = null
	_pod_timer -= dt
	if _pod_timer > 0.0:
		return
	_pod_timer = randf_range(240.0, 420.0)
	var a := randf() * TAU
	var d := randf_range(70.0, 220.0)
	var x := cos(a) * d
	var z := sin(a) * d
	pod = SupplyPod.new()
	pod.world = self
	pod.target = Vector3(x, terrain.height_at(x, z), z)
	add_child(pod)
	hud.toast("Supply pod inbound: %d m %s of the base. Follow the orange beacon." % [roundi(d), compass_word(Vector3(x, 0, z))], 6.0, Color(1.0, 0.75, 0.4))
	sfx("bell")


func _open_pod() -> void:
	var cash := randi_range(3000, 12000) * (1.0 + 0.15 * state.rank_index())
	state.credits += cash
	state.earned += cash
	var got := PackedStringArray([GameState.inr(cash)])
	if randf() < 0.6:
		state.repair_kits += 1
		got.append("a repair kit (G)")
	if randf() < 0.45:
		state.battery_cells += 1
		got.append("a battery cell (B)")
	state.pods_opened += 1
	hud.toast("Supply pod: " + ", ".join(got), 5.0, Color(1.0, 0.8, 0.45))
	if randf() < 0.15:
		state.dig_meter = state.next_relic_kg
		_dig(0.001)
	sfx("doorOpen_001")
	pod.open()
	pod = null


func _sol_summary() -> Dictionary:
	var s0 := state.sol_start
	var by: Dictionary = state.sol_kg
	var total := float(by.you) + float(by.sweeper) + float(by.drones)
	var mvp := "you"
	for k in by:
		if float(by[k]) > float(by[mvp]):
			mvp = k
	return {
		sol = state.sol, kg = total, earned = state.earned - float(s0.get("earned", state.earned)),
		hexes = state.hexes_cleared.size() - int(s0.get("hexes", 0)), relics = state.relics_found.size() - int(s0.get("relics", 0)),
		pods = state.pods_opened - int(s0.get("pods", 0)), mvp = mvp, mvp_share = (float(by[mvp]) / total) if total > 0.0 else 0.0,
	}


func save_game() -> void:
	if mode != "play":
		return
	var v := driven()
	if v:
		var p := v.global_position + v.right() * 2.8
		state.player_pos = Vector3(p.x, terrain.height_at(p.x, p.z) + 0.8, p.z)
	else:
		state.player_pos = player.global_position + Vector3(0, 0.2, 0)
	state.player_yaw = player.yaw
	if cart:
		state.cart = {pos = [cart.global_position.x, cart.global_position.y, cart.global_position.z], yaw = cart.rotation.y, kg = cart.load_kg}
	for veh in [sweeper, charger]:
		state.vehicles[veh.kind] = [veh.global_position.x, veh.global_position.y, veh.global_position.z, veh.heading]
	state.save(rust)


func exit_to_menu() -> void:
	save_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit_to_menu.emit()
