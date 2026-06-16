package.path = "./pet-runtime/lua/?.lua;" .. package.path

local Config = require("config")
local Pet = require("pet")
local Animation = require("animation")

Config.debug.movement_logs = false
Config.debug.expression_logs = false
Config.debug.drag_logs = false
Config.movement.wander_interval_min = 0.05
Config.movement.wander_interval_max = 0.05
Config.movement.wander_duration_min = 3.0
Config.movement.wander_duration_max = 3.0
Config.movement.wander_speed_px_per_sec = 29

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
  end
end

local function assert_truthy(value, message)
  if not value then
    error(message, 2)
  end
end

local function new_pet()
  math.randomseed(7)
  return Pet.new()
end

local function is_move_sprite(sprite)
  for _, item in ipairs(Config.sprites.move_left_track) do
    if sprite == item then
      return true
    end
  end
  for _, item in ipairs(Config.sprites.move_right_track) do
    if sprite == item then
      return true
    end
  end
  return sprite == Config.sprites.move_left or sprite == Config.sprites.move_right
end

local pet = new_pet()
Pet.choose_next_walk(pet, 1)
local movement_before_blink = pet.movement_state
Pet.set_expression_debug(pet, "blink")
Pet.update(pet, 0.05, false)
assert_equal(pet.movement_state, movement_before_blink, "blink must not change movement state")

pet = new_pet()
Pet.set_expression_debug(pet, "sleepy")
pet.idle_left = 0
Pet.update(pet, 0.016, false)
assert_equal(pet.movement_state, "wander", "sleepy must not permanently block wander")
assert_equal(pet.expression_state, "neutral", "wander should wake sleepy expression to neutral")

pet = new_pet()
Pet.begin_drag(pet, 10, 10, 100, 100)
Pet.drag_to(pet, 110, 100)
Pet.end_drag(pet)
assert_equal(pet.movement_state, "settling", "drag release should enter settling")
assert_equal(pet.ai_movement_enabled, false, "settling should temporarily disable movement")
Pet.update(pet, (Config.drag.settle_time or 0.3) + 0.01, false)
assert_equal(pet.ai_movement_enabled, true, "settling end should restore movement")
assert_equal(pet.movement_state, "idle", "settling end should return to idle")

pet = new_pet()
pet.idle_left = 0
Pet.update(pet, 0.016, false)
assert_equal(pet.movement_state, "wander", "wander timer should enter wander")
assert_truthy(math.abs(pet.velocity_x or 0) > 0, "wander should set horizontal velocity")

local pose = Animation.debug_pose_for(pet)
assert_truthy(is_move_sprite(pose.sprite), "wander should render a move_left or move_right body frame")

print("pet_runtime_regression.lua: ok")
