# Aseprite Workflow

This is the Teti Track 128x128 high-resolution master production chain. The downstream runtime and test assets will be derived later as 64x64, 48x48, and 32x32 variants.

## Source Projects

The `.aseprite` files live under `art/aseprite/`:

| file | role |
|---|---|
| `master/teti_track_master_front_128.aseprite` | Front neutral body master. Exports `body/teti_track_front_neutral_128.png`. |
| `master/teti_track_master_side_128.aseprite` | Side body master. Exports `body/teti_track_side_128.png`. |
| `faces/teti_track_faces_128.aseprite` | Six face states in frame order: neutral, blink, sleepy, focused, warning, collapsed. |
| `motion/teti_track_motion_128.aseprite` | Four motion frames: idle 1, idle 2, move left 1, move right 1. |
| `hats/teti_track_hats_128.aseprite` | Six hats in frame order: none, beanie, engineer, antenna, warning light, sprout. |

## Script Boundary

`tools/asset-build/build_master_128.sh` is the production entrypoint. It uses Aseprite CLI `--frame-range n,n --save-as` because the runtime names are an explicit contract and the current source files have stable frame order.

The Lua helpers in `art/aseprite/scripts/` are for source inspection and ad hoc tag/sheet exports:

| script | role |
|---|---|
| `export_tags.lua` | Export a tagged sheet from the active sprite. |
| `preview_sheet.lua` | Export a quick sheet for visual inspection. |
| `sheet_manifest.lua` | Write a markdown manifest of frame order and tags. |

The Python helper `tools/asset-build/build_master_128.py` composes previews, the 6x3 runtime sheet, and the markdown sheet manifest. It uses only the Python standard library.

`previews/teti_track_master_preview_128.png` is a curated editorial overview. It includes a PARTS section that is not recoverable from the current flattened master `.aseprite` files. The normal rebuild preserves this committed file when it already exists. If building into an empty output directory, the Python helper creates a same-size fallback overview so the output set is still complete. Set `REBUILD_MASTER_PREVIEW=1` to replace it with the generated fallback.

## Standard Rebuild

```bash
make assets-master-128
```

Equivalent direct command:

```bash
./tools/asset-build/build_master_128.sh
```

To test into a temporary output directory:

```bash
MASTER_128_OUT_DIR=/tmp/tetibot-master-128 ./tools/asset-build/build_master_128.sh
```

To intentionally regenerate the fallback master preview:

```bash
REBUILD_MASTER_PREVIEW=1 ./tools/asset-build/build_master_128.sh
```
