class_name GameUI
extends CanvasLayer
## All 2D UI: HUD, main menu, garage (upgrade shop), results and pause screens.
## Built in code; emits signals that main.gd turns into game-state changes.

signal play_requested
signal garage_requested
signal menu_requested
signal resume_requested
signal quit_requested

const CYAN := Color(0.0, 0.9, 1.0)
const PINK := Color(1.0, 0.2, 0.85)
const GOLD := Color(1.0, 0.85, 0.2)
const DIM := Color(0.7, 0.7, 0.8)

var _root: Control
var _screens := {}

# HUD widgets
var _score_label: Label
var _best_label: Label
var _time_label: Label
var _coins_label: Label
var _speed_label: Label
var _combo_box: VBoxContainer
var _combo_mult: Label
var _combo_points: Label
var _combo_bar: ProgressBar
var _boost_bar: ProgressBar
var _effects_box: VBoxContainer
var _countdown_label: Label
var _popup_layer: Control
var _popup_slot := 0

# Menu / garage / results widgets
var _menu_stats: Label
var _menu_play: Button
var _garage_cash: Label
var _garage_rows: VBoxContainer
var _garage_back: Button
var _results_title: Label
var _results_score: Label
var _results_best: Label
var _results_details: Label
var _results_retry: Button
var _pause_resume: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_hud()
	_build_menu()
	_build_garage()
	_build_results()
	_build_pause()
	GameData.cash_changed.connect(func(_c: int) -> void: _refresh_cash_labels())


func show_screen(screen_name: String) -> void:
	for key in _screens:
		var s: Control = _screens[key]
		s.visible = key == screen_name or (key == "hud" and screen_name == "pause")
	match screen_name:
		"menu":
			_refresh_cash_labels()
			_menu_play.grab_focus()
		"garage":
			refresh_garage()
			_garage_back.grab_focus()
		"results":
			_results_retry.grab_focus()
		"pause":
			_pause_resume.grab_focus()
		"hud":
			for c in _popup_layer.get_children():
				c.queue_free()


# --- HUD ---------------------------------------------------------------------------

func update_hud(d: Dictionary) -> void:
	_score_label.text = _fmt(d["score"])
	_best_label.text = "BEST " + _fmt(d["best"])
	var t: float = d["time"]
	_time_label.text = "%d" % ceili(t)
	_time_label.modulate = Color(1, 0.3, 0.3) if t < 10.0 and fmod(t, 1.0) > 0.5 else Color.WHITE
	_coins_label.text = "COINS %d" % d["coins"]
	_speed_label.text = "%d km/h" % d["speed_kmh"]
	_boost_bar.value = d["boost_ratio"] * 100.0

	var chain: bool = d["chain_active"]
	_combo_box.visible = chain
	if chain:
		_combo_mult.text = "DRIFT  x%d" % d["multiplier"]
		if d["double"]:
			_combo_mult.text += "  (2X)"
		_combo_points.text = _fmt(d["chain_points"])
		_combo_bar.value = d["grace_ratio"] * 100.0
		_combo_points.modulate = GOLD if d["drifting"] else Color(1, 1, 1, 0.7)

	var effects: Array = d["effects"]
	var labels := _effects_box.get_children()
	for i in maxi(effects.size(), labels.size()):
		if i >= labels.size():
			var l := _label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
			_effects_box.add_child(l)
			labels.append(l)
		var lab: Label = labels[i]
		lab.visible = i < effects.size()
		if lab.visible:
			lab.text = effects[i][0]
			lab.modulate = effects[i][1]


func show_countdown(text: String) -> void:
	_countdown_label.text = text
	_countdown_label.visible = true
	_countdown_label.scale = Vector2(1.6, 1.6)
	_countdown_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_countdown_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(0.45)
	tw.tween_property(_countdown_label, "modulate:a", 0.0, 0.25)


func popup(text: String, color: Color, size := 36) -> void:
	var l := _label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	var base_y := _popup_layer.size.y * 0.26 + (_popup_slot % 4) * 58.0
	_popup_slot += 1
	l.position = Vector2(0, base_y)
	l.size.x = _popup_layer.size.x
	l.pivot_offset = Vector2(_popup_layer.size.x / 2.0, size / 2.0)
	l.scale = Vector2(0.5, 0.5)
	_popup_layer.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", base_y - 50.0, 0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(l.queue_free)


