local Animation = require("animation")
local Config = require("config")

local Pet = {}

local function clamp(value, min, max)
  if value < min then
    return min
  end
  if value > max then
    return max
  end
  return value
end

local function rand_between(min, max)
  return min + math.random() * (max - min)
end

local function reset_timers(pet)
  local anim = Config.animation
  pet.blink_in = rand_between(anim.blink_min_delay, anim.blink_max_delay)
  pet.move_in = rand_between(anim.move_min_delay, anim.move_max_delay)
end

local function start_state(pet, state)
  pet.state = state
  pet.state_t = 0
end

local function read_desktop_bounds()
  if usagi and usagi.desktop_bounds then
    local x, y, w, h = usagi.desktop_bounds()
    if w and h and w > 0 and h > 0 then
      return {
        x = x or 0,
        y = y or 0,
        w = w,
        h = h,
      }
    end
  end

  local desktop = Config.desktop
  return {
    x = desktop.fallback_x,
    y = desktop.fallback_y,
    w = desktop.fallback_w,
    h = desktop.fallback_h,
  }
end

local function window_limits(pet)
  local margin = Config.desktop.margin
  local min_x = pet.desktop.x + margin
  local min_y = pet.desktop.y + margin
  local max_x = pet.desktop.x + pet.desktop.w - pet.size - margin
  local max_y = pet.desktop.y + pet.desktop.h - pet.size - margin

  if max_x < min_x then
    max_x = min_x
  end
  if max_y < min_y then
    max_y = min_y
  end

  return min_x, max_x, min_y, max_y
end

local function sync_window(pet, x, y)
  local min_x, max_x, min_y, max_y = window_limits(pet)
  pet.window_x = clamp(x, min_x, max_x)
  pet.window_y = clamp(y, min_y, max_y)

  local target_x = math.floor(pet.window_x + 0.5)
  local target_y = math.floor(pet.window_y + 0.5)

  if pet.last_window_x == target_x and pet.last_window_y == target_y then
    return
  end

  pet.last_window_x = target_x
  pet.last_window_y = target_y

  if usagi and usagi.set_window_position then
    usagi.set_window_position(target_x, target_y)
  end
end

local function choose_move_dir(pet)
  local min_x, max_x = window_limits(pet)
  if pet.window_x <= min_x + 1 then
    return 1
  end
  if pet.window_x >= max_x - 1 then
    return -1
  end
  return -pet.move_dir
end

local function update_body_breath(pet, dt)
  local breathing = Config.breathing
  if not breathing.enabled then
    pet.body_offset_y = 0
    return
  end

  pet.breath_t = pet.breath_t + dt
  local wave = (math.sin(pet.breath_t * breathing.body_speed + pet.idle_phase) + 1) * 0.5
  pet.body_offset_y = math.floor(wave * breathing.body_amplitude + 0.5)
end

local function sync_from_native_window(pet)
  if usagi and usagi.window_position then
    local x, y = usagi.window_position()
    if x and y then
      pet.window_x = x
      pet.window_y = y
      pet.last_window_x = math.floor(x + 0.5)
      pet.last_window_y = math.floor(y + 0.5)
    end
  end
end

function Pet.new()
  local desktop = read_desktop_bounds()
  local size = Config.pet_size
  local pet = {
    x = 0,
    y = 0,
    size = size,
    desktop = desktop,
    window_x = 0,
    window_y = 0,
    base_y = 0,
    last_window_x = nil,
    last_window_y = nil,
    state = "idle",
    state_t = 0,
    idle_frame = 1,
    idle_t = 0,
    blink_in = 0,
    move_in = 0,
    move_dir = 1,
    idle_phase = math.random() * math.pi * 2,
    breath_t = 0,
    body_offset_y = 0,
    drag_pending = false,
    is_dragging = false,
    drag_offset_x = 0,
    drag_offset_y = 0,
    drag_start_screen_x = 0,
    drag_start_screen_y = 0,
    drag_last_screen_x = 0,
    drag_last_screen_y = 0,
    drag_grab_offset_x = 0,
    drag_grab_offset_y = 0,
  }

  local min_x, max_x, min_y, max_y = window_limits(pet)
  pet.window_x = min_x + (max_x - min_x) * Config.desktop.start_x_ratio
  pet.base_y = min_y + (max_y - min_y) * Config.desktop.start_y_ratio
  pet.window_y = pet.base_y

  reset_timers(pet)
  sync_window(pet, pet.window_x, pet.window_y)
  return pet
end

function Pet.set_window_position(pet, x, y)
  sync_window(pet, x, y)
end

