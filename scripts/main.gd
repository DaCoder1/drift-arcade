extends Node
## Game flow: menu -> countdown -> timed arena run -> results -> garage.
## Owns scoring (drift chains + multiplier), pickups and power-up effects.
##
## Run with `-- --smoke-test` to let an autopilot drive a short run headless
## and print a summary (used to sanity-check the game without a screen).
## Add `--capture=<dir>` (with a real display) to also save screenshots.

enum State { MENU, GARAGE, COUNTDOWN, PLAYING, PAUSED, RESULTS }

const SPAWN_POS := Vector3(0, 0, 40)
const SPAWN_YAW := -PI / 2.0
const MAX_MULTIPLIER := 10
const LONG_DRIFT_TIME := 3.0
const TARGET_COINS := 30
const MAX_POWERUPS := 3
const CONE_POINTS := 75
const COIN_CASH := 5
const SCORE_PER_CASH := 30
const MAGNET_POWERUP_RADIUS := 20.0

var state := State.MENU
var arena: Arena
var car: DriftCar
var cam: ChaseCamera
var skid: SkidMarks
var ui: GameUI
var pickups_root: Node3D

# Run state
var score := 0
var time_left := 0.0
var coins := 0
var cones_hit := 0
var best_chain := 0
var chain_active := false
var chain_points := 0.0
var multiplier := 1
var chain_grace := 0.0
var drift_seg_time := 0.0
var last_drift_side := 0
var was_drifting := false
var double_time := 0.0
var magnet_time := 0.0
var shield := false
var powerup_timer := 0.0
var countdown := 0.0
var _countdown_step := 0
var _was_boosting := false

# Smoke test
var _smoke_test := false
var _test_time := 0.0
var _capture_dir := ""
var _captured := {}
var _test := {"max_speed": 0.0, "drift_time": 0.0, "crashes": 0, "banked": 0, "pickups": []}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()

	var world := Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

	arena = Arena.new()
	world.add_child(arena)
	for c in arena.cones:
		c.hit.connect(_on_cone_hit)

	skid = SkidMarks.new()
	world.add_child(skid)
	pickups_root = Node3D.new()
	world.add_child(pickups_root)

	car = DriftCar.new()
	world.add_child(car)
	car.skid_marks = skid
	car.crashed.connect(_on_car_crashed)

	cam = ChaseCamera.new()
	cam.target = car
	world.add_child(cam)
	cam.make_current()

	ui = GameUI.new()
	add_child(ui)
	ui.play_requested.connect(start_run)
	ui.garage_requested.connect(open_garage)
	ui.menu_requested.connect(show_menu)
	ui.resume_requested.connect(resume)
	ui.quit_requested.connect(func() -> void: get_tree().quit())

	_smoke_test = "--smoke-test" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
	if _smoke_test:
		GameData.save_path = "user://smoke_test_save.cfg"
		GameData.reset_progress()

	car.apply_stats()
	car.reset_to(SPAWN_POS, SPAWN_YAW)
	cam.snap()
	show_menu()
	if _smoke_test:
		print("[smoke] starting run")
		start_run()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("pause"):
		match state:
			State.PLAYING, State.COUNTDOWN:
				pause()
			State.PAUSED:
				resume()
			State.GARAGE:
				show_menu()


# --- State changes ---------------------------------------------------------------

func show_menu() -> void:
	get_tree().paused = false
	state = State.MENU
	_clear_pickups()
	car.controls_enabled = false
	car.set_shield_visible(false)
	car.apply_stats()
	car.reset_to(SPAWN_POS, SPAWN_YAW)
	cam.orbit_mode = true
	ui.show_screen("menu")


func open_garage() -> void:
	get_tree().paused = false
	state = State.GARAGE
	car.controls_enabled = false
	cam.orbit_mode = true
	ui.show_screen("garage")


func start_run() -> void:
	get_tree().paused = false
	score = 0
	coins = 0
	cones_hit = 0
	best_chain = 0
	chain_active = false
	chain_points = 0.0
	multiplier = 1
	was_drifting = false
	last_drift_side = 0
	double_time = 0.0
	magnet_time = 0.0
	shield = false
	time_left = GameData.run_time()
	powerup_timer = 3.0

	arena.reset_cones()
	skid.clear_marks()
	_clear_pickups()
	for i in 5:
		_spawn_coin_line()

	car.apply_stats()
	car.boost = car.boost_capacity * 0.5
	car.controls_enabled = false
	car.set_shield_visible(false)
	car.reset_to(SPAWN_POS, SPAWN_YAW)
	cam.orbit_mode = false
	cam.snap()

	state = State.COUNTDOWN
	countdown = 0.01 if _smoke_test else 3.0
	_countdown_step = 4
	ui.show_screen("hud")
	_update_hud()


