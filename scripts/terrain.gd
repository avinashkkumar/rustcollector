class_name Terrain
extends Node3D
## Endless, gently rolling Martian plain streamed in 64 m chunks around a focus point.
## Heavy work (noise, mesh arrays, collision heights) runs on worker threads; the main
## thread only turns finished data into nodes, a couple of chunks per frame.

const CHUNK := 64.0
const RES_HI := 65  # 1 m grid near the camera
const RES_LO := 33  # 2 m grid further out
const HI_RADIUS := 2.5  # chunks
const SKIRT := 0.8  # skirts hide cracks where LODs meet
const COL_N := 65  # collision samples per side (1 m)
const PAD_HALF := 19.5

var seed_value := 1337
var view_chunks := 4
var streaming := true
var force_hi := false  # benchmark: every chunk at full detail
var view_dist := 260.0
var rust: RustField
var chunks := {}  # Vector2i -> Node3D
var built_count := 0

var _data := {}  # Vector2i -> Dictionary of computed arrays
var _pending := {}  # Vector2i -> WorkerThreadPool task id
var _done: Array = []
var _ready_queue: Array = []
var _mutex := Mutex.new()
var _noise: FastNoiseLite
var _detail: FastNoiseLite
var _shader: Shader
var _detail_tex: NoiseTexture2D
var _normal_tex: NoiseTexture2D
var _center := Vector2i(1 << 30, 1 << 30)
static var _topo := {}  # res -> {indices, uvs, border}


func setup() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.006
	_noise.fractal_octaves = 3
	_detail = FastNoiseLite.new()
	_detail.seed = seed_value + 1
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.05
	_detail.fractal_octaves = 2
	_shader = load("res://shaders/terrain.gdshader")
	_detail_tex = _noise_texture(false, 0.05)
	_normal_tex = _noise_texture(true, 0.09)
	for res in [RES_HI, RES_LO]:
		if not _topo.has(res):
			_topo[res] = _make_topology(res)


## Index buffer, UVs and border loop for a res x res grid plus a skirt ring.
static func _make_topology(n: int) -> Dictionary:
	var idx := PackedInt32Array()
	var uvs := PackedVector2Array()
	for z in n - 1:
		for x in n - 1:
			var i := z * n + x
			idx.append_array([i, i + 1, i + n, i + 1, i + n + 1, i + n])
	for z in n:
		for x in n:
			uvs.append(Vector2(float(x) / (n - 1), float(z) / (n - 1)))
	var border := PackedInt32Array()
	for x in n - 1:
		border.append(x)
	for z in n - 1:
		border.append(z * n + n - 1)
	for x in range(n - 1, 0, -1):
		border.append((n - 1) * n + x)
	for z in range(n - 1, 0, -1):
		border.append(z * n)
	var base := n * n
	var m := border.size()
	for j in m:
		uvs.append(uvs[border[j]])
		var a := border[j]
		var b := border[(j + 1) % m]
		var a2 := base + j
		var b2 := base + (j + 1) % m
		# both windings so the skirt is visible from either side
		idx.append_array([a, b, a2, b, b2, a2, a, a2, b, b, a2, b2])
	return {indices = idx, uvs = uvs, border = border}


## Fairly flat: long low swells plus a little surface detail. The colony pad is levelled.
func height_fn(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * 2.4 + _detail.get_noise_2d(x, z) * 0.22
	return h * smoothstep(PAD_HALF + 2.0, PAD_HALF + 26.0, maxf(absf(x), absf(z)))


static func key_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CHUNK), floori(z / CHUNK))


func height_at(x: float, z: float) -> float:
	var k := key_of(x, z)
	if not _data.has(k):
		return height_fn(x, z)
	var d: Dictionary = _data[k]
	var hs: PackedFloat32Array = d.h
	var n: int = d.res
	var e := n + 2
	var step := CHUNK / (n - 1)
	var lx := (x - k.x * CHUNK) / step
	var lz := (z - k.y * CHUNK) / step
	var ix := clampi(int(lx), 0, n - 2)
	var iz := clampi(int(lz), 0, n - 2)
	var tx := lx - ix
	var tz := lz - iz
	var b := (iz + 1) * e + ix + 1
	return lerpf(lerpf(hs[b], hs[b + 1], tx), lerpf(hs[b + e], hs[b + e + 1], tx), tz)


