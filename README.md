# TetiBot

TetiBot includes a 128x128 high-resolution Aseprite master asset pipeline for Teti Track. The committed master PNGs under `pet-runtime/assets/master_128/` are the upstream source for later 64x64, 48x48, and 32x32 runtime assets.

Rebuild the master assets from the repository root:

```bash
make assets-master-128
```

See `docs/art-pipeline/` for Aseprite setup, naming, and new-Mac rebuild notes.

## Chatmail MVP

The macOS Tauri shell integrates Delta Chat Core through `deltachat-rpc-server`. The visible desktop pet is the repository's original usagi runtime, not a WebView recreation. This preserves Teti's layered breathing, blinking and expression states, animated tracks, natural random movement, dragging/falling behavior, and hat picker.

Teti starts with only the transparent usagi desktop pet visible. The Tauri Mail window stays hidden until the user right-clicks the pet and chooses **Mail**. Adoption and communication settings are entries inside Mail and never appear automatically at app launch.

On macOS, Tauri remains the single regular application represented in the Dock. It launches usagi with `USAGI_ACCESSORY_APP=1`, so the original interactive pet window remains visible without registering a second Dock icon.

> Delta Chat Core is an external source dependency. It is **not included in this repository and is not a Git submodule**. Cloning TetiBot alone does not download Core.

Clone Core anywhere on the Mac, then pass its directory to Make:

```bash
git clone https://github.com/chatmail/core.git /path/to/core
make chatmail-run DELTA_CORE_DIR=/path/to/core
```

`make chatmail-run` builds both `engine/usagi` and `deltachat-rpc-server` from source before starting Teti. For a non-default checkout layout, all source/runtime locations are configurable:

```bash
make chatmail-run \
  DELTA_CORE_DIR=/path/to/core \
  USAGI_MANIFEST=/path/to/usagi/Cargo.toml \
  USAGI_BIN=/path/to/usagi/target/release/usagi \
  TETI_PET_PROJECT=/path/to/TetiBot/pet-runtime/lua
```

The current reference checkout is Core `main` at commit `24848c0265485d9254b77010e54ba756428321da`. See `docs/delta-chat-core-source.md` for cross-Mac setup, path overrides, version checks, and source-build commands. See `docs/chatmail-mvp.md` for the interoperability contract and module boundaries.