func pause() -> void:
	state = State.PAUSED
	get_tree().paused = true
	ui.show_screen("pause")


func resume() -> void:
	get_tree().paused = false
	state = State.PLAYING if car.controls_enabled else State.COUNTDOWN
	ui.show_screen("hud")


func end_run() -> void:
	if chain_active:
		_bank_chain()
	state = State.RESULTS
	car.controls_enabled = false
	var cash_earned := coins * COIN_CASH + score / SCORE_PER_CASH
	var new_best := score > GameData.best_score
	if new_best:
		GameData.best_score = score
	GameData.runs_played += 1
	GameData.add_cash(cash_earned)
	GameData.save_game()
	Sfx.play("go", 0.5)
	ui.show_results({
		"score": score, "best": GameData.best_score, "new_best": new_best,
		"best_chain": best_chain, "coins": coins, "cones": cones_hit, "cash_earned": cash_earned,
	})
	if _smoke_test:
		_finish_smoke_test(cash_earned)


# --- Per-frame -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if _smoke_test:
		_drive_bot(delta)
	match state:
		State.COUNTDOWN:
			countdown -= delta
			var step := ceili(countdown)
			if step != _countdown_step:
				_countdown_step = step
				if step > 0:
					ui.show_countdown(str(step))
					Sfx.play("beep")
				else:
					ui.show_countdown("GO!")
					Sfx.play("go")
					state = State.PLAYING
					car.controls_enabled = true
			_update_hud()
		State.PLAYING:
			_update_run(delta)
			_update_hud()


func _process(_delta: float) -> void:
	var driving := state in [State.COUNTDOWN, State.PLAYING, State.RESULTS]
	if state == State.PAUSED:
		Sfx.set_engine(0.0, 0.0, false)
		Sfx.set_screech(0.0)
		return
	Sfx.set_engine(car.speed / car.top_speed, maxf(car.throttle, 0.0), true)
	var screech := 0.0
	if driving and car.is_drifting:
		screech = clampf((car.drift_angle - 6.0) / 30.0, 0.2, 1.0) * clampf(car.speed / 15.0, 0.0, 1.0)
	Sfx.set_screech(screech)
	if car.boosting and not _was_boosting:
		Sfx.play("boost")
	_was_boosting = car.boosting


func _update_run(delta: float) -> void:
	time_left -= delta
	double_time = maxf(double_time - delta, 0.0)
	magnet_time = maxf(magnet_time - delta, 0.0)
	_update_drift(delta)
	_update_pickups(delta)
	if time_left <= 0.0:
		time_left = 0.0
		end_run()


func _update_drift(delta: float) -> void:
	if car.is_drifting:
		if not chain_active:
			chain_active = true
			chain_points = 0.0
			multiplier = 1
			drift_seg_time = 0.0
		elif not was_drifting:
			_bump_multiplier("SWITCH!" if car.drift_side != last_drift_side else "CHAIN")
		last_drift_side = car.drift_side
		chain_grace = GameData.combo_grace()
		drift_seg_time += delta
		if drift_seg_time >= LONG_DRIFT_TIME:
			drift_seg_time -= LONG_DRIFT_TIME
			_bump_multiplier("LONG DRIFT")
		var angle_factor := clampf(car.drift_angle / 25.0, 0.4, 2.5)
		chain_points += car.speed * angle_factor * delta * 4.0
		car.add_boost(clampf(car.drift_angle / 30.0, 0.3, 1.5) * 14.0 * delta)
	else:
		drift_seg_time = 0.0
		if chain_active:
			chain_grace -= delta
			if chain_grace <= 0.0:
				_bank_chain()
	was_drifting = car.is_drifting


func _bump_multiplier(reason: String) -> void:
	if multiplier >= MAX_MULTIPLIER:
		return
	multiplier += 1
	ui.popup("%s  x%d" % [reason, multiplier], GameUI.CYAN, 30)
	Sfx.play("combo", 1.0 + multiplier * 0.06)


