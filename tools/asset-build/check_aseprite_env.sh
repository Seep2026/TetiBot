#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ASEPRITE_BIN="/Users/macstudio/Documents/AICoRun/aseprite/build/bin/aseprite"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ASEPRITE_BIN="${ASEPRITE_BIN:-${DEFAULT_ASEPRITE_BIN}}"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

printf 'TetiBot root: %s\n' "${ROOT_DIR}"
printf 'Aseprite CLI: %s\n' "${ASEPRITE_BIN}"

if [[ ! -x "${ASEPRITE_BIN}" ]]; then
  fail "Aseprite CLI was not found or is not executable. Set ASEPRITE_BIN=/path/to/aseprite and try again."
fi

"${ASEPRITE_BIN}" --version

required_paths=(
  "art/aseprite/master/teti_track_master_front_128.aseprite"
  "art/aseprite/master/teti_track_master_side_128.aseprite"
  "art/aseprite/faces/teti_track_faces_128.aseprite"
  "art/aseprite/motion/teti_track_motion_128.aseprite"
  "art/aseprite/hats/teti_track_hats_128.aseprite"
  "art/aseprite/scripts/export_tags.lua"
  "art/aseprite/scripts/preview_sheet.lua"
  "art/aseprite/scripts/sheet_manifest.lua"
  "tools/asset-build/build_master_128.py"
)

missing=0
for path in "${required_paths[@]}"; do
  if [[ -e "${ROOT_DIR}/${path}" ]]; then
    printf 'ok: %s\n' "${path}"
  else
    printf 'missing: %s\n' "${path}" >&2
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  fail "Aseprite asset pipeline files are incomplete."
fi

printf 'Aseprite environment looks ready.\n'
