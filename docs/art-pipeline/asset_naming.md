# Asset Naming

The master asset names are intentionally explicit. Runtime code should be able to infer category, state, and size from a file name without consulting the Aseprite source.

## Rules

- Use lowercase snake case.
- End every 128x128 master PNG with `_128.png`.
- Keep source project names prefixed with `teti_track_`.
- Use category folders for runtime output: `body`, `faces`, `motion`, `hats`, `previews`, `sheets`.
- Keep preview and sheet names prefixed with `teti_track_`.

## Body

```text
teti_track_front_neutral_128.png
teti_track_side_128.png
```

Body files include the whole base track pet in a canonical pose.

## Faces

```text
face_<state>_128.png
```

Current states:

```text
neutral
blink
sleepy
focused
warning
collapsed
```

## Motion

```text
idle_<index>_128.png
move_<direction>_<index>_128.png
```

Current motion outputs:

```text
idle_1_128.png
idle_2_128.png
move_left_1_128.png
move_right_1_128.png
```

## Hats

```text
hat_<variant>_128.png
```

Current variants:

```text
none
beanie
engineer
antenna
warning_light
sprout
```

## Sheets

The runtime master sheet is a 6 column by 3 row grid with 128x128 cells:

```text
sheets/teti_track_master_sheet_128.png
sheets/teti_track_master_sheet_128.md
```

The markdown file is the coordinate contract for downstream slicing and resizing.
