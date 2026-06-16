local Animation = require("animation")
local Config = require("config")

local Pet = {}

local function movement_log(message, ...)
  if Config.debug and Config.debug.movement_logs then
    print(string.format("[TetiMovement] " .. message, ...))
  end
end

local function expression_log(message, ...)
  if Config.debug and Config.debug.expression_logs then
    print(string.format("[TetiExpression] " .. message, ...))
  end
end

local function drag_log(message, ...)
  if Config.debug and Config.debug.drag_logs then
    print(string.format("[TetiDrag] " .. message, ...))
  end
end

local function clamp(value, min, max)
  if value < min then
    return min
  end
  if value > max then
    return max
  end
  return value
end

local function start_state(pet, state, animation_state)
  pet.movement_state = state
  pet.state = animation_state or state
  pet.state_t = 0
end

local function start_settling(pet)
  pet.settle_left = Config.drag.settle_time or 0.3
  pet.ai_movement_enabled = false
  start_state(pet, "settling")
  drag_log("release -> settling")
end

local start_idle

local function rand_between(min, max)
  return min + math.random() * (max - min)
end

local LOCKED_EXPRESSIONS = {
  warning = true,
  collapsed = true,
}

local function schedule_next_blink(pet)
  local expression = Config.expression
  pet.blink_in = rand_between(expression.blink_interval_min or 4.0, expression.blink_interval_max or 8.0)
end

local function set_expression(pet, expression, lock_duration, force)
  if not force and (pet.expression_lock_left or 0) > 0 and LOCKED_EXPRESSIONS[pet.expression] then
    return false
  end

  if pet.expression ~= expression then
    pet.expression_t = 0
  end
  pet.expression = expression
  pet.expression_state = expression
  pet.expression_lock_left = lock_duration or 0
  if expression ~= "blink" then
    pet.blink_left = 0
    pet.expression_previous = expression
  end
  return true
end

local function can_blink(pet)
  return pet.expression == "neutral" or pet.expression == "focused"
end

local function start_blink(pet)
  if not can_blink(pet) then
    schedule_next_blink(pet)
    return
  end

  local expression = Config.expression
  pet.expression_previous = pet.expression
  set_expression(pet, "blink", 0, true)
  expression_log("blink start")
  pet.blink_left = rand_between(expression.blink_duration_min or 0.10, expression.blink_duration_max or 0.18)
end

local function update_expression(pet, dt, frozen)
  local expression = Config.expression
  pet.expression_t = (pet.expression_t or 0) + dt

  if (pet.expression_lock_left or 0) > 0 then
    pet.expression_lock_left = math.max(0, pet.expression_lock_left - dt)
  end

  if pet.expression == "blink" then
    pet.blink_left = math.max(0, (pet.blink_left or 0) - dt)
    if pet.blink_left <= 0 then
      set_expression(pet, pet.expression_previous or "neutral", 0, true)
      expression_log("blink end -> %s", pet.expression)
      schedule_next_blink(pet)
    end
    return
  end

  if (pet.expression_lock_left or 0) > 0 and LOCKED_EXPRESSIONS[pet.expression] then
    return
  end

  local movement_state = pet.movement_state or pet.state
  local interacting = pet.mouse_hovered or pet.drag_pending or pet.is_dragging or movement_state == "dragged"
  if movement_state == "dragged" or pet.is_dragging then
    pet.idle_expression_t = 0
    set_expression(pet, "focused")
    return
  end

  if movement_state == "settling" then
    pet.idle_expression_t = 0
    set_expression(pet, "neutral")
    return
  end

  if interacting then
    pet.idle_expression_t = 0
    if pet.expression == "sleepy" then
      set_expression(pet, "neutral")
    end
  elseif movement_state == "idle" and not frozen then
    pet.idle_expression_t = (pet.idle_expression_t or 0) + dt
  else
    pet.idle_expression_t = 0
    if pet.expression == "sleepy" then
      set_expression(pet, "neutral")
    end
  end

  if (pet.idle_expression_t or 0) >= (expression.sleepy_after_idle or 60.0) and pet.expression == "neutral" then
    set_expression(pet, "sleepy")
    return
  end

  if can_blink(pet) then
    pet.blink_in = (pet.blink_in or 0) - dt
    if pet.blink_in <= 0 then
      start_blink(pet)
    end
  else
    schedule_next_blink(pet)
  end
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

