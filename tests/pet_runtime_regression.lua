package.path = "./pet-runtime/lua/?.lua;" .. package.path

local Config = require("config")
local Pet = require("pet")
local Animation = require("animation")
local HatRegistry = require("hat_registry")

Config.debug.movement_logs = false
Config.debug.expression_logs = false
Config.debug.drag_logs = false
Config.debug.hat_logs = false
Config.movement.wander_interval_min = 0.05
Config.movement.wander_interval_max = 0.05
Config.movement.wander_duration_min = 3.0
Config.movement.wander_duration_max = 3.0
Config.movement.wander_speed_px_per_sec = 29

assert(HatRegistry.validate(), "runtime hat registry should validate")

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

local movement_before_hat = pet.movement_state
local expression_before_hat = pet.expression_state
assert_truthy(Pet.set_hat(pet, "focus_goggles"), "set_hat should accept an unlocked manifest hat")
assert_equal(pet.hatState.currentHat, "focus_goggles", "set_hat should update currentHat")
assert_equal(pet.movement_state, movement_before_hat, "set_hat must not change movement state")
assert_equal(pet.expression_state, expression_before_hat, "set_hat must not change expression state")
pose = Animation.debug_pose_for(pet)
assert_equal(
  pose.hat_sprite,
  Config.hats.by_id.focus_goggles.sprite,
  "render pose should use the selected hat overlay"
)

pet.movement_state = "idle"
pet.state = "idle"
pet.state_t = 1.0
pose = Animation.debug_pose_for(pet)
assert_equal(pose.face_dy, -1, "regression setup should select the raised idle face frame")
assert_equal(pose.hat_dx, pose.face_dx, "hat must inherit the body horizontal pose transform")
assert_equal(pose.hat_dy, pose.face_dy, "hat must inherit the body vertical pose transform")

pet.body_offset_y = 1
pose = Animation.debug_pose_for(pet)
assert_equal(pose.face_dy, 0, "face must inherit the +1px body breathing offset")
assert_equal(pose.hat_dy, pose.face_dy, "hat must inherit the same body breathing offset")

local movement_before_cycle = pet.movement_state
assert_truthy(Pet.cycle_hat(pet), "H shortcut cycle should select the next unlocked hat")
assert_equal(pet.movement_state, movement_before_cycle, "cycling hats must not change movement state")
assert_equal(pet.expression_state, expression_before_hat, "cycling hats must not change expression state")

print("pet_runtime_regression.lua: ok")
