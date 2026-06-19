local Config = require("config")

local Menu = {}

local function clamp(value, minimum, maximum)
  if value < minimum then
    return minimum
  end
  if value > maximum then
    return maximum
  end
  return value
end

local function point_in_rect(x, y, rect)
  return x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h
end

local function text_size(text)
  if usagi and usagi.measure_text then
    local width, height = usagi.measure_text(text)
    return width or 0, height or 0
  end
  return #text * 6, 7
end

local function compact_label(label)
  local limit = Config.menu.picker_label_chars
  if #label <= limit then
    return label
  end
  return string.sub(label, 1, limit - 1) .. "."
end

local function root_labels()
  return { Config.menu.hats_label, Config.menu.label }
end

local function picker_labels(menu)
  local hat_id = Config.hats.menu[menu.hat_index]
  local hat = Config.hats.by_id[hat_id]
  return {
    Config.menu.picker_previous_label,
    compact_label(hat.label),
    Config.menu.picker_next_label,
    Config.menu.picker_close_label,
  }
end

local function item_width(label)
  local text_width = text_size(label)
  -- Two extra pixels protect the final glyph from the menu border.
  return math.max(Config.menu.minimum_item_w, text_width + Config.menu.text_pad_x * 2 + 2)
end

local function menu_width(labels)
  local width = 0
  for _, label in ipairs(labels) do
    width = width + item_width(label)
  end
  return width
end

local function item_rect(menu, labels, index)
  local x = menu.x
  for previous = 1, index - 1 do
    x = x + item_width(labels[previous])
  end
  return {
    x = x,
    y = menu.y,
    w = item_width(labels[index]),
    h = Config.menu.item_h,
  }
end

local function labels_for(menu)
  if menu.view == "hats" then
    return picker_labels(menu)
  end
  return root_labels()
end

local function resize(menu)
  menu.w = menu_width(labels_for(menu))
  menu.h = Config.menu.item_h
end

local function place_in_top_safe_area(menu)
  resize(menu)
  local margin = Config.menu.safe_margin
  local maximum_x = math.max(margin, usagi.GAME_W - menu.w - margin)
  if menu.open_x >= usagi.GAME_W * 0.5 then
    menu.x = margin
  else
    menu.x = maximum_x
  end
  menu.x = clamp(menu.x, margin, maximum_x)
  menu.y = margin
end

local function current_hat_index(pet)
  local hat_state = pet.hatState or pet.hat_state
  local current_hat = hat_state and hat_state.currentHat or "none"
  for index, hat_id in ipairs(Config.hats.menu) do
    if hat_id == current_hat then
      return index
    end
  end
  return 1
end

local function cycle_hat(menu, pet, pet_module, step)
  local count = #Config.hats.menu
  menu.hat_index = ((menu.hat_index - 1 + step) % count) + 1
  pet_module.set_hat(pet, Config.hats.menu[menu.hat_index])
  place_in_top_safe_area(menu)
end

local function draw_item(rect, label, highlighted)
  local mouse_x, mouse_y = input.mouse()
  local hovered = point_in_rect(mouse_x, mouse_y, rect)
  local fill = (hovered or highlighted) and gfx.COLOR_DARK_BLUE or gfx.COLOR_DARK_GRAY
  gfx.rect_fill(rect.x, rect.y, rect.w, rect.h, fill)
  local text_width, text_height = text_size(label)
  gfx.text(
    label,
    rect.x + math.max(1, math.floor((rect.w - text_width) * 0.5)),
    rect.y + math.max(1, math.floor((rect.h - text_height) * 0.5)),
    gfx.COLOR_WHITE
  )
end

function Menu.new()
  local menu = {
    visible = false,
    view = "root",
    x = 0,
    y = 0,
    w = 0,
    h = Config.menu.item_h,
    open_x = 0,
    hat_index = 1,
  }
  resize(menu)
  return menu
end

function Menu.show(menu, x, y)
  menu.visible = true
  menu.view = "root"
  menu.open_x = x
  place_in_top_safe_area(menu)
end

function Menu.hide(menu)
  menu.visible = false
  menu.view = "root"
end

function Menu.rect(menu)
  return { x = menu.x, y = menu.y, w = menu.w, h = menu.h }
end

function Menu.update(menu, pet, pet_module)
  if not menu.visible then
    return false
  end

  local mouse_x, mouse_y = input.mouse()
  local inside = point_in_rect(mouse_x, mouse_y, Menu.rect(menu))
  if not input.mouse_pressed(input.MOUSE_LEFT) then
    return inside
  end

  if not inside then
    Menu.hide(menu)
    return true
  end

  local labels = labels_for(menu)
  if menu.view == "root" then
    if point_in_rect(mouse_x, mouse_y, item_rect(menu, labels, 1)) then
      menu.view = "hats"
      menu.hat_index = current_hat_index(pet)
      place_in_top_safe_area(menu)
    elseif point_in_rect(mouse_x, mouse_y, item_rect(menu, labels, 2)) then
      usagi.quit()
    end
    return true
  end

  if point_in_rect(mouse_x, mouse_y, item_rect(menu, labels, 1)) then
    cycle_hat(menu, pet, pet_module, -1)
  elseif point_in_rect(mouse_x, mouse_y, item_rect(menu, labels, 2)) then
    Menu.hide(menu)
  elseif point_in_rect(mouse_x, mouse_y, item_rect(menu, labels, 3)) then
    cycle_hat(menu, pet, pet_module, 1)
  elseif point_in_rect(mouse_x, mouse_y, item_rect(menu, labels, 4)) then
    Menu.hide(menu)
  end
  return true
end

function Menu.draw(menu)
  if not menu.visible then
    return
  end

  local labels = labels_for(menu)
  for index, label in ipairs(labels) do
    draw_item(item_rect(menu, labels, index), label, menu.view == "hats" and index == 2)
  end
  gfx.rect(menu.x, menu.y, menu.w, menu.h, gfx.COLOR_WHITE)
end

return Menu