local function read_display_bounds()
  if usagi and usagi.display_bounds then
    local displays = usagi.display_bounds()
    if displays and #displays > 0 then
      return displays
    end
  end

  return { read_desktop_bounds() }
end

local function bounds_limits(bounds, size)
  local margin = Config.desktop.margin
  local edge_margin = Config.desktop.edge_margin or 0
  local dock_margin = Config.desktop.dock_margin or margin
  local min_x = bounds.x + edge_margin
  local min_y = bounds.y + margin
  local max_x = bounds.x + bounds.w - size - edge_margin
  local max_y = bounds.y + bounds.h - size - dock_margin

  if max_x < min_x then
    max_x = min_x
  end
  if max_y < min_y then
    max_y = min_y
  end

  return min_x, max_x, min_y, max_y
end

local function window_limits(pet)
  return bounds_limits(pet.desktop, pet.size)
end

local function display_for_x(pet, x)
  local center_x = x + pet.size * 0.5
  local nearest = pet.desktop
  local nearest_distance = math.huge

  for _, display in ipairs(pet.displays or {}) do
    local left = display.x or 0
    local right = left + (display.w or 0)
    if center_x >= left and center_x < right then
      return display
    end

    local distance = math.min(math.abs(center_x - left), math.abs(center_x - right))
    if distance < nearest_distance then
      nearest = display
      nearest_distance = distance
    end
  end

  return nearest
end

local function rail_y(pet, x)
  local display = display_for_x(pet, x or pet.window_x)
  local _, _, _, max_y = bounds_limits(display, pet.size)
  return max_y
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

local function sync_rail(pet)
  pet.base_y = rail_y(pet, pet.window_x)
end

local function approach(value, target, amount)
  if value < target then
    return math.min(value + amount, target)
  end
  if value > target then
    return math.max(value - amount, target)
  end
  return value
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
  local displays = read_display_bounds()
  local size = Config.pet_size
  local pet = {
    x = 0,
    y = 0,
    size = size,
    desktop = desktop,
    displays = displays,
    window_x = 0,
    window_y = 0,
    base_y = 0,
    last_window_x = nil,
    last_window_y = nil,
    state = "idle",
    movement_state = "idle",
	    state_t = 0,
	    idle_frame = 1,
	    idle_t = 0,
	    expression = "neutral",
	    expression_state = "neutral",
	    expression_previous = "neutral",
	    expression_t = 0,
	    expression_lock_left = 0,
	    blink_in = 0,
	    blink_left = 0,
	    idle_expression_t = 0,
	    mouse_hovered = false,
	    failure_count = 0,
	    move_in = 0,
    move_dir = 1,
    velocity_x = 0,
    target_x = 0,
    idle_left = 0,
    wander_left = 0,
    ai_movement_enabled = true,
    move_speed_current = Config.desktop.move_speed,
    fall_vy = 0,
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
    settle_left = 0,
    settle_after_fall = false,
  }

  local min_x, max_x = window_limits(pet)
	  pet.window_x = min_x + (max_x - min_x) * Config.desktop.start_x_ratio
	  sync_rail(pet)
	  pet.window_y = pet.base_y

	  schedule_next_blink(pet)
	  start_idle(pet)
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
	  pet.move_speed_current = 0
	  pet.velocity_x = 0
	  pet.ai_movement_enabled = false
	  start_state(pet, "dragged")
	  set_expression(pet, "focused", 0, true)
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
	    set_expression(pet, "focused", 0, true)
	  end

  sync_window(pet, screen_x - pet.drag_grab_offset_x, screen_y - pet.drag_grab_offset_y)
  pet.drag_last_screen_x = screen_x
  pet.drag_last_screen_y = screen_y
