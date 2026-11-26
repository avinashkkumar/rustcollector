class_name Story
extends Control
## Opening story: a few typewriter slides. Space/Enter/click = next, Esc = skip.

signal finished

const SLIDES := [
	["SOL 1 AFTER THE STORM", "The Great Storm raged for 212 sols. When the sky finally cleared, Rustfall Base, a small Indian-run solar outpost on the plains of Mars, lay buried under a thick crust of red iron-oxide dust."],
	["RED GOLD", "Back home, that rust is worth money. Ultra-fine Martian iron oxide feeds steel mills, pigment plants and radiation shielding across the inner system. Every kilogram you ship pays ₹25."],
	["THE LAST CONTRACTOR", "The mining company pulled out. You stayed. They left you a scrub brush, a 25 kg tank, a half-charged base battery and an export depot that ships whatever you bring it. Solar panels, machines and everything else, you will have to buy."],
	["THE PLAN", "Clear the plain hexagon by hexagon; every hexagon you restore pays a bonus. Sell rust, buy better tools, expand the solar field, and keep your machines charged. If one runs flat out on the plain, send the charger cart."],
	["THE PLAIN NEVER ENDS", "Mars is wide and the rust goes on forever. How far will you get?"],
]

var _i := 0
var _title: Label
var _body: Label
var _hint: Label
var _tw: Tween
var _voice: AudioStreamPlayer
var _tts_voice := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV;
	float horizon = 0.62 + sin(uv.x * 7.0 + 1.3) * 0.012 + sin(uv.x * 19.0) * 0.004;
	vec3 sky = mix(vec3(0.55, 0.33, 0.22), vec3(0.10, 0.05, 0.04), pow(1.0 - uv.y / horizon, 1.4));
	vec3 ground = mix(vec3(0.42, 0.18, 0.09), vec3(0.16, 0.07, 0.04), (uv.y - horizon) / (1.0 - horizon));
	vec3 c = uv.y < horizon ? sky : ground;
	float drift = sin(uv.x * 40.0 + TIME * 0.7 + uv.y * 9.0) * sin(uv.y * 31.0 - TIME * 0.5);
	c += vec3(0.04, 0.02, 0.01) * drift;
	c *= 1.0 - 0.45 * length(uv - 0.5);
	COLOR = vec4(c, 1.0);
}
"""
	sm.shader = sh
	bg.material = sm
	add_child(bg)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -460
	box.offset_right = 460
	box.offset_top = -170
	box.offset_bottom = 170
	box.add_theme_constant_override("separation", 22)
	add_child(box)
	_title = UiKit.label("", 30, UiKit.ACCENT)
	box.add_child(_title)
	_body = UiKit.label("", 24, Color(1, 0.94, 0.88))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 920
	box.add_child(_body)
	_hint = UiKit.label("", 15, UiKit.MUTED)
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.offset_top = -60
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_voice = AudioStreamPlayer.new()
	add_child(_voice)
	_tts_voice = _pick_tts_voice()
	_show(0)


## Narration: bundled recordings (assets/voice/story_N.ogg) if present, otherwise the OS
## text-to-speech voice (Speech Dispatcher on Linux, SAPI on Windows).
func _pick_tts_voice() -> String:
	if not Config.narrator:
		return ""
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		return ""
	# Prefer an Indian or British English voice when the OS has one.
	for want in ["en_IN", "en-IN", "en_GB", "en-GB"]:
		for v in DisplayServer.tts_get_voices():
			if str(v.get("language", "")).begins_with(want):
				return v.id
	return voices[0]


func _narrate(i: int) -> void:
	DisplayServer.tts_stop()
	_voice.stop()
	if not Config.narrator:
		return
	var path := "res://assets/voice/story_%d.ogg" % (i + 1)
	if ResourceLoader.exists(path):
		_voice.stream = load(path)
		_voice.play()
	elif _tts_voice != "":
		var text: String = SLIDES[i][0].capitalize() + ". " + SLIDES[i][1]
		DisplayServer.tts_speak(text.replace("₹25", "25 rupees"), _tts_voice, 90, 0.95, 0.95)


func _exit_tree() -> void:
	DisplayServer.tts_stop()


func _show(i: int) -> void:
	_i = i
	_title.text = SLIDES[i][0]
	_body.text = SLIDES[i][1]
	_body.visible_ratio = 0.0
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(_body, "visible_ratio", 1.0, _body.text.length() * 0.022)
	_hint.text = "Space / Enter: %s   ·   Esc: skip story" % ("begin" if i == SLIDES.size() - 1 else "next")
	_narrate(i)


func _unhandled_input(e: InputEvent) -> void:
	var next: bool = e.is_action_pressed("ui_accept") or e.is_action_pressed("jump") or (e is InputEventMouseButton and e.pressed)
	if e.is_action_pressed("pause") or e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		finished.emit()
	elif next:
		get_viewport().set_input_as_handled()
		if _body.visible_ratio < 1.0:
			_tw.kill()
			_body.visible_ratio = 1.0
		elif _i + 1 < SLIDES.size():
			_show(_i + 1)
		else:
			finished.emit()
