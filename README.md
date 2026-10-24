# Weed World

A cozy third-person forest adventure for 1–4 players. You play a **Keling**, a little forest creature, exploring a magical forest with friends to find new strains, then rolling and smoking together at beautiful viewpoints.

Built with **Godot 4.7** (GDScript, Mobile renderer). Android first, with a Windows build in every release.

## Download

Every merge to `main` publishes a [release](../../releases/latest) with:
- `WeedWorld-<version>.apk`: Android (arm64). Allow installs from unknown sources, then open the APK.
- `WeedWorld-<version>-windows.zip`: Windows 10/11 (x86_64). Unzip and run `WeedWorld.exe`.

## Controls

| | Phone | Keyboard + mouse | Gamepad |
|---|---|---|---|
| Move | Left joystick (push gently to walk) | WASD (C toggles walk) | Left stick |
| Sprint | Push past the ring, or the sprint button | Shift | B / L3 / LT |
| Jump | Jump button (hold for higher) | Space | A |
| Grab | Hand button | E or F | X |
| Camera | Drag on the right, pinch to zoom | Click to capture, mouse, wheel | Right stick, LB/RB |
| Emotes | Smiley button | 1 dance, 2 cheer, 3 sit, 4 nod | D-pad |
| World map | Tap the minimap | M (or click the minimap) | Y |
| On the map | Drag, pinch, tap to set a waypoint | Drag, wheel, click to set a waypoint, E finds you | Left stick, LB/RB, A marks, X finds you, B closes |

The top-left corner shows FPS and triangles drawn. Tap it, or press 0 (Back on a gamepad), for the debug readout. F11 toggles fullscreen, H shows the control hints again.

## Project layout

- `player/`: the Keling (controller, animation graph, procedural layer: breathing, lean, foot IK, spring bones; procedural grab with arm IK and finger curls)
- `camera/`: third-person orbit camera
- `ui/`: HUD (shared look in `hud_theme.gd`, Fredoka and Nunito fonts under OFL), touch controls, place-name banners
- `ui/map/`: the world map. `map_baker.gd` paints it once at load from the forest's own terrain fields and tree list (storybook shader + brushed crowns), `minimap.gd` and `world_map.gd` share it through `map_state.gd`; named places live in `map_landmarks.gd`
- `ui/loading/`: the loading screen and main scene (threaded load, forest grown on a worker thread, shader warm-up)
- `branding/`: app icons and the boot splash, made by `tools/icon_compose.py` and `tools/splash_compose.py` from renders of the real Keling and forest
- `world/forest/`: the Whispering Glade, a 100 × 100 m magical forest grown at load time from a fixed seed (terrain, procedural trees, scatter, water, golden-hour lighting, magic FX). `forest_level.tscn` is the main scene; `forest.tscn` runs standalone with a fly camera.
- `assets/nature/`: Quaternius Stylized Nature MegaKit (CC0), re-dressed in the forest's own shaders
- `assets/audio/forest/`: the forest soundscape, synthesised from scratch by `tools/synth_forest_audio.py` (original, no third-party audio)
- `scenes/`: test grounds and the pickable herb
- `assets/characters/keling/`: rigged model and retargeted animation library
- `tools/`: offline pipeline (rigging, animation retargeting) and headless tests
- `art_source/`: source assets for the tools (ignored by Godot)

### Regenerating the character

```sh
python3 tools/rig_keling.py art_source/keling_meshy_source.glb assets/characters/keling/keling.glb
python3 tools/slim_ual.py <UAL1.glb> <UAL2.glb> <UAL1_RM.glb> <UAL2_RM.glb> art_source/ual_keling_clips.glb
godot --headless --path . -s res://tools/retarget_animations.gd
```

### Headless checks

```sh
godot --headless --path . -s res://tools/smoke_test.gd      # scripted run through every move
godot --headless --path . -s res://tools/foot_slip_test.gd  # planted-foot sliding per gait
godot --headless --path . -s res://tools/grab_test.gd       # grab reach: hand-to-herb distance at grip
godot --headless --path . -s res://tools/forest_check.gd    # grow the forest, walk the Keling across it
godot --headless --path . -s res://tools/loading_check.gd   # boot through the loading screen into the forest
# HUD / map screenshots (needs a GPU or xvfb + GL; looks only)
xvfb-run godot --path . --rendering-method gl_compatibility -s res://tools/map_preview.gd -- /tmp/map_preview
```

### Regenerating the icon and splash

```sh
xvfb-run godot --path . --rendering-driver vulkan --resolution 1024x1024 -s res://tools/render_icon_portrait.gd -- art_source/keling_portrait.png Surprise 0.4 20
xvfb-run godot --path . --rendering-driver vulkan --resolution 1920x864 -s res://tools/render_key_art.gd -- art_source/key_art.png
python3 tools/icon_compose.py && python3 tools/splash_compose.py   # needs Pillow and numpy
```

### Regenerating the forest sounds

```sh
python3 tools/synth_forest_audio.py   # needs numpy, scipy and ffmpeg with libvorbis
```

## Releases and signing

`.github/workflows/release.yml` exports the APK and the Windows build on every push to `main` and publishes a GitHub release with the newest patch notes.

The APK is signed with a release keystore. For a permanent key (so updates always install over the previous version), add these repository secrets:
- `ANDROID_KEYSTORE_BASE64`: `base64 -w0 release.keystore`
- `ANDROID_KEYSTORE_ALIAS`
- `ANDROID_KEYSTORE_PASSWORD`

Without them, CI generates a keystore and keeps it in the Actions cache.

## Credits

- Keling model: generated with [Meshy](https://www.meshy.ai), rigged in this repo.
- Animations: [Universal Animation Library](https://quaternius.com) 1 and 2 by **Quaternius**, CC0. Retargeted to the Keling by `tools/retarget_animations.gd`.
