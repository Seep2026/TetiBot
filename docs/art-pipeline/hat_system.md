# TetiBot Hat System

The 128x128 hat assets are transparent overlays placed above the current body
and face frames. The single pixel source of truth is:

`art/aseprite/hats/teti_track_hat_master.aseprite`

The master contains the visible `HATS` layer, hidden `HEAD_GUIDE_LAYER`, and one
tagged frame per hat. `hats_manifest.json` only maps stable IDs and labels to
those Aseprite frame numbers; it does not generate pixels.
All 18 production hats set `menu` to `true` and are available through the
right-click hat selector in Aseprite tag order.

## Asset Contract

- Canvas: 128x128 RGBA PNG.
- Anchor: `head_top_center` at `(64, 16)`, two pixels above the head top.
- Allowed opaque bounds: `x=30..98`, `y=8..30`.
- Hat PNGs contain only the overlay; they do not contain body or face pixels.
- `hat_none_128.png` is fully transparent.
- Every hat uses an 8px top-safe area, 1px outline, and at most 2px shadow.
- Legacy masters and temporary Codex PNG references have been removed. The
  production build rejects debug, deprecated, fallback, and Codex paths.

The asset build validates dimensions and opaque bounds. It never trims, crops,
packs, redraws, or repairs hat pixels after Aseprite export.

## Visual Rules

Production hats use this shared six-color family:

- Mint green `#7FE3C2`
- Soft cream `#F6F1E6`
- Warm yellow `#FFD36E`
- Soft coral `#FF8F7A`
- Muted blue `#7FA8FF`
- Outline/shadow `#2B2F3A`

Silhouettes stay rounded and slightly bottom-heavy. Outlines are 1px, highlights
are limited to one pixel row or isolated pixels, and shadows are no deeper than
2px. Accessories use no more than two flat color steps. Sharp spikes are
reserved for the antenna stem; all other tips and corners are softened.

The basic family is intentionally distinct but related: beanie is warm coral
and cream, engineer is warm yellow, antenna combines muted blue with a soft
coral signal tip, warning light uses coral/yellow on a mint base, and sprout
stays mint/cream. All five share the same low attachment zone around the
`head_top_center` anchor and remain readable in the generated 64x64 preview.

## Rebuild

From the repository root:

```bash
make assets-master-128
```

The build regenerates:

- `pet-runtime/assets/master_128/hats/*.png`
- `pet-runtime/assets/master_128/hats/hats_manifest.json`
- `pet-runtime/assets/master_128/previews/teti_track_hats_preview_128.png`
- `pet-runtime/assets/master_128/previews/teti_track_hats_preview_64.png`
- `pet-runtime/assets/master_128/sheets/teti_track_master_sheet_128.*`
- `pet-runtime/lua/sprites.png`
- `pet-runtime/lua/sprites_manifest.lua`
- `pet-runtime/lua/hats_manifest.lua`

Runtime code never owns a duplicate hat list. Add a manifest entry and rebuild
the sheet to make the new ID available to `Pet.set_hat(pet, hat_id)`.

Each rebuild invalidates previous production hat outputs and runtime atlas
metadata before exporting all 18 Aseprite frames. The generated Lua registry
records SHA-256 values for the master, manifest, and atlas plus every source
tag, production PNG path, and atlas sprite index. `hat_registry.lua` validates
this metadata at startup and refuses stale or fallback bindings.

## Runtime

`pet.hatState` contains `currentHat`, `unlockedHats`, and `isChanging`.
Selecting a hat only changes `currentHat`; movement and expression state remain
untouched. Hat rendering inherits the same body pose offset used by the face,
while the native pet window supplies the shared world transform for wander and
drag. Render order is body, face, hat, then future effects.

Right-click the pet and choose `Hats >` to open the compact hat menu. Press `H`
to cycle all unlocked hats in manifest order during development.

Run `make pet-dev` to show the hat clipping debug overlay: green is the current
hat alpha bounds, blue is the body alpha bounds, and red is the full 128x128
canvas boundary. Production/exported builds do not draw these guides.
