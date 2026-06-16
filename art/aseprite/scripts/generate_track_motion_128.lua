-- Generate Teti Track 128x128 track-motion production frames.
-- Run with:
--   aseprite -b --script art/aseprite/scripts/generate_track_motion_128.lua --script-param root=/path/to/TetiBot

local pc = app.pixelColor
local rgba = pc.rgba
local rgbaR = pc.rgbaR
local rgbaG = pc.rgbaG
local rgbaB = pc.rgbaB
local rgbaA = pc.rgbaA

local ROOT = app.params["root"] or app.fs.currentPath
local MOTION_ASE = app.fs.joinPath(ROOT, "art/aseprite/motion/teti_track_motion_128.aseprite")
local OUT = app.fs.joinPath(ROOT, "pet-runtime/assets/master_128/motion")
local TRACK_OUT = app.fs.joinPath(OUT, "track")

local C = {
  transparent = rgba(0, 0, 0, 0),
  outline = rgba(5, 58, 51, 255),
  outline2 = rgba(18, 85, 74, 255),
  mint = rgba(111, 220, 176, 255),
  mintHi = rgba(182, 250, 214, 255),
  mintLight = rgba(145, 236, 194, 255),
  mintDark = rgba(39, 146, 119, 255),
  facePanel = rgba(247, 250, 232, 255),
  faceShade = rgba(222, 238, 207, 255),
  faceEdge = rgba(113, 202, 161, 255),
  face = rgba(11, 15, 25, 255),
  white = rgba(255, 255, 255, 255),
  treadInk = rgba(7, 15, 26, 255),
  treadHousing = rgba(27, 38, 51, 255),
  treadHousingHi = rgba(66, 79, 92, 255),
  treadBelt = rgba(15, 23, 34, 255),
  treadBeltMid = rgba(38, 50, 63, 255),
  treadSide = rgba(49, 62, 76, 255),
  wheelOuter = rgba(82, 94, 102, 255),
  wheelHi = rgba(174, 183, 178, 255),
  wheelCore = rgba(49, 57, 64, 255),
  shadow = rgba(18, 28, 35, 72),
  shadow2 = rgba(18, 28, 35, 36),
  dust = rgba(181, 190, 187, 110),
}

local BELT = { x0 = 27, y0 = 90, x1 = 101, y1 = 107, r = 8 }
local EDGE_GUARD = { left = 8, right = 119 }

local function q(s)
  return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

os.execute("mkdir -p " .. q(TRACK_OUT))

local function clamp(v)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return math.floor(v + 0.5)
end

local function blend(dst, src)
  local sa = rgbaA(src) / 255
  local da = rgbaA(dst) / 255
  local outA = sa + da * (1 - sa)
  if outA <= 0 then return C.transparent end
  return rgba(
    clamp((rgbaR(src) * sa + rgbaR(dst) * da * (1 - sa)) / outA),
    clamp((rgbaG(src) * sa + rgbaG(dst) * da * (1 - sa)) / outA),
    clamp((rgbaB(src) * sa + rgbaB(dst) * da * (1 - sa)) / outA),
    clamp(outA * 255))
end

local function img(w, h, fill)
  local out = Image(w, h, ColorMode.RGB)
  out:clear(fill or C.transparent)
  return out
end

local function pset(im, x, y, color)
  if x < 0 or y < 0 or x >= im.width or y >= im.height then return end
  if rgbaA(color) < 255 then
    im:putPixel(x, y, blend(im:getPixel(x, y), color))
  else
    im:putPixel(x, y, color)
  end
end

local function rect(im, x0, y0, x1, y1, color)
  for y = y0, y1 do
    for x = x0, x1 do pset(im, x, y, color) end
  end
end

local function hline(im, x0, x1, y, color)
  if x0 > x1 then x0, x1 = x1, x0 end
  for x = x0, x1 do pset(im, x, y, color) end
end

local function vline(im, x, y0, y1, color)
  if y0 > y1 then y0, y1 = y1, y0 end
  for y = y0, y1 do pset(im, x, y, color) end
end

local function line(im, x0, y0, x1, y1, color)
  local dx = math.abs(x1 - x0)
  local sx = x0 < x1 and 1 or -1
  local dy = -math.abs(y1 - y0)
  local sy = y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    pset(im, x0, y0, color)
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

