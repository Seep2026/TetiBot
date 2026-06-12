# Aseprite CLI Setup

TetiBot uses Aseprite as the source of truth for the 128x128 high-resolution master assets. The committed runtime output is generated from `.aseprite` projects with the Aseprite CLI.

## CLI Resolution

The asset scripts look for Aseprite in this order:

1. `ASEPRITE_BIN`, if set.
2. The current production fallback path on this Mac:
   `/Users/macstudio/Documents/AICoRun/aseprite/build/bin/aseprite`

Check the environment from the repository root:

```bash
make check-aseprite-env
```

Or explicitly:

```bash
ASEPRITE_BIN=/path/to/aseprite ./tools/asset-build/check_aseprite_env.sh
```

The current local CLI reports:

```text
Aseprite 1.x-dev
```

The macOS build may print an `LSModifyNotification` warning before the version string when running headless. That warning has not affected batch export.

## Required Layout

```text
art/aseprite/master/
art/aseprite/faces/
art/aseprite/motion/
art/aseprite/hats/
art/aseprite/scripts/
tools/asset-build/
pet-runtime/assets/master_128/
```

The scripts use paths relative to the Git repository root. Do not hardcode a local clone path in asset scripts.

## New Mac Checklist

1. Clone TetiBot with submodules.
2. Install or build Aseprite.
3. Export `ASEPRITE_BIN` if Aseprite is not at the fallback path.
4. Run `make check-aseprite-env`.
5. Run `make assets-master-128` when you need to rebuild PNG output.