func _build_hud() -> void:
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_screen("hud", hud)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	hud.add_child(margin)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	# Top row: score | time | coins & speed
	var top := HBoxContainer.new()
	col.add_child(top)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	top.add_child(left)
	left.add_child(_label("SCORE", 18, DIM))
	_score_label = _label("0", 44, Color.WHITE)
	left.add_child(_score_label)
	_best_label = _label("BEST 0", 18, DIM)
	left.add_child(_best_label)
	top.add_child(_spacer())
	var center := VBoxContainer.new()
	top.add_child(center)
	center.add_child(_label("TIME", 18, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_time_label = _label("60", 56, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	center.add_child(_time_label)
	top.add_child(_spacer())
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 280
	top.add_child(right)
	_coins_label = _label("COINS 0", 32, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_coins_label)
	_speed_label = _label("0 km/h", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_speed_label)

	# Combo display under the timer
	_combo_box = VBoxContainer.new()
	_combo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_combo_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_combo_box.custom_minimum_size.x = 320
	col.add_child(_combo_box)
	_combo_mult = _label("DRIFT x1", 30, CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	_combo_box.add_child(_combo_mult)
	_combo_points = _label("0", 48, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_combo_box.add_child(_combo_points)
	_combo_bar = _bar(CYAN, Vector2(320, 10))
	_combo_box.add_child(_combo_bar)
	_combo_box.visible = false

	col.add_child(_spacer(true))

	# Bottom row: nitro | active power-ups
	var bottom := HBoxContainer.new()
	col.add_child(bottom)
	var boost_col := VBoxContainer.new()
	bottom.add_child(boost_col)
	boost_col.add_child(_label("NITRO  [SHIFT]", 18, Color(0.5, 0.8, 1.0)))
	_boost_bar = _bar(Color(0.25, 0.6, 1.0), Vector2(300, 22))
	boost_col.add_child(_boost_bar)
	bottom.add_child(_spacer())
	_effects_box = VBoxContainer.new()
	_effects_box.alignment = BoxContainer.ALIGNMENT_END
	_effects_box.custom_minimum_size.x = 280
	bottom.add_child(_effects_box)

	_popup_layer = Control.new()
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_popup_layer)

	_countdown_label = _label("", 140, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.resized.connect(func() -> void: _countdown_label.pivot_offset = _countdown_label.size / 2.0)
	_countdown_label.visible = false
	hud.add_child(_countdown_label)


# --- Menu ----------------------------------------------------------------------------

func _build_menu() -> void:
	var box := _panel_screen("menu")
	var title := _label("DRIFT ARCADE", 72, PINK, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.2))
	title.add_theme_constant_override("outline_size", 16)
	box.add_child(title)
	box.add_child(_label("Chain drifts. Grab power-ups. Upgrade your ride.", 22, CYAN, HORIZONTAL_ALIGNMENT_CENTER))
	_menu_stats = _label("", 22, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_menu_stats)
	box.add_child(_gap(10))
	_menu_play = _button("PLAY", play_requested.emit)
	box.add_child(_menu_play)
	box.add_child(_button("GARAGE", garage_requested.emit))
	if OS.get_name() != "Web":
		box.add_child(_button("QUIT", quit_requested.emit))
	box.add_child(_gap(10))
	var help := _label(
		"W/S or Up/Down  throttle & brake    A/D or Left/Right  steer\n"
		+ "SPACE  handbrake    SHIFT  nitro    ESC  pause    F11  fullscreen\n"
		+ "Gamepad: RT/LT throttle & brake, left stick steer, A handbrake, X/RB nitro",
		16, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(help)


# --- Garage --------------------------------------------------------------------------

func refresh_garage() -> void:
	_refresh_cash_labels()
	for c in _garage_rows.get_children():
		c.queue_free()
	for id in GameData.UPGRADE_ORDER:
		var info: Dictionary = GameData.UPGRADES[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		text.add_child(_label(String(info["name"]), 24, Color.WHITE))
		text.add_child(_label(String(info["desc"]), 15, DIM))
		row.add_child(text)
		var lv := GameData.level(id)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 4)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for i in GameData.MAX_LEVEL:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(16, 22)
			pip.color = CYAN if i < lv else Color(1, 1, 1, 0.15)
			pips.add_child(pip)
		row.add_child(pips)
		var price := GameData.cost(id)
		var btn := _button("MAX" if price < 0 else "$%d" % price, func() -> void: _buy(id))
		btn.custom_minimum_size = Vector2(130, 42)
		btn.disabled = not GameData.can_buy(id)
		row.add_child(btn)
		_garage_rows.add_child(row)


func _buy(id: String) -> void:
	if GameData.buy(id):
		Sfx.play("bank")
		refresh_garage()
		_garage_back.grab_focus()


func _build_garage() -> void:
	var box := _panel_screen("garage")
	box.custom_minimum_size.x = 640
	box.add_theme_constant_override("separation", 8)
	box.add_child(_label("GARAGE", 40, PINK, HORIZONTAL_ALIGNMENT_CENTER))
	_garage_cash = _label("", 24, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_garage_cash)
	_garage_rows = VBoxContainer.new()
	_garage_rows.add_theme_constant_override("separation", 4)
	box.add_child(_garage_rows)
	box.add_child(_gap(4))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	_garage_back = _button("BACK", menu_requested.emit)
	buttons.add_child(_garage_back)
	buttons.add_child(_button("PLAY", play_requested.emit))
	box.add_child(buttons)


func _refresh_cash_labels() -> void:
	if _garage_cash:
		_garage_cash.text = "CASH  $%s" % _fmt(GameData.cash)
	if _menu_stats:
		_menu_stats.text = "BEST %s     CASH $%s" % [_fmt(GameData.best_score), _fmt(GameData.cash)]


# --- Results / pause -------------------------------------------------------------------

func show_results(r: Dictionary) -> void:
	_results_score.text = _fmt(r["score"])
	_results_best.text = "NEW BEST!" if r["new_best"] else "BEST  %s" % _fmt(r["best"])
	_results_best.modulate = GOLD if r["new_best"] else DIM
	_results_details.text = (
		"Biggest combo   %s\n" % _fmt(r["best_chain"])
		+ "Coins   %d     Cones smashed   %d\n" % [r["coins"], r["cones"]]
		+ "Cash earned   $%s" % _fmt(r["cash_earned"]))
	show_screen("results")


func _build_results() -> void:
	var box := _panel_screen("results")
	_results_title = _label("TIME UP!", 56, PINK, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_results_title)
	_results_score = _label("0", 64, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_results_score)
	_results_best = _label("", 26, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_results_best)
	_results_details = _label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_results_details)
	box.add_child(_gap(8))
	_results_retry = _button("RETRY", play_requested.emit)
	box.add_child(_results_retry)
	box.add_child(_button("GARAGE", garage_requested.emit))
	box.add_child(_button("MENU", menu_requested.emit))


func _build_pause() -> void:
	var box := _panel_screen("pause")
	box.add_child(_label("PAUSED", 56, PINK, HORIZONTAL_ALIGNMENT_CENTER))
	_pause_resume = _button("RESUME", resume_requested.emit)
	box.add_child(_pause_resume)
	box.add_child(_button("QUIT TO MENU", menu_requested.emit))


# --- Helpers ------------------------------------------------------------------------------

func _add_screen(screen_name: String, c: Control) -> void:
	_screens[screen_name] = c
	c.visible = false
	_root.add_child(c)


func _panel_screen(screen_name: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_add_screen(screen_name, center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box


func _label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 52)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		action.call())
	return b


func _bar(color: Color, min_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = min_size
	bar.max_value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(4)
	bg.border_color = Color(1, 1, 1, 0.25)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _spacer(vertical := false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _gap(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 22
	th.set_stylebox("normal", "Button", _box(Color(0.08, 0.06, 0.14, 0.92), CYAN, 2))
	th.set_stylebox("hover", "Button", _box(Color(0.18, 0.08, 0.28, 0.95), PINK, 2))
	th.set_stylebox("pressed", "Button", _box(Color(0.3, 0.1, 0.4, 1.0), PINK, 2))
	th.set_stylebox("disabled", "Button", _box(Color(0.08, 0.08, 0.1, 0.7), Color(0.3, 0.3, 0.35), 2))
	var focus := _box(Color(0, 0, 0, 0), GOLD, 3)
	focus.draw_center = false
	th.set_stylebox("focus", "Button", focus)
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_focus_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.5))
	th.set_font_size("font_size", "Button", 24)
	th.set_constant("outline_size", "Label", 8)
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	var panel := _box(Color(0.04, 0.03, 0.08, 0.88), PINK, 2)
	panel.set_content_margin_all(24)
	th.set_stylebox("panel", "PanelContainer", panel)
	return th


func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(10)
	return s


static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