local function ellipse(im, cx, cy, rx, ry, color)
  for y = cy - ry, cy + ry do
    for x = cx - rx, cx + rx do
      local dx = (x - cx) / math.max(1, rx)
      local dy = (y - cy) / math.max(1, ry)
      if dx * dx + dy * dy <= 1 then pset(im, x, y, color) end
    end
  end
end

local function roundedRect(im, x0, y0, x1, y1, r, fill, outline)
  for y = y0, y1 do
    for x = x0, x1 do
      local dx = math.max(x0 + r - x, 0, x - (x1 - r))
      local dy = math.max(y0 + r - y, 0, y - (y1 - r))
      local inside = dx * dx + dy * dy <= r * r
      local edge = dx * dx + dy * dy >= (r - 1) * (r - 1) or x == x0 or x == x1 or y == y0 or y == y1
      if inside then pset(im, x, y, edge and outline or fill) end
    end
  end
end

local function insideRoundedRect(x, y, x0, y0, x1, y1, r)
  local dx = math.max(x0 + r - x, 0, x - (x1 - r))
  local dy = math.max(y0 + r - y, 0, y - (y1 - r))
  return dx * dx + dy * dy <= r * r
end

local function maskedRect(im, x0, y0, x1, y1, mask, color)
  for y = y0, y1 do
    for x = x0, x1 do
      if insideRoundedRect(x, y, mask.x0, mask.y0, mask.x1, mask.y1, mask.r) then
        pset(im, x, y, color)
      end
    end
  end
end

local function blit(dst, src, ox, oy)
  for y = 0, src.height - 1 do
    for x = 0, src.width - 1 do
      local px = src:getPixel(x, y)
      if rgbaA(px) > 0 then pset(dst, ox + x, oy + y, px) end
    end
  end
end

local function drawShadow(im, cx, cy, rx)
  ellipse(im, cx, cy, rx, 5, C.shadow2)
  ellipse(im, cx, cy, math.floor(rx * 0.72), 3, C.shadow)
  hline(im, cx - rx + 4, cx + rx - 4, cy + 4, C.shadow)
end

local WHEEL_DOTS = {
  { 0, -8 }, { 6, -5 }, { 8, 0 }, { 0, 8 }, { -6, 5 }, { -8, 0 },
}

local function phase_index(phase)
  return ((phase - 1) % 6) + 1
end

local function drawWheel(im, cx, cy, phase)
  local p = phase_index(phase or 1)
  local dot = WHEEL_DOTS[p]
  local odot = WHEEL_DOTS[phase_index(p + 3)]

  ellipse(im, cx, cy, 15, 15, C.treadInk)
  ellipse(im, cx, cy, 12, 12, C.wheelOuter)
  ellipse(im, cx, cy, 9, 9, C.wheelHi)
  ellipse(im, cx, cy, 6, 6, C.wheelCore)
  line(im, cx, cy, cx + dot[1], cy + dot[2], C.treadHousingHi)
  line(im, cx, cy, cx + odot[1], cy + odot[2], C.treadBeltMid)
  rect(im, cx - 4, cy - 4, cx + 4, cy + 4, C.wheelCore)
  if dot[1] * dot[1] + dot[2] * dot[2] <= 81 then
    pset(im, cx + dot[1], cy + dot[2], C.white)
    pset(im, cx + dot[1] - 1, cy + dot[2], C.wheelHi)
  end
end

local function drawBeltLugs(im, offset)
  local start = 27 + (((offset or 0) % 12) - 12)
  for x = start, 104, 12 do
    maskedRect(im, x, 91, x + 5, 94, BELT, C.treadBeltMid)
    maskedRect(im, x + 6, 103, x + 11, 106, BELT, C.treadSide)
  end
end

local function drawTread(im, opts)
  opts = opts or {}
  local shadowPulse = opts.shadowPulse or 0
  drawShadow(im, 64, 116, 48 + shadowPulse)
  roundedRect(im, 18, 82, 110, 113, 13, C.treadHousing, C.treadInk)
  hline(im, 28, 100, 84, C.treadHousingHi)
  hline(im, 24, 104, 112, C.treadInk)
  roundedRect(im, 27, 90, 101, 107, 8, C.treadBelt, C.treadInk)
  drawBeltLugs(im, opts.beltOffset or 0)
  hline(im, 33, 95, 92, C.treadBeltMid)
  hline(im, 33, 95, 105, C.treadSide)
  roundedRect(im, 51, 91, 77, 106, 5, C.treadSide, C.treadInk)

  local leftPhase = opts.wheelPhase or 1
  local rightPhase = phase_index(leftPhase + 3)
  drawWheel(im, 35, 98, leftPhase)
  drawWheel(im, 93, 98, rightPhase)
  rect(im, 58, 108, 70, 110, C.treadHousingHi)
