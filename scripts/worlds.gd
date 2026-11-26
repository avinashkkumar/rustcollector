class_name Worlds
extends RefCounted
## Minecraft-style worlds: each world is a folder under `root` holding meta.json (name, seed,
## creation time) and that world's save files. GameState.save_dir points at the selected one.

## Developer runs (--playtest, --debug-shot) switch this to "user://dev/worlds/".
static var root := "user://worlds/"


static func dir_of(id: String) -> String:
	return root + id + "/"


## Summary of every world, most recently played first.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var da := DirAccess.open(root)
	if da == null:
		return out
	for id in da.get_directories():
		var m := read_meta(id)
		if m.is_empty():
			continue
		var save := dir_of(id) + "save.json"
		m.played = false
		m.last_played = int(m.get("created", 0))
		if FileAccess.file_exists(save):
			var d = JSON.parse_string(FileAccess.get_file_as_string(save))
			if typeof(d) == TYPE_DICTIONARY:
				m.played = true
				m.sol = int(d.get("sol", 1))
				m.credits = float(d.get("credits", 0.0))
				m.earned = float(d.get("earned", 0.0))
				m.play_time = float(d.get("play_time", 0.0))
				m.hexes = (d.get("hexes_cleared", []) as Array).size()
				m.last_played = FileAccess.get_modified_time(save)
		out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.last_played > b.last_played)
	return out


static func read_meta(id: String) -> Dictionary:
	var p := dir_of(id) + "meta.json"
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	d.id = id
	d.seed = int(d.get("seed", 4242))
	return d


static func _write_meta(id: String, m: Dictionary) -> void:
	var f := FileAccess.open(dir_of(id) + "meta.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({name = m.name, seed = int(m.seed), created = int(m.created)}, "  "))


## Seed text like Minecraft: blank = random, a whole number = that number, any other text = its hash.
static func parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t == "":
		return randi() % 2000000000
	if t.is_valid_int():
		return absi(t.to_int()) % 2000000000
	return absi(t.hash()) % 2000000000


static func create(world_name: String, seed_text: String) -> String:
	var n := world_name.strip_edges()
	if n == "":
		n = next_default_name()
	var id := "%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
	DirAccess.make_dir_recursive_absolute(dir_of(id))
	_write_meta(id, {name = n, seed = parse_seed(seed_text), created = int(Time.get_unix_time_from_system())})
	return id


static func rename(id: String, new_name: String) -> void:
	var m := read_meta(id)
	if m.is_empty() or new_name.strip_edges() == "":
		return
	m.name = new_name.strip_edges()
	_write_meta(id, m)


static func delete(id: String) -> void:
	var d := dir_of(id)
	var da := DirAccess.open(d)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(d + f)
	DirAccess.remove_absolute(d.trim_suffix("/"))


## Points the game's save at this world and returns its meta (empty if it does not exist).
static func select(id: String) -> Dictionary:
	var m := read_meta(id)
	if not m.is_empty():
		GameState.save_dir = dir_of(id)
	return m


static func next_default_name() -> String:
	var names := {}
	for w in list():
		names[w.name] = true
	var i := 1
	while names.has("Colony %d" % i):
		i += 1
	return "Colony %d" % i


## Older versions kept a single save directly in user://. Move it into a world of its own.
static func migrate_legacy(from_dir := "user://") -> String:
	if not FileAccess.file_exists(from_dir + "save.json"):
		return ""
	var id := create("My colony", "4242")  # the old fixed seed, so the terrain matches
	for f in ["save.json", "save_rust.bin", "save_dust.bin"]:
		if FileAccess.file_exists(from_dir + f):
			DirAccess.rename_absolute(from_dir + f, dir_of(id) + f)
	return id


static func describe(w: Dictionary) -> String:
	var when := Time.get_datetime_string_from_unix_time(int(w.last_played) + _tz_offset(), true).substr(0, 16)
	if not w.played:
		return "New world  ·  seed %d  ·  created %s" % [w.seed, when]
	var mins := int(float(w.play_time) / 60.0)
	return "Sol %d  ·  %s  ·  %d hexes  ·  %dh %02dm played  ·  %s  ·  seed %d" % [
		w.sol, GameState.inr(w.credits), w.hexes, mins / 60, mins % 60, when, w.seed]


static func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
