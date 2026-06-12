-- Export tagged frames from the active Aseprite sprite.
--
-- This helper is kept for ad hoc tag-driven exports. The production
-- master_128 build currently uses Aseprite CLI frame ranges because the
-- frame-to-runtime-name mapping is explicit and stable in build_master_128.sh.
--
-- Example:
--   aseprite -b source.aseprite \
--     --script-param output=/tmp/source_sheet.png \
--     --script-param tag=faces \
--     --script-param columns=6 \
--     --script art/aseprite/scripts/export_tags.lua

local sprite = app.activeSprite
if not sprite then
  error("No active sprite. Open a .aseprite file before running export_tags.lua.")
end

local output = app.params["output"]
if not output or output == "" then
  error("Missing script-param: output=/path/to/sheet.png")
end

local tag_name = app.params["tag"]
local columns = tonumber(app.params["columns"] or "0")

local function has_tag(name)
  if not name or name == "" then
    return true
  end
  for _, tag in ipairs(sprite.tags) do
    if tag.name == name then
      return true
    end
  end
  return false
end

if not has_tag(tag_name) then
  error("Tag not found: " .. tag_name)
end

local options = {
  ui = false,
  askOverwrite = false,
  filename = output,
  type = SpriteSheetType.ROWS,
}

if tag_name and tag_name ~= "" then
  options.tag = tag_name
end

if columns and columns > 0 then
  options.columns = columns
end

app.command.ExportSpriteSheet(options)
print("exported tagged sheet: " .. output)