end

function Pet.end_drag(pet)
  local was_dragging = pet.is_dragging
  local was_interacting = pet.drag_pending or pet.is_dragging or pet.movement_state == "dragged"
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

  sync_rail(pet)
  if was_dragging and pet.window_y < pet.base_y - 1 then
    pet.fall_vy = 0
    pet.settle_after_fall = true
    start_state(pet, "falling")
	  elseif was_dragging then
	    sync_window(pet, pet.window_x, pet.base_y)
	    start_settling(pet)
	    set_expression(pet, "neutral")
	  elseif was_interacting then
	    sync_window(pet, pet.window_x, pet.base_y)
	    pet.ai_movement_enabled = true
	    start_idle(pet)
	    start_blink(pet)
	  end
	end

	function Pet.drag_blocks_motion(pet)
	  return pet.drag_pending or pet.is_dragging or pet.movement_state == "dragged"
	end

	function Pet.set_hover(pet, hovered)
	  pet.mouse_hovered = hovered and true or false
	  if pet.mouse_hovered and pet.expression == "sleepy" then
	    pet.idle_expression_t = 0
	    set_expression(pet, "neutral")
	  end
	end

	function Pet.set_expression_debug(pet, expression)
	  if expression == "blink" then
	    start_blink(pet)
	    return
	  end

	  local lock = 0
	  if expression == "warning" then
	    lock = Config.expression.warning_min_duration or 1.5
	  elseif expression == "collapsed" then
	    lock = Config.expression.collapsed_min_duration or 3.0
	  end
	  set_expression(pet, expression, lock, true)
	end

	function Pet.report_error(pet)
	  pet.failure_count = (pet.failure_count or 0) + 1
	  if pet.failure_count >= 3 then
	    set_expression(pet, "collapsed", Config.expression.collapsed_min_duration or 3.0, true)
	  else
	    set_expression(pet, "warning", Config.expression.warning_min_duration or 1.5, true)
	  end
	end

	function Pet.clear_error(pet)
	  pet.failure_count = 0
	  if LOCKED_EXPRESSIONS[pet.expression] and (pet.expression_lock_left or 0) <= 0 then
	    set_expression(pet, "neutral", 0, true)
	  end
	end

	function Pet.choose_next_walk(pet, preferred_dir)
  local min_x, max_x = window_limits(pet)
  local desktop = Config.desktop
  local movement = Config.movement or {}

  if movement.wander_enabled == false or pet.ai_movement_enabled == false then
    return
  end

  local dir = preferred_dir or pet.move_dir

  if pet.window_x <= min_x + 8 then
    dir = 1
  elseif pet.window_x >= max_x - 8 then
    dir = -1
  elseif math.random() < (desktop.turn_chance or 0.42) then
    dir = -dir
  end

  local duration = rand_between(movement.wander_duration_min or 1.2, movement.wander_duration_max or 3.0)
  local speed = movement.wander_speed_px_per_sec or desktop.move_speed or 29
  local distance = speed * duration

  local target = clamp(pet.window_x + dir * distance, min_x, max_x)
  if math.abs(target - pet.window_x) < 8 then
    dir = -dir
    target = clamp(pet.window_x + dir * distance, min_x, max_x)
  end
  if math.abs(target - pet.window_x) < 8 then
    target = clamp(pet.window_x + dir * 32, min_x, max_x)
    dir = target >= pet.window_x and 1 or -1
  end

	  pet.move_dir = dir
	  pet.target_x = target
	  pet.wander_left = duration
	  if pet.expression == "sleepy" then
	    set_expression(pet, "neutral")
	  end
	  pet.move_speed_current = speed
	  pet.velocity_x = dir * speed
  start_state(pet, "wander", dir < 0 and "move_left" or "move_right")
  movement_log(
    "start wander dir=%s duration=%dms speed=%.1f",
    dir < 0 and "left" or "right",
    math.floor(duration * 1000 + 0.5),
    speed
  )
end

