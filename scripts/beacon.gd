class_name Beacon
extends Node3D
## A tall light pillar with a floating "name · distance" label, visible from far away.
## Used for the player's waypoint and for supply pods.

var title := "Waypoint"
var color := Color(0.4, 0.9, 1.0)
var _label: Label3D
var _beam: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	_beam = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.18
	c.bottom_radius = 0.35
	c.height = 70.0
	c.radial_segments = 12
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	_beam.mesh = c
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, 0.35)
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 4.0
	m.distance_fade_max_distance = 14.0
	_beam.material_override = m
	_beam.position.y = 35.0
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0012
	_label.font_size = 26
	_label.outline_size = 8
	_label.modulate = color
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.position.y = 3.0
	add_child(_label)


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.2
	var cam := get_viewport().get_camera_3d()
	if cam:
		var d := Vector2(cam.global_position.x - global_position.x, cam.global_position.z - global_position.z).length()
		var t := "%s · %d m" % [title, roundi(d)]
		if _label.text != t:
			_label.text = t
