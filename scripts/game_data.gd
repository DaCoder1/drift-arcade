extends Node
## Persistent progress (cash, best score, upgrade levels) and derived car stats.
## Also registers the input map so keyboard and gamepad bindings live in one place.

signal cash_changed(amount: int)

var save_path := "user://save.cfg"
const MAX_LEVEL := 5

const UPGRADES := {
	"engine": {"name": "Engine", "desc": "Higher top speed and acceleration", "base_cost": 120},
	"tires": {"name": "Tires", "desc": "Sharper steering and more grip", "base_cost": 100},
	"nitro": {"name": "Nitro Tank", "desc": "Bigger boost tank, drifts refill it faster", "base_cost": 110},
	"combo": {"name": "Combo Timer", "desc": "More time to chain drifts together", "base_cost": 140},
	"clock": {"name": "Extra Time", "desc": "+5 seconds per run", "base_cost": 160},
	"magnet": {"name": "Coin Magnet", "desc": "Pull in coins from further away", "base_cost": 90},
	"luck": {"name": "Lucky Charm", "desc": "Power-ups spawn more often and last longer", "base_cost": 150},
}
const UPGRADE_ORDER := ["engine", "tires", "nitro", "combo", "clock", "magnet", "luck"]

var cash := 0
var best_score := 0
var runs_played := 0
var levels := {}


func _ready() -> void:
	_setup_input()
	for id in UPGRADE_ORDER:
		levels[id] = 0
	load_game()


# --- Upgrades -----------------------------------------------------------------

func level(id: String) -> int:
	return int(levels.get(id, 0))


## Returns the price of the next level, or -1 when the upgrade is maxed.
func cost(id: String) -> int:
	var lv := level(id)
	if lv >= MAX_LEVEL:
		return -1
	var base: int = UPGRADES[id]["base_cost"]
	return int(round(base * pow(lv + 1, 1.7) / 10.0)) * 10


func can_buy(id: String) -> bool:
	var c := cost(id)
	return c > 0 and cash >= c


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	add_cash(-cost(id))
	levels[id] = level(id) + 1
	save_game()
	return true


func add_cash(amount: int) -> void:
	cash = maxi(cash + amount, 0)
	cash_changed.emit(cash)


# --- Derived stats --------------------------------------------------------------

func top_speed() -> float:
	return 30.0 + 3.0 * level("engine")

func acceleration() -> float:
	return 17.0 + 2.5 * level("engine")

func steer_rate() -> float:
	return 2.3 + 0.15 * level("tires")

func grip() -> float:
	return 7.0 + 0.6 * level("tires")

func boost_capacity() -> float:
	return 100.0 + 25.0 * level("nitro")

func boost_fill_rate() -> float:
	return 1.0 + 0.25 * level("nitro")

func combo_grace() -> float:
	return 1.5 + 0.3 * level("combo")

func run_time() -> float:
	return 60.0 + 5.0 * level("clock")

func magnet_radius() -> float:
	return 2.5 + 1.5 * level("magnet")

func powerup_interval() -> float:
	return 7.0 - 0.8 * level("luck")

func powerup_duration_mult() -> float:
	return 1.0 + 0.12 * level("luck")


# --- Save / load ----------------------------------------------------------------

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "cash", cash)
	cfg.set_value("progress", "best_score", best_score)
	cfg.set_value("progress", "runs_played", runs_played)
	for id in UPGRADE_ORDER:
		cfg.set_value("upgrades", id, level(id))
	cfg.save(save_path)


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	cash = int(cfg.get_value("progress", "cash", 0))
	best_score = int(cfg.get_value("progress", "best_score", 0))
	runs_played = int(cfg.get_value("progress", "runs_played", 0))
	for id in UPGRADE_ORDER:
		levels[id] = clampi(int(cfg.get_value("upgrades", id, 0)), 0, MAX_LEVEL)


func reset_progress() -> void:
	cash = 0
	best_score = 0
	runs_played = 0
	for id in UPGRADE_ORDER:
		levels[id] = 0
	save_game()
	cash_changed.emit(cash)


# --- Input ------------------------------------------------------------------------

func _setup_input() -> void:
	_add_action("accelerate", [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_add_action("brake", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_add_action("steer_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_add_action("steer_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_add_action("handbrake", [KEY_SPACE], [JOY_BUTTON_A], [])
	_add_action("boost", [KEY_SHIFT], [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER], [])
	_add_action("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])
	_add_action("toggle_fullscreen", [KEY_F11], [], [])


func _add_action(action: String, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.15)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = b
		InputMap.action_add_event(action, ev)
	for a in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = a[0]
		ev.axis_value = a[1]
		InputMap.action_add_event(action, ev)