function Pet.begin_drag(pet, mouse_x, mouse_y, screen_x, screen_y)
  if not Config.drag.enabled then
    Pet.end_drag(pet)
    return
  end

  sync_from_native_window(pet)
  screen_x = screen_x or (pet.window_x + (mouse_x or 0))
  screen_y = screen_y or (pet.window_y + (mouse_y or 0))

  pet.drag_pending = true
  pet.is_dragging = false
  pet.drag_offset_x = mouse_x or 0
  pet.drag_offset_y = mouse_y or 0
  pet.drag_start_screen_x = screen_x
  pet.drag_start_screen_y = screen_y
  pet.drag_last_screen_x = screen_x
  pet.drag_last_screen_y = screen_y
  pet.drag_grab_offset_x = screen_x - pet.window_x
  pet.drag_grab_offset_y = screen_y - pet.window_y
end

function Pet.drag_to(pet, screen_x, screen_y)
  if not pet.drag_pending and not pet.is_dragging then
    return
  end

  screen_x = screen_x or pet.drag_start_screen_x
  screen_y = screen_y or pet.drag_start_screen_y

  local frame_dx = screen_x - pet.drag_last_screen_x
  local frame_dy = screen_y - pet.drag_last_screen_y
  local max_delta = Config.drag.max_frame_delta or 0
  if max_delta > 0 and frame_dx * frame_dx + frame_dy * frame_dy > max_delta * max_delta then
    return
  end

  if pet.drag_pending then
    local dx = screen_x - pet.drag_start_screen_x
    local dy = screen_y - pet.drag_start_screen_y
    local threshold = Config.drag.start_threshold or 0
    if dx * dx + dy * dy < threshold * threshold then
      return
    end

    pet.drag_pending = false
    pet.is_dragging = true
  end

  sync_window(pet, screen_x - pet.drag_grab_offset_x, screen_y - pet.drag_grab_offset_y)
  pet.drag_last_screen_x = screen_x
  pet.drag_last_screen_y = screen_y
  pet.base_y = pet.window_y
end

function Pet.end_drag(pet)
  pet.drag_pending = false
  pet.is_dragging = false
  pet.drag_offset_x = 0
  pet.drag_offset_y = 0
  pet.drag_start_screen_x = 0
  pet.drag_start_screen_y = 0
  pet.drag_last_screen_x = 0
  pet.drag_last_screen_y = 0
  pet.drag_grab_offset_x = 0
  pet.drag_grab_offset_y = 0
  pet.base_y = pet.window_y
end

function Pet.drag_blocks_motion(pet)
  return pet.drag_pending or pet.is_dragging
end

local function update_move(pet, dt)
  local direction = pet.state == "move_left" and -1 or 1
  local speed = Config.desktop.move_speed
  local next_x = pet.window_x + direction * speed * dt
  local min_x, max_x = window_limits(pet)

  if next_x <= min_x then
    pet.move_dir = 1
  elseif next_x >= max_x then
    pet.move_dir = -1
  end

  sync_window(pet, next_x, pet.base_y)
end

function Pet.update(pet, dt, frozen)
  update_body_breath(pet, dt)

  if frozen then
    return
  end

  if Pet.drag_blocks_motion(pet) then
    return
  end

  local anim = Config.animation
  pet.state_t = pet.state_t + dt

  if pet.state == "blink" then
    if pet.state_t >= anim.blink_time then
      start_state(pet, "idle")
      reset_timers(pet)
    end
    return
  end

  if pet.state == "move_left" or pet.state == "move_right" then
    update_move(pet, dt)
    if pet.state_t >= anim.move_time then
      start_state(pet, "idle")
      reset_timers(pet)
    end
    return
  end

  pet.idle_t = pet.idle_t + dt
  if pet.idle_t >= anim.idle_frame_time then
    pet.idle_t = 0
    pet.idle_frame = pet.idle_frame == 1 and 2 or 1
  end

  pet.blink_in = pet.blink_in - dt
  pet.move_in = pet.move_in - dt

  if pet.blink_in <= 0 then
    start_state(pet, "blink")
  elseif pet.move_in <= 0 then
    pet.move_dir = choose_move_dir(pet)
    start_state(pet, pet.move_dir < 0 and "move_left" or "move_right")
  end
end

function Pet.bounds(pet)
  return {
    x = pet.x,
    y = pet.y,
    w = pet.size,
    h = pet.size,
  }
end

function Pet.contains(pet, x, y)
  local b = Pet.bounds(pet)
  return x >= b.x and y >= b.y and x < b.x + b.w and y < b.y + b.h
end

function Pet.draw(pet)
  Animation.draw(pet)
end

return Pet
