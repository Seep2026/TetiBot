#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ASEPRITE_BIN="/Users/macstudio/Documents/AICoRun/aseprite/build/bin/aseprite"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ASEPRITE_BIN="${ASEPRITE_BIN:-${DEFAULT_ASEPRITE_BIN}}"
OUT_DIR="${MASTER_128_OUT_DIR:-${ROOT_DIR}/pet-runtime/assets/master_128}"
ART_DIR="${ROOT_DIR}/art/aseprite"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if [[ ! -x "${ASEPRITE_BIN}" ]]; then
  fail "Aseprite CLI was not found or is not executable. Set ASEPRITE_BIN=/path/to/aseprite and try again."
fi

mkdir -p \
  "${OUT_DIR}/body" \
  "${OUT_DIR}/faces" \
  "${OUT_DIR}/motion" \
  "${OUT_DIR}/hats" \
  "${OUT_DIR}/previews" \
  "${OUT_DIR}/sheets"

export_frame() {
  local source_file="$1"
  local frame_index="$2"
  local output_file="$3"

  if [[ ! -f "${source_file}" ]]; then
    fail "source Aseprite file does not exist: ${source_file}"
  fi

  printf 'export: %s frame %s -> %s\n' "${source_file#${ROOT_DIR}/}" "${frame_index}" "${output_file#${ROOT_DIR}/}"
  "${ASEPRITE_BIN}" -b "${source_file}" --frame-range "${frame_index},${frame_index}" --save-as "${output_file}"
}

front="${ART_DIR}/master/teti_track_master_front_128.aseprite"
side="${ART_DIR}/master/teti_track_master_side_128.aseprite"
faces="${ART_DIR}/faces/teti_track_faces_128.aseprite"
motion="${ART_DIR}/motion/teti_track_motion_128.aseprite"
hats="${ART_DIR}/hats/teti_track_hats_128.aseprite"

export_frame "${front}" 0 "${OUT_DIR}/body/teti_track_front_neutral_128.png"
export_frame "${side}" 0 "${OUT_DIR}/body/teti_track_side_128.png"

export_frame "${faces}" 0 "${OUT_DIR}/faces/face_neutral_128.png"
export_frame "${faces}" 1 "${OUT_DIR}/faces/face_blink_128.png"
export_frame "${faces}" 2 "${OUT_DIR}/faces/face_sleepy_128.png"
export_frame "${faces}" 3 "${OUT_DIR}/faces/face_focused_128.png"
export_frame "${faces}" 4 "${OUT_DIR}/faces/face_warning_128.png"
export_frame "${faces}" 5 "${OUT_DIR}/faces/face_collapsed_128.png"

export_frame "${motion}" 0 "${OUT_DIR}/motion/idle_1_128.png"
export_frame "${motion}" 1 "${OUT_DIR}/motion/idle_2_128.png"
export_frame "${motion}" 2 "${OUT_DIR}/motion/move_left_1_128.png"
export_frame "${motion}" 3 "${OUT_DIR}/motion/move_right_1_128.png"

export_frame "${hats}" 0 "${OUT_DIR}/hats/hat_none_128.png"
export_frame "${hats}" 1 "${OUT_DIR}/hats/hat_beanie_128.png"
export_frame "${hats}" 2 "${OUT_DIR}/hats/hat_engineer_128.png"
export_frame "${hats}" 3 "${OUT_DIR}/hats/hat_antenna_128.png"
export_frame "${hats}" 4 "${OUT_DIR}/hats/hat_warning_light_128.png"
export_frame "${hats}" 5 "${OUT_DIR}/hats/hat_sprout_128.png"

python_args=(--asset-root "${OUT_DIR}")
if [[ "${REBUILD_MASTER_PREVIEW:-0}" == "1" ]]; then
  python_args+=(--rebuild-master-preview)
fi

python3 "${SCRIPT_DIR}/build_master_128.py" "${python_args[@]}"

printf 'master_128 asset build complete: %s\n' "${OUT_DIR}"
