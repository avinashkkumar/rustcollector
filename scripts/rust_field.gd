class_name RustField
extends RefCounted
## Endless rust layer. One byte per 25 cm cell, stored per 64 m chunk (256x256).
## Unmodified chunks are regenerated from noise on demand; modified ones are kept and saved.
## Also owns the hexagon grid maths and per-hex clean statistics.

const RES := 256
const PPM := 4.0
const CHUNK := 64.0
const KG_PER_UNIT := 0.12 / 255.0  # a fully rusted 25 cm cell holds 0.12 kg
const HEX_W := 20.0  # hexagon flat-to-flat width in metres
const SQRT3 := 1.7320508
const PAD_IN := 19.5
const PAD_OUT := 25.0

var chunks := {}  # Vector2i -> {data, image, tex, modified}
var uploads := 0
var removed_kg := 0.0
var touched_hexes := {}  # hexes painted since the HUD last polled
var _dirty := {}
# Tyre tracks and footprints pressed into the rust (not cleaning). Separate R8 texture per chunk,
# created only where something has driven or walked.
var tracks := {}  # Vector2i -> {data, image, tex}
var _track_dirty := {}
var on_track_created: Callable  # (key, texture) -> void, set by the world to hook up terrain
var _gen: FastNoiseLite
var _sample: FastNoiseLite
var _hex_init := {}
static var _hex_offsets := PackedVector2Array()


func setup(seed_value: int) -> void:
	_gen = FastNoiseLite.new()
	_gen.seed = seed_value + 7
	_gen.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_gen.frequency = 0.02 / PPM
	_gen.fractal_octaves = 3
	_sample = _gen.duplicate()
	if _hex_offsets.is_empty():
		for zi in range(-12, 13, 3):
			for xi in range(-12, 13, 3):
				var p := Vector2(xi, zi)
				if hex_dist(p / HEX_W) < 0.47:
					_hex_offsets.append(p)


# ---------------------------------------------------------------- chunks

func _generate(k: Vector2i) -> PackedByteArray:
	_gen.offset = Vector3(k.x * RES, k.y * RES, 0)
	var data := _gen.get_image(RES, RES, false, false, false).get_data()
	var ox := k.x * CHUNK
	var oz := k.y * CHUNK
	if ox < PAD_OUT and ox + CHUNK > -PAD_OUT and oz < PAD_OUT and oz + CHUNK > -PAD_OUT:
		for y in RES:
			var wz := absf(oz + y / PPM)
			if wz >= PAD_OUT:
				continue
			for x in RES:
				var d := maxf(absf(ox + x / PPM), wz)
				if d < PAD_OUT:
					var i := y * RES + x
					data[i] = int(data[i] * smoothstep(PAD_IN, PAD_OUT, d))
	return data


func chunk(k: Vector2i) -> Dictionary:
	if not chunks.has(k):
		chunks[k] = {data = _generate(k), image = null, tex = null, modified = false}
	return chunks[k]


func texture_for(k: Vector2i) -> ImageTexture:
	var c := chunk(k)
	if c.tex == null:
		c.image = Image.create_from_data(RES, RES, false, Image.FORMAT_R8, c.data)
		c.tex = ImageTexture.create_from_image(c.image)
	return c.tex


## Frees an unmodified chunk that scrolled out of view (it can be regenerated exactly).
func release(k: Vector2i) -> void:
	if chunks.has(k) and not chunks[k].modified:
		chunks.erase(k)
		_dirty.erase(k)
	tracks.erase(k)
	_track_dirty.erase(k)


func track_texture(k: Vector2i) -> ImageTexture:
	return tracks[k].tex if tracks.has(k) else null