end

local function drawConnectors(im, xoff, yoff)
  xoff = xoff or 0
  yoff = yoff or 0
  rect(im, 36 + xoff, 76 + yoff, 46 + xoff, 86 + yoff, C.treadBeltMid)
  rect(im, 82 + xoff, 76 + yoff, 92 + xoff, 86 + yoff, C.treadBeltMid)
  hline(im, 37 + xoff, 45 + xoff, 76 + yoff, C.treadHousingHi)
  hline(im, 83 + xoff, 91 + xoff, 76 + yoff, C.treadHousingHi)
end

local function drawFace(im, xoff, yoff)
  xoff = xoff or 0
  yoff = yoff or 0
  rect(im, 45 + xoff, 43 + yoff, 52 + xoff, 52 + yoff, C.face)
  rect(im, 76 + xoff, 43 + yoff, 83 + xoff, 52 + yoff, C.face)
  pset(im, 50 + xoff, 45 + yoff, C.white)
  pset(im, 81 + xoff, 45 + yoff, C.white)
  hline(im, 60 + xoff, 68 + xoff, 62 + yoff, C.face)
end

local function drawBodyFront(im, opts)
  opts = opts or {}
  local x = opts.x or 0
  local y = opts.y or 0
  roundedRect(im, 27 + x, 18 + y, 101 + x, 80 + y, 11, C.mint, C.outline)
  hline(im, 38 + x, 91 + x, 21 + y, C.mintHi)
  hline(im, 34 + x, 96 + x, 25 + y, C.mintLight)
  vline(im, 30 + x, 31 + y, 67 + y, C.mintHi)
  vline(im, 99 + x, 32 + y, 68 + y, C.mintDark)
  hline(im, 36 + x, 94 + x, 78 + y, C.mintDark)
  roundedRect(im, 35 + x, 32 + y, 93 + x, 70 + y, 4, C.facePanel, C.faceEdge)
  hline(im, 40 + x, 88 + x, 34 + y, C.white)
  hline(im, 40 + x, 88 + x, 69 + y, C.faceShade)
  drawFace(im, x, y)
end

local function dust(im, dir, phase)
  return
end

local function cleanupEdges(im)
  for y = 0, im.height - 1 do
    for x = 0, EDGE_GUARD.left - 1 do
      im:putPixel(x, y, C.transparent)
    end
    for x = EDGE_GUARD.right + 1, im.width - 1 do
      im:putPixel(x, y, C.transparent)
    end
  end
end

local function scanEdgeAlpha(im)
  local count = 0
  for y = 0, im.height - 1 do
    for x = 0, EDGE_GUARD.left - 1 do
      if rgbaA(im:getPixel(x, y)) > 0 then count = count + 1 end
    end
    for x = EDGE_GUARD.right + 1, im.width - 1 do
      if rgbaA(im:getPixel(x, y)) > 0 then count = count + 1 end
    end
  end
  return count
end

local function sprite(opts)
  opts = opts or {}
  local im = img(128, 128)
  drawTread(im, opts)
  drawConnectors(im, opts.bodyX or 0, opts.bodyY or 0)
  drawBodyFront(im, { x = opts.bodyX or 0, y = opts.bodyY or 0 })
  if opts.dir then dust(im, opts.dir, opts.phase or 1) end
  cleanupEdges(im)
  return im
end

local IDLE_BODY_Y = { 0, 0, -1, 0 }
local MOVE_BODY_Y = { 0, 0, 0, 0, -1, 0 }
local MOVE_BODY_X = { 0, 0, 1, 1, 0, 0 }

local frames = {}
local function addFrame(name, im, duration)
  table.insert(frames, { name = name, image = im, duration = duration })
end

for i = 1, 4 do
  addFrame(string.format("idle_breathe_%02d_128", i), sprite({
    bodyY = IDLE_BODY_Y[i],
    wheelPhase = 1,
    beltOffset = 0,
  }), 0.5)
end

for i = 1, 6 do
  addFrame(string.format("move_left_%02d_128", i), sprite({
    dir = "left",
    phase = i,
    bodyX = -MOVE_BODY_X[i],
    bodyY = MOVE_BODY_Y[i],
    wheelPhase = 7 - i,
    beltOffset = (i - 1) * 2,
    shadowPulse = (i == 3 or i == 4) and 1 or 0,
  }), 1 / 8)
