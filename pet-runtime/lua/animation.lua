local Config = require("config")

local Animation = {}

local function sprite_source(sprite)
  local index = sprite - 1
  local cell = Config.sprite_size
  local col = index % Config.sprite_sheet_columns
  local row = math.floor(index / Config.sprite_sheet_columns)
  return col * cell, row * cell
end

local function frame_for(pet)
  local sprites = Config.sprites

  if pet.state == "blink" then
    return sprites.face_blink, false
  end

  if pet.state == "move_left" then
    if pet.state_t < 0.18 then
      return sprites.side, true
    end
    return sprites.move_left, false
  end

  if pet.state == "move_right" then
    if pet.state_t < 0.18 then
      return sprites.side, false
    end
    return sprites.move_right, false
  end

  return pet.idle_frame == 1 and sprites.front or sprites.idle_2, false
end

local function draw_full(sprite, pet, flip_x)
  gfx.spr_ex(
    sprite,
    math.floor(pet.x),
    math.floor(pet.y),
    flip_x,
    false,
    0,
    gfx.COLOR_TRUE_WHITE,
    1.0
  )
end

local function draw_rect(sx, sy, sw, sh, dx, dy, flip_x)
  gfx.sspr_ex(
    sx,
    sy,
    sw,
    sh,
    dx,
    dy,
    sw,
    sh,
    flip_x,
    false,
    0,
    gfx.COLOR_TRUE_WHITE,
    1.0
  )
end

local function draw_layered(sprite, pet, flip_x)
  if not gfx.sspr_ex or not Config.breathing.enabled then
    draw_full(sprite, pet, flip_x)
    return
  end

  local sx, sy = sprite_source(sprite)
  local size = Config.sprite_size
  local body_cut_y = Config.breathing.body_cut_y
  local body_overlap = Config.breathing.body_overlap
  local body_h = math.min(size, body_cut_y + body_overlap)
  local track_h = size - body_cut_y
  local x = math.floor(pet.x)
  local y = math.floor(pet.y)
  local body_y = y + (pet.body_offset_y or 0)

  draw_rect(sx, sy + body_cut_y, size, track_h, x, y + body_cut_y, flip_x)
  draw_rect(sx, sy, size, body_h, x, body_y, flip_x)
end

function Animation.draw(pet)
  local sprite, flip_x = frame_for(pet)
  draw_layered(sprite, pet, flip_x)
end

return Animation
