local icon = "__base__/graphics/icons/roboport.png"

data:extend({
  {
    type = "selection-tool",
    name = "robo-grid-tool",
    icon = icon,
    icon_size = 64,
    flags = { "only-in-cursor", "not-stackable", "spawnable" },
    subgroup = "tool",
    order = "z[robo-grid]",
    stack_size = 1,
    select = {
      border_color = { r = 0.2, g = 0.9, b = 0.3 },
      cursor_box_type = "copy",
      mode = { "nothing" },
    },
    alt_select = {
      border_color = { r = 1, g = 0.5, b = 0 },
      cursor_box_type = "not-allowed",
      mode = { "same-force", "any-entity" },
      entity_type_filters = { "roboport" },
    },
  },
  {
    type = "shortcut",
    name = "robo-grid-tool",
    order = "b[blueprints]-r[robo-grid]",
    action = "spawn-item",
    item_to_spawn = "robo-grid-tool",
    icon = icon,
    icon_size = 64,
    small_icon = icon,
    small_icon_size = 64,
  },
})
