-- Export a simple preview sheet for the active sprite.
--
-- This is useful when inspecting a whole .aseprite source file outside the
-- runtime naming pipeline. For the committed master_128 output, the shell
-- script exports named frames and the Python helper assembles final previews.

local sprite = app.activeSprite
if not sprite then
  error("No active sprite. Open a .aseprite file before running preview_sheet.lua.")
end

local output = app.params["output"]
if not output or output == "" then
  error("Missing script-param: output=/path/to/preview.png")
end

local columns = tonumber(app.params["columns"] or tostring(#sprite.frames))
if columns < 1 then
  columns = 1
end

app.command.ExportSpriteSheet({
  ui = false,
  askOverwrite = false,
  filename = output,
  type = SpriteSheetType.ROWS,
  columns = columns,
})

print("exported preview sheet: " .. output)