## Presses a soft dent of `depth` (0..1) into the rust layer, e.g. under a wheel or a boot.
func press(pos: Vector3, radius_m: float, depth: float) -> void:
	var r := maxf(radius_m * PPM, 0.75)
	var r2 := r * r
	var gx := pos.x * PPM
	var gy := pos.z * PPM
	var x0 := floori(gx - r)
	var x1 := floori(gx + r)
	var y0 := floori(gy - r)
	var y1 := floori(gy + r)
	for ky in range(floori(float(y0) / RES), floori(float(y1) / RES) + 1):
		for kx in range(floori(float(x0) / RES), floori(float(x1) / RES) + 1):
			var k := Vector2i(kx, ky)
			if not tracks.has(k):
				var blank := PackedByteArray()
				blank.resize(RES * RES)
				var img := Image.create_from_data(RES, RES, false, Image.FORMAT_R8, blank)
				tracks[k] = {data = blank, image = img, tex = ImageTexture.create_from_image(img)}
				if on_track_created.is_valid():
					on_track_created.call(k, tracks[k].tex)
			var t: Dictionary = tracks[k]
			var data: PackedByteArray = t.data
			t.data = PackedByteArray()  # sole owner: write in place
			var bx := kx * RES
			var by := ky * RES
			for y in range(maxi(y0 - by, 0), mini(y1 - by, RES - 1) + 1):
				var dy := by + y + 0.5 - gy
				for x in range(maxi(x0 - bx, 0), mini(x1 - bx, RES - 1) + 1):
					var dx := bx + x + 0.5 - gx
					var d2 := dx * dx + dy * dy
					if d2 > r2:
						continue
					var i := y * RES + x
					data[i] = maxi(data[i], int(depth * 255.0 * (1.0 - 0.6 * d2 / r2)))
			t.data = data
			_track_dirty[k] = true


## Removes rust in a soft circle. strength = fraction of a full cell removed at the centre.
## Returns kilograms removed.
func paint(pos: Vector3, radius_m: float, strength: float) -> float:
	var r := maxf(radius_m * PPM, 1.0)
	var r2 := r * r
	var gx := pos.x * PPM
	var gy := pos.z * PPM
	var x0 := floori(gx - r)
	var x1 := floori(gx + r)
	var y0 := floori(gy - r)
	var y1 := floori(gy + r)
	var amt := strength * 255.0
	var removed := 0
	for ky in range(floori(float(y0) / RES), floori(float(y1) / RES) + 1):
		for kx in range(floori(float(x0) / RES), floori(float(x1) / RES) + 1):
			var k := Vector2i(kx, ky)
			var c := chunk(k)
			# Take sole ownership so writes happen in place (packed arrays are copy-on-write;
			# holding a second reference would copy all 64 KB on the first write).
			var data: PackedByteArray = c.data
			c.data = PackedByteArray()
			var bx := kx * RES
			var by := ky * RES
			var got := 0
			for y in range(maxi(y0 - by, 0), mini(y1 - by, RES - 1) + 1):
				var dy := by + y + 0.5 - gy
				var row := y * RES
				for x in range(maxi(x0 - bx, 0), mini(x1 - bx, RES - 1) + 1):
					var dx := bx + x + 0.5 - gx
					var d2 := dx * dx + dy * dy
					if d2 > r2:
						continue
					var i := row + x
					var v := data[i]
					if v == 0:
						continue
					var nv := maxi(v - (int(amt * (1.0 - 0.7 * d2 / r2)) + 1), 0)
					data[i] = nv
					got += v - nv
			c.data = data
			if got > 0:
				c.modified = true
				_dirty[k] = true
				removed += got
	if removed == 0:
		return 0.0
	touched_hexes[hex_key(pos.x, pos.z)] = true
	if radius_m > 1.5:
		for o in [Vector2(radius_m, 0), Vector2(-radius_m, 0), Vector2(0, radius_m), Vector2(0, -radius_m)]:
			touched_hexes[hex_key(pos.x + o.x, pos.z + o.y)] = true
	var kg := removed * KG_PER_UNIT
	removed_kg += kg
	return kg


func upload() -> void:
	for k in _dirty:
		var c: Dictionary = chunks[k]
		if c.tex:
			c.image.set_data(RES, RES, false, Image.FORMAT_R8, c.data)
			c.tex.update(c.image)
			uploads += 1
	_dirty.clear()
	for k in _track_dirty:
		var t: Dictionary = tracks[k]
		t.image.set_data(RES, RES, false, Image.FORMAT_R8, t.data)
		t.tex.update(t.image)
	_track_dirty.clear()


