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

var mode := "play"
var seed_value := 4242
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
		var body := StaticBody3D.new()
		body.collision_layer = 4
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size * scl
		cs.shape = box
		cs.position.y = box.size.y * 0.5
		body.add_child(cs)
		body.position = holder.position
		body.rotation.y = holder.rotation.y
		add_child(body)
	return holder


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
	var pcs := CollisionShape3D.new()
	var pbox := BoxShape3D.new()
	pbox.size = pm.size
	pcs.shape = pbox
	pad_body.position = pad.position
	pad_body.add_child(pcs)
	add_child(pad_body)

	prop("hangar_largeA", -13, -5, 90, 4.2)
	prop("hangar_roundGlass", 11, -12, 0, 3.0)
	prop("hangar_smallA", -13, 11, 0, 3.0)
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


func _refresh_solar() -> void:
	_solar_label.visible = state.panels > 0
	solar.visible_instance_count = state.panels
	(solar.get_meta("poles") as MultiMesh).visible_instance_count = state.panels


## Garage: back wall, side walls and roof, open to the south, with a charging post per bay.
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
	for n in ["impactMetal_002", "computerNoise_000", "computerNoise_002", "doorOpen_001", "laserSmall_000", "forceField_001"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/sfx/%s.ogg" % n)
		p.volume_db = -8.0
		add_child(p)
		_sfx[n] = p
	_clean_loop = AudioStreamPlayer.new()
	var st: AudioStreamOggVorbis = load("res://assets/sfx/spaceEngineLow_000.ogg")
	st.loop = true
	_clean_loop.stream = st
	_clean_loop.volume_db = -50.0
	add_child(_clean_loop)


func sfx(n: String) -> void:
	if _sfx.has(n) and mode == "play" and not _sfx[n].playing:
		_sfx[n].play()


# ---------------------------------------------------------------- cleaning (every cleaner yields rust)

func player_clean(pos: Vector3, tool: Dictionary, dt: float) -> bool:
	var free := state.capacity() - state.tank
	if free <= 0.01:
		_warn("Rust tank full! Export it at the depot.")
		return false
	var kg := rust.paint(pos, tool.radius, float(tool.rate) * dt)
	if kg <= 0.0:
		return false
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
		_warn("Sweeper hopper full! Press Q at the export depot, or Q anywhere to dump it.")
		return
	var kg := rust.paint(pos, radius, strength)
	if kg > 0.0:
		state.hopper = minf(state.hopper + kg, GameState.SWEEPER_HOPPER)
		state.collected += kg
		state.sol_kg.sweeper += kg
		_dig(kg)
		cleaned_kg_total += kg
		_sweeper_fx_t = 0.12
		sweeper_fx.global_position = pos


func drone_clean(pos: Vector3, radius: float, strength: float) -> bool:
	var kg := rust.paint(pos, radius, strength)
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
	sfx("laserSmall_000")


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


## Q in the sweeper: export at the depot, otherwise dump the load back onto the ground.
func empty_hopper() -> void:
	if state.hopper <= 0.05:
		hud.toast("Hopper is already empty.", 2.0)
		return
	if _flat_dist(sweeper.global_position, DEPOT) < 11.0:
		var c := state.sell(state.hopper)
		hud.toast("Exported %.0f kg from the hopper  ->  +%s" % [state.hopper, GameState.inr(c)], 3.0)
		sfx("computerNoise_000")
	else:
		var back := sweeper.global_position - sweeper.forward() * 3.5
		rust.deposit(back, state.hopper)
		hud.toast("Dumped %.0f kg of rust on the ground. (Export it at the depot for ₹.)" % state.hopper, 3.5)
		sfx("impactMetal_002")
	state.hopper = 0.0


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
		if mode == "play" and c >= GameState.HEX_CLEAR:
			var hn := RustField.hex_name(k)
			if not state.hexes_cleared.has(hn):
				state.hexes_cleared.append(hn)
				state.credits += GameState.HEX_BONUS
				state.earned += GameState.HEX_BONUS
				hud.toast("Hexagon %s cleared! Bonus +%s" % [hn, GameState.inr(GameState.HEX_BONUS)], 4.0)
				sfx("laserSmall_000")
	rust.touched_hexes.clear()


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
				sfx("forceField_001")
			for m in missions.check(state):
				hud.mission_complete(m)
				sfx("laserSmall_000")
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
	_update_interaction()
	_autosave_t += dt
	if _autosave_t > 60.0:
		_autosave_t = 0.0
		save_game()


var _sky_t := 0.0
var _headlamp: SpotLight3D


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
	if _headlamp == null:
		_headlamp = SpotLight3D.new()
		_headlamp.spot_range = 26.0
		_headlamp.spot_angle = 34.0
		_headlamp.light_color = Color(1.0, 0.95, 0.85)
		player.camera.add_child(_headlamp)
	_headlamp.visible = night > 0.3
	_headlamp.light_energy = 2.2 * night
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
	var v := driven()
	if v == null:
		var p := player.global_position
		if _flat_dist(p, DEPOT) < 6.5:
			if state.tank > 0.05:
				prompt = "[E] Export %.1f kg of rust at %s/kg  (+%s)" % [state.tank, GameState.inr(state.price_now()), GameState.inr(state.tank * state.price_now())]
				_act = "export"
			else:
				prompt = "Export depot: bring rust here to ship it off-world"
		elif _flat_dist(p, TERMINAL) < 4.0:
			prompt = "[E] Open base terminal  (upgrades · solar · vehicles)"
			_act = "shop"
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
		if v == sweeper and _flat_dist(v.global_position, DEPOT) < 11.0 and state.hopper > 0.05:
			prompt = "[Q] Export the hopper here: %.0f kg  (+%s)" % [state.hopper, GameState.inr(state.hopper * state.price_now())]
		elif bay_of(v) >= 0 and absf(v.speed) < 0.5:
			prompt = "[E] Get out, then plug in at the charging post"
		_act = "exit"
	hud.set_prompt(prompt)


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
		sfx("forceField_001")
	elif e.is_action_pressed("vehicle_empty") and driven() == sweeper:
		empty_hopper()
	elif e.is_action_pressed("waypoint"):
		_place_waypoint()
	elif e.is_action_pressed("use_kit") and _near_vehicle and player.active and state.repair_kits > 0:
		var worst: Array = _near_vehicle.worst_part()
		_near_vehicle.cond[worst[0]] = minf(float(worst[1]) + 0.5, 1.0)
		state.repair_kits -= 1
		_near_vehicle.flat_warned = false
		_near_vehicle._update_wear_visuals()
		hud.toast("Repair kit used on the %s %s." % [_near_vehicle.display_name(), str(GameState.PART_NAMES[worst[0]]).to_lower()], 3.0)
		sfx("forceField_001")
	elif e.is_action_pressed("use_cell") and _near_vehicle and player.active and state.battery_cells > 0:
		_near_vehicle.energy = minf(_near_vehicle.energy + 10.0, _near_vehicle.battery)
		state.battery_cells -= 1
		hud.toast("Battery cell installed: +10 kWh for the %s." % _near_vehicle.display_name(), 3.0)
		sfx("forceField_001")
	elif e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _do_action() -> void:
	match _act:
		"export":
			var c := state.sell(state.tank)
			hud.toast("Exported %.1f kg of rust  ->  +%s" % [state.tank, GameState.inr(c)], 3.0)
			state.tank = 0.0
			sfx("computerNoise_000")
		"shop":
			hud.open_shop()
			sfx("computerNoise_002")
		"open_pod":
			_open_pod()
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
func price(item: String) -> int:
	match item:
		"tool":
			return GameState.TOOLS[state.tool_lvl + 1].cost if state.tool_lvl < GameState.TOOLS.size() - 1 else -1
		"power", "width", "reach":
			return state.mod_cost(item) if state.mods[item] < int(GameState.TOOL_MODS[item].max) else -1
		"tank":
			return GameState.TANKS[state.tank_lvl + 1].cost if state.tank_lvl < GameState.TANKS.size() - 1 else -1
		"boots":
			return GameState.BOOTS[state.boots_lvl + 1].cost if state.boots_lvl < GameState.BOOTS.size() - 1 else -1
		"panel":
			return state.panel_cost() if state.panels < GameState.MAX_PANELS else -1
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
		"panel":
			state.panels += 1
			_refresh_solar()
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
	sfx("forceField_001")
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
	sfx("computerNoise_002")


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
	sfx("laserSmall_000")


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
	for veh in [sweeper, charger]:
		state.vehicles[veh.kind] = [veh.global_position.x, veh.global_position.y, veh.global_position.z, veh.heading]
	state.save(rust)


func exit_to_menu() -> void:
	save_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit_to_menu.emit()
