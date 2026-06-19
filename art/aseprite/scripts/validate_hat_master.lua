local path = app.params["path"]
if not path or path == "" then error("missing --script-param path=/path/to/hat-master") end
local manifestPath = app.params["manifest"]
if not manifestPath or manifestPath == "" then
  error("missing --script-param manifest=/path/to/hats_manifest.json")
end

local manifestFile = assert(io.open(manifestPath, "r"))
local manifest = json.decode(manifestFile:read("*a"))
manifestFile:close()
assert(manifest and manifest.hats, "hat manifest must contain a hats array")

local spr = app.open(path)
if not spr then error("cannot open hat master: " .. path) end

local function findLayer(name)
  for _, layer in ipairs(spr.layers) do
    if layer.name == name then return layer end
  end
  return nil
end

local hats = findLayer("HATS")
local guide = findLayer("HEAD_GUIDE_LAYER")
assert(spr.width == 128 and spr.height == 128, "hat master must be 128x128")
assert(#spr.frames == 18, "hat master must contain 18 frames")
assert(hats and #hats.cels == 18, "HATS layer must contain 18 cels")
assert(guide and #guide.cels == 18, "HEAD_GUIDE_LAYER must contain 18 cels")
assert(guide.isVisible == false, "HEAD_GUIDE_LAYER must be hidden")
assert(#spr.tags == 18, "hat master must contain 18 named tags")
assert(#manifest.hats == 18, "hat manifest must contain 18 hats")

local seen = {}
for index, definition in ipairs(manifest.hats) do
  local tag = spr.tags[index]
  local expectedFrame = definition.source_frame + 1
  assert(not seen[definition.id], "duplicate hat id in manifest: " .. definition.id)
  seen[definition.id] = true
  assert(tag.name == definition.id,
    string.format("tag %d must be '%s', got '%s'", index, definition.id, tag.name))
  assert(tag.fromFrame.frameNumber == expectedFrame and tag.toFrame.frameNumber == expectedFrame,
    string.format("tag '%s' must map only frame %d", definition.id, expectedFrame))
  assert(definition.file == "hat_" .. definition.id .. "_128.png",
    "production filename does not match hat id: " .. definition.id)
end

print("hat master valid: 128x128, 18 tags mapped 1:1 to hats_manifest.json")
spr:close()