func _bank_chain() -> void:
	chain_active = false
	var total := int(chain_points * multiplier * (2 if double_time > 0.0 else 1))
	chain_points = 0.0
	if total <= 0:
		return
	score += total
	best_chain = maxi(best_chain, total)
	_test["banked"] += 1
	var title := "DRIFT"
	if total >= 10000:
		title = "LEGENDARY DRIFT!"
	elif total >= 4000:
		title = "INSANE DRIFT!"
	elif total >= 1500:
		title = "GREAT DRIFT!"
	elif total >= 500:
		title = "NICE DRIFT"
	ui.popup("%s  +%s" % [title, GameUI._fmt(total)], GameUI.GOLD, 40 if total >= 1500 else 32)
	Sfx.play("bank")


func _update_hud() -> void:
	var effects: Array = []
	if double_time > 0.0:
		effects.append(["2X SCORE  %.1f" % double_time, Pickup.INFO[Pickup.Kind.DOUBLE]["color"]])
	if magnet_time > 0.0:
		effects.append(["MAGNET  %.1f" % magnet_time, Pickup.INFO[Pickup.Kind.MAGNET]["color"]])
	if shield:
		effects.append(["SHIELD READY", Pickup.INFO[Pickup.Kind.SHIELD]["color"]])
	ui.update_hud({
		"score": score, "best": GameData.best_score, "time": time_left, "coins": coins,
		"speed_kmh": int(car.speed * 3.6), "boost_ratio": car.boost / car.boost_capacity,
		"chain_active": chain_active, "chain_points": int(chain_points), "multiplier": multiplier,
		"grace_ratio": chain_grace / GameData.combo_grace() if not car.is_drifting else 1.0,
		"drifting": car.is_drifting, "double": double_time > 0.0, "effects": effects,
	})


# --- Pickups ---------------------------------------------------------------------------

func _update_pickups(delta: float) -> void:
	powerup_timer -= delta
	if powerup_timer <= 0.0:
		powerup_timer = GameData.powerup_interval() * randf_range(0.8, 1.2)
		if _count_pickups(false) < MAX_POWERUPS:
			_spawn_powerup(Pickup.random_powerup_kind(), arena.random_open_point(4.0, car.global_position, 20.0))
	if _count_pickups(true) < TARGET_COINS - 8:
		_spawn_coin_line()

	var radius := MAGNET_POWERUP_RADIUS if magnet_time > 0.0 else GameData.magnet_radius()
	for p in pickups_root.get_children():
		var pk := p as Pickup
		if pk == null or not pk.is_coin() or pk.is_queued_for_deletion():
			continue
		var d := car.global_position - pk.global_position
		d.y = 0.0
		var dist := d.length()
		if dist < radius and dist > 0.01:
			pk.global_position += d / dist * minf(dist, 35.0 * delta)


func _count_pickups(coins_only: bool) -> int:
	var n := 0
	for p in pickups_root.get_children():
		var pk := p as Pickup
		if pk and not pk.is_queued_for_deletion() and pk.is_coin() == coins_only:
			n += 1
	return n


func _spawn_coin_line() -> void:
	var start := arena.random_open_point(4.0, car.global_position, 15.0)
	var ang := randf() * TAU
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	for i in 6:
		var p := start + dir * i * 3.5
		if arena.is_open(p, 2.0):
			_spawn_pickup(Pickup.Kind.COIN, p)


func _spawn_powerup(kind: Pickup.Kind, pos: Vector3) -> void:
	_spawn_pickup(kind, pos)


func _spawn_pickup(kind: Pickup.Kind, pos: Vector3) -> void:
	var p := Pickup.new()
	p.setup(kind)
	p.position = pos
	pickups_root.add_child(p)
	p.collected.connect(_on_pickup_collected)


func _clear_pickups() -> void:
	for p in pickups_root.get_children():
		p.queue_free()


func _on_pickup_collected(p: Pickup) -> void:
	if state != State.PLAYING:
		return
	var dur := GameData.powerup_duration_mult()
	match p.kind:
		Pickup.Kind.COIN:
			coins += 1
			Sfx.play("coin", randf_range(0.95, 1.1), -4.0)
			return
		Pickup.Kind.NITRO:
			car.boost = car.boost_capacity
		Pickup.Kind.DOUBLE:
			double_time = 10.0 * dur
		Pickup.Kind.TIME:
			time_left += 6.0
		Pickup.Kind.MAGNET:
			magnet_time = 10.0 * dur
		Pickup.Kind.SHIELD:
			shield = true
			car.set_shield_visible(true)
	_test["pickups"].append(p.display_name())
	ui.popup(p.display_name() + "!", p.color(), 34)
	Sfx.play("pickup")


