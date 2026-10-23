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
| Camera | Drag on the right, pinch to zoom | Click to capture, mouse, wheel | Right stick, LB/RB |
| Emotes | Smiley button | 1 dance, 2 cheer, 3 sit, 4 nod | D-pad |

F3 shows a debug readout, F11 toggles fullscreen.

## Project layout

- `player/`: the Keling (controller, animation graph, procedural layer: breathing, lean, foot IK, spring bones)
- `camera/`: third-person orbit camera
- `ui/`: HUD and touch controls
- `scenes/`: test grounds
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
