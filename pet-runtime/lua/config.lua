local Config = {}
local SpriteManifest = require("sprites_manifest")
local HatManifest = require("hats_manifest")

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
  move_speed = 29,
  move_speed_min = 20,
  move_speed_max = 40,
  walk_min_distance = 180,
  walk_max_distance = 760,
  long_walk_chance = 0.12,
  idle_min_delay = 5.0,
  idle_max_delay = 12.0,
  turn_chance = 0.32,
  fall_gravity = 900,
  fall_max_speed = 520,
}

Config.movement = {
  wander_enabled = true,
  wander_interval_min = 5.0,
  wander_interval_max = 12.0,
  wander_duration_min = 1.2,
  wander_duration_max = 3.0,
  wander_speed_px_per_sec = 29,
}

Config.breathing = {
  enabled = true,
  body_amplitude = 1,
  body_speed = 2.6,
  body_cut_y = 92,
  body_overlap = 6,
}

Config.drag = {
  enabled = true,
  start_threshold = 3,
  max_frame_delta = 320,
  settle_time = 0.3,
}

Config.interaction = {
  screen_rect = { x = 28, y = 28, w = 72, h = 48 },
}

Config.animation = {
  idle_frame_time = 0.46,
  idle_fps = 2,
  blink_time = 0.14,
  blink_min_delay = 1.8,
  blink_max_delay = 3.8,
  move_time = 0.9,
  move_min_delay = 2.0,
  move_max_delay = 3.6,
  move_low_fps = 5,
  move_normal_fps = 8,
  move_high_fps = 12,
  move_normal_speed = 28,
  move_high_speed = 48,
}

Config.expression = {
  overlay_enabled = true,
  blink_interval_min = 4.0,
  blink_interval_max = 8.0,
  blink_duration_min = 0.10,
  blink_duration_max = 0.18,
  sleepy_after_idle = 60.0,
  warning_min_duration = 1.5,
  collapsed_min_duration = 3.0,
  debug_keys = true,
}

Config.debug = {
  movement_logs = true,
  expression_logs = true,
  drag_logs = true,
  hat_logs = true,
  hat_bounds = true,
}

Config.sprites = SpriteManifest
Config.hats = HatManifest

Config.menu = {
  -- The built-in Usagi font is not a CJK font. Keep the UTF-8 text here
  -- for a future font.png, but render ASCII now to avoid mojibake.
  label_utf8 = "\233\128\128\229\135\186",
  label = "Exit",
  hats_label = "Hats >",
  mail_label = "Mail",
  item_h = 13,
  minimum_item_w = 15,
  picker_label_chars = 8,
  picker_previous_label = "<",
  picker_next_label = ">",
  picker_close_label = "X",
  safe_margin = 3,
  text_pad_x = 4,
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
    pixel_perfect = true,
  }
end

return Config
