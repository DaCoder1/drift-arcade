# CLAUDE.md

## Workflow rules (from the project owner)

- **All work goes on the `dev` branch.** Do not merge, push, or commit to `main`
  until the owner explicitly says to merge `dev` into `main`.
- **If you are unsure about anything, ask the owner** instead of guessing or
  picking something arbitrary.

## Project

Drift Arcade: a 3D arcade drift game made with **Godot 4.3** (GDScript, Forward+).
Everything (meshes, materials, UI, sound) is generated in code, so there are no
art or audio assets.

- `scenes/main.tscn`: the only scene. Its root runs `scripts/main.gd`.
- `scripts/main.gd`: game flow (menu, countdown, run, results, garage), scoring,
  pickups, power-up effects, and the smoke-test autopilot.
- `scripts/car.gd` (`DriftCar`): arcade drift physics, the car model, and effects.
- `scripts/arena.gd` (`Arena`): floor shader, walls, obstacles, cones, environment.
- `scripts/game_ui.gd` (`GameUI`): HUD, menu, garage, results, pause.
- `scripts/game_data.gd` (autoload `GameData`): save data, upgrade costs and
  stats, input map.
- `scripts/sfx.gd` (autoload `Sfx`): procedurally generated sound effects and
  the engine sound.
- `scripts/pickup.gd`, `cone.gd`, `skid_marks.gd`, `chase_camera.gd`: game objects.

## Testing

Headless smoke test. An autopilot drives a short run, grabs every power-up,
buys an upgrade, and exits with code 0 on PASS:

```bash
godot --headless --path . --import
godot --headless --path . -- --smoke-test
```

The smoke test uses its own save file (`user://smoke_test_save.cfg`), so it
never touches real progress. To also capture screenshots, run it with a
display and add `--capture=<dir>`. Without a GPU you can use
`xvfb-run ... --rendering-driver opengl3`. In headless mode, the
`mesh_get_surface_count` errors come from the dummy renderer and are harmless.