## 0..255 rust value at a world position, generating the chunk if needed.
func value_at(x: float, z: float) -> int:
	var gx := floori(x * PPM)
	var gy := floori(z * PPM)
	var k := Vector2i(floori(float(gx) / RES), floori(float(gy) / RES))
	if not chunks.has(k):
		return initial_at(x, z)
	return chunks[k].data[(gy - k.y * RES) * RES + (gx - k.x * RES)]


func rust_at(x: float, z: float) -> float:
	return value_at(x, z) / 255.0


## The untouched rust value (matches what _generate produces for that cell).
func initial_at(x: float, z: float) -> int:
	var gx := floori(x * PPM)
	var gy := floori(z * PPM)
	var v := int(clampf(_sample.get_noise_2d(gx, gy) * 0.5 + 0.5, 0.0, 1.0) * 255.0)
	var d := maxf(absf(gx / PPM), absf(gy / PPM))
	if d < PAD_OUT:
		v = int(v * smoothstep(PAD_IN, PAD_OUT, d))
	return v


# ---------------------------------------------------------------- hexagons
# Pointy-top hex grid, 20 m across the flats. Same maths as the terrain shader overlay.

static func hex_dist(p: Vector2) -> float:
	var a := absf(p.x)
	var b := absf(p.y)
	return maxf(a * 0.5 + b * SQRT3 * 0.5, a)


static func hex_center(x: float, z: float) -> Vector2:
	var p := Vector2(x, z) / HEX_W
	var s := Vector2(1.0, SQRT3)
	var a := (p / s).floor() + Vector2(0.5, 0.5)
	var b := ((p - Vector2(0.5, 1.0)) / s).floor() + Vector2(0.5, 0.5)
	var ca := a * s
	var cb := (b + Vector2(0.5, 0.5)) * s
	var c := ca if (p - ca).length_squared() < (p - cb).length_squared() else cb
	return c * HEX_W


static func hex_key(x: float, z: float) -> Vector2i:
	var c := hex_center(x, z) / HEX_W
	return Vector2i(roundi(c.x * 2.0), roundi(c.y / (SQRT3 * 0.5)))


static func key_center(k: Vector2i) -> Vector2:
	return Vector2(k.x * 0.5, k.y * SQRT3 * 0.5) * HEX_W


## Fraction of the hex's original rust that has been removed (sampled on a 3 m grid).
func hex_clean(k: Vector2i) -> float:
	var c := key_center(k)
	var init: float = _hex_init.get(k, -1.0)
	if init < 0.0:
		init = 0.0
		for o in _hex_offsets:
			init += initial_at(c.x + o.x, c.y + o.y)
		_hex_init[k] = init
	if init <= 0.0:
		return 1.0
	var cur := 0.0
	for o in _hex_offsets:
		cur += value_at(c.x + o.x, c.y + o.y)
	return clampf(1.0 - cur / init, 0.0, 1.0)


func hex_pristine_kg(k: Vector2i) -> float:
	hex_clean(k)
	# Sample grid is 3 m; each sample stands for 9 m² = 144 cells.
	return float(_hex_init.get(k, 0.0)) * 144.0 * KG_PER_UNIT


static func hex_name(k: Vector2i) -> String:
	return "%d:%d" % [k.x, k.y]


# ---------------------------------------------------------------- save

func to_save() -> Dictionary:
	var out := {}
	for k in chunks:
		if chunks[k].modified:
			out["%d,%d" % [k.x, k.y]] = (chunks[k].data as PackedByteArray).compress(FileAccess.COMPRESSION_ZSTD)
	return out


func from_save(d: Dictionary) -> void:
	for key in d:
		var parts: PackedStringArray = str(key).split(",")
		var k := Vector2i(int(parts[0]), int(parts[1]))
		var raw: PackedByteArray = d[key]
		var data := raw.decompress(RES * RES, FileAccess.COMPRESSION_ZSTD)
		if data.size() == RES * RES:
			chunks[k] = {data = data, image = null, tex = null, modified = true}
