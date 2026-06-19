local Config = require("config")

local HatRegistry = {}

local EXPECTED_SOURCE = "art/aseprite/hats/teti_track_hat_master.aseprite"
local EXPECTED_RUNTIME_ROOT = "pet-runtime/assets/master_128/hats/"
local FORBIDDEN_PATH_PARTS = { "debug", "deprecated", "fallback", "codex" }

local function log(message, ...)
  print(string.format("[TetiHat] " .. message, ...))
end

local function warning(errors, message, ...)
  local rendered = string.format(message, ...)
  errors[#errors + 1] = rendered
  log("WARNING: %s", rendered)
end

local function contains_forbidden_path(path)
  local lower = string.lower(path or "")
  for _, part in ipairs(FORBIDDEN_PATH_PARTS) do
    if string.find(lower, part, 1, true) then
      return true
    end
  end
  return false
end

local function valid_sha256(value)
  return type(value) == "string" and #value == 64 and string.match(value, "^%x+$") ~= nil
end

function HatRegistry.validate()
  local hats = Config.hats or {}
  local errors = {}

  log("loading from source: %s", tostring(hats.source))
  if hats.source ~= "aseprite_master" then
    warning(errors, "unexpected source '%s'", tostring(hats.source))
  end
  if hats.source_path ~= EXPECTED_SOURCE or contains_forbidden_path(hats.source_path) then
    warning(errors, "forbidden or unexpected source path '%s'", tostring(hats.source_path))
  end
  if hats.expected_count ~= 18 or #(hats.order or {}) ~= 18 then
    warning(errors, "expected 18 hats, manifest has %d", #(hats.order or {}))
  end
  if not valid_sha256(hats.source_sha256)
      or not valid_sha256(hats.manifest_sha256)
      or not valid_sha256(hats.atlas_sha256) then
    warning(errors, "source, manifest, or atlas hash is missing")
  end
  if hats.cache ~= "fresh" then
    warning(errors, "atlas cache is not marked fresh")
  end
  if hats.render_layer ~= "world" then
    warning(errors, "hat render layer must be world, got '%s'", tostring(hats.render_layer))
  end
  if hats.transform ~= "linked_to_body" then
    warning(errors, "hat transform must be linked_to_body, got '%s'", tostring(hats.transform))
  end
  if not hats.anchor or hats.anchor.name ~= "head_top_center"
      or hats.anchor.x ~= 64 or hats.anchor.y ~= 16 then
    warning(errors, "head anchor must be head_top_center at 64,16")
  end

  local seen_ids = {}
  local seen_keys = {}
  local registry_count = 0
  for index, hat_id in ipairs(hats.order or {}) do
    local hat = hats.by_id and hats.by_id[hat_id] or nil
    if seen_ids[hat_id] then
      warning(errors, "duplicate hat id '%s'", hat_id)
    end
    seen_ids[hat_id] = true

    if not hat then
      warning(errors, "missing registry entry '%s'", hat_id)
    else
      registry_count = registry_count + 1
      local expected_key = "hat_" .. hat_id .. "_128"
      local expected_file = EXPECTED_RUNTIME_ROOT .. expected_key .. ".png"
      if hat.asset_key ~= expected_key then
        warning(errors, "invalid asset key for '%s': %s", hat_id, tostring(hat.asset_key))
      end
      if hat.file ~= expected_file or contains_forbidden_path(hat.file) then
        warning(errors, "invalid production path for '%s': %s", hat_id, tostring(hat.file))
      end
      if hat.source_tag ~= hat_id or hat.source_frame ~= index - 1 then
        warning(errors, "source tag/frame mismatch for '%s'", hat_id)
      end
      if type(hat.sprite) ~= "number" or hat.sprite < 1 then
        warning(errors, "invalid atlas sprite for '%s'", hat_id)
      end
      if seen_keys[hat.asset_key] then
        warning(errors, "duplicate asset key '%s'", tostring(hat.asset_key))
      end
      seen_keys[hat.asset_key] = true
      log("mapped tag: %s -> %s", hat.source_tag, hat.asset_key)
    end
  end

  for hat_id, _ in pairs(hats.by_id or {}) do
    if not seen_ids[hat_id] then
      warning(errors, "unlisted registry entry '%s'", hat_id)
    end
  end
  if registry_count ~= 18 then
    warning(errors, "loaded registry count is %d, expected 18", registry_count)
  end

  log("render layer: %s", tostring(hats.render_layer))
  log("transform: %s", tostring(hats.transform))
  log("cache: %s atlas=%s build=%s", tostring(hats.cache), tostring(hats.atlas_sha256), tostring(hats.build_id))

  if #errors > 0 then
    error(string.format("hat registry validation failed with %d error(s)", #errors))
  end
  return true
end

return HatRegistry