function start_idle(pet)
  local movement = Config.movement or {}
  local min_delay = movement.wander_interval_min or Config.desktop.idle_min_delay or 5.0
  local max_delay = movement.wander_interval_max or Config.desktop.idle_max_delay or 12.0
  pet.idle_left = rand_between(min_delay, max_delay)
  pet.wander_left = 0
  pet.velocity_x = 0
  start_state(pet, "idle")
  movement_log("state=idle, nextWanderIn=%dms", math.floor(pet.idle_left * 1000 + 0.5))
end

local function update_idle(pet, dt)
  pet.idle_t = pet.idle_t + dt
  if pet.idle_t >= 1 / (Config.animation.idle_fps or 4) then
    pet.idle_t = 0
    pet.idle_frame = pet.idle_frame == 1 and 2 or 1
  end

  if pet.ai_movement_enabled == false or (Config.movement and Config.movement.wander_enabled == false) then
    return
  end

  pet.idle_left = pet.idle_left - dt
  if pet.idle_left <= 0 then
    Pet.choose_next_walk(pet)
  end
end

local function update_settling(pet, dt)
  sync_rail(pet)
  sync_window(pet, pet.window_x, pet.base_y)
  pet.settle_left = math.max(0, (pet.settle_left or 0) - dt)
  if pet.settle_left <= 0 then
    pet.ai_movement_enabled = true
    drag_log("settling end -> movement enabled")
    start_idle(pet)
  end
end

local function update_patrol(pet, dt)
  local direction = pet.move_dir
  local speed = pet.move_speed_current or Config.desktop.move_speed
  pet.wander_left = math.max(0, (pet.wander_left or 0) - dt)
  pet.velocity_x = direction * speed
  local next_x = pet.window_x + direction * speed * dt
  local min_x, max_x = window_limits(pet)
  local target_x = clamp(pet.target_x or next_x, min_x, max_x)

  if direction < 0 then
    next_x = math.max(next_x, target_x)
  else
    next_x = math.min(next_x, target_x)
  end

  local target_y = rail_y(pet, next_x)
  pet.base_y = target_y
  local next_y = approach(pet.window_y, target_y, (Config.desktop.fall_max_speed or 520) * dt)
  sync_window(pet, next_x, next_y)

  if math.abs(next_x - target_x) < 1 or pet.wander_left <= 0 then
    pet.velocity_x = 0
    movement_log("stop wander -> idle")
    start_idle(pet)
  end
end

local function update_fall(pet, dt)
  sync_rail(pet)
  local gravity = Config.desktop.fall_gravity or 900
  local max_speed = Config.desktop.fall_max_speed or 520
  pet.fall_vy = math.min((pet.fall_vy or 0) + gravity * dt, max_speed)

  local next_y = pet.window_y + pet.fall_vy * dt
  if next_y >= pet.base_y then
    pet.fall_vy = 0
    sync_window(pet, pet.window_x, pet.base_y)
    if pet.settle_after_fall then
      pet.settle_after_fall = false
      start_settling(pet)
    else
      Pet.choose_next_walk(pet, pet.move_dir)
    end
    return
  end

  sync_window(pet, pet.window_x, next_y)
end

	function Pet.update(pet, dt, frozen)
	  if frozen then
    update_expression(pet, dt, true)
    update_body_breath(pet, dt)
    return
  end

  if Pet.drag_blocks_motion(pet) then
    update_expression(pet, dt, true)
    update_body_breath(pet, dt)
    return
  end

  pet.state_t = pet.state_t + dt

  local movement_state = pet.movement_state or pet.state

  if movement_state == "falling" then
    update_fall(pet, dt)
  elseif movement_state == "idle" then
    sync_rail(pet)
    sync_window(pet, pet.window_x, pet.base_y)
    update_idle(pet, dt)
  elseif movement_state == "settling" then
    update_settling(pet, dt)
  elseif movement_state == "wander" or pet.state == "move_left" or pet.state == "move_right" then
    update_patrol(pet, dt)
  else
    start_idle(pet)
  end

  update_expression(pet, dt, false)
  update_body_breath(pet, dt)
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
