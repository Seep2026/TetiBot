-- Write a small markdown manifest for the active sprite's frame order and tags.
--
-- Example:
--   aseprite -b source.aseprite \
--     --script-param output=/tmp/source_manifest.md \
--     --script art/aseprite/scripts/sheet_manifest.lua

local sprite = app.activeSprite
if not sprite then
  error("No active sprite. Open a .aseprite file before running sheet_manifest.lua.")
end

local output = app.params["output"]
if not output or output == "" then
  error("Missing script-param: output=/path/to/manifest.md")
end

local file = assert(io.open(output, "w"))
file:write("# Aseprite Sheet Manifest\n\n")
file:write("- source: `" .. sprite.filename .. "`\n")
file:write("- size: " .. sprite.width .. "x" .. sprite.height .. "\n")
file:write("- frames: " .. #sprite.frames .. "\n\n")

file:write("## Frames\n\n")
file:write("| frame | duration_ms |\n")
file:write("|---:|---:|\n")
for i, frame in ipairs(sprite.frames) do
  file:write("| " .. (i - 1) .. " | " .. frame.duration * 1000 .. " |\n")
end

file:write("\n## Tags\n\n")
if #sprite.tags == 0 then
  file:write("_No tags._\n")
else
  file:write("| tag | from | to | direction |\n")
  file:write("|---|---:|---:|---|\n")
  for _, tag in ipairs(sprite.tags) do
    file:write("| `" .. tag.name .. "` | " .. tag.fromFrame.frameNumber - 1 .. " | " .. tag.toFrame.frameNumber - 1 .. " | " .. tag.direction .. " |\n")
  end
end

file:close()
print("wrote manifest: " .. output)
