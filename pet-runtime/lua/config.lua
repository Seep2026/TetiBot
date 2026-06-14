local Config = {}

Config.game_width = 128
Config.game_height = 128
Config.sprite_size = 128
Config.sprite_sheet = "sprites.png"

Config.pet_size = 128
Config.sprite_sheet_columns = 6

Config.desktop = {
  fallback_x = 0,
  fallback_y = 0,
  fallback_w = 1440,
  fallback_h = 900,
  margin = 24,
  edge_margin = 0,
  dock_margin = 78,
  start_x_ratio = 0.72,
  move_speed = 48,
  move_speed_min = 34,
  move_speed_max = 68,
  walk_min_distance = 180,
  walk_max_distance = 760,
  long_walk_chance = 0.24,
  idle_min_delay = 0.5,
  idle_max_delay = 1.8,
  turn_chance = 0.42,
  fall_gravity = 900,
  fall_max_speed = 520,
}

Config.breathing = {
  enabled = true,
  body_amplitude = 2,
  body_speed = 2.6,
  body_cut_y = 92,
  body_overlap = 6,
}

Config.drag = {
  enabled = true,
  start_threshold = 3,
  max_frame_delta = 320,
}

Config.animation = {
  idle_frame_time = 0.46,
  blink_time = 0.14,
  blink_min_delay = 1.8,
  blink_max_delay = 3.8,
  move_time = 0.9,
  move_min_delay = 2.0,
  move_max_delay = 3.6,
}

Config.sprites = {
  front = 1,
  side = 2,
  face_neutral = 3,
  face_blink = 4,
  idle_1 = 9,
  idle_2 = 10,
  move_left = 11,
  move_right = 12,
}

Config.menu = {
  -- The built-in Usagi font is not a CJK font. Keep the UTF-8 text here
  -- for a future font.png, but render ASCII now to avoid mojibake.
  label_utf8 = "\233\128\128\229\135\186",
  label = "Exit",
  w = 44,
  h = 20,
}

function Config.usagi()
  return {
    name = "Teti",
    game_id = "ai.seep.tetibot.prototype",
    game_width = Config.game_width,
    game_height = Config.game_height,
    sprite_size = Config.sprite_size,
    icon = 1,
    pause_menu = false,
    pet_window = true,
    pixel_perfect = false,
  }
end

return Config
