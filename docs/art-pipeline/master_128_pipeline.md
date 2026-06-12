# master_128 Pipeline

`pet-runtime/assets/master_128/` contains the committed 128x128 high-resolution source exports for Teti Track. These files are the upstream master inputs for later 64x64 production sprites and smaller 48x48/32x32 runtime or test variants.

## Output Groups

```text
pet-runtime/assets/master_128/
  body/
  faces/
  motion/
  hats/
  previews/
  sheets/
```

## Required PNG Output

Body:

```text
body/teti_track_front_neutral_128.png
body/teti_track_side_128.png
```

Faces:

```text
faces/face_neutral_128.png
faces/face_blink_128.png
faces/face_sleepy_128.png
faces/face_focused_128.png
faces/face_warning_128.png
faces/face_collapsed_128.png
```

Motion:

```text
motion/idle_1_128.png
motion/idle_2_128.png
motion/move_left_1_128.png
motion/move_right_1_128.png
```

Hats:

```text
hats/hat_none_128.png
hats/hat_beanie_128.png
hats/hat_engineer_128.png
hats/hat_antenna_128.png
hats/hat_warning_light_128.png
hats/hat_sprout_128.png
```

Previews and sheets:

```text
previews/teti_track_master_preview_128.png
previews/teti_track_faces_preview_128.png
previews/teti_track_motion_preview_128.png
previews/teti_track_hats_preview_128.png
sheets/teti_track_master_sheet_128.png
sheets/teti_track_master_sheet_128.md
```

The motion preview is a 3-column visual overview: idle, move left, and move right. The full runtime sheet still includes both `idle_1_128` and `idle_2_128`.

`teti_track_master_preview_128.png` is preserved by default because the current committed image includes curated PARTS layout that is not present as separate layers in the flattened Aseprite sources. The build script generates a fallback overview only when the file is missing or when `REBUILD_MASTER_PREVIEW=1` is set.

## Frame Mapping

| source | frame | output |
|---|---:|---|
| `teti_track_master_front_128.aseprite` | 0 | `body/teti_track_front_neutral_128.png` |
| `teti_track_master_side_128.aseprite` | 0 | `body/teti_track_side_128.png` |
| `teti_track_faces_128.aseprite` | 0 | `faces/face_neutral_128.png` |
| `teti_track_faces_128.aseprite` | 1 | `faces/face_blink_128.png` |
| `teti_track_faces_128.aseprite` | 2 | `faces/face_sleepy_128.png` |
| `teti_track_faces_128.aseprite` | 3 | `faces/face_focused_128.png` |
| `teti_track_faces_128.aseprite` | 4 | `faces/face_warning_128.png` |
| `teti_track_faces_128.aseprite` | 5 | `faces/face_collapsed_128.png` |
| `teti_track_motion_128.aseprite` | 0 | `motion/idle_1_128.png` |
| `teti_track_motion_128.aseprite` | 1 | `motion/idle_2_128.png` |
| `teti_track_motion_128.aseprite` | 2 | `motion/move_left_1_128.png` |
| `teti_track_motion_128.aseprite` | 3 | `motion/move_right_1_128.png` |
| `teti_track_hats_128.aseprite` | 0 | `hats/hat_none_128.png` |
| `teti_track_hats_128.aseprite` | 1 | `hats/hat_beanie_128.png` |
| `teti_track_hats_128.aseprite` | 2 | `hats/hat_engineer_128.png` |
| `teti_track_hats_128.aseprite` | 3 | `hats/hat_antenna_128.png` |
| `teti_track_hats_128.aseprite` | 4 | `hats/hat_warning_light_128.png` |
| `teti_track_hats_128.aseprite` | 5 | `hats/hat_sprout_128.png` |

## Current Production Readiness

The body, face, motion, and hat groups are sufficient as 128x128 upstream masters for the first 64x64 production pass. They establish shape language, state naming, and sheet coordinates.

Still worth manual review before locking the final 64x64 runtime set:

- `idle_1_128` and `idle_2_128` are visually identical today unless the idle wobble is refined later.
- Motion smear and wheel/contact shadows may need tuning after the pet host renders movement in context.
- Hat alignment should be checked again after the final downscale rules are chosen.
- Face readability should be checked at 64x64, 48x48, and 32x32.
