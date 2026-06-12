Config = require("config")
Pet = require("pet")
Input = require("input")
Menu = require("menu")

function _config()
  return Config.usagi()
end

function _init()
  math.randomseed(os.time())
  input.set_mouse_visible(true)

  State = {
    pet = Pet.new(),
    menu = Menu.new(),
  }
end

function _update(dt)
  Input.update(State.pet, State.menu, Pet, Menu)
  Pet.update(State.pet, dt, State.menu.visible or Pet.drag_blocks_motion(State.pet))
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
  Menu.draw(State.menu)
end
