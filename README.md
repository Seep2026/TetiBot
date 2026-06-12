# TetiBot

TetiBot includes a 128x128 high-resolution Aseprite master asset pipeline for Teti Track. The committed master PNGs under `pet-runtime/assets/master_128/` are the upstream source for later 64x64, 48x48, and 32x32 runtime assets.

Rebuild the master assets from the repository root:

```bash
make assets-master-128
```

See `docs/art-pipeline/` for Aseprite setup, naming, and new-Mac rebuild notes.