func normal_at(x: float, z: float) -> Vector3:
	return Vector3(height_at(x - 1.0, z) - height_at(x + 1.0, z), 2.0, height_at(x, z - 1.0) - height_at(x, z + 1.0)).normalized()


# ---------------------------------------------------------------- streaming

func _wanted_keys(c: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r2 := (radius + 0.5) * (radius + 0.5)
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz <= r2:
				out.append(Vector2i(c.x + dx, c.y + dz))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - c).length_squared() < (b - c).length_squared())
	return out


## Builds every chunk around `center` synchronously (loading screen / benchmark).
func preload_area(center: Vector3, radius: int) -> void:
	var c := key_of(center.x, center.z)
	_center = c
	for k in _wanted_keys(c, radius):
		if not chunks.has(k):
			_build_nodes(compute_data(k, _res_for(k)))
	_update_collision()


func _res_for(k: Vector2i) -> int:
	return RES_HI if force_hi or Vector2(k - _center).length() <= HI_RADIUS else RES_LO


func update(focus: Vector3) -> void:
	# Collect finished worker tasks.
	for k in _pending.keys():
		if WorkerThreadPool.is_task_completed(_pending[k]):
			WorkerThreadPool.wait_for_task_completion(_pending[k])
			_pending.erase(k)
	_mutex.lock()
	_ready_queue.append_array(_done)
	_done.clear()
	_mutex.unlock()
	# Turn at most two chunks per frame into nodes to keep frame times flat.
	for i in mini(2, _ready_queue.size()):
		_build_nodes(_ready_queue.pop_front())
	if not streaming:
		return
	var c := key_of(focus.x, focus.z)
	if c == _center:
		return
	_center = c
	for k in _wanted_keys(c, view_chunks):
		if _pending.has(k):
			continue
		var res := _res_for(k)
		if chunks.has(k) and chunks[k].get_meta("res") == res:
			continue
		if _data.has(k) and _data[k].res == res:
			_ready_queue.append(_data[k])
		else:
			_pending[k] = WorkerThreadPool.add_task(_compute_task.bind(k, res), false, "terrain chunk")
	var limit := (view_chunks + 1.5) * (view_chunks + 1.5)
	for k in chunks.keys():
		if Vector2(k - c).length_squared() > limit:
			chunks[k].queue_free()
			chunks.erase(k)
			_data.erase(k)
			if rust:
				rust.release(k)
	_update_collision()


func _compute_task(k: Vector2i, res: int) -> void:
	var d := compute_data(k, res)
	_mutex.lock()
	_done.append(d)
	_mutex.unlock()


## Pure computation (thread-safe): heights, mesh arrays (incl. skirt), collision heights.
func compute_data(k: Vector2i, n: int) -> Dictionary:
	var ox := k.x * CHUNK
	var oz := k.y * CHUNK
	var e := n + 2
	var step := CHUNK / (n - 1)
	var h := PackedFloat32Array()
	h.resize(e * e)
	for z in e:
		for x in e:
			h[z * e + x] = height_fn(ox + (x - 1) * step, oz + (z - 1) * step)
	var topo: Dictionary = _topo[n]
	var border: PackedInt32Array = topo.border
	var total := n * n + border.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	verts.resize(total)
	norms.resize(total)
	tans.resize(total * 4)
	for z in n:
		for x in n:
			var b := (z + 1) * e + x + 1
			var i := z * n + x
			verts[i] = Vector3(x * step, h[b], z * step)
			var nx := h[b - 1] - h[b + 1]
			var nz := h[b - e] - h[b + e]
			norms[i] = Vector3(nx, 2.0 * step, nz).normalized()
			var t := Vector3(2.0 * step, -nx, 0.0).normalized()
			tans[i * 4] = t.x
			tans[i * 4 + 1] = t.y
			tans[i * 4 + 2] = t.z
			tans[i * 4 + 3] = 1.0
	for j in border.size():
		var src := border[j]
		var i := n * n + j
		verts[i] = verts[src] - Vector3(0, SKIRT, 0)
		norms[i] = norms[src]
		for c in 4:
			tans[i * 4 + c] = tans[src * 4 + c]
	var col := PackedFloat32Array()
	col.resize(COL_N * COL_N)
	var cs := (n - 1) / float(COL_N - 1)
	for z in COL_N:
		for x in COL_N:
			var gx := x * cs
			var gz := z * cs
			var ix := mini(int(gx), n - 2)
			var iz := mini(int(gz), n - 2)
			var tx := gx - ix
			var tz := gz - iz
			var b := (iz + 1) * e + ix + 1
			col[z * COL_N + x] = lerpf(lerpf(h[b], h[b + 1], tx), lerpf(h[b + e], h[b + e + 1], tx), tz)
	return {key = k, res = n, h = h, verts = verts, norms = norms, tans = tans, col = col}


