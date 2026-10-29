# Drift Arcade

A neon 3D arcade drift game made with Godot 4. Chain drifts into huge combos,
grab power-ups, smash cones, and spend your cash on upgrades in the garage.

## Running

1. Install [Godot 4.3](https://godotengine.org/download) or newer (the standard build; you don't need .NET).
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** to play.

## Playing in the browser

The game is exported for the web and deployed to GitHub Pages by
`.github/workflows/deploy-web.yml`. The workflow runs on every push to `main`,
and you can also start it by hand from the repo's **Actions** tab.

One-time setup: in the repo's **Settings → Pages**, set **Source** to **GitHub Actions**.
GitHub Pages needs either a public repo or a paid GitHub plan.

To build the web version yourself, install the Godot 4.3 export templates
(Editor → Manage Export Templates), then run **Project → Export → Web**, or:

```bash
godot --headless --export-release "Web" build/web/index.html
```

Serve `build/web/` over HTTP to play it. Opening `index.html` directly from disk won't work.

## How to play

Each run is a timed session in the arena (60 seconds, more with upgrades).

- **Drift** to build up points. Kick the car sideways with the handbrake, or steer hard at speed.
- **Chain** drifts: start a new drift before the combo bar runs out and the multiplier goes up (up to x10).
  Holding one drift for 3 seconds also raises it. When a chain ends, its points times the multiplier are added to your score.
- **Don't hit walls mid-combo.** A hard crash is a WIPEOUT and the chain's points are lost.
- **Drifting fills your nitro.** Burn it with SHIFT.
- **Coins** and **score** turn into cash at the end of the run.

### Power-ups

| Pickup | Effect |
|---|---|
| **N** Nitro | Fills the nitro tank |
| **2X** Score | Double points for 10 seconds |
| **+T** Time | +6 seconds on the clock |
| **M** Magnet | Pulls in nearby coins for 10 seconds |
| **S** Shield | Saves your combo from one crash |

### Garage upgrades (5 levels each)

Engine, Tires, Nitro Tank, Combo Timer, Extra Time, Coin Magnet, Lucky Charm.
Progress is saved automatically.

### Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Throttle / brake | W / S or Up / Down | RT / LT |
| Steer | A / D or Left / Right | Left stick or D-pad |
| Handbrake | Space | A |
| Nitro | Shift | X or RB |
| Pause | Esc / P | Start |
| Fullscreen | F11 | |

## Development

Everything is generated in code (no asset files). See `CLAUDE.md` for the
code layout. To run the headless smoke test:

```bash
godot --headless --path . --import
godot --headless --path . -- --smoke-test
```
