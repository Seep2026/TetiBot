Config = require("config")
Pet = require("pet")
Input = require("input")
Menu = require("menu")
HatRegistry = require("hat_registry")

function _config()
  return Config.usagi()
end

function _init()
  math.randomseed(os.time())
  input.set_mouse_visible(true)
  HatRegistry.validate()

  State = {
    pet = Pet.new(),
    menu = Menu.new(),
  }
end

local function sync_external_pet_status(dt)
  State.status_poll_t = (State.status_poll_t or 0) - dt
  if State.status_poll_t > 0 then
    return
  end
  State.status_poll_t = 0.5

  if not usagi or not usagi.load then
    return
  end

  local ok, data = pcall(usagi.load)
  if not ok or not data then
    return
  end

  if data.pet_status then
    Pet.apply_status(State.pet, data.pet_status)
  end

  if data.command and data.nonce and data.nonce ~= State.last_command_nonce then
    State.last_command_nonce = data.nonce
    if data.command == "set_hat" and data.hat_id then
      Pet.set_hat(State.pet, data.hat_id)
    end
  end
end

function _update(dt)
  sync_external_pet_status(dt)
  Input.update(State.pet, State.menu, Pet, Menu)
  Pet.update(State.pet, dt, Pet.drag_blocks_motion(State.pet))
end

local function clear_canvas()
  if gfx.clear_transparent then
    gfx.clear_transparent()
  else
    gfx.clear(gfx.COLOR_BLACK)
  end
end

function _draw(_dt)
  clear_canvas()
  Pet.draw(State.pet)
  Menu.draw(State.menu, State.pet)
end
