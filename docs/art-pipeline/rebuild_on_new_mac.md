# Rebuild On A New Mac

This checklist rebuilds the Teti Track 128x128 master asset output on a clean macOS environment.

## Clone

```bash
git clone --recurse-submodules https://github.com/Seep2026/TetiBot.git
cd TetiBot
git submodule update --init --recursive
```

## Install Or Point To Aseprite

If Aseprite is already available:

```bash
export ASEPRITE_BIN=/path/to/aseprite
```

If you use the same local source-build layout as the current machine, the scripts will fall back to:

```text
/Users/macstudio/Documents/AICoRun/aseprite/build/bin/aseprite
```

## Verify

```bash
make check-aseprite-env
```

## Rebuild

```bash
make assets-master-128
```

This regenerates:

- `pet-runtime/assets/master_128/body/`
- `pet-runtime/assets/master_128/faces/`
- `pet-runtime/assets/master_128/motion/`
- `pet-runtime/assets/master_128/hats/`
- `pet-runtime/assets/master_128/previews/`
- `pet-runtime/assets/master_128/sheets/`

## Review Changes

```bash
git status --short
git diff --stat
```

If only expected PNG/markdown files changed, commit them with the source `.aseprite` changes.
