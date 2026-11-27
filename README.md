# Rustfall: Colony Cleanup

A relaxed first-person cleaning game on an endless Martian plain, with a built-in benchmark for
comparing the same hardware under **Linux and Windows** (and native vs **AMD FSR 1 / FSR 2**).

Built with Godot 4.7.2 (Forward+, Vulkan on both OSes). Art: [Kenney](https://kenney.nl) (CC0).

---

## The game

The Great Storm buried Rustfall Base under a thick crust of iron-oxide dust. Off-world, that rust
sells for rupees. You are the last contractor on the payroll, with a scrub brush and a 25 kg tank.

- **Clean** rust off the ground. The layer is ~14 cm thick and cleared ground drops to bare brown rock.
- **Export** rust at the depot for ₹ (the market price drifts between about ₹19 and ₹32/kg).
- **Hexagons:** the whole plain is a hex grid. Every hexagon cleaned to 90% pays a bonus that grows
  with how much rust it held and how hard that rust was (about ₹2,500 near the base, more further
  out). The minimap panel shows the hexagon's crust, progress and bonus; you hear at 50%.
- **Difficulty** per world (chosen when you create it): *Relaxed*, *Standard* or *Hard* changes
  prices, upgrade costs, wear, battery drain, mastery speed, the hauler's fee and how close to the
  base the crust starts.
- **Crust:** the rust gets harder further from the base (Crust I–IV at 140 / 320 / 600 m on
  Standard, darker on the ground). A tool below the needed tier cleans at 25% per missing tier, so
  you have to upgrade to push outward. The Sweeper handles up to Crust III, drones Crust II.
- **Progression, on foot first:** each tool earns **mastery stars** (★1–★5) from the rust it
  cleans (+5% speed each); power / width / reach upgrades can't go above your stars, and width adds
  only 6% radius per level. Better tools and tanks unlock with **contractor rank**; the **Sweeper**
  needs rank *Grit Grinder* **and 25 hexagons cleared by hand**, the Charger cart *Plain Sweeper*,
  drones *Hex Hunter*. Locked items show what they still need.
- **Handcart:** push it (E) to where you work, tip your tank in (Q), push it back and export it
  with your tank at the depot. Away from the cart, **Q drops your tank as a rust sack**; the hauler
  collects sacks every 2 minutes for a fee (10 / 25 / 40% by difficulty).
- **Rust sacks keep every kilogram.** In the Sweeper, Q away from the depot bags the hopper into a
  sack behind you. Get it back by driving over it with the brush on, or on foot with **E** (into
  your tank, or into the handcart when it is beside you), then sell it at the depot at full price.
  Vehicles export from up to 13 m from the depot and drive on and off the base pad from any side.
- **Unloading takes time:** exporting, tipping into the handcart, filling or emptying a sack and
  emptying the Sweeper's hopper each take a few seconds (more rust, longer) with a progress bar in
  the prompt. Walking off or driving away cancels it and keeps the rust where it was. The Sweeper
  lifts a sack at 150 kg/s, so park over it (or crawl across it) until it is gone.
- **Sleep:** the bunk in the garage (between the two bays) lets you sleep from 17:15 to 05:15 for
  ₹500 a night (more on Hard, less on Relaxed). You wake at 06:30 the next sol; vehicles plugged in
  at the posts charge from the base battery overnight, and the hauler still calls.
- **Base terminal** has tabs: Tools, Gear, Power, Vehicles, Workshop, Drones, Paint.
- **Power:** solar panels (bought, none at start) charge the base battery during the day. You
  place them yourself: **P** shows a preview where you aim (green = OK, red says why not), **R**
  rotates, left-click places, **E** on a placed panel picks it up again. Within 60 m of the base.
  Vehicles charge **only in the garage**: park in a bay, walk to the charging post and press **E**
  to plug the cable in (E again to unplug). A plugged-in vehicle will not drive.
- **Vehicles** (bought, none at start) roll on Mars-rover style wheels (open aluminium drums,
  chevron grousers, curved spokes, rocker-bogie legs with per-wheel suspension):
  the *Sweeper* (roller brush + 900 kg hopper) and the *Charger cart*, a mobile battery whose
  cable you connect to a stranded Sweeper by hand. Top speed is 25 km/h (Sweeper) and 31 km/h
  (cart); the **mouse wheel** sets a speed limit from 20% to 100% (60% in a new world, saved per
  world). Slower driving uses less battery per km (power grows with the square of speed and the
  brush works on the ground it covers), so the HUD range grows as you scroll down. Shift boosts
  past the limit at a much higher cost per km.
- **Sweeper upgrades** (Vehicles tab): a **wider brush head** (4.6 → 5.6 → 6.8 → 8.2 m; the roller
  grows and draws power in proportion), a **bigger hopper** (900 → 1,400 → 2,000 → 3,000 kg) and a
  bigger battery pack.
- **Leave a vehicle anywhere:** step out and it sets its parking brake and stays put, however far
  you walk away. (Vehicles used to fall through the ground once you were out of range; one found
  under the ground in an older save is lifted back on top.)
- **Wear and tear:** tyres wear with distance (3x faster when boosting), the brush with sweeping,
  the motor with throttle, boost and crashes. Worn parts cost grip, speed, cleaning power and
  battery; a failed motor stops the vehicle. Grime builds up and a dying motor smokes. Repair parts
  in the **Workshop** (base terminal) with the vehicle parked in its garage bay, or tow it there.
- **Drones** work on their own inside a hexagon zone around the base (upgradeable 1–4 rings).
- **Worlds** (like Minecraft): keep as many separate colonies as you like. *Worlds* on the title
  screen lists them with sol, balance, hexes, play time and seed; Play, Rename or Delete (asks to
  confirm). *Create new world* takes a name and an optional seed: blank is random, a number is used
  as-is, any word works too. Each world has its own terrain and its own save under
  `user://worlds/<id>/`; *Continue* opens the last one played. A save from an older version moves
  into a world called "My colony" automatically.
- **Tracks:** tyres press twin tracks into the rust (with berms); boots leave footprints.
- **Buildings** collide with their real shapes. **Space** facing a ledge up to 2.5 m pulls you up
  (works mid-jump too); ladders on the garage and hangars reach the roofs. **L** is your torch.
- **Supply pods** (PUBG-style airdrops) land somewhere on the plain every few minutes with a light
  beacon. Open them for ₹, **repair kits** (G at a vehicle: +50% to its worst part) and **battery
  cells** (B at a vehicle: +10 kWh). **T** drops a waypoint beacon where you look.
- **Contractor ranks** (CS-style), from Rust Rookie to Legend of Rustfall, each adding +3% to the
  export price; an **end-of-sol report** card (rust, ₹, hexes, relics, MVP); vehicle **paint jobs**.
- **Missions** (20) guide the early game; **relics** (12) turn up under the rust; a 16-minute
  day/night cycle; the plain never ends.

### Controls

| On foot | | Driving | |
|---|---|---|---|
| WASD | move | W/S | throttle / brake & reverse |
| Shift | sprint | A/D | steer |
| Space | jump; at a ledge, climb up | Shift | boost (faster, much more power per km) |
| LMB or F | clean | Space | handbrake |
| E | interact (depot, terminal, vehicles, sacks, bunk) | R | brush / charge cable on-off |
| M | big map | Q | empty hopper (export at depot, bag into a sack elsewhere) |
| H | hexagon grid on/off | E | exit vehicle |
| T | waypoint (T on it again removes it) | mouse | free look (recentres by itself) |
| Q | tip tank into handcart, or drop a sack | L | headlights on/off |
| P / R | place solar panel / rotate it | wheel | speed limit (20–100%) |
| L | torch | | |
| G / B | use repair kit / battery cell at a vehicle | V | chase / hood camera |
| F3 | FPS counter | F1 | key guide (full keyboard map) |
| Esc | pause menu (settings, mission log) | F11 / Alt+Enter | fullscreen on/off |

---

## Building

Requires Godot **4.7.2** with export templates (Linux + Windows).

```bash
./build.sh            # -> build/linux/Rustfall.x86_64, build/windows/Rustfall.exe
```

`build/` sits on the shared drive, so the same folder is usable from both operating systems:
run `build/linux/Rustfall.x86_64` on Linux and `build\windows\Rustfall.exe` on Windows.
Benchmark results from both go to `build/benchmark_results/`.

---

## Benchmark

From the main menu (**Run benchmark** + preset), or from the command line:

```bash
# Linux
./Rustfall.x86_64 --run-benchmark --bench-preset=high --bench-autoquit
# Windows (console build prints the summary)
Rustfall.console.exe --run-benchmark --bench-preset=high --bench-autoquit
```

| Flag | Meaning |
|---|---|
| `--run-benchmark` | start the benchmark immediately |
| `--bench-preset=low\|medium\|high\|ultra` | quality preset (default `high`) |
| `--bench-upscaler=off\|fsr1\|fsr2` | AMD FSR 1.0 (spatial) or FSR 2.2 (temporal) |
| `--bench-scale=0.67` | render scale (FSR modes: 0.77 Ultra Quality, 0.67 Quality, 0.59 Balanced, 0.5 Performance) |
| `--bench-windowed=1920x1080` | windowed at a fixed size (default: borderless fullscreen at native resolution) |
| `--bench-exclusive` | exclusive fullscreen instead of borderless (e.g. to compare Windows flip models) |
| `--bench-out=DIR` | output folder (default `build/benchmark_results`) |
| `--bench-screenshots` | save one screenshot per stage (adds a small hitch; off by default) |
| `--bench-autoquit` | exit when done |
| `--display-driver wayland` | (Linux, Godot flag) native Wayland instead of X11/XWayland |

### What it runs

5 s shader warm-up (every effect is shown once so pipelines compile before measuring), then five
20-second scripted stages. The world is generated from a fixed seed and fully built before
measuring (no streaming), so both OSes render exactly the same frames:

1. **Colony Flyover**: base buildings, shadows, lights, terrain to the horizon.
2. **Surface Sweep**: ground-level camera continuously removing rust (CPU painting, texture
   uploads, parallax rust layer, particles).
3. **Drone Swarm**: 48 autonomous drones cleaning (script load, particles, lights).
4. **Sweeper Run**: the Sweeper at speed with the Charger cart alongside, chase camera.
5. **Dust Storm**: max load with volumetric fog, a dense dust storm and 16 extra shadowed lights.

VSync is forced off and the frame cap removed, so the numbers show the real load.

### Output (per run folder)

- `frames.csv`: one row per frame: frame time, FPS, GPU time, CPU render time, physics time,
  draw calls, primitives, objects, VRAM.
- `summary.json` / `summary.txt`: per stage and overall: average FPS, 1% and 0.1% lows,
  p50/p90/p95/p99/p99.9 frame times, frame-time SD and CV, **frame pacing** (average and p95/p99
  frame-to-frame change, % of frames changing by >2 ms / >4 ms), stutters (frames >2× the recent
  average and >4 ms above it), hitches >50 ms, GPU/CPU averages, plus full system info (OS,
  distribution, CPU, GPU, driver, Vulkan version, display server, resolution, internal resolution,
  upscaler, refresh rate).

### Comparing Linux vs Windows (and FSR)

Run the suite on each OS (3 runs each of native, FSR 1 Quality, FSR 2 Quality):

```bash
build/linux/run_benchmarks.sh            # Linux   (PRESET=medium RUNS=5 ... to change)
build\windows\run_benchmarks.bat         # Windows (run_benchmarks.bat medium 5)
```

Then build one report from everything in `build/benchmark_results/`:

```bash
python3 build/compare_benchmarks.py build/benchmark_results --baseline "Linux · high · OFF"
```

It writes `comparison.html`: overall and per-stage tables with deltas vs the baseline and
± across runs, frame time over the run, frame-time percentile curves, and per-stage bars.

**For a fair comparison**
- Same preset, upscaler, scale and native resolution on both OSes; same monitor refresh.
- Laptop plugged in, same power profile (Linux: *performance*; Windows: *Best performance*).
- Close other apps; let the machine cool between suites.
- Treat the very first run after a driver or game update as a warm-up: Godot caches compiled
  pipelines on disk, so later runs have fewer one-off compile hitches.
- On Linux, try both X11 (default) and `DISPLAY_DRIVER=wayland`: the display path differs.

### FSR availability on this machine (Radeon 860M)

| | Linux | Windows |
|---|---|---|
| In-game FSR 1.0 / FSR 2.2 | ✔ Vulkan compute (RADV, `shaderFloat16` supported) | ✔ Vulkan compute (AMD driver) |
| Driver/compositor-level FSR 1 | `gamescope -F fsr -w 1280 -h 800 -W 1920 -H 1200 -f -- ./Rustfall.x86_64 ...` | AMD Adrenalin **Radeon Super Resolution** (RSR), exclusive fullscreen |

The in-game FSR passes are the same shader code on both OSes, so differences you see come from the
driver and OS, not from the upscaler. Gamescope/RSR are a second, driver-side comparison (set the
game's own upscaler to `off` and its scale to `1.0` when using them).

---

## Narrator

The opening story is narrated. If `assets/voice/story_N.ogg` exist they are used (identical on both
OSes); otherwise the OS speech engine speaks the text (Speech Dispatcher on Linux, SAPI on Windows).
To record the narration with Piper (offline neural TTS), see `tools/make_narration.sh`.

## Graphics presets

| | Low | Medium (auto on iGPU) | High (auto on dGPU) | Ultra |
|---|---|---|---|---|
| Render scale | 60% FSR 1 | 85% FSR 1 | 100% | 100% |
| AA | FXAA | MSAA 2× | MSAA 2× | MSAA 4× |
| Shadows | 1k, 1 split | 2k, 2 splits | 4k, 4 splits | 4k, 4 splits, softer |
| Rust parallax steps | off | 6 | 10 | 16 |
| SSAO / SSIL / volumetric fog | – | – | SSAO | all |
| View distance | 170 m | 260 m | 340 m | 400 m |

## Project layout

```
scenes/main.tscn        entry scene (scripts/boot.gd)
scripts/
  boot.gd               menu / story / game / benchmark switching, command line
  config.gd             settings, quality presets, FSR, input map (autoload "Config")
  world.gd              base, power grid, cleaning, hexagons, drones zone, interactions, shop logic
  terrain.gd            endless streamed terrain (worker threads, 2 LODs with skirts)
  rust_field.gd         per-chunk rust layer, painting, hex grid maths and statistics
  game_state.gd         economy (₹), progression, save/load
  missions.gd           mission chain
  player.gd vehicle.gd drone.gd dust_fx.gd
  hud.gd hex_map.gd settings_panel.gd main_menu.gd story.gd ui_kit.gd
  benchmark.gd          scripted benchmark, statistics, CSV/JSON/TXT output
shaders/terrain.gdshader  rust layer (parallax occlusion), rock, hexagon overlay
tools/                  compare_benchmarks.py, run_benchmarks.sh/.bat, make_narration.sh
```

## Credits

- 3D models, sounds and particle textures: **Kenney** (www.kenney.nl), CC0 1.0. See `assets/LICENSE-*.txt`.
- Engine: Godot Engine (MIT).