end

for i = 1, 6 do
  addFrame(string.format("move_right_%02d_128", i), sprite({
    dir = "right",
    phase = i,
    bodyX = MOVE_BODY_X[i],
    bodyY = MOVE_BODY_Y[i],
    wheelPhase = i,
    beltOffset = -(i - 1) * 2,
    shadowPulse = (i == 3 or i == 4) and 1 or 0,
  }), 1 / 8)
end

local function saveImage(im, path)
  local spr = Sprite(im.width, im.height, ColorMode.RGB)
  spr.layers[1].name = "image"
  spr.cels[1].image:clear(C.transparent)
  spr.cels[1].image:putImage(im)
  spr:saveAs(path)
end

local function saveProject()
  local spr = Sprite(128, 128, ColorMode.RGB)
  local layer = spr.layers[1]
  layer.name = "composited_track_motion"
  for i = 2, #frames do spr:newEmptyFrame() end
  for i, fr in ipairs(frames) do
    spr.frames[i].duration = fr.duration
    if i == 1 then
      spr.cels[1].image:clear(C.transparent)
      spr.cels[1].image:putImage(fr.image)
    else
      spr:newCel(layer, i, fr.image, Point(0, 0))
    end
  end
  spr:newTag(1, 4).name = "idle_breathe"
  spr:newTag(5, 10).name = "move_left"
  spr:newTag(11, 16).name = "move_right"
  spr:saveAs(MOTION_ASE)
end

local function composeGrid(list, cols)
  local rows = math.ceil(#list / cols)
  local out = img(cols * 128, rows * 128)
  for i, fr in ipairs(list) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    blit(out, fr.image, col * 128, row * 128)
  end
  return out
end

saveProject()

saveImage(frames[1].image, app.fs.joinPath(OUT, "idle_1_128.png"))
saveImage(frames[2].image, app.fs.joinPath(OUT, "idle_2_128.png"))
saveImage(frames[5].image, app.fs.joinPath(OUT, "move_left_1_128.png"))
saveImage(frames[11].image, app.fs.joinPath(OUT, "move_right_1_128.png"))

for _, fr in ipairs(frames) do
  saveImage(fr.image, app.fs.joinPath(TRACK_OUT, fr.name .. ".png"))
end

local sheetName = "teti_track_motion_track_sheet_128.png"
saveImage(composeGrid(frames, 6), app.fs.joinPath(TRACK_OUT, sheetName))

local json = {
  "{",
  '  "image": "' .. sheetName .. '",',
  '  "cell": { "w": 128, "h": 128 },',
  '  "columns": 6,',
  '  "animations": {',
  '    "idle_breathe": { "frames": ["idle_breathe_01_128", "idle_breathe_02_128", "idle_breathe_03_128", "idle_breathe_04_128"], "fps": 2 },',
  '    "move_left": { "frames": ["move_left_01_128", "move_left_02_128", "move_left_03_128", "move_left_04_128", "move_left_05_128", "move_left_06_128"], "fps": { "low": 5, "normal": 8, "high": 12 } },',
  '    "move_right": { "frames": ["move_right_01_128", "move_right_02_128", "move_right_03_128", "move_right_04_128", "move_right_05_128", "move_right_06_128"], "fps": { "low": 5, "normal": 8, "high": 12 } }',
  "  },",
  '  "frames": [',
}

for i, fr in ipairs(frames) do
  local index = i - 1
  local x = (index % 6) * 128
  local y = math.floor(index / 6) * 128
  local comma = i < #frames and "," or ""
  table.insert(json, string.format('    { "name": "%s", "x": %d, "y": %d, "w": 128, "h": 128 }%s', fr.name, x, y, comma))
end
table.insert(json, "  ]")
table.insert(json, "}")

local jsonFile = io.open(app.fs.joinPath(TRACK_OUT, "teti_track_motion_track_sheet_128.json"), "w")
jsonFile:write(table.concat(json, "\n"))
jsonFile:write("\n")
jsonFile:close()

local edgeReport = {}
for _, fr in ipairs(frames) do
  table.insert(edgeReport, string.format("%s=%d", fr.name, scanEdgeAlpha(fr.image)))
end

print("Generated Teti Track track-motion frames: " .. TRACK_OUT)
print("edge-alpha-scan " .. table.concat(edgeReport, " "))
