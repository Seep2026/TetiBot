local Config = require("config")

local Menu = {}

local function clamp(value, min, max)
  if value < min then
    return min
  end
  if value > max then
    return max
  end
  return value
end

local function point_in_rect(x, y, rect)
  return x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h
end

function Menu.new()
  return {
    visible = false,
    x = 0,
    y = 0,
    w = Config.menu.w,
    h = Config.menu.h,
  }
end

function Menu.show(menu, x, y)
  menu.visible = true
  menu.x = clamp(x, 2, usagi.GAME_W - menu.w - 2)
  menu.y = clamp(y, 2, usagi.GAME_H - menu.h - 2)
end

function Menu.hide(menu)
  menu.visible = false
end

function Menu.rect(menu)
  return { x = menu.x, y = menu.y, w = menu.w, h = menu.h }
end

function Menu.update(menu)
  if not menu.visible then
    return false
  end

  local mx, my = input.mouse()
  local inside = point_in_rect(mx, my, Menu.rect(menu))

  if input.mouse_pressed(input.MOUSE_LEFT) then
    if inside then
      usagi.quit()
    else
      Menu.hide(menu)
    end
    return true
  end

  return inside
end

function Menu.draw(menu)
  if not menu.visible then
    return
  end

  local mx, my = input.mouse()
  local hovered = point_in_rect(mx, my, Menu.rect(menu))
  local fill = hovered and gfx.COLOR_DARK_BLUE or gfx.COLOR_DARK_GRAY

  gfx.rect_fill(menu.x, menu.y, menu.w, menu.h, fill)
  gfx.rect(menu.x, menu.y, menu.w, menu.h, gfx.COLOR_WHITE)
  gfx.text(Config.menu.label, menu.x + 8, menu.y + 6, gfx.COLOR_WHITE)
end

return Menu
