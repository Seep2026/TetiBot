local Config = require("config")

local Input = {}

local DEBUG_EXPRESSIONS = {
  { key = "KEY_1", expression = "neutral" },
  { key = "KEY_2", expression = "blink" },
  { key = "KEY_3", expression = "sleepy" },
  { key = "KEY_4", expression = "focused" },
  { key = "KEY_5", expression = "warning" },
  { key = "KEY_6", expression = "collapsed" },
}

local function mouse_screen(mx, my)
  if input.mouse_screen then
    return input.mouse_screen()
  end

  if usagi and usagi.window_position then
    local wx, wy = usagi.window_position()
    return (wx or 0) + mx, (wy or 0) + my
  end

  return mx, my
end

function Input.update(pet, menu, pet_module, menu_module)
  local mx, my = input.mouse()
  local sx, sy = mouse_screen(mx, my)
  local hovered = pet_module.contains(pet, mx, my)

  if pet_module.set_hover then
    pet_module.set_hover(pet, hovered)
  end

  if Config.expression.debug_keys and input.key_pressed and pet_module.set_expression_debug then
    for _, item in ipairs(DEBUG_EXPRESSIONS) do
      local key = input[item.key]
      if key and input.key_pressed(key) then
        pet_module.set_expression_debug(pet, item.expression)
      end
    end
  end

  if input.mouse_pressed(input.MOUSE_RIGHT) then
    pet_module.end_drag(pet)
    if hovered then
      menu_module.show(menu, mx, my)
    else
      menu_module.hide(menu)
    end
  end

  if menu_module.update(menu) then
    pet_module.end_drag(pet)
    return
  end

  if input.mouse_pressed(input.MOUSE_LEFT) then
    if hovered then
      menu_module.hide(menu)
      pet_module.begin_drag(pet, mx, my, sx, sy)
    end
  elseif input.mouse_held(input.MOUSE_LEFT) then
    pet_module.drag_to(pet, sx, sy)
  elseif input.mouse_released(input.MOUSE_LEFT) then
    pet_module.end_drag(pet)
  end
end

return Input