func _on_cone_hit(_cone: Cone) -> void:
	if state != State.PLAYING:
		return
	cones_hit += 1
	Sfx.play("cone", randf_range(0.9, 1.2))
	if chain_active:
		chain_points += CONE_POINTS
	else:
		score += CONE_POINTS * (2 if double_time > 0.0 else 1)
	ui.popup("CONE +%d" % CONE_POINTS, Color(1.0, 0.55, 0.1), 22)


func _on_car_crashed(impact: float) -> void:
	cam.add_shake(clampf(impact / 20.0, 0.3, 1.0))
	if state != State.PLAYING:
		return
	_test["crashes"] += 1
	Sfx.play("crash", randf_range(0.9, 1.1), linear_to_db(clampf(impact / 25.0, 0.3, 1.0)))
	if not chain_active:
		return
	if shield:
		shield = false
		car.set_shield_visible(false)
		ui.popup("SHIELD SAVED YOUR COMBO!", GameUI.CYAN, 30)
		Sfx.play("shield")
	else:
		chain_active = false
		chain_points = 0.0
		multiplier = 1
		ui.popup("WIPEOUT!  combo lost", Color(1.0, 0.25, 0.25), 36)
		Sfx.play("wipeout")


# --- Smoke test autopilot ------------------------------------------------------------------

func _drive_bot(delta: float) -> void:
	if state != State.PLAYING:
		return
	_test_time += delta
	_test["max_speed"] = maxf(_test["max_speed"], car.speed)
	if car.is_drifting:
		_test["drift_time"] += delta
	Input.action_press("accelerate")
	# Accelerate, then hold a left turn with periodic handbrake flicks.
	if _test_time > 1.5:
		Input.action_press("steer_left")
	var phase := fmod(_test_time, 3.0)
	if _test_time > 1.5 and phase < 0.35:
		Input.action_press("handbrake")
	else:
		Input.action_release("handbrake")
	if _test_time > 6.0 and _test_time < 8.0:
		Input.action_press("boost")
	else:
		Input.action_release("boost")
	# Drop each power-up type in the car's path once.
	var drops := [Pickup.Kind.NITRO, Pickup.Kind.DOUBLE, Pickup.Kind.TIME, Pickup.Kind.MAGNET, Pickup.Kind.SHIELD]
	var slot := int(_test_time)
	if slot >= 2 and slot - 2 < drops.size() and fmod(_test_time, 1.0) < delta:
		_spawn_powerup(drops[slot - 2], car.global_position + car.velocity * 0.15)
	for shot in [4.0, 7.0, 11.0]:
		if _test_time >= shot and not _captured.has(shot):
			_captured[shot] = true
			await _capture("run_%d" % int(shot))
	if _test_time > 14.0:
		time_left = 0.0


func _capture(shot_name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_capture_dir.path_join(shot_name + ".png"))


func _finish_smoke_test(cash_earned: int) -> void:
	for a in ["accelerate", "steer_left", "handbrake", "boost"]:
		Input.action_release(a)
	print("[smoke] max speed: %.1f m/s, drift time: %.1f s, banked chains: %d, crashes: %d" % [
		_test["max_speed"], _test["drift_time"], _test["banked"], _test["crashes"]])
	print("[smoke] score: %d, coins: %d, cones: %d, cash earned: %d" % [score, coins, cones_hit, cash_earned])
	print("[smoke] power-ups collected: %s" % [_test["pickups"]])
	var before := GameData.top_speed()
	GameData.add_cash(100000)
	var bought := GameData.buy("engine")
	print("[smoke] bought engine: %s, top speed %.1f -> %.1f, level %d" % [bought, before, GameData.top_speed(), GameData.level("engine")])
	await _capture("results")
	open_garage()
	await get_tree().process_frame
	await _capture("garage")
	show_menu()
	await get_tree().create_timer(0.5).timeout
	await _capture("menu")
	var ok: bool = _test["drift_time"] > 1.0 and _test["banked"] > 0 and bought and _test["pickups"].size() >= 3
	print("[smoke] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