func _build_nodes(d: Dictionary) -> void:
	var k: Vector2i = d.key
	_data[k] = d
	if chunks.has(k):
		if chunks[k].get_meta("res") == d.res:
			return
		chunks[k].free()  # replace with the new level of detail
		chunks.erase(k)
	if streaming and Vector2(k - _center).length() > view_chunks + 1.5:
		return
	var root := Node3D.new()
	root.set_meta("res", d.res)
	root.position = Vector3(k.x * CHUNK, 0, k.y * CHUNK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d.verts
	arrays[Mesh.ARRAY_NORMAL] = d.norms
	arrays[Mesh.ARRAY_TANGENT] = d.tans
	arrays[Mesh.ARRAY_TEX_UV] = _topo[d.res].uvs
	arrays[Mesh.ARRAY_INDEX] = _topo[d.res].indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("detail_noise", _detail_tex)
	mat.set_shader_parameter("rock_normal", _normal_tex)
	mat.set_shader_parameter("rust_mask", rust.texture_for(k))
	var tt := rust.track_texture(k)
	if tt:
		mat.set_shader_parameter("track_mask", tt)
	mi.material_override = mat
	mi.visibility_range_end = view_dist + CHUNK
	# A near-flat plain barely self-shadows (rust-edge shadows are done in the shader), so skip
	# drawing every chunk into every shadow cascade.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	add_child(root)
	chunks[k] = root
	built_count += 1
	if Vector2(k - _center).length() <= 1.5:
		_ensure_collision(k)


func _update_collision() -> void:
	for k in chunks:
		var near := Vector2(k - _center).length() <= 1.5
		var body: Node = chunks[k].get_node_or_null("Body")
		if near and body == null:
			_ensure_collision(k)
		elif not near and body != null:
			body.queue_free()
			body.name = "Dying"


func _ensure_collision(k: Vector2i) -> void:
	var root: Node3D = chunks[k]
	if root.get_node_or_null("Body"):
		return
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = COL_N
	shape.map_depth = COL_N
	shape.map_data = _data[k].col
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.position = Vector3(CHUNK * 0.5, 0, CHUNK * 0.5)
	body.add_child(cs)
	root.add_child(body)


## Called when tracks appear in a chunk that is already built.
func set_track_texture(k: Vector2i, tex: Texture2D) -> void:
	if chunks.has(k):
		((chunks[k].get_node("Mesh") as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("track_mask", tex)


func set_view(dist: float) -> void:
	view_dist = dist
	view_chunks = clampi(ceili(dist / CHUNK), 2, 8)
	_center = Vector2i(1 << 30, 1 << 30)  # force a refresh on the next update
	for k in chunks:
		(chunks[k].get_node("Mesh") as MeshInstance3D).visibility_range_end = dist + CHUNK


func _noise_texture(normal_map: bool, freq: float) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.seed = seed_value + (11 if normal_map else 5)
	fn.noise_type = FastNoiseLite.TYPE_CELLULAR if normal_map else FastNoiseLite.TYPE_SIMPLEX
	fn.frequency = freq
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = fn
	if normal_map:
		tex.as_normal_map = true
		tex.bump_strength = 5.0
	return tex


func _exit_tree() -> void:
	for k in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[k])
	_pending.clear()
