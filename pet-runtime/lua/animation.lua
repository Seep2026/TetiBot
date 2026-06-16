local Config = require("config")

local Animation = {}

local function sprite_source(sprite)
  local index = sprite - 1
  local cell = Config.sprite_size
  local col = index % Config.sprite_sheet_columns
  local row = math.floor(index / Config.sprite_sheet_columns)
  return col * cell, row * cell
end

local FACE_OFFSETS = {
  idle_breathe = {
    { x = 0, y = 0 },
    { x = 0, y = 0 },
    { x = 0, y = -1 },
    { x = 0, y = 0 },
  },
  move_left = {
    { x = 0, y = 0 },
    { x = 0, y = 0 },
    { x = -1, y = 0 },
    { x = -1, y = 0 },
    { x = 0, y = -1 },
    { x = 0, y = 0 },
  },
  move_right = {
    { x = 0, y = 0 },
    { x = 0, y = 0 },
    { x = 1, y = 0 },
    { x = 1, y = 0 },
    { x = 0, y = -1 },
    { x = 0, y = 0 },
  },
}

local function sequence_index(sequence, t, fps)
  if not sequence or #sequence == 0 then
    return nil
  end
  return (math.floor(t * fps) % #sequence) + 1
end

local function sequence_frame(sequence, t, fps)
  local index = sequence_index(sequence, t, fps)
  if not index then
    return nil
  end
  return sequence[index]
end

local function sequence_pose(sequence, t, fps, offsets)
  local index = sequence_index(sequence, t, fps)
  if not index then
    return nil, { x = 0, y = 0 }
  end
  return sequence[index], (offsets and offsets[index]) or { x = 0, y = 0 }
end

local function movement_fps(pet)
  local animation = Config.animation
  local speed = math.abs(pet.move_speed_current or 0)
  if speed >= (animation.move_high_speed or 62) then
    return animation.move_high_fps or 18
  end
  if speed >= (animation.move_normal_speed or 48) then
    return animation.move_normal_fps or 12
  end
  return animation.move_low_fps or 8
end

local function pose_for(pet)
  local sprites = Config.sprites
  local movement_state = pet.movement_state or pet.state
  local velocity_x = pet.velocity_x or 0

  if pet.state == "move_left" or (movement_state == "wander" and velocity_x < -0.1) then
    local sprite, offset = sequence_pose(sprites.move_left_track, pet.state_t, movement_fps(pet), FACE_OFFSETS.move_left)
    return sprite or sprites.move_left, false, offset.x, offset.y
  end

  if pet.state == "move_right" or (movement_state == "wander" and velocity_x > 0.1) then
    local sprite, offset = sequence_pose(sprites.move_right_track, pet.state_t, movement_fps(pet), FACE_OFFSETS.move_right)
    return sprite or sprites.move_right, false, offset.x, offset.y
  end

  local sprite, offset = sequence_pose(sprites.idle_breathe, pet.state_t, Config.animation.idle_fps or 4, FACE_OFFSETS.idle_breathe)
  return sprite or (pet.idle_frame == 1 and sprites.front or sprites.idle_2), false, offset.x, offset.y
end

local function face_sprite_for(pet)
  local overlays = Config.sprites.face_overlay or {}
  return overlays[pet.expression or "neutral"] or overlays.neutral
end

local function draw_sprite(sprite, x, y, flip_x)
  gfx.spr_ex(
    sprite,
    math.floor(x),
    math.floor(y),
    flip_x or false,
    false,
    0,
    gfx.COLOR_TRUE_WHITE,
    1.0
  )
end

local function draw_full(sprite, pet, flip_x)
  draw_sprite(sprite, pet.x, pet.y, flip_x)
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
  local sprite, flip_x, face_dx, face_dy = pose_for(pet)
  draw_layered(sprite, pet, flip_x)

  if Config.expression.overlay_enabled and Config.sprites.face_clear then
    local x = pet.x + (face_dx or 0)
    local y = pet.y + (face_dy or 0)
    draw_sprite(Config.sprites.face_clear, x, y, false)
    local face = face_sprite_for(pet)
    if face then
      draw_sprite(face, x, y, false)
    end
  end
end

function Animation.debug_pose_for(pet)
  local sprite, flip_x, face_dx, face_dy = pose_for(pet)
  return {
    sprite = sprite,
    flip_x = flip_x,
    face_dx = face_dx,
    face_dy = face_dy,
  }
end

return Animation
